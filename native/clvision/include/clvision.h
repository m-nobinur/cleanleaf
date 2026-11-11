#ifndef CLVISION_H_
#define CLVISION_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define CLV_API __attribute__((visibility("default")))

typedef enum clv_status {
  CLV_OK = 0,
  CLV_NO_QUAD = 1,
  CLV_ERR_NOT_IMPLEMENTED = -1,
  CLV_ERR_INVALID_ARGUMENT = -2,
  CLV_ERR_DECODE = -3,
  CLV_ERR_ENCODE = -4,
  CLV_ERR_INTERNAL = -5,
} clv_status;

// Values match the Dart PageFilter enum order.
typedef enum clv_filter {
  CLV_FILTER_ORIGINAL = 0,
  CLV_FILTER_ENHANCED_COLOR = 1,
  CLV_FILTER_GRAYSCALE = 2,
  CLV_FILTER_BLACK_WHITE = 3,
} clv_filter;

#define CLV_JPEG_QUALITY 85

typedef struct clv_render_params {
  int32_t filter;            // clv_filter
  int32_t rotation_degrees;  // clockwise: 0, 90, 180, 270
  float aspect_ratio;        // long side / short side; 0 keeps the quad's own ratio
  int32_t max_long_side;     // output cap in pixels; 0 renders at full size
  // Manual adjustments (D-49); 0 leaves the page unchanged. Tone and sharpness skip B&W,
  // saturation skips single-channel output.
  float brightness;          // -1..1, a gamma curve that keeps black and white
  float contrast;            // -1..1, pivoting on mid-grey
  float saturation;          // -1..1; -1 is grey
  float sharpness;           // -1..1; below 0 softens
  float straighten_degrees;  // -45..45 clockwise after rotation, zoomed so the page stays filled
  int32_t encode_png;        // 1 encodes lossless PNG instead of JPEG
} clv_render_params;

// OpenCV version the library was linked against, e.g. "4.13.0". Static storage.
CLV_API const char* clv_opencv_version(void);

// A camera frame in YUV_420_888 layout, as CameraX ImageAnalysis delivers it.
typedef struct clv_yuv_frame {
  const uint8_t* y;
  const uint8_t* u;
  const uint8_t* v;
  int32_t width;
  int32_t height;
  int32_t y_row_stride;
  int32_t uv_row_stride;
  int32_t uv_pixel_stride;
  int32_t rotation_degrees;  // clockwise turn that makes the frame upright: 0, 90, 180, 270
} clv_yuv_frame;

// Corners are written as TL, TR, BR, BL (x, y) pairs normalized to 0..1 in the
// upright image, so corners_out holds 8 floats. Detection returns CLV_OK, or
// CLV_NO_QUAD when no page is found; confidence_out (the weakest corner's heatmap
// peak) is written in both cases. The model must be loaded (clv_model_load).

// Detects a page in a colour camera frame.
CLV_API int32_t clv_detect_frame(const clv_yuv_frame* frame, float* corners_out,
                                 float* confidence_out);

// Detects a page in an encoded colour still (JPEG or PNG), upright per its EXIF
// orientation.
CLV_API int32_t clv_detect_image(const uint8_t* encoded, int32_t length, float* corners_out,
                                 float* confidence_out);

// Warps the quad (8 normalized floats, TL, TR, BR, BL) of an encoded still to a
// flat page, applies rotation, straighten, filter and adjustments, and encodes JPEG at
// CLV_JPEG_QUALITY (or PNG when params->encode_png is 1).
// On CLV_OK, *jpeg_out is owned by the caller and released with clv_free.
CLV_API int32_t clv_render_page(const uint8_t* encoded, int32_t length, const float* quad,
                                const clv_render_params* params, uint8_t** jpeg_out,
                                int32_t* jpeg_length_out);

// Downscales an encoded image so its long side is at most max_side and encodes
// JPEG at CLV_JPEG_QUALITY. On CLV_OK, release *jpeg_out with clv_free.
CLV_API int32_t clv_thumbnail(const uint8_t* encoded, int32_t length, int32_t max_side,
                              uint8_t** jpeg_out, int32_t* jpeg_length_out);

CLV_API void clv_free(void* buffer);

// DocAligner LC100 corner model (decisions.md D-11), run with LiteRT + XNNPACK.
// Input: 256x256x3 BGR floats in 0..1, NHWC, stretch-resized from a colour image.
// Output: 128x128x4 heatmaps, NHWC, channels TL, TR, BR, BL.
#define CLV_MODEL_INPUT_SIZE 256
#define CLV_MODEL_HEATMAP_SIZE 128

enum { CLV_ERR_MODEL_NOT_LOADED = -6 };

// Loads the model once per process (the bytes are copied); later calls return
// CLV_OK without reloading.
CLV_API int32_t clv_model_load(const uint8_t* model, int32_t length);

CLV_API int32_t clv_model_loaded(void);

// Thread-safe; concurrent callers are serialized.
CLV_API int32_t clv_model_run(const float* input, float* heatmaps_out);

// Rebuilds the loaded model's interpreter with XNNPACK fp16 inference (FORCE_FP16) or fp32.
// Returns 1 when fp16 runs, 0 when fp32 runs (also when the CPU can't run fp16), or a negative
// clv_status.
CLV_API int32_t clv_model_set_fp16(int32_t enabled);

// QR and barcode reading (decisions.md D-47), with zxing-cpp.
enum { CLV_NO_CODE = 2 };

// Code families to look for; or them together.
typedef enum clv_code_formats {
  CLV_CODES_MATRIX = 1,  // QR, Micro QR, rMQR, Data Matrix, Aztec, PDF417, MaxiCode
  CLV_CODES_LINEAR = 2,  // EAN/UPC, Code 128, Code 39, Code 93, ITF, Codabar, DataBar
} clv_code_formats;

#define CLV_CODE_FORMAT_SIZE 32

typedef struct clv_code {
  char format[CLV_CODE_FORMAT_SIZE];  // NUL-terminated name, e.g. "QR Code", "EAN-13"
  uint8_t* text;                      // UTF-8, not NUL-terminated; release with clv_free
  int32_t text_length;
} clv_code;

// Reads the first code in a frame's luma plane (u and v are unused). Returns CLV_OK and fills
// code_out, or CLV_NO_CODE.
CLV_API int32_t clv_decode_frame_codes(const clv_yuv_frame* frame, int32_t formats,
                                       clv_code* code_out);

// Reads the first code in an encoded still (JPEG or PNG), as clv_decode_frame_codes.
CLV_API int32_t clv_decode_image_codes(const uint8_t* encoded, int32_t length, int32_t formats,
                                       clv_code* code_out);

#ifdef __cplusplus
}
#endif

#endif  // CLVISION_H_
