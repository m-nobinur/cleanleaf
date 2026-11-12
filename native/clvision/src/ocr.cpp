#include <opencv2/core.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <numeric>
#include <string>
#include <vector>

#include "clvision.h"
#include "tflite/c/c_api.h"
#include "tflite/delegates/xnnpack/xnnpack_delegate.h"

// PP-OCR det (DB) + rec (CTC), a step-by-step port of T-032's reference pipeline
// (.local/fixtures/ocr-en-v0/tools/ppocr_ref.py), which matches the official PaddleOCR 3.7 one.

namespace {

constexpr int kDetSide = 960;
constexpr int kRecHeight = 48;
constexpr int kRecMinWidth = 320;
// The dynamic rec model matches ONNX only at widths divisible by 8 (one extra CTC step otherwise).
constexpr int kRecWidthStep = 8;
constexpr float kMean[3] = {0.485f, 0.456f, 0.406f};
constexpr float kStd[3] = {0.229f, 0.224f, 0.225f};
constexpr double kBinaryThreshold = 0.3;
constexpr double kBoxThreshold = 0.6;
constexpr double kUnclipRatio = 1.5;
constexpr size_t kMaxCandidates = 1000;
// D-59 line flags (T-032): the Latin head drops or guesses other scripts.
constexpr double kLowConfidence = 0.8;
constexpr double kLowCoverage = 0.6;
// Auto re-reads a page with Tesseract eng+ben from this flagged share of line width on (D-59).
constexpr double kNonLatinShare = 0.25;

using Clock = std::chrono::steady_clock;

double msSince(Clock::time_point t) {
  return std::chrono::duration<double, std::milli>(Clock::now() - t).count();
}

struct Net {
  std::vector<uint8_t> bytes;
  TfLiteModel* model = nullptr;
  TfLiteDelegate* xnnpack = nullptr;
  TfLiteInterpreterOptions* options = nullptr;
  TfLiteInterpreter* interpreter = nullptr;
  bool fp16 = false;
  int width = 0;  // input width the interpreter is allocated for

  ~Net() { release(); }

  void release() {
    TfLiteInterpreterDelete(interpreter);
    TfLiteInterpreterOptionsDelete(options);
    if (xnnpack != nullptr) TfLiteXNNPackDelegateDelete(xnnpack);
    TfLiteModelDelete(model);
    interpreter = nullptr;
    options = nullptr;
    xnnpack = nullptr;
    model = nullptr;
  }

  bool create(bool wantFp16, int threads) {
    release();
    fp16 = wantFp16;
    model = TfLiteModelCreate(bytes.data(), bytes.size());
    if (model == nullptr) return false;
    TfLiteXNNPackDelegateOptions xnn = TfLiteXNNPackDelegateOptionsDefault();
    xnn.num_threads = threads;
    if (fp16) xnn.flags |= TFLITE_XNNPACK_DELEGATE_FLAG_FORCE_FP16;
    xnnpack = TfLiteXNNPackDelegateCreate(&xnn);
    if (xnnpack == nullptr) return false;
    options = TfLiteInterpreterOptionsCreate();
    TfLiteInterpreterOptionsSetNumThreads(options, threads);
    TfLiteInterpreterOptionsAddDelegate(options, xnnpack);
    interpreter = TfLiteInterpreterCreate(model, options);
    if (interpreter == nullptr || TfLiteInterpreterAllocateTensors(interpreter) != kTfLiteOk) {
      return false;
    }
    width = TfLiteTensorDim(input(), 2);
    return true;
  }

  // Falls back to fp32 when fp16 can't be built (no fp16 arithmetic, e.g. A53).
  bool load(const uint8_t* data, int32_t length, bool wantFp16, int threads) {
    bytes.assign(data, data + length);
    return create(wantFp16, threads) || (wantFp16 && create(false, threads));
  }

  TfLiteTensor* input() { return TfLiteInterpreterGetInputTensor(interpreter, 0); }
  const TfLiteTensor* output() { return TfLiteInterpreterGetOutputTensor(interpreter, 0); }

  bool resizeWidth(int w) {
    if (w == width) return true;
    const int dims[4] = {1, kRecHeight, w, 3};
    if (TfLiteInterpreterResizeInputTensor(interpreter, 0, dims, 4) != kTfLiteOk ||
        TfLiteInterpreterAllocateTensors(interpreter) != kTfLiteOk) {
      return false;
    }
    width = w;
    return true;
  }
};

using Quad = std::array<cv::Point2f, 4>;

struct Word {
  std::string text;
  double conf = 0;
  Quad quad;
};

struct Line {
  Quad quad;
  std::string text;
  double conf = 0;
  double coverage = 0;  // the words' share of the line's width (T-032's CTC coverage)
  std::vector<Word> words;
};

struct Stats {
  double decodeMs = 0, detPreMs = 0, detInferMs = 0, detPostMs = 0;
  double recPrepMs = 0, recInferMs = 0, recResizeMs = 0, recDecodeMs = 0;
  int resizes = 0;
};

// mini_box: the min-area rectangle's corners, TL, TR, BR, BL by the reference's x-sort rule.
Quad miniBox(const std::vector<cv::Point2f>& points, double* shortSide) {
  const cv::RotatedRect rect = cv::minAreaRect(points);
  cv::Point2f p[4];
  rect.points(p);
  std::stable_sort(p, p + 4, [](cv::Point2f a, cv::Point2f b) { return a.x < b.x; });
  const int i1 = p[1].y > p[0].y ? 0 : 1, i4 = p[1].y > p[0].y ? 1 : 0;
  const int i2 = p[3].y > p[2].y ? 2 : 3, i3 = p[3].y > p[2].y ? 3 : 2;
  *shortSide = std::min(rect.size.width, rect.size.height);
  return {p[i1], p[i2], p[i3], p[i4]};
}

// Mean probability inside the box (box_score_fast).
double boxScore(const cv::Mat& pred, const Quad& box) {
  const int w = pred.cols, h = pred.rows;
  float minX = box[0].x, maxX = box[0].x, minY = box[0].y, maxY = box[0].y;
  for (const auto& p : box) {
    minX = std::min(minX, p.x);
    maxX = std::max(maxX, p.x);
    minY = std::min(minY, p.y);
    maxY = std::max(maxY, p.y);
  }
  const int xmin = std::clamp(int(std::floor(minX)), 0, w - 1);
  const int xmax = std::clamp(int(std::ceil(maxX)), 0, w - 1);
  const int ymin = std::clamp(int(std::floor(minY)), 0, h - 1);
  const int ymax = std::clamp(int(std::ceil(maxY)), 0, h - 1);
  cv::Mat mask = cv::Mat::zeros(ymax - ymin + 1, xmax - xmin + 1, CV_8U);
  std::vector<cv::Point> poly;
  for (const auto& p : box) poly.emplace_back(int(p.x - xmin), int(p.y - ymin));  // truncates, as numpy
  cv::fillPoly(mask, std::vector<std::vector<cv::Point>>{poly}, 1);
  return cv::mean(pred(cv::Rect(xmin, ymin, mask.cols, mask.rows)), mask)[0];
}

// A rectangle offset by d (Clipper's round join) has the rectangle grown by d as its min-area rect.
std::vector<cv::Point2f> unclip(const Quad& box) {
  const std::vector<cv::Point2f> poly(box.begin(), box.end());
  const double d = std::abs(cv::contourArea(poly)) * kUnclipRatio / cv::arcLength(poly, true);
  cv::RotatedRect rect = cv::minAreaRect(poly);
  rect.size.width += float(2 * d);
  rect.size.height += float(2 * d);
  std::vector<cv::Point2f> out(4);
  rect.points(out.data());
  return out;
}

// DB post-processing on the canvas map; boxes come back in page pixels (canvas / scale).
std::vector<Quad> dbBoxes(const cv::Mat& pred, double scale, int pageW, int pageH) {
  cv::Mat bitmap = pred > kBinaryThreshold;
  std::vector<std::vector<cv::Point>> contours;
  cv::findContours(bitmap, contours, cv::RETR_LIST, cv::CHAIN_APPROX_SIMPLE);
  const double srcW = kDetSide / scale, srcH = kDetSide / scale;
  std::vector<Quad> boxes;
  for (size_t i = 0; i < contours.size() && i < kMaxCandidates; ++i) {
    double shortSide;
    const std::vector<cv::Point2f> points(contours[i].begin(), contours[i].end());
    const Quad box = miniBox(points, &shortSide);
    if (shortSide < 3 || boxScore(pred, box) < kBoxThreshold) continue;
    Quad grown = miniBox(unclip(box), &shortSide);
    if (shortSide < 5) continue;
    for (auto& p : grown) {
      p.x = float(std::clamp(std::nearbyint(p.x / pred.cols * srcW), 0.0, srcW));
      p.y = float(std::clamp(std::nearbyint(p.y / pred.rows * srcH), 0.0, srcH));
    }
    boxes.push_back(grown);
  }
  // filter_boxes: clockwise from the min x+y corner, clipped to the page, at least 4 px a side.
  std::vector<Quad> kept;
  for (const Quad& b : boxes) {
    int tl = 0, br = 0;
    for (int k = 1; k < 4; ++k) {
      if (b[k].x + b[k].y < b[tl].x + b[tl].y) tl = k;
      if (b[k].x + b[k].y > b[br].x + b[br].y) br = k;
    }
    std::vector<int> rest;
    for (int k = 0; k < 4; ++k) {
      if (k != tl && k != br) rest.push_back(k);
    }
    if (rest.size() != 2) continue;
    const bool firstIsTr = b[rest[0]].y - b[rest[0]].x <= b[rest[1]].y - b[rest[1]].x;
    Quad q = {b[tl], b[firstIsTr ? rest[0] : rest[1]], b[br], b[firstIsTr ? rest[1] : rest[0]]};
    for (auto& p : q) {
      p.x = std::clamp(p.x, 0.0f, float(pageW - 1));
      p.y = std::clamp(p.y, 0.0f, float(pageH - 1));
    }
    if (int(cv::norm(q[0] - q[1])) <= 3 || int(cv::norm(q[0] - q[3])) <= 3) continue;
    kept.push_back(q);
  }
  // sorted_boxes: top to bottom, then left to right within 10 px.
  std::stable_sort(kept.begin(), kept.end(), [](const Quad& a, const Quad& b) {
    return a[0].y != b[0].y ? a[0].y < b[0].y : a[0].x < b[0].x;
  });
  for (size_t i = 0; i + 1 < kept.size(); ++i) {
    for (size_t j = i + 1; j-- > 0;) {
      if (std::abs(kept[j + 1][0].y - kept[j][0].y) < 10 && kept[j + 1][0].x < kept[j][0].x) {
        std::swap(kept[j], kept[j + 1]);
      } else {
        break;
      }
    }
  }
  return kept;
}

// The line flattened to its own size; tall crops turn a quarter counter-clockwise.
cv::Mat cropLine(const cv::Mat& page, const Quad& q, bool* rotated) {
  const int w = int(std::max(cv::norm(q[0] - q[1]), cv::norm(q[2] - q[3])));
  const int h = int(std::max(cv::norm(q[0] - q[3]), cv::norm(q[1] - q[2])));
  const cv::Point2f dst[4] = {{0, 0}, {float(w), 0}, {float(w), float(h)}, {0, float(h)}};
  cv::Mat crop;
  cv::warpPerspective(page, crop, cv::getPerspectiveTransform(q.data(), dst), cv::Size(w, h),
                      cv::INTER_CUBIC, cv::BORDER_REPLICATE);
  *rotated = double(crop.rows) / std::max(crop.cols, 1) >= 1.5;
  if (*rotated) cv::rotate(crop, crop, cv::ROTATE_90_COUNTERCLOCKWISE);
  return crop;
}

struct Glyph {
  int cls;
  float prob;
  double x0, x1;  // in resized-line pixels
};

// Greedy CTC over [steps x classes]; a step is stepPx resized-line pixels wide.
void ctcDecode(const float* probs, int steps, int classes, double stepPx, std::vector<Glyph>* out) {
  int prev = -1;
  for (int t = 0; t < steps; ++t) {
    const float* row = probs + size_t(t) * classes;
    const int best = int(std::max_element(row, row + classes) - row);
    if (best != prev && best != 0) out->push_back({best, row[best], t * stepPx, (t + 1) * stepPx});
    prev = best;
  }
}

int roundUp(int width) { return (width + kRecWidthStep - 1) / kRecWidthStep * kRecWidthStep; }

// The rec input width cropLine + resize will produce, from the quad alone (for ordering).
int paddedWidth(const Quad& q) {
  double w = int(std::max(cv::norm(q[0] - q[1]), cv::norm(q[2] - q[3])));
  double h = int(std::max(cv::norm(q[0] - q[3]), cv::norm(q[1] - q[2])));
  if (h / std::max(w, 1.0) >= 1.5) std::swap(w, h);
  return roundUp(std::max(kRecMinWidth, int(kRecHeight * w / h)));
}

bool isCancelled(const int32_t* cancel) {
  return cancel != nullptr && __atomic_load_n(cancel, __ATOMIC_RELAXED) != 0;
}

// Line weight in the flagged share: the quad's top edge, as T-032 measured it.
double topEdge(const Quad& q) { return std::max(1.0, double(cv::norm(q[1] - q[0]))); }

struct Page {
  std::vector<Line> lines;
  double flagged = 0;  // share of line width with kLowConfidence or kLowCoverage
  bool nonLatin = false;
};

class Engine {
 public:
  Net det;
  Net rec;  // width-dynamic 1x48xWx3
  std::vector<std::string> classes;  // index 0 is the CTC blank

  // stopIfNonLatin ends the read once the page is known to be non-Latin; its lines are then partial.
  int read(const cv::Mat& page, bool stopIfNonLatin, const int32_t* cancel, Page* out, Stats* stats) {
    auto t = Clock::now();
    const double scale = std::min(1.0, double(kDetSide) / std::max(page.cols, page.rows));
    TfLiteTensor* in = det.input();
    cv::Mat canvas(kDetSide, kDetSide, CV_32FC3, TfLiteTensorData(in));
    canvas.setTo(cv::Scalar((1 - kMean[0]) / kStd[0], (1 - kMean[1]) / kStd[1],
                            (1 - kMean[2]) / kStd[2]));
    cv::Mat resized;
    cv::resize(page, resized,
               cv::Size(std::max(1, int(std::lround(page.cols * scale))),
                        std::max(1, int(std::lround(page.rows * scale)))));
    cv::Mat roi = canvas(cv::Rect(0, 0, resized.cols, resized.rows));
    resized.convertTo(roi, CV_32FC3, 1 / 255.0);
    cv::subtract(roi, cv::Scalar(kMean[0], kMean[1], kMean[2]), roi);
    cv::divide(roi, cv::Scalar(kStd[0], kStd[1], kStd[2]), roi);
    stats->detPreMs = msSince(t);
    t = Clock::now();
    if (TfLiteInterpreterInvoke(det.interpreter) != kTfLiteOk) return CLV_ERR_INTERNAL;
    stats->detInferMs = msSince(t);
    t = Clock::now();
    const cv::Mat pred(kDetSide, kDetSide, CV_32F, TfLiteTensorData(det.output()));
    const std::vector<Quad> boxes = dbBoxes(pred, scale, page.cols, page.rows);
    stats->detPostMs = msSince(t);

    // Widest last, so the interpreter is resized once per distinct width.
    std::vector<int> widths(boxes.size());
    for (size_t i = 0; i < boxes.size(); ++i) widths[i] = paddedWidth(boxes[i]);
    std::vector<size_t> order(boxes.size());
    std::iota(order.begin(), order.end(), 0);
    std::stable_sort(order.begin(), order.end(), [&](size_t a, size_t b) { return widths[a] < widths[b]; });
    double total = 0, flagged = 0;
    for (const Quad& b : boxes) total += topEdge(b);
    std::vector<Line> lines(boxes.size());
    std::vector<bool> done(boxes.size());
    for (size_t i : order) {
      if (isCancelled(cancel)) return CLV_CANCELLED;
      t = Clock::now();
      bool rotated;
      const cv::Mat crop = cropLine(page, boxes[i], &rotated);
      const double ratio = double(crop.cols) / crop.rows;
      const int imgW = std::max(kRecMinWidth, int(kRecHeight * ratio));
      cv::Mat line;  // the reference's 48-px resize, unpadded
      cv::resize(crop, line, cv::Size(std::min(imgW, int(std::ceil(kRecHeight * ratio))), kRecHeight));
      stats->recPrepMs += msSince(t);
      std::vector<Glyph> glyphs;
      const int status = recognize(line, roundUp(imgW), &glyphs, stats);
      if (status != CLV_OK) return status;
      Line& l = lines[i];
      l.quad = boxes[i];
      buildLine(glyphs, line.cols, rotated, &l);
      done[i] = true;
      if (l.conf < kLowConfidence || l.coverage < kLowCoverage) flagged += topEdge(l.quad);
      if (stopIfNonLatin && flagged >= kNonLatinShare * total) break;
    }
    out->flagged = total > 0 ? flagged / total : 0;
    out->nonLatin = total > 0 && flagged >= kNonLatinShare * total;
    out->lines.clear();
    for (size_t i = 0; i < lines.size(); ++i) {
      if (done[i]) out->lines.push_back(std::move(lines[i]));
    }
    return CLV_OK;
  }

 private:
  int recognize(const cv::Mat& line, int width, std::vector<Glyph>* glyphs, Stats* stats) {
    auto t = Clock::now();
    if (rec.width != width) {
      if (!rec.resizeWidth(width)) return CLV_ERR_INTERNAL;
      ++stats->resizes;
    }
    stats->recResizeMs += msSince(t);
    TfLiteTensor* in = rec.input();
    cv::Mat input(kRecHeight, width, CV_32FC3, TfLiteTensorData(in));
    input.setTo(cv::Scalar::all(0));
    cv::Mat content = input(cv::Rect(0, 0, line.cols, kRecHeight));
    line.convertTo(content, CV_32FC3, 1 / 127.5, -1.0);
    t = Clock::now();
    if (TfLiteInterpreterInvoke(rec.interpreter) != kTfLiteOk) return CLV_ERR_INTERNAL;
    stats->recInferMs += msSince(t);
    t = Clock::now();
    const TfLiteTensor* out = rec.output();
    const int steps = TfLiteTensorDim(out, 1), classCount = TfLiteTensorDim(out, 2);
    if (classCount != int(classes.size())) return CLV_ERR_INTERNAL;
    ctcDecode(static_cast<const float*>(TfLiteTensorData(out)), steps, classCount, double(width) / steps,
              glyphs);
    stats->recDecodeMs += msSince(t);
    return CLV_OK;
  }

  // Text, mean glyph confidence, word boxes along the line quad (words split at spaces) and coverage.
  void buildLine(const std::vector<Glyph>& glyphs, int contentWidth, bool rotated, Line* line) {
    const Quad& q = line->quad;
    auto at = [&](double a, double b) { return q[0] + (q[1] - q[0]) * float(a) + (q[3] - q[0]) * float(b); };
    double sum = 0, wordSum = 0;
    int wordCount = 0;
    std::string word;
    double x0 = 0, x1 = 0;
    auto flush = [&] {
      if (word.empty()) return;
      const double a = std::clamp(x0 / contentWidth, 0.0, 1.0);
      const double b = std::clamp(x1 / contentWidth, 0.0, 1.0);
      line->words.push_back({word, wordSum / wordCount, {at(a, 0), at(b, 0), at(b, 1), at(a, 1)}});
      word.clear();
      wordSum = 0;
      wordCount = 0;
    };
    for (const Glyph& g : glyphs) {
      line->text += classes[g.cls];
      sum += g.prob;
      if (classes[g.cls] == " ") {
        flush();
        continue;
      }
      if (word.empty()) x0 = g.x0;
      word += classes[g.cls];
      wordSum += g.prob;
      ++wordCount;
      x1 = g.x1;
    }
    flush();
    line->conf = glyphs.empty() ? 0 : sum / glyphs.size();
    if (rotated) {
      // Column text has no reliable glyph positions: one word over the whole line, coverage 0 as T-032.
      line->words.clear();
      if (!line->text.empty()) line->words.push_back({line->text, line->conf, q});
      return;
    }
    double covered = 0;
    for (const Word& w : line->words) covered += cv::norm(w.quad[1] - w.quad[0]);
    line->coverage = covered / std::max(1.0, cv::norm(q[1] - q[0]));
  }
};

void appendJsonString(std::string* out, const std::string& s) {
  out->push_back('"');
  for (unsigned char c : s) {
    if (c == '"' || c == '\\') {
      out->push_back('\\');
      out->push_back(char(c));
    } else if (c < 0x20) {
      char buf[8];
      std::snprintf(buf, sizeof buf, "\\u%04x", c);
      out->append(buf);
    } else {
      out->push_back(char(c));
    }
  }
  out->push_back('"');
}

void appendQuad(std::string* out, const Quad& q) {
  char buf[96];
  std::snprintf(buf, sizeof buf, "[[%.1f,%.1f],[%.1f,%.1f],[%.1f,%.1f],[%.1f,%.1f]]", q[0].x, q[0].y,
                q[1].x, q[1].y, q[2].x, q[2].y, q[3].x, q[3].y);
  out->append(buf);
}

// The five entities Tesseract's HOcrEscape writes.
void appendHocrText(std::string* out, const std::string& s) {
  for (char c : s) {
    switch (c) {
      case '<': out->append("&lt;"); break;
      case '>': out->append("&gt;"); break;
      case '"': out->append("&quot;"); break;
      case '\'': out->append("&#39;"); break;
      case '&': out->append("&amp;"); break;
      default: out->push_back(c);
    }
  }
}

// "bbox l t r b": the quad's integer bounds inside the page, as Tesseract writes them.
std::string bbox(const Quad& q, int width, int height) {
  float l = q[0].x, t = q[0].y, r = q[0].x, b = q[0].y;
  for (const auto& p : q) {
    l = std::min(l, p.x);
    t = std::min(t, p.y);
    r = std::max(r, p.x);
    b = std::max(b, p.y);
  }
  char buf[64];
  std::snprintf(buf, sizeof buf, "bbox %d %d %d %d", std::clamp(int(std::floor(l)), 0, width),
                std::clamp(int(std::floor(t)), 0, height), std::clamp(int(std::ceil(r)), 0, width),
                std::clamp(int(std::ceil(b)), 0, height));
  return buf;
}

// hOCR in the shape of Tesseract's, so the app's one parser reads both engines.
std::string toHocr(const std::vector<Line>& lines, int width, int height) {
  std::string out = "<div class='ocr_page' id='page_1' title='bbox 0 0 " + std::to_string(width) + " " +
                    std::to_string(height) + "'>\n";
  int lineId = 0, wordId = 0;
  for (const Line& l : lines) {
    if (l.words.empty()) continue;
    out += " <span class='ocr_line' id='line_1_" + std::to_string(++lineId) + "' title='" +
           bbox(l.quad, width, height) + "'>";
    for (const Word& w : l.words) {
      out += "<span class='ocrx_word' id='word_1_" + std::to_string(++wordId) + "' title='" +
             bbox(w.quad, width, height) + "; x_wconf " +
             std::to_string(std::clamp(int(std::lround(w.conf * 100)), 0, 100)) + "'>";
      appendHocrText(&out, w.text);
      out += "</span> ";
    }
    out += "</span>\n";
  }
  out += "</div>\n";
  return out;
}

std::string toJson(const Engine& e, int width, int height, const Page& page, const Stats& s) {
  const std::vector<Line>& lines = page.lines;
  std::string text;
  for (const Line& l : lines) {
    if (l.text.empty()) continue;
    if (!text.empty()) text += '\n';
    text += l.text;
  }
  char head[128];
  std::snprintf(head, sizeof head,
                "{\"width\":%d,\"height\":%d,\"flagged\":%.4f,\"non_latin\":%s,\"text\":", width,
                height, page.flagged, page.nonLatin ? "true" : "false");
  std::string out = head;
  appendJsonString(&out, text);
  out += ",\"hocr\":";
  appendJsonString(&out, toHocr(lines, width, height));
  out += ",\"lines\":[";
  for (size_t i = 0; i < lines.size(); ++i) {
    const Line& l = lines[i];
    if (i > 0) out += ',';
    out += "{\"text\":";
    appendJsonString(&out, l.text);
    char conf[64];
    std::snprintf(conf, sizeof conf, ",\"conf\":%.4f,\"coverage\":%.4f,\"quad\":", l.conf, l.coverage);
    out += conf;
    appendQuad(&out, l.quad);
    out += ",\"words\":[";
    for (size_t k = 0; k < l.words.size(); ++k) {
      if (k > 0) out += ',';
      out += "{\"text\":";
      appendJsonString(&out, l.words[k].text);
      std::snprintf(conf, sizeof conf, ",\"conf\":%.4f,\"quad\":", l.words[k].conf);
      out += conf;
      appendQuad(&out, l.words[k].quad);
      out += '}';
    }
    out += "]}";
  }
  char stats[512];
  std::snprintf(stats, sizeof stats,
                "],\"stages\":{\"decode_ms\":%.1f,\"det_pre_ms\":%.1f,\"det_infer_ms\":%.1f,"
                "\"det_post_ms\":%.1f,\"det_total_ms\":%.1f,\"rec_prep_ms\":%.1f,\"rec_infer_ms\":%.1f,"
                "\"rec_resize_ms\":%.1f,\"rec_decode_ms\":%.1f,\"rec_total_ms\":%.1f,\"resizes\":%d,"
                "\"boxes\":%zu,\"det_fp16\":%d,\"rec_fp16\":%d}}",
                s.decodeMs, s.detPreMs, s.detInferMs, s.detPostMs,
                s.decodeMs + s.detPreMs + s.detInferMs + s.detPostMs, s.recPrepMs, s.recInferMs,
                s.recResizeMs, s.recDecodeMs, s.recPrepMs + s.recInferMs + s.recResizeMs + s.recDecodeMs,
                s.resizes, lines.size(), int(e.det.fp16), int(e.rec.fp16));
  out += stats;
  return out;
}

}  // namespace

struct clv_ocr {
  Engine engine;
};

clv_ocr* clv_ocr_create(const uint8_t* det, int32_t det_length, const uint8_t* rec,
                        int32_t rec_length, const char* dict, int32_t dict_length, int32_t fp16,
                        int32_t threads) {
  if (det == nullptr || det_length <= 0 || rec == nullptr || rec_length <= 0 || dict == nullptr ||
      dict_length <= 0 || threads <= 0) {
    return nullptr;
  }
  auto* ocr = new clv_ocr();
  Engine& e = ocr->engine;
  e.classes.emplace_back();  // CTC blank
  const std::string all(dict, size_t(dict_length));
  for (size_t at = 0; at <= all.size();) {
    const size_t nl = std::min(all.find('\n', at), all.size());
    if (nl > at) e.classes.push_back(all.substr(at, nl - at));
    at = nl + 1;
  }
  e.classes.push_back(" ");
  const bool ok = e.det.load(det, det_length, fp16 != 0, threads) &&
                  TfLiteTensorDim(e.det.input(), 1) == kDetSide &&
                  TfLiteTensorDim(e.det.input(), 2) == kDetSide &&
                  e.rec.load(rec, rec_length, fp16 != 0, threads);
  if (!ok) {
    delete ocr;
    return nullptr;
  }
  return ocr;
}

void clv_ocr_destroy(clv_ocr* ocr) { delete ocr; }

int32_t clv_ocr_read(clv_ocr* ocr, const uint8_t* encoded, int32_t length, int32_t stop_if_non_latin,
                     const int32_t* cancel, char** json_out, int32_t* json_length_out) {
  if (ocr == nullptr || encoded == nullptr || length <= 0 || json_out == nullptr ||
      json_length_out == nullptr) {
    return CLV_ERR_INVALID_ARGUMENT;
  }
  try {
    Stats stats;
    auto t = Clock::now();
    const cv::Mat page =
        cv::imdecode(cv::Mat(1, length, CV_8U, const_cast<uint8_t*>(encoded)), cv::IMREAD_COLOR);
    if (page.empty()) return CLV_ERR_DECODE;
    stats.decodeMs = msSince(t);
    Page result;
    const int status = ocr->engine.read(page, stop_if_non_latin != 0, cancel, &result, &stats);
    if (status != CLV_OK) return status;
    const std::string json = toJson(ocr->engine, page.cols, page.rows, result, stats);
    auto* buffer = static_cast<char*>(std::malloc(json.size()));
    if (buffer == nullptr) return CLV_ERR_INTERNAL;
    std::memcpy(buffer, json.data(), json.size());
    *json_out = buffer;
    *json_length_out = int32_t(json.size());
    return CLV_OK;
  } catch (const std::exception&) {
    return CLV_ERR_INTERNAL;
  }
}
