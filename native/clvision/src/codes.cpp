#include <opencv2/core.hpp>
#include <opencv2/imgcodecs.hpp>

#include <ReadBarcode.h>

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "clvision.h"

namespace {

ZXing::ReaderOptions options(int32_t formats) {
  std::vector<ZXing::BarcodeFormat> wanted;
  if (formats & CLV_CODES_MATRIX) wanted.push_back(ZXing::BarcodeFormat::AllMatrix);
  if (formats & CLV_CODES_LINEAR) wanted.push_back(ZXing::BarcodeFormat::AllLinear);
  return ZXing::ReaderOptions()
      .formats(ZXing::BarcodeFormats(std::move(wanted)))
      .maxNumberOfSymbols(1);
}

int32_t decode(const ZXing::ImageView& image, int32_t formats, clv_code* code_out) {
  const ZXing::Barcode barcode = ZXing::ReadBarcode(image, options(formats));
  if (!barcode.isValid()) return CLV_NO_CODE;
  const std::string text = barcode.text();
  auto* bytes = static_cast<uint8_t*>(std::malloc(std::max<size_t>(text.size(), 1)));
  if (bytes == nullptr) return CLV_ERR_INTERNAL;
  std::memcpy(bytes, text.data(), text.size());
  const std::string_view name = ZXing::Name(barcode.format());
  const size_t name_length = std::min(name.size(), size_t{CLV_CODE_FORMAT_SIZE - 1});
  std::memcpy(code_out->format, name.data(), name_length);
  code_out->format[name_length] = '\0';
  code_out->text = bytes;
  code_out->text_length = static_cast<int32_t>(text.size());
  return CLV_OK;
}

bool valid_formats(int32_t formats) {
  return formats != 0 && (formats & ~(CLV_CODES_MATRIX | CLV_CODES_LINEAR)) == 0;
}

}  // namespace

int32_t clv_decode_frame_codes(const clv_yuv_frame* frame, int32_t formats, clv_code* code_out) {
  if (frame == nullptr || frame->y == nullptr || code_out == nullptr || frame->width <= 0 ||
      frame->height <= 0 || frame->y_row_stride < frame->width || !valid_formats(formats)) {
    return CLV_ERR_INVALID_ARGUMENT;
  }
  try {
    // Upright first, so a barcode held level on screen is scanned along its bars' normal.
    const ZXing::ImageView luma(frame->y, frame->width, frame->height, ZXing::ImageFormat::Lum,
                                frame->y_row_stride);
    return decode(luma.rotated(frame->rotation_degrees), formats, code_out);
  } catch (const std::exception&) {
    return CLV_ERR_INTERNAL;
  }
}

int32_t clv_decode_image_codes(const uint8_t* encoded, int32_t length, int32_t formats,
                               clv_code* code_out) {
  if (encoded == nullptr || length <= 0 || code_out == nullptr || !valid_formats(formats)) {
    return CLV_ERR_INVALID_ARGUMENT;
  }
  try {
    const cv::Mat gray = cv::imdecode(cv::Mat(1, length, CV_8U, const_cast<uint8_t*>(encoded)),
                                      cv::IMREAD_GRAYSCALE);
    if (gray.empty()) return CLV_ERR_DECODE;
    const ZXing::ImageView luma(gray.data, gray.cols, gray.rows, ZXing::ImageFormat::Lum,
                                static_cast<int>(gray.step));
    return decode(luma, formats, code_out);
  } catch (const std::exception&) {  // cv::Exception, bad_alloc
    return CLV_ERR_INTERNAL;
  }
}
