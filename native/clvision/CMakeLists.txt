cmake_minimum_required(VERSION 3.18)
project(clvision LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(OpenCV 4.13 REQUIRED COMPONENTS core imgproc imgcodecs)
message(STATUS "clvision: OpenCV ${OpenCV_VERSION} from ${OpenCV_DIR}")

# Globbed so new source files need no CMake edit; jni_*.cpp only build for Android.
file(GLOB sources CONFIGURE_DEPENDS src/*.cpp)
file(GLOB jni_sources CONFIGURE_DEPENDS src/jni_*.cpp)
if(NOT ANDROID)
  list(REMOVE_ITEM sources ${jni_sources})
endif()

add_library(clvision SHARED ${sources})

# LiteRT C API (decisions.md D-11): headers from the LiteRT AAR plus the vendored
# XNNPACK delegate header; the hook supplies the per-platform library.
set(LITERT_INCLUDE_DIR "" CACHE PATH "LiteRT AAR headers directory")
set(LITERT_LIBRARY "" CACHE FILEPATH "LiteRT C API shared library")
add_library(litert SHARED IMPORTED)
set_target_properties(litert PROPERTIES
  IMPORTED_LOCATION "${LITERT_LIBRARY}"
  INTERFACE_INCLUDE_DIRECTORIES "${LITERT_INCLUDE_DIR};${CMAKE_CURRENT_SOURCE_DIR}/third_party/litert")
target_link_libraries(clvision PRIVATE litert)
target_include_directories(clvision PRIVATE include ${OpenCV_INCLUDE_DIRS})
target_link_libraries(clvision PRIVATE opencv_core opencv_imgproc opencv_imgcodecs)
set_target_properties(clvision PROPERTIES
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN ON)
target_compile_options(clvision PRIVATE -ffunction-sections -fdata-sections)

if(ANDROID)
  # Export only the C and JNI symbols and drop unreachable OpenCV code.
  target_link_options(clvision PRIVATE
    -Wl,--gc-sections
    -Wl,--exclude-libs,ALL
    -Wl,-z,max-page-size=16384)
  target_link_libraries(clvision PRIVATE log)
elseif(APPLE)
  target_link_options(clvision PRIVATE -Wl,-dead_strip)
  # Host tests load LiteRT from the shared cache instead of bundling it.
  get_filename_component(litert_dir "${LITERT_LIBRARY}" DIRECTORY)
  set_target_properties(clvision PROPERTIES BUILD_RPATH "${litert_dir}" INSTALL_RPATH "${litert_dir}")
endif()

install(TARGETS clvision LIBRARY DESTINATION lib)
