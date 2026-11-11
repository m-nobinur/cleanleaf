#include <jni.h>

#include "clvision.h"

extern "C" JNIEXPORT jstring JNICALL
Java_com_bnwise_cleanleaf_vision_ClVision_opencvVersion(JNIEnv* env, jclass) {
  return env->NewStringUTF(clv_opencv_version());
}
