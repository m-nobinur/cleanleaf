cmake_minimum_required(VERSION 3.18)
project(clvision LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(OpenCV REQUIRED COMPONENTS core imgproc imgcodecs)
message(STATUS "clvision: OpenCV ${OpenCV_VERSION} from ${OpenCV_DIR}")

add_library(clvision SHARED clvision.cpp)
target_include_directories(clvision PRIVATE ${OpenCV_INCLUDE_DIRS})
target_link_libraries(clvision PRIVATE opencv_core opencv_imgproc opencv_imgcodecs)
set_target_properties(clvision PROPERTIES
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN ON)
target_compile_options(clvision PRIVATE -ffunction-sections -fdata-sections)

if(ANDROID)
  # Export only our C and JNI symbols; drop unreachable OpenCV code.
  target_link_options(clvision PRIVATE
    -Wl,--gc-sections
    -Wl,--exclude-libs,ALL
    -Wl,-z,max-page-size=16384)
  target_link_libraries(clvision PRIVATE log)
elseif(APPLE)
  target_link_options(clvision PRIVATE -Wl,-dead_strip)
endif()

install(TARGETS clvision LIBRARY DESTINATION lib)
