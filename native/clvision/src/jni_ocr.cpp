#include <jni.h>

#include <cstdlib>
#include <vector>

#include "clvision.h"

// det and every entry of recs are direct ByteBuffers holding .tflite files; dict is UTF-8.
// Returns the engine handle, or 0.
extern "C" JNIEXPORT jlong JNICALL Java_com_bnwise_cleanleaf_vision_ClVision_ocrCreate(
    JNIEnv* env, jclass, jobject det, jobjectArray recs, jbyteArray dict, jboolean fp16,
    jint threads) {
  const jsize count = env->GetArrayLength(recs);
  std::vector<const uint8_t*> recBytes;
  std::vector<int32_t> recLengths;
  for (jsize i = 0; i < count; ++i) {
    jobject buffer = env->GetObjectArrayElement(recs, i);
    recBytes.push_back(static_cast<const uint8_t*>(env->GetDirectBufferAddress(buffer)));
    recLengths.push_back(static_cast<int32_t>(env->GetDirectBufferCapacity(buffer)));
    env->DeleteLocalRef(buffer);
  }
  jbyte* dictBytes = env->GetByteArrayElements(dict, nullptr);
  clv_ocr* ocr = clv_ocr_create(static_cast<const uint8_t*>(env->GetDirectBufferAddress(det)),
                                static_cast<int32_t>(env->GetDirectBufferCapacity(det)),
                                recBytes.data(), recLengths.data(), count,
                                reinterpret_cast<const char*>(dictBytes),
                                env->GetArrayLength(dict), fp16 ? 1 : 0, threads);
  env->ReleaseByteArrayElements(dict, dictBytes, JNI_ABORT);
  return reinterpret_cast<jlong>(ocr);
}

extern "C" JNIEXPORT void JNICALL Java_com_bnwise_cleanleaf_vision_ClVision_ocrDestroy(JNIEnv*,
                                                                                    jclass,
                                                                                    jlong ocr) {
  clv_ocr_destroy(reinterpret_cast<clv_ocr*>(ocr));
}

// Returns the UTF-8 JSON of clv_ocr_read, or null on failure.
extern "C" JNIEXPORT jbyteArray JNICALL Java_com_bnwise_cleanleaf_vision_ClVision_ocrRead(
    JNIEnv* env, jclass, jlong ocr, jbyteArray encoded) {
  jbyte* bytes = env->GetByteArrayElements(encoded, nullptr);
  char* json = nullptr;
  int32_t length = 0;
  const int32_t status = clv_ocr_read(reinterpret_cast<clv_ocr*>(ocr),
                                      reinterpret_cast<const uint8_t*>(bytes),
                                      env->GetArrayLength(encoded), &json, &length);
  env->ReleaseByteArrayElements(encoded, bytes, JNI_ABORT);
  if (status != CLV_OK) return nullptr;
  jbyteArray out = env->NewByteArray(length);
  if (out != nullptr) env->SetByteArrayRegion(out, 0, length, reinterpret_cast<const jbyte*>(json));
  clv_free(json);
  return out;
}
