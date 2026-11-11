#!/usr/bin/env bash
# Trimmed static OpenCV for Android (core, imgproc, imgcodecs; JPEG + PNG only).
# Usage: build_opencv_android.sh <opencv-src-dir> <install-prefix> [abi]
set -euo pipefail
src=$1
prefix=$2
abi=${3:-arm64-v8a}
ndk=$(ls -d "$HOME"/Library/Android/sdk/ndk/28.* | tail -1)
ninja=$(ls "$HOME"/Library/Android/sdk/cmake/*/bin/ninja | tail -1)
build=$(mktemp -d)
cmake -S "$src" -B "$build" -G Ninja -DCMAKE_MAKE_PROGRAM="$ninja" \
  -DCMAKE_TOOLCHAIN_FILE="$ndk/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI="$abi" -DANDROID_PLATFORM=android-24 -DANDROID_STL=c++_static \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix" \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DBUILD_SHARED_LIBS=OFF -DBUILD_LIST=core,imgproc,imgcodecs \
  -DBUILD_ZLIB=ON -DBUILD_PNG=ON -DBUILD_JPEG=ON \
  -DWITH_TIFF=OFF -DWITH_WEBP=OFF -DWITH_OPENJPEG=OFF -DWITH_JASPER=OFF \
  -DWITH_OPENEXR=OFF -DWITH_AVIF=OFF -DWITH_IMGCODEC_HDR=OFF \
  -DWITH_IMGCODEC_SUNRASTER=OFF -DWITH_IMGCODEC_PXM=OFF -DWITH_IMGCODEC_PFM=OFF \
  -DWITH_OPENCL=OFF -DWITH_IPP=OFF -DWITH_ITT=OFF -DWITH_PROTOBUF=OFF \
  -DWITH_ADE=OFF -DWITH_EIGEN=OFF -DWITH_LAPACK=OFF -DWITH_FFMPEG=OFF \
  -DWITH_ANDROID_MEDIANDK=OFF -DWITH_TBB=OFF -DBUILD_TBB=OFF \
  -DBUILD_ANDROID_PROJECTS=OFF -DBUILD_ANDROID_EXAMPLES=OFF -DBUILD_JAVA=OFF \
  -DBUILD_opencv_apps=OFF -DBUILD_TESTS=OFF -DBUILD_PERF_TESTS=OFF \
  -DBUILD_EXAMPLES=OFF -DBUILD_DOCS=OFF \
  -DCMAKE_C_FLAGS="-ffunction-sections -fdata-sections" \
  -DCMAKE_CXX_FLAGS="-ffunction-sections -fdata-sections"
cmake --build "$build" --target install -j "$(sysctl -n hw.ncpu)"
rm -rf "$build"
