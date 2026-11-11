#include <jni.h>

#include <cstdlib>
#include <cstring>

#include "clvision.h"

// Returns the format name, a NUL, then the UTF-8 text, or null when the frame has no code.
// Bytes, not a jstring: NewStringUTF takes modified UTF-8 and aborts on emoji or embedded NULs.
extern "C" JNIEXPORT jbyteArray JNICALL Java_com_bnwise_cleanleaf_vision_ClVision_decodeCodes(
    JNIEnv* env, jclass, jobject y, jint width, jint height, jint y_row_stride,
    jint rotation_degrees, jint formats) {
  const auto* luma = static_cast<const uint8_t*>(env->GetDirectBufferAddress(y));
  if (luma == nullptr) return nullptr;
  const clv_yuv_frame frame{luma, nullptr, nullptr, width, height, y_row_stride, 0, 0,
                            rotation_degrees};
  clv_code code{};
  if (clv_decode_frame_codes(&frame, formats, &code) != CLV_OK) return nullptr;
  const auto name_length = static_cast<jsize>(std::strlen(code.format));
  jbyteArray out = env->NewByteArray(name_length + 1 + code.text_length);
  if (out != nullptr) {
    const jbyte separator = 0;
    env->SetByteArrayRegion(out, 0, name_length, reinterpret_cast<const jbyte*>(code.format));
    env->SetByteArrayRegion(out, name_length, 1, &separator);
    env->SetByteArrayRegion(out, name_length + 1, code.text_length,
                            reinterpret_cast<const jbyte*>(code.text));
  }
  clv_free(code.text);
  return out;
}
