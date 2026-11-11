#!/usr/bin/env bash
# One-time host build of static OpenCV for `flutter test` on macOS (arm64).
# Usage: build_opencv_macos.sh <opencv-src-dir> <install-prefix>
set -euo pipefail
src=$1
prefix=$2
ninja=$(ls "$HOME"/Library/Android/sdk/cmake/*/bin/ninja | tail -1)
build=$(mktemp -d)
cmake -S "$src" -B "$build" -G Ninja -DCMAKE_MAKE_PROGRAM="$ninja" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix" \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DBUILD_SHARED_LIBS=OFF -DBUILD_LIST=core,imgproc,imgcodecs \
  -DBUILD_ZLIB=ON -DBUILD_PNG=ON -DBUILD_JPEG=ON \
  -DWITH_TIFF=OFF -DWITH_WEBP=OFF -DWITH_OPENJPEG=OFF -DWITH_JASPER=OFF \
  -DWITH_OPENEXR=OFF -DWITH_AVIF=OFF -DWITH_IMGCODEC_HDR=OFF \
  -DWITH_IMGCODEC_SUNRASTER=OFF -DWITH_IMGCODEC_PXM=OFF -DWITH_IMGCODEC_PFM=OFF \
  -DWITH_OPENCL=OFF -DWITH_IPP=OFF -DWITH_ITT=OFF -DWITH_PROTOBUF=OFF \
  -DWITH_ADE=OFF -DWITH_EIGEN=OFF -DWITH_LAPACK=OFF -DWITH_FFMPEG=OFF \
  -DWITH_OPENEXR=OFF -DBUILD_opencv_apps=OFF -DBUILD_JAVA=OFF \
  -DBUILD_opencv_python3=OFF -DBUILD_TESTS=OFF -DBUILD_PERF_TESTS=OFF \
  -DBUILD_EXAMPLES=OFF -DBUILD_DOCS=OFF
cmake --build "$build" --target install -j "$(sysctl -n hw.ncpu)"
rm -rf "$build"
