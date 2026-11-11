#include <jni.h>

#include "clvision.h"

namespace {

const uint8_t* address(JNIEnv* env, jobject buffer) {
  return static_cast<const uint8_t*>(env->GetDirectBufferAddress(buffer));
}

}  // namespace

// The planes are the direct buffers of an ImageProxy; out receives 8 normalized
// corner floats followed by the confidence.
extern "C" JNIEXPORT jint JNICALL Java_com_bnwise_cleanleaf_vision_ClVision_detectFrame(
    JNIEnv* env, jclass, jobject y, jobject u, jobject v, jint width, jint height,
    jint y_row_stride, jint uv_row_stride, jint uv_pixel_stride, jint rotation_degrees,
    jfloatArray out) {
  const clv_yuv_frame frame{address(env, y), address(env, u),  address(env, v),
                            width,           height,           y_row_stride,
                            uv_row_stride,   uv_pixel_stride,  rotation_degrees};
  if (frame.y == nullptr || frame.u == nullptr || frame.v == nullptr ||
      env->GetArrayLength(out) < 9) {
    return CLV_ERR_INVALID_ARGUMENT;
  }
  float result[9];
  const int32_t status = clv_detect_frame(&frame, result, result + 8);
  if (status == CLV_OK) env->SetFloatArrayRegion(out, 0, 9, result);
  return status;
}
