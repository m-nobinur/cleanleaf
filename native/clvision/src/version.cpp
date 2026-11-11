#include <opencv2/core/utility.hpp>

#include <cstdlib>
#include <string>

#include "clvision.h"

// Asks the linked library rather than the CV_VERSION header macro, so the call
// proves OpenCV is actually linked.
const char* clv_opencv_version(void) {
  static const std::string version = cv::getVersionString();
  return version.c_str();
}

void clv_free(void* buffer) { std::free(buffer); }
