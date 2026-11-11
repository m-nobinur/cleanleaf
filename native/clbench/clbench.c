#define _GNU_SOURCE
#include <errno.h>
#include <jni.h>
#include <sched.h>

// Pins the calling thread; threads it creates afterwards inherit the mask.
JNIEXPORT jint JNICALL
Java_com_bnwise_cleanleaf_detection_Affinity_pin(JNIEnv *env, jobject thiz, jint mask) {
  cpu_set_t set;
  CPU_ZERO(&set);
  for (int cpu = 0; cpu < 32; cpu++) {
    if (mask & (1 << cpu)) CPU_SET(cpu, &set);
  }
  return sched_setaffinity(0, sizeof(set), &set) == 0 ? 0 : errno;
}
