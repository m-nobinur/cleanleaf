#include <jni.h>

#include <string>

#include "clvision.h"

namespace {

// Pins a Java byte array for the duration of a call, read-only.
class Bytes {
 public:
  Bytes(JNIEnv* env, jbyteArray array)
      : env_(env), array_(array), data_(env->GetByteArrayElements(array, nullptr)) {}
  ~Bytes() { env_->ReleaseByteArrayElements(array_, data_, JNI_ABORT); }
  const uint8_t* data() const { return reinterpret_cast<const uint8_t*>(data_); }
  int32_t length() const { return env_->GetArrayLength(array_); }

 private:
  JNIEnv* env_;
  jbyteArray array_;
  jbyte* data_;
};

}  // namespace

// det and rec hold the .tflite files, dict the UTF-8 classes one per line. Returns the engine handle,
// or 0.
extern "C" JNIEXPORT jlong JNICALL Java_com_bnwise_cleanleaf_vision_ClVision_ocrCreate(
    JNIEnv* env, jclass, jbyteArray det, jbyteArray rec, jbyteArray dict, jboolean fp16,
    jint threads) {
  const Bytes d(env, det), r(env, rec), classes(env, dict);
  return reinterpret_cast<jlong>(clv_ocr_create(d.data(), d.length(), r.data(), r.length(),
                                                reinterpret_cast<const char*>(classes.data()),
                                                classes.length(), fp16 ? 1 : 0, threads));
}

extern "C" JNIEXPORT void JNICALL Java_com_bnwise_cleanleaf_vision_ClVision_ocrDestroy(JNIEnv*,
                                                                                    jclass,
                                                                                    jlong ocr) {
  clv_ocr_destroy(reinterpret_cast<clv_ocr*>(ocr));
}

// The UTF-8 JSON of clv_ocr_read; null when the int in cancel (a direct buffer) stopped it. Throws
// IllegalStateException on any other failure.
extern "C" JNIEXPORT jbyteArray JNICALL Java_com_bnwise_cleanleaf_vision_ClVision_ocrRead(
    JNIEnv* env, jclass, jlong ocr, jbyteArray encoded, jboolean stopIfNonLatin, jobject cancel) {
  char* json = nullptr;
  int32_t length = 0;
  int32_t status;
  {
    const Bytes page(env, encoded);
    status = clv_ocr_read(reinterpret_cast<clv_ocr*>(ocr), page.data(), page.length(),
                          stopIfNonLatin ? 1 : 0,
                          static_cast<const int32_t*>(env->GetDirectBufferAddress(cancel)), &json,
                          &length);
  }
  if (status == CLV_CANCELLED) return nullptr;
  if (status != CLV_OK) {
    env->ThrowNew(env->FindClass("java/lang/IllegalStateException"),
                  ("clv_ocr_read failed: " + std::to_string(status)).c_str());
    return nullptr;
  }
  jbyteArray out = env->NewByteArray(length);
  if (out != nullptr) env->SetByteArrayRegion(out, 0, length, reinterpret_cast<const jbyte*>(json));
  clv_free(json);
  return out;
}
