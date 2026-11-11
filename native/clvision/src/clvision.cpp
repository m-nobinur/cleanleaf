// Candidate B: the shared spike algorithm as a C++ core, called from Dart
// (FFI) and Kotlin (JNI) through one shared library.
#include <opencv2/core.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#define CLV_API extern "C" __attribute__((visibility("default")))

namespace {

constexpr int kFrameLongSide = 480;

using Clock = std::chrono::steady_clock;

double lapMs(Clock::time_point& t) {
  const auto now = Clock::now();
  const double ms = std::chrono::duration<double, std::milli>(now - t).count();
  t = now;
  return ms;
}

// TL, TR, BR, BL by coordinate sum and difference; ties keep the earlier point.
void orderCorners(const std::vector<cv::Point2f>& p, float* out) {
  auto pick = [&](auto key, bool wantMax) {
    cv::Point2f best = p[0];
    for (size_t i = 1; i < p.size(); ++i) {
      const bool better = wantMax ? key(p[i]) > key(best) : key(p[i]) < key(best);
      if (better) best = p[i];
    }
    return best;
  };
  auto sum = [](const cv::Point2f& a) { return a.x + a.y; };
  auto diff = [](const cv::Point2f& a) { return a.x - a.y; };
  const cv::Point2f ordered[4] = {pick(sum, false), pick(diff, true),
                                  pick(sum, true), pick(diff, false)};
  for (int i = 0; i < 4; ++i) {
    out[2 * i] = ordered[i].x;
    out[2 * i + 1] = ordered[i].y;
  }
}

bool detect(const cv::Mat& src, float* corners) {
  const double scale = double(kFrameLongSide) / std::max(src.cols, src.rows);
  cv::Mat small, blurred, edges, dilated;
  cv::resize(src, small,
             cv::Size(int(std::lround(src.cols * scale)), int(std::lround(src.rows * scale))),
             0, 0, cv::INTER_AREA);
  cv::GaussianBlur(small, blurred, cv::Size(5, 5), 0);
  cv::Canny(blurred, edges, 50, 150);
  cv::dilate(edges, dilated, cv::getStructuringElement(cv::MORPH_RECT, cv::Size(3, 3)),
             cv::Point(-1, -1), 1, cv::BORDER_REPLICATE);
  std::vector<std::vector<cv::Point>> contours;
  cv::findContours(dilated, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);
  const double minArea = 0.1 * small.cols * small.rows;
  double bestArea = 0;
  std::vector<cv::Point> best, approx;
  for (const auto& c : contours) {
    const double area = cv::contourArea(c);
    if (area < minArea || area <= bestArea) continue;
    cv::approxPolyDP(c, approx, 0.02 * cv::arcLength(c, true), true);
    if (approx.size() == 4 && cv::isContourConvex(approx)) {
      bestArea = area;
      best = approx;
    }
  }
  if (best.empty()) return false;
  std::vector<cv::Point2f> pts;
  for (const auto& q : best) pts.emplace_back(float(q.x / scale), float(q.y / scale));
  orderCorners(pts, corners);
  return true;
}

// Shadow division: estimate the paper background on a 1/4 copy and divide.
cv::Mat enhance(const cv::Mat& img) {
  cv::Mat small, bg, bgBlur, bgFull, out;
  cv::resize(img, small, cv::Size(img.cols / 4, img.rows / 4), 0, 0, cv::INTER_AREA);
  const int k = (std::min(small.cols, small.rows) / 20) | 1;
  cv::morphologyEx(small, bg, cv::MORPH_CLOSE,
                   cv::getStructuringElement(cv::MORPH_ELLIPSE, cv::Size(k, k)),
                   cv::Point(-1, -1), 1, cv::BORDER_REPLICATE);
  cv::GaussianBlur(bg, bgBlur, cv::Size(k, k), 0);
  cv::resize(bgBlur, bgFull, img.size(), 0, 0, cv::INTER_LINEAR);
  cv::divide(img, bgFull, out, 255);
  return out;
}

uint8_t* copyOut(const std::vector<uchar>& buf) {
  auto* out = static_cast<uint8_t*>(std::malloc(buf.size()));
  std::memcpy(out, buf.data(), buf.size());
  return out;
}

// timings: decode, warp, enhance, encode (ms), then the output mean.
std::vector<uchar> still(const cv::Mat& jpeg, const float* corners, int outW, int outH,
                         double* timings) {
  auto t = Clock::now();
  const cv::Mat src = cv::imdecode(jpeg, cv::IMREAD_COLOR);
  timings[0] = lapMs(t);
  cv::Point2f s[4];
  for (int i = 0; i < 4; ++i) s[i] = {corners[2 * i], corners[2 * i + 1]};
  const cv::Point2f d[4] = {{0, 0}, {outW - 1.f, 0}, {outW - 1.f, outH - 1.f}, {0, outH - 1.f}};
  cv::Mat warped;
  cv::warpPerspective(src, warped, cv::getPerspectiveTransform(s, d), cv::Size(outW, outH),
                      cv::INTER_LINEAR, cv::BORDER_REPLICATE);
  timings[1] = lapMs(t);
  const cv::Mat enhanced = enhance(warped);
  timings[2] = lapMs(t);
  std::vector<uchar> buf;
  cv::imencode(".jpg", enhanced, buf);
  timings[3] = lapMs(t);
  const cv::Scalar m = cv::mean(enhanced);
  timings[4] = (m[0] + m[1] + m[2]) / 3;
  return buf;
}

}  // namespace

// Returns 1 and writes TL, TR, BR, BL (x, y) in source pixels when a page is found.
CLV_API int clv_detect_gray(const uint8_t* gray, int w, int h, int stride, float* corners) {
  return detect(cv::Mat(h, w, CV_8UC1, const_cast<uint8_t*>(gray), size_t(stride)), corners);
}

// Decode, warp to outW x outH, enhance, encode. Returns the JPEG size; free *out with clv_free.
CLV_API int clv_still_jpeg(const uint8_t* jpeg, int len, const float* corners, int outW,
                           int outH, uint8_t** out, double* timings) {
  const auto buf = still(cv::Mat(1, len, CV_8UC1, const_cast<uint8_t*>(jpeg)), corners, outW,
                         outH, timings);
  *out = copyOut(buf);
  return int(buf.size());
}

CLV_API int clv_encode_bgr_jpeg(const uint8_t* bgr, int w, int h, uint8_t** out) {
  std::vector<uchar> buf;
  cv::imencode(".jpg", cv::Mat(h, w, CV_8UC3, const_cast<uint8_t*>(bgr)), buf);
  *out = copyOut(buf);
  return int(buf.size());
}

CLV_API void clv_free(void* p) { std::free(p); }

CLV_API const char* clv_build_info() {
  static const std::string info = cv::getBuildInformation();
  return info.c_str();
}

CLV_API int clv_num_threads() { return cv::getNumThreads(); }

#ifdef __ANDROID__
#include <jni.h>

extern "C" JNIEXPORT jboolean JNICALL Java_com_bnwise_cleanleaf_visionspike_ClVision_detect(
    JNIEnv* env, jclass, jobject plane, jint w, jint h, jint stride, jfloatArray out) {
  auto* p = static_cast<uint8_t*>(env->GetDirectBufferAddress(plane));
  float c[8];
  const bool found = detect(cv::Mat(h, w, CV_8UC1, p, size_t(stride)), c);
  if (found) env->SetFloatArrayRegion(out, 0, 8, c);
  return found;
}

extern "C" JNIEXPORT jbyteArray JNICALL Java_com_bnwise_cleanleaf_visionspike_ClVision_stillJpeg(
    JNIEnv* env, jclass, jobject jpeg, jfloatArray corners, jint outW, jint outH,
    jdoubleArray timings) {
  auto* p = static_cast<uint8_t*>(env->GetDirectBufferAddress(jpeg));
  const auto len = int(env->GetDirectBufferCapacity(jpeg));
  float c[8];
  env->GetFloatArrayRegion(corners, 0, 8, c);
  double t[5];
  const auto buf = still(cv::Mat(1, len, CV_8UC1, p), c, outW, outH, t);
  env->SetDoubleArrayRegion(timings, 0, 5, t);
  jbyteArray result = env->NewByteArray(jsize(buf.size()));
  env->SetByteArrayRegion(result, 0, jsize(buf.size()), reinterpret_cast<const jbyte*>(buf.data()));
  return result;
}

extern "C" JNIEXPORT jstring JNICALL Java_com_bnwise_cleanleaf_visionspike_ClVision_buildInfo(
    JNIEnv* env, jclass) {
  return env->NewStringUTF(clv_build_info());
}

extern "C" JNIEXPORT jint JNICALL Java_com_bnwise_cleanleaf_visionspike_ClVision_numThreads(
    JNIEnv*, jclass) {
  return cv::getNumThreads();
}
#endif
