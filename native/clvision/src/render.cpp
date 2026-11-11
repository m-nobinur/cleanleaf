#include <opencv2/core.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <vector>

#include "clvision.h"

namespace {

// OpenCV kernels must be odd; below 3 they do nothing.
int oddKernel(double size) { return std::max(3, int(size) | 1); }

double distance(cv::Point2f a, cv::Point2f b) { return std::hypot(a.x - b.x, a.y - b.y); }

// Corners in pixels of an image of `size`, edge convention (0..cols, 0..rows).
void toPixels(const float* quad, cv::Size size, cv::Point2f out[4]) {
  for (int i = 0; i < 4; ++i) out[i] = {quad[2 * i] * size.width, quad[2 * i + 1] * size.height};
}

// The page's own size: the longer of each pair of opposite edges.
cv::Size2d naturalSize(const cv::Point2f q[4]) {
  return {std::max(distance(q[0], q[1]), distance(q[3], q[2])),
          std::max(distance(q[0], q[3]), distance(q[1], q[2]))};
}

cv::Size outputSize(cv::Size2d natural, float aspect, int maxLongSide) {
  double w = natural.width, h = natural.height;
  if (aspect > 0) {  // keep the long side, snap the short one
    if (w >= h) {
      h = w / aspect;
    } else {
      w = h / aspect;
    }
  }
  const double longSide = std::max(w, h);
  if (maxLongSide > 0 && longSide > maxLongSide) {
    w *= maxLongSide / longSide;
    h *= maxLongSide / longSide;
  }
  return {std::max(1, int(std::lround(w))), std::max(1, int(std::lround(h)))};
}

// How far a page turned `degrees` must be enlarged to cover its own frame: the frame turned
// back must fit inside the enlarged page.
double fillScale(cv::Size size, double degrees) {
  const double a = degrees * CV_PI / 180, c = std::abs(std::cos(a)), s = std::abs(std::sin(a));
  const double wh = double(size.width) / size.height;
  return std::max(c + s / wh, c + s * wh);
}

// The warp step: flattens the quad to `size`, turns it `rotation` degrees clockwise and then
// `straighten` degrees about its centre, all in one resampling pass. Phase 2 anchors (Coons
// patch) replace this with a remap over the same inputs.
cv::Mat flatten(const cv::Mat& src, const float* quad, cv::Size size, int rotation,
                double straighten) {
  if (rotation % 180 != 0) size = {size.height, size.width};
  cv::Point2f s[4];
  toPixels(quad, src.size(), s);
  // Edge to pixel-centre convention, on both sides, so a full-frame quad is an identity.
  const float w = float(size.width) - 0.5f, h = float(size.height) - 0.5f;
  const cv::Point2f out[4] = {{-0.5f, -0.5f}, {w, -0.5f}, {w, h}, {-0.5f, h}};
  cv::Point2f d[4];
  for (int i = 0; i < 4; ++i) {
    s[i] -= cv::Point2f(0.5f, 0.5f);
    d[i] = out[(i + rotation / 90) % 4];  // each quarter turn moves a corner one place on
  }
  cv::Mat transform = cv::getPerspectiveTransform(s, d);
  if (straighten != 0) {
    cv::Mat turn = cv::Mat::eye(3, 3, CV_64F);
    const cv::Point2f centre((size.width - 1) * 0.5f, (size.height - 1) * 0.5f);
    // OpenCV's positive angle turns counter-clockwise.
    cv::getRotationMatrix2D(centre, -straighten, fillScale(size, straighten))
        .copyTo(turn.rowRange(0, 2));
    transform = turn * transform;
  }
  cv::Mat page;
  cv::warpPerspective(src, page, transform, size, cv::INTER_CUBIC, cv::BORDER_REPLICATE);
  return page;
}

// A background far darker than the paper is content (a dark band, logo or box), not shadow:
// fade it to the paper colour so division keeps its tone instead of amplifying its noise.
// Shadows down to half the paper brightness are still removed fully.
void keepDarkContent(cv::Mat& bg) {
  cv::Mat maxes, luma, weight, blended;
  cv::reduce(bg.reshape(1, int(bg.total())), maxes, 0, cv::REDUCE_MAX);
  cv::Scalar paper;
  for (int c = 0; c < bg.channels(); ++c) paper[c] = maxes.at<uint8_t>(c);
  if (bg.channels() == 3) {
    cv::cvtColor(bg, luma, cv::COLOR_BGR2GRAY);
  } else {
    luma = bg;
  }
  double paperLuma = 0;
  cv::minMaxLoc(luma, nullptr, &paperLuma);
  constexpr double kContent = 0.35, kShadow = 0.5;
  luma.convertTo(weight, CV_32F, 1 / (paperLuma * (kShadow - kContent) + 1e-6),
                 -kContent / (kShadow - kContent));
  cv::min(cv::max(weight, 0), 1, weight);
  if (bg.channels() == 3) cv::merge(std::vector<cv::Mat>(3, weight), weight);
  bg.convertTo(blended, CV_32F);
  blended = (blended - paper).mul(weight) + paper;
  blended.convertTo(bg, CV_8U);
}

// Paper colour per pixel: close away the ink on an eighth-size copy, blur, scale back up.
cv::Mat background(const cv::Mat& page) {
  cv::Mat small, bg;
  cv::resize(page, small, {std::max(1, page.cols / 8), std::max(1, page.rows / 8)}, 0, 0,
             cv::INTER_AREA);
  const int k = oddKernel(std::min(small.cols, small.rows) / 20.0);
  cv::morphologyEx(small, bg, cv::MORPH_CLOSE,
                   cv::getStructuringElement(cv::MORPH_ELLIPSE, {k, k}), {-1, -1}, 1,
                   cv::BORDER_REPLICATE);
  cv::GaussianBlur(bg, bg, {k, k}, 0);
  keepDarkContent(bg);
  cv::resize(bg, bg, page.size(), 0, 0, cv::INTER_LINEAR);
  return bg;
}

// Shadow removal and white balance in one step: paper becomes white.
void divideBackground(cv::Mat& page) { cv::divide(page, background(page), page, 255); }

// Stretches luma [black, 240] to [0, 255]; black is the 1st percentile, capped so a sparse
// page whose percentile lands on paper still keeps its mid-tones.
void levels(cv::Mat& page) {
  cv::Mat sample;
  cv::resize(page, sample, {std::max(1, page.cols / 4), std::max(1, page.rows / 4)}, 0, 0,
             cv::INTER_NEAREST);
  if (sample.channels() == 3) cv::cvtColor(sample, sample, cv::COLOR_BGR2GRAY);
  int histogram[256] = {};
  for (int y = 0; y < sample.rows; ++y) {
    const uint8_t* row = sample.ptr<uint8_t>(y);
    for (int x = 0; x < sample.cols; ++x) ++histogram[row[x]];
  }
  const int target = int(sample.total() / 100);
  int black = 0;
  for (int count = 0; black < 255 && (count += histogram[black]) <= target;) ++black;
  black = std::min(black, 96);
  constexpr int kWhite = 240;
  cv::Mat lut(1, 256, CV_8U);
  for (int v = 0; v < 256; ++v) {
    lut.at<uint8_t>(v) = cv::saturate_cast<uint8_t>((v - black) * 255.0 / (kWhite - black));
  }
  cv::LUT(page, lut, page);
}

// Pushes colours away from (amount > 0) or towards (amount < 0, -1 is grey) their luma.
void saturate(cv::Mat& page, double amount) {
  cv::Mat gray;
  cv::cvtColor(page, gray, cv::COLOR_BGR2GRAY);
  cv::cvtColor(gray, gray, cv::COLOR_GRAY2BGR);
  cv::addWeighted(page, 1 + amount, gray, -amount, 0, page);
}

// Sharpens for amount > 0, blurs towards the Gaussian at -1. Sigma follows the page size so a
// capped preview looks like the full render.
void unsharp(cv::Mat& page, double amount) {
  const double sigma = std::max(0.8, std::min(page.cols, page.rows) / 2000.0);
  cv::Mat blurred;
  cv::GaussianBlur(page, blurred, {0, 0}, sigma);
  cv::addWeighted(page, 1 + amount, blurred, -amount, 0, page);
}

// Brightness and contrast as one lookup: a gamma curve, then a gain about mid-grey. Both
// scale by up to 2^1.5 either way.
void tone(cv::Mat& page, double brightness, double contrast) {
  const double gamma = std::pow(2.0, -1.5 * brightness), gain = std::pow(2.0, 1.5 * contrast);
  cv::Mat lut(1, 256, CV_8U);
  for (int v = 0; v < 256; ++v) {
    const double x = std::pow(v / 255.0, gamma);
    lut.at<uint8_t>(v) = cv::saturate_cast<uint8_t>(((x - 0.5) * gain + 0.5) * 255);
  }
  cv::LUT(page, lut, page);
}

// The manual adjustments, after the filter. A binary B&W page has no tone to shift and would
// only grow grey edges, so it keeps none of them.
void adjust(cv::Mat& page, const clv_render_params& p) {
  if (p.filter == CLV_FILTER_BLACK_WHITE) return;
  if (p.brightness != 0 || p.contrast != 0) tone(page, p.brightness, p.contrast);
  if (p.saturation != 0 && page.channels() == 3) saturate(page, p.saturation);
  if (p.sharpness != 0) unsharp(page, p.sharpness > 0 ? 1.5 * p.sharpness : p.sharpness);
}

// Drops ink blobs too small to be a full stop at this page size.
void removeSpecks(cv::Mat& bw) {
  const double side = std::min(bw.cols, bw.rows) / 1000.0;
  const int maxArea = std::max(2, int(side * side));
  cv::Mat ink, labels, stats, centroids;
  cv::bitwise_not(bw, ink);
  const int n = cv::connectedComponentsWithStats(ink, labels, stats, centroids, 8, CV_32S);
  std::vector<uint8_t> speck(n, 0);
  bool any = false;
  for (int i = 1; i < n; ++i) {
    speck[i] = stats.at<int>(i, cv::CC_STAT_AREA) <= maxArea;
    any = any || speck[i];
  }
  if (!any) return;
  for (int y = 0; y < bw.rows; ++y) {
    const int* label = labels.ptr<int>(y);
    uint8_t* row = bw.ptr<uint8_t>(y);
    for (int x = 0; x < bw.cols; ++x) {
      if (speck[label[x]]) row[x] = 255;
    }
  }
}

// cv::adaptiveThreshold (Gaussian, THRESH_BINARY) with the local mean taken at quarter size
// for large blocks: the mean is smooth at that scale, and the full-size blur was the slowest
// step of the whole render.
void gaussianAdaptiveThreshold(cv::Mat& page, int block, double c) {
  const double sigma = 0.3 * ((block - 1) * 0.5 - 1) + 0.8;  // OpenCV's sigma for this block
  const int f = block >= 33 ? 4 : 1;
  cv::Mat mean;
  cv::resize(page, mean, {std::max(1, page.cols / f), std::max(1, page.rows / f)}, 0, 0,
             cv::INTER_AREA);
  cv::GaussianBlur(mean, mean, {0, 0}, sigma / f, 0, cv::BORDER_REPLICATE);
  cv::resize(mean, mean, page.size(), 0, 0, cv::INTER_LINEAR);
  cv::subtract(mean, cv::Scalar::all(c), mean);
  cv::compare(page, mean, page, cv::CMP_GT);
}

// Adaptive threshold finds ink at any shading but hollows strokes wider than about block/7,
// so deep-dark areas of the shadow-free page are filled in as ink too. The fill stays below
// 0.35 * 255, where keepDarkContent leaves the deepest shadowed paper, so shadows stay white.
void blackWhite(cv::Mat& page) {
  cv::Mat solid = page.clone();
  divideBackground(solid);
  cv::threshold(solid, solid, 80, 255, cv::THRESH_BINARY);
  gaussianAdaptiveThreshold(page, oddKernel(std::min(page.cols, page.rows) / 40.0), 12);
  cv::bitwise_and(page, solid, page);
  removeSpecks(page);
}

void applyFilter(cv::Mat& page, int filter) {
  switch (filter) {
    case CLV_FILTER_ENHANCED_COLOR:
      divideBackground(page);
      levels(page);
      saturate(page, 0.3);
      unsharp(page, 0.6);
      break;
    case CLV_FILTER_GRAYSCALE:
      divideBackground(page);
      levels(page);
      unsharp(page, 0.6);
      break;
    case CLV_FILTER_BLACK_WHITE:
      blackWhite(page);
      break;
    default:
      break;
  }
}

int32_t encode(const cv::Mat& image, bool png, uint8_t** out, int32_t* length) {
  std::vector<uchar> buf;
  const bool encoded = png ? cv::imencode(".png", image, buf)
                           : cv::imencode(".jpg", image, buf,
                                          {cv::IMWRITE_JPEG_QUALITY, CLV_JPEG_QUALITY});
  if (!encoded) return CLV_ERR_ENCODE;
  auto* copy = static_cast<uint8_t*>(std::malloc(buf.size()));
  if (copy == nullptr) return CLV_ERR_INTERNAL;
  std::memcpy(copy, buf.data(), buf.size());
  *out = copy;
  *length = int32_t(buf.size());
  return CLV_OK;
}

// Decoding applies the EXIF orientation, matching the space corners are stored in.
cv::Mat decode(const uint8_t* encoded, int32_t length, int flags) {
  return cv::imdecode(cv::Mat(1, length, CV_8U, const_cast<uint8_t*>(encoded)), flags);
}

// Also false for NaN.
bool within(float value, float limit) { return std::abs(value) <= limit; }

bool validAdjustments(const clv_render_params& p) {
  return within(p.brightness, 1) && within(p.contrast, 1) && within(p.saturation, 1) &&
         within(p.sharpness, 1) && within(p.straighten_degrees, 45) &&
         (p.encode_png == 0 || p.encode_png == 1);
}

bool validQuad(const float* quad) {
  for (int i = 0; i < 8; ++i) {
    if (!(quad[i] >= 0.f && quad[i] <= 1.f)) return false;  // also rejects NaN
  }
  return true;
}

int32_t renderPage(const uint8_t* encoded, int32_t length, const float* quad,
                   const clv_render_params& params, uint8_t** out, int32_t* outLength) {
  const int rotation = ((params.rotation_degrees % 360) + 360) % 360;
  if (params.filter < CLV_FILTER_ORIGINAL || params.filter > CLV_FILTER_BLACK_WHITE ||
      rotation % 90 != 0 || !(params.aspect_ratio == 0.f || params.aspect_ratio >= 1.f) ||
      std::isinf(params.aspect_ratio) || params.max_long_side < 0 || !validQuad(quad) ||
      !validAdjustments(params)) {
    return CLV_ERR_INVALID_ARGUMENT;
  }
  const bool gray =
      params.filter == CLV_FILTER_GRAYSCALE || params.filter == CLV_FILTER_BLACK_WHITE;
  cv::Mat src = decode(encoded, length, gray ? cv::IMREAD_GRAYSCALE : cv::IMREAD_COLOR);
  if (src.empty()) return CLV_ERR_DECODE;

  cv::Point2f corners[4];
  toPixels(quad, src.size(), corners);
  const cv::Size2d natural = naturalSize(corners);
  if (natural.width < 2 || natural.height < 2 ||
      !cv::isContourConvex(std::vector<cv::Point2f>(corners, corners + 4))) {
    return CLV_ERR_INVALID_ARGUMENT;
  }
  const cv::Size size = outputSize(natural, params.aspect_ratio, params.max_long_side);
  const double straighten = params.straighten_degrees;
  // Cubic sampling aliases when it shrinks a lot, so shrink the source by area first.
  const double scale = std::max(size.width / natural.width, size.height / natural.height) *
                       (straighten != 0 ? fillScale(size, straighten) : 1);
  if (scale < 0.5) cv::resize(src, src, {}, scale, scale, cv::INTER_AREA);

  cv::Mat page = flatten(src, quad, size, rotation, straighten);
  src.release();
  applyFilter(page, params.filter);
  adjust(page, params);
  return encode(page, params.encode_png == 1, out, outLength);
}

int32_t thumbnail(const uint8_t* encoded, int32_t length, int32_t maxSide, uint8_t** out,
                  int32_t* outLength) {
  // ANYCOLOR keeps a grayscale render single-channel; unlike UNCHANGED it still applies EXIF.
  cv::Mat image = decode(encoded, length, cv::IMREAD_ANYCOLOR);
  if (image.empty()) return CLV_ERR_DECODE;
  const double scale = double(maxSide) / std::max(image.cols, image.rows);
  if (scale < 1) {
    const cv::Size size(std::max(1, int(std::lround(image.cols * scale))),
                        std::max(1, int(std::lround(image.rows * scale))));
    cv::resize(image, image, size, 0, 0, cv::INTER_AREA);
  }
  return encode(image, false, out, outLength);
}

template <typename F>
int32_t guarded(F&& run) {
  try {
    return run();
  } catch (const std::exception&) {  // cv::Exception, bad_alloc
    return CLV_ERR_INTERNAL;
  }
}

}  // namespace

int32_t clv_render_page(const uint8_t* encoded, int32_t length, const float* quad,
                        const clv_render_params* params, uint8_t** jpeg_out,
                        int32_t* jpeg_length_out) {
  if (encoded == nullptr || length <= 0 || quad == nullptr || params == nullptr ||
      jpeg_out == nullptr || jpeg_length_out == nullptr) {
    return CLV_ERR_INVALID_ARGUMENT;
  }
  return guarded(
      [&] { return renderPage(encoded, length, quad, *params, jpeg_out, jpeg_length_out); });
}

int32_t clv_thumbnail(const uint8_t* encoded, int32_t length, int32_t max_side,
                      uint8_t** jpeg_out, int32_t* jpeg_length_out) {
  if (encoded == nullptr || length <= 0 || max_side <= 0 || jpeg_out == nullptr ||
      jpeg_length_out == nullptr) {
    return CLV_ERR_INVALID_ARGUMENT;
  }
  return guarded([&] { return thumbnail(encoded, length, max_side, jpeg_out, jpeg_length_out); });
}
