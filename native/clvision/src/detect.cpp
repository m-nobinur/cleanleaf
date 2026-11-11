#include <opencv2/core.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>

#include <algorithm>
#include <array>
#include <cmath>
#include <exception>
#include <vector>

#include "clvision.h"

// DocAligner post-processing as frozen in decisions.md D-11 (T-018 spike, model only).
namespace {

constexpr int kInput = CLV_MODEL_INPUT_SIZE;
constexpr int kHeatmap = CLV_MODEL_HEATMAP_SIZE;
constexpr float kThreshold = 0.3f;  // blob threshold and minimum channel peak
constexpr double kMinAreaFraction = 0.02;
const double kMaxAbsCos = std::cos(CV_PI / 6);  // corner angles within 30..150 degrees

using Quad = std::array<cv::Point2f, 4>;

// Centroid of the largest 8-connected blob at or above the threshold, normalized to the image:
// heatmap cell c covers [c, c + 1) / 128 of it.
bool blobCentroid(const cv::Mat& channel, cv::Point2f& out) {
  const cv::Mat mask = channel >= kThreshold;
  cv::Mat labels, stats, centroids;
  const int count = cv::connectedComponentsWithStats(mask, labels, stats, centroids, 8, CV_32S);
  if (count <= 1) return false;
  int best = 1;
  for (int i = 2; i < count; ++i) {
    if (stats.at<int>(i, cv::CC_STAT_AREA) > stats.at<int>(best, cv::CC_STAT_AREA)) best = i;
  }
  out = {float((centroids.at<double>(best, 0) + 0.5) / kHeatmap),
         float((centroids.at<double>(best, 1) + 0.5) / kHeatmap)};
  return true;
}

// Clockwise (y down) from the corner with the smallest x + y, the order of T-007 labels and D-31.
// Sorting by angle also untangles channels that swapped corners, as the spike did.
void sortClockwise(Quad& q) {
  const cv::Point2f c = (q[0] + q[1] + q[2] + q[3]) * 0.25f;
  std::sort(q.begin(), q.end(), [c](cv::Point2f a, cv::Point2f b) {
    return std::atan2(a.y - c.y, a.x - c.x) < std::atan2(b.y - c.y, b.x - c.x);
  });
  std::rotate(q.begin(), std::min_element(q.begin(), q.end(), [](cv::Point2f a, cv::Point2f b) {
                return a.x + a.y < b.x + b.y;
              }),
              q.end());
}

// Convex, corner angles within 30..150 degrees and at least 2% of the frame, measured in pixels
// of the upright image.
bool plausible(const Quad& q, cv::Size size) {
  std::vector<cv::Point2f> p;
  for (const cv::Point2f& corner : q) p.emplace_back(corner.x * size.width, corner.y * size.height);
  if (!cv::isContourConvex(p) || cv::contourArea(p) < kMinAreaFraction * size.area()) return false;
  for (int i = 0; i < 4; ++i) {
    const cv::Point2f a = p[(i + 3) % 4] - p[i], b = p[(i + 1) % 4] - p[i];
    const double cos = a.dot(b) / (cv::norm(a) * cv::norm(b) + 1e-9);
    if (std::abs(cos) > kMaxAbsCos) return false;
  }
  return true;
}

// `bgr` is the upright image stretched to the model input; `size` is its real size in pixels.
int32_t detect(const cv::Mat& bgr, cv::Size size, float* corners_out, float* confidence_out) {
  cv::Mat input;
  bgr.convertTo(input, CV_32FC3, 1.0 / 255);
  cv::Mat heatmaps(kHeatmap, kHeatmap, CV_32FC4);
  const int32_t status = clv_model_run(input.ptr<float>(), heatmaps.ptr<float>());
  if (status != CLV_OK) return status;
  std::vector<cv::Mat> channels;
  cv::split(heatmaps, channels);
  double confidence = 1;
  for (const cv::Mat& channel : channels) {
    double peak;
    cv::minMaxLoc(channel, nullptr, &peak);
    confidence = std::min(confidence, peak);
  }
  *confidence_out = float(confidence);
  Quad q;
  if (confidence < kThreshold) return CLV_NO_QUAD;
  for (int k = 0; k < 4; ++k) {
    if (!blobCentroid(channels[k], q[k])) return CLV_NO_QUAD;
  }
  sortClockwise(q);
  if (!plausible(q, size)) return CLV_NO_QUAD;
  for (int k = 0; k < 4; ++k) {
    corners_out[2 * k] = q[k].x;
    corners_out[2 * k + 1] = q[k].y;
  }
  return CLV_OK;
}

bool validFrame(const clv_yuv_frame* f) {
  if (f == nullptr || f->y == nullptr || f->u == nullptr || f->v == nullptr) return false;
  const int chromaWidth = (f->width + 1) / 2;
  return f->width >= 2 && f->height >= 2 && f->y_row_stride >= f->width &&
         f->uv_pixel_stride >= 1 &&
         f->uv_row_stride >= (chromaWidth - 1) * f->uv_pixel_stride + 1 &&
         f->rotation_degrees >= 0 && f->rotation_degrees < 360 && f->rotation_degrees % 90 == 0;
}

}  // namespace

int32_t clv_detect_frame(const clv_yuv_frame* frame, float* corners_out, float* confidence_out) {
  if (!validFrame(frame) || corners_out == nullptr || confidence_out == nullptr) {
    return CLV_ERR_INVALID_ARGUMENT;
  }
  try {
    const clv_yuv_frame& f = *frame;
    const cv::Mat y(f.height, f.width, CV_8UC1, const_cast<uint8_t*>(f.y), f.y_row_stride);
    // Gathered sample by sample: with pixel stride 2 each chroma buffer ends one byte short of a
    // full interleaved row, so it can't be wrapped as a 2-channel Mat.
    const int chromaWidth = (f.width + 1) / 2, chromaHeight = (f.height + 1) / 2;
    cv::Mat cr(chromaHeight, chromaWidth, CV_8UC1), cb(chromaHeight, chromaWidth, CV_8UC1);
    for (int row = 0; row < chromaHeight; ++row) {
      const uint8_t* u = f.u + row * f.uv_row_stride;
      const uint8_t* v = f.v + row * f.uv_row_stride;
      uint8_t* crRow = cr.ptr<uint8_t>(row);
      uint8_t* cbRow = cb.ptr<uint8_t>(row);
      for (int col = 0; col < chromaWidth; ++col) {
        crRow[col] = v[col * f.uv_pixel_stride];
        cbRow[col] = u[col * f.uv_pixel_stride];
      }
    }
    // Downscale first, then convert: the stretch to 256x256 commutes with the colour conversion
    // and the rotation, so only the model input is converted and turned.
    const cv::Size input(kInput, kInput);
    cv::Mat planes[3];
    cv::resize(y, planes[0], input, 0, 0, cv::INTER_LINEAR);
    cv::resize(cr, planes[1], input, 0, 0, cv::INTER_LINEAR);
    cv::resize(cb, planes[2], input, 0, 0, cv::INTER_LINEAR);
    cv::Mat ycrcb, bgr;
    cv::merge(planes, 3, ycrcb);
    // Full-range BT.601 (JFIF), the camera's YUV and the JPEG still alike.
    cv::cvtColor(ycrcb, bgr, cv::COLOR_YCrCb2BGR);
    cv::Size upright(f.width, f.height);
    if (f.rotation_degrees != 0) {
      const int turn = f.rotation_degrees == 90    ? cv::ROTATE_90_CLOCKWISE
                       : f.rotation_degrees == 180 ? cv::ROTATE_180
                                                   : cv::ROTATE_90_COUNTERCLOCKWISE;
      cv::rotate(bgr, bgr, turn);
      if (f.rotation_degrees != 180) upright = {f.height, f.width};
    }
    return detect(bgr, upright, corners_out, confidence_out);
  } catch (const std::exception&) {  // cv::Exception, bad_alloc
    return CLV_ERR_INTERNAL;
  }
}

int32_t clv_detect_image(const uint8_t* encoded, int32_t length, float* corners_out,
                         float* confidence_out) {
  if (encoded == nullptr || length <= 0 || corners_out == nullptr || confidence_out == nullptr) {
    return CLV_ERR_INVALID_ARGUMENT;
  }
  try {
    // IMREAD_COLOR applies the EXIF orientation, so corners land in the frame D-31 stores.
    const cv::Mat image =
        cv::imdecode(cv::Mat(1, length, CV_8U, const_cast<uint8_t*>(encoded)), cv::IMREAD_COLOR);
    if (image.empty()) return CLV_ERR_DECODE;
    cv::Mat bgr;
    cv::resize(image, bgr, cv::Size(kInput, kInput), 0, 0, cv::INTER_LINEAR);
    return detect(bgr, image.size(), corners_out, confidence_out);
  } catch (const std::exception&) {
    return CLV_ERR_INTERNAL;
  }
}
