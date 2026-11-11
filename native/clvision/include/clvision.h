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
// CLV_NO_QUAD when no page is found.

// Detects a page in a colour camera frame.
CLV_API int32_t clv_detect_frame(const clv_yuv_frame* frame, float* corners_out,
                                 float* confidence_out);

// Detects a page in an encoded colour still (JPEG or PNG), upright per its EXIF
// orientation.
CLV_API int32_t clv_detect_image(const uint8_t* encoded, int32_t length, float* corners_out,
                                 float* confidence_out);

// Warps the quad (8 normalized floats, TL, TR, BR, BL) of an encoded still to a
// flat page, applies rotation and filter, and encodes JPEG at CLV_JPEG_QUALITY.
// On CLV_OK, *jpeg_out is owned by the caller and released with clv_free.
CLV_API int32_t clv_render_page(const uint8_t* encoded, int32_t length, const float* quad,
                                const clv_render_params* params, uint8_t** jpeg_out,
                                int32_t* jpeg_length_out);

// Downscales an encoded image so its long side is at most max_side and encodes
// JPEG at CLV_JPEG_QUALITY. On CLV_OK, release *jpeg_out with clv_free.
CLV_API int32_t clv_thumbnail(const uint8_t* encoded, int32_t length, int32_t max_side,
                              uint8_t** jpeg_out, int32_t* jpeg_length_out);

CLV_API void clv_free(void* buffer);

#ifdef __cplusplus
}
#endif

#endif  // CLVISION_H_
