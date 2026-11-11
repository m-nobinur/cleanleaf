#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <jni.h>
#include <sched.h>
#include <stdint.h>
#include <stdlib.h>

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

// LiteRT C API, resolved from the already loaded libtensorflowlite_jni.so. The AAR ships
// no xnnpack_delegate.h; this prefix matches TfLiteXNNPackDelegateOptions in LiteRT v1.4.1
// and main, and the oversized tail absorbs the rest (returned by value via a caller buffer).
typedef struct {
  int32_t num_threads;
  uint32_t runtime_flags;
  uint32_t flags;
  unsigned char rest[500];
} XnnOptions;

static void *(*model_create)(const void *, size_t);
static void (*model_delete)(void *);
static void *(*options_create)(void);
static void (*options_delete)(void *);
static void (*options_set_threads)(void *, int32_t);
static void (*options_add_delegate)(void *, void *);
static void *(*interpreter_create)(const void *, const void *);
static void (*interpreter_delete)(void *);
static int (*interpreter_allocate)(void *);
static void *(*interpreter_input)(const void *, int32_t);
static const void *(*interpreter_output)(const void *, int32_t);
static int (*interpreter_invoke)(void *);
static int (*tensor_from)(void *, const void *, size_t);
static int (*tensor_to)(const void *, void *, size_t);
static XnnOptions (*xnn_defaults)(void);
static void *(*xnn_create)(const XnnOptions *);
static void (*xnn_delete)(void *);

typedef struct {
  void *model, *options, *interpreter, *xnn;
} Bench;

static int resolved;

static int resolve(void) {
  if (resolved) return 0;
  void *lib = dlopen("libtensorflowlite_jni.so", RTLD_NOW | RTLD_NOLOAD);
  if (!lib) lib = dlopen("libtensorflowlite_jni.so", RTLD_NOW);
  if (!lib) return -1;
#define SYM(var, name) if (!(*(void **)&var = dlsym(lib, name))) return -2
  SYM(model_create, "TfLiteModelCreate");
  SYM(model_delete, "TfLiteModelDelete");
  SYM(options_create, "TfLiteInterpreterOptionsCreate");
  SYM(options_delete, "TfLiteInterpreterOptionsDelete");
  SYM(options_set_threads, "TfLiteInterpreterOptionsSetNumThreads");
  SYM(options_add_delegate, "TfLiteInterpreterOptionsAddDelegate");
  SYM(interpreter_create, "TfLiteInterpreterCreate");
  SYM(interpreter_delete, "TfLiteInterpreterDelete");
  SYM(interpreter_allocate, "TfLiteInterpreterAllocateTensors");
  SYM(interpreter_input, "TfLiteInterpreterGetInputTensor");
  SYM(interpreter_output, "TfLiteInterpreterGetOutputTensor");
  SYM(tensor_from, "TfLiteTensorCopyFromBuffer");
  SYM(tensor_to, "TfLiteTensorCopyToBuffer");
  SYM(xnn_defaults, "TfLiteXNNPackDelegateOptionsDefault");
  SYM(xnn_create, "TfLiteXNNPackDelegateCreate");
  SYM(xnn_delete, "TfLiteXNNPackDelegateDelete");
  SYM(interpreter_invoke, "TfLiteInterpreterInvoke");
#undef SYM
  resolved = 1;
  return 0;
}

// Returns a handle, or a negative error code.
JNIEXPORT jlong JNICALL
Java_com_bnwise_cleanleaf_detection_NativeBench_create(JNIEnv *env, jobject thiz, jobject model,
                                                       jint threads, jboolean explicit_xnnpack,
                                                       jint extra_flags) {
  int rc = resolve();
  if (rc) return rc;
  Bench *b = calloc(1, sizeof(Bench));
  b->model = model_create((*env)->GetDirectBufferAddress(env, model),
                          (size_t)(*env)->GetDirectBufferCapacity(env, model));
  if (!b->model) return -10;
  b->options = options_create();
  options_set_threads(b->options, threads);
  if (explicit_xnnpack) {
    XnnOptions o = xnn_defaults();
    o.num_threads = threads;
    o.flags |= (uint32_t)extra_flags;
    b->xnn = xnn_create(&o);
    if (!b->xnn) return -11;
    options_add_delegate(b->options, b->xnn);
  }
  b->interpreter = interpreter_create(b->model, b->options);
  if (!b->interpreter) return -12;
  if (interpreter_allocate(b->interpreter) != 0) return -13;
  return (jlong)(intptr_t)b;
}

JNIEXPORT jint JNICALL
Java_com_bnwise_cleanleaf_detection_NativeBench_run(JNIEnv *env, jobject thiz, jlong handle,
                                                    jobject input, jobject output) {
  Bench *b = (Bench *)(intptr_t)handle;
  if (tensor_from(interpreter_input(b->interpreter, 0), (*env)->GetDirectBufferAddress(env, input),
                  (size_t)(*env)->GetDirectBufferCapacity(env, input)) != 0) return -1;
  if (interpreter_invoke(b->interpreter) != 0) return -2;
  return tensor_to(interpreter_output(b->interpreter, 0), (*env)->GetDirectBufferAddress(env, output),
                   (size_t)(*env)->GetDirectBufferCapacity(env, output)) != 0 ? -3 : 0;
}

JNIEXPORT void JNICALL
Java_com_bnwise_cleanleaf_detection_NativeBench_destroy(JNIEnv *env, jobject thiz, jlong handle) {
  Bench *b = (Bench *)(intptr_t)handle;
  interpreter_delete(b->interpreter);
  if (b->xnn) xnn_delete(b->xnn);
  options_delete(b->options);
  model_delete(b->model);
  free(b);
}
