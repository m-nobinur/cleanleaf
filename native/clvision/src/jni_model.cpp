#include <jni.h>

#include "clvision.h"

// model is a direct ByteBuffer holding the .tflite file.
extern "C" JNIEXPORT jint JNICALL
Java_com_bnwise_cleanleaf_vision_ClVision_loadModel(JNIEnv* env, jclass, jobject model) {
  const auto* bytes = static_cast<const uint8_t*>(env->GetDirectBufferAddress(model));
  if (bytes == nullptr) return CLV_ERR_INVALID_ARGUMENT;
  return clv_model_load(bytes, static_cast<int32_t>(env->GetDirectBufferCapacity(model)));
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_bnwise_cleanleaf_vision_ClVision_isModelLoaded(JNIEnv*, jclass) {
  return clv_model_loaded() != 0;
}
