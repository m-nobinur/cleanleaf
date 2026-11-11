#include <mutex>
#include <vector>

#include "clvision.h"
#include "tflite/c/c_api.h"
#include "tflite/delegates/xnnpack/xnnpack_delegate.h"

namespace {

// OptionsDefault returns this struct by value; the size must match the LiteRT
// 1.4.2 binary (measured: 64 bytes on arm64, 36 on armeabi-v7a).
static_assert(sizeof(TfLiteXNNPackDelegateOptions) == (sizeof(void*) == 8 ? 64 : 36),
              "xnnpack_delegate.h does not match the linked LiteRT");

constexpr int kThreads = 4;
constexpr size_t kInputBytes =
    sizeof(float) * CLV_MODEL_INPUT_SIZE * CLV_MODEL_INPUT_SIZE * 3;
constexpr size_t kOutputBytes =
    sizeof(float) * CLV_MODEL_HEATMAP_SIZE * CLV_MODEL_HEATMAP_SIZE * 4;

struct Model {
  std::vector<uint8_t> bytes;
  bool fp16 = false;
  TfLiteModel* model = nullptr;
  TfLiteDelegate* xnnpack = nullptr;
  TfLiteInterpreterOptions* options = nullptr;
  TfLiteInterpreter* interpreter = nullptr;

  ~Model() {
    TfLiteInterpreterDelete(interpreter);
    TfLiteInterpreterOptionsDelete(options);
    if (xnnpack != nullptr) TfLiteXNNPackDelegateDelete(xnnpack);
    TfLiteModelDelete(model);
  }
};

std::mutex mutex;
Model* loaded = nullptr;  // Lives for the process.

bool create(Model& m) {
  m.model = TfLiteModelCreate(m.bytes.data(), m.bytes.size());
  if (m.model == nullptr) return false;
  TfLiteXNNPackDelegateOptions xnn = TfLiteXNNPackDelegateOptionsDefault();
  xnn.num_threads = kThreads;
  if (m.fp16) xnn.flags |= TFLITE_XNNPACK_DELEGATE_FLAG_FORCE_FP16;
  m.xnnpack = TfLiteXNNPackDelegateCreate(&xnn);
  if (m.xnnpack == nullptr) return false;
  m.options = TfLiteInterpreterOptionsCreate();
  TfLiteInterpreterOptionsSetNumThreads(m.options, kThreads);
  TfLiteInterpreterOptionsAddDelegate(m.options, m.xnnpack);
  m.interpreter = TfLiteInterpreterCreate(m.model, m.options);
  return m.interpreter != nullptr && TfLiteInterpreterAllocateTensors(m.interpreter) == kTfLiteOk &&
         TfLiteTensorByteSize(TfLiteInterpreterGetInputTensor(m.interpreter, 0)) == kInputBytes &&
         TfLiteTensorByteSize(TfLiteInterpreterGetOutputTensor(m.interpreter, 0)) == kOutputBytes;
}

// Falls back to fp32 when fp16 is asked for but can't be built (no fp16 arithmetic, e.g. A53).
Model* build(const uint8_t* bytes, size_t length, bool fp16) {
  auto* m = new Model();
  m->bytes.assign(bytes, bytes + length);
  m->fp16 = fp16;
  if (create(*m)) return m;
  delete m;
  return fp16 ? build(bytes, length, false) : nullptr;
}

}  // namespace

int32_t clv_model_load(const uint8_t* model, int32_t length) {
  if (model == nullptr || length <= 0) return CLV_ERR_INVALID_ARGUMENT;
  std::lock_guard<std::mutex> lock(mutex);
  if (loaded != nullptr) return CLV_OK;
  loaded = build(model, size_t(length), false);  // D-11: fp32 until fp16 is adopted
  return loaded != nullptr ? CLV_OK : CLV_ERR_INTERNAL;
}

int32_t clv_model_set_fp16(int32_t enabled) {
  std::lock_guard<std::mutex> lock(mutex);
  if (loaded == nullptr) return CLV_ERR_MODEL_NOT_LOADED;
  Model* next = build(loaded->bytes.data(), loaded->bytes.size(), enabled != 0);
  if (next == nullptr) return CLV_ERR_INTERNAL;
  delete loaded;
  loaded = next;
  return loaded->fp16;
}

int32_t clv_model_loaded(void) {
  std::lock_guard<std::mutex> lock(mutex);
  return loaded != nullptr;
}

int32_t clv_model_run(const float* input, float* heatmaps_out) {
  if (input == nullptr || heatmaps_out == nullptr) return CLV_ERR_INVALID_ARGUMENT;
  std::lock_guard<std::mutex> lock(mutex);
  if (loaded == nullptr) return CLV_ERR_MODEL_NOT_LOADED;
  TfLiteInterpreter* interpreter = loaded->interpreter;
  if (TfLiteTensorCopyFromBuffer(TfLiteInterpreterGetInputTensor(interpreter, 0), input,
                                 kInputBytes) != kTfLiteOk ||
      TfLiteInterpreterInvoke(interpreter) != kTfLiteOk ||
      TfLiteTensorCopyToBuffer(TfLiteInterpreterGetOutputTensor(interpreter, 0), heatmaps_out,
                               kOutputBytes) != kTfLiteOk) {
    return CLV_ERR_INTERNAL;
  }
  return CLV_OK;
}
