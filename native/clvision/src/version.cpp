#include <opencv2/core/version.hpp>

#include <cstdlib>

#include "clvision.h"

const char* clv_opencv_version(void) { return CV_VERSION; }

void clv_free(void* buffer) { std::free(buffer); }
