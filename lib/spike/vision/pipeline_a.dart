import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'spike_types.dart';

// Candidate A: the shared spike algorithm through opencv_dart (dartcv4).

const _frameLongSide = 480;

/// [plane] is an 8-bit Y plane with [stride] bytes per row. Rows are repacked
/// into native memory because `Mat.fromBuffer` takes no step.
Float32List? detectFrameA(Uint8List plane, int width, int height, int stride) {
  final buf = malloc<Uint8>(width * height);
  final packed = buf.asTypedList(width * height);
  for (var row = 0; row < height; row++) {
    packed.setRange(row * width, row * width + width, plane, row * stride);
  }
  final src = cv.Mat.fromBuffer(height, width, cv.MatType.CV_8UC1, buf.cast());
  try {
    return _detect(src);
  } finally {
    src.dispose();
    malloc.free(buf);
  }
}

Float32List? _detect(cv.Mat src) {
  final scale = _frameLongSide / math.max(src.cols, src.rows);
  final small = cv.resize(src, (
    (src.cols * scale).round(),
    (src.rows * scale).round(),
  ), interpolation: cv.INTER_AREA);
  final blurred = cv.gaussianBlur(small, (5, 5), 0);
  final edges = cv.canny(blurred, 50, 150);
  final kernel = cv.getStructuringElement(cv.MORPH_RECT, (3, 3));
  final dilated = cv.dilate(edges, kernel, borderType: cv.BORDER_REPLICATE);
  final (contours, hierarchy) = cv.findContours(
    dilated,
    cv.RETR_EXTERNAL,
    cv.CHAIN_APPROX_SIMPLE,
  );
  final minArea = 0.1 * small.cols * small.rows;
  var bestArea = 0.0;
  List<(double, double)>? best;
  for (final contour in contours) {
    final area = cv.contourArea(contour);
    if (area < minArea || area <= bestArea) continue;
    final approx = cv.approxPolyDP(
      contour,
      0.02 * cv.arcLength(contour, true),
      true,
    );
    if (approx.length == 4 && cv.isContourConvex(approx)) {
      bestArea = area;
      best = [
        for (final p in approx)
          (p.x.toDouble() / scale, p.y.toDouble() / scale),
      ];
    }
    approx.dispose();
  }
  for (final m in [small, blurred, edges, kernel, dilated]) {
    m.dispose();
  }
  contours.dispose();
  hierarchy.dispose();
  return best == null ? null : orderCorners(best);
}

StillResult stillA(Uint8List jpeg, Float32List corners, int outW, int outH) {
  final sw = Stopwatch()..start();
  final src = cv.imdecode(jpeg, cv.IMREAD_COLOR);
  final decodeMs = _lap(sw);
  final srcPts = cv.VecPoint2f.fromList([
    for (var i = 0; i < 4; i++) cv.Point2f(corners[2 * i], corners[2 * i + 1]),
  ]);
  final dstPts = cv.VecPoint2f.fromList([
    cv.Point2f(0, 0),
    cv.Point2f(outW - 1.0, 0),
    cv.Point2f(outW - 1.0, outH - 1.0),
    cv.Point2f(0, outH - 1.0),
  ]);
  final m = cv.getPerspectiveTransform2f(srcPts, dstPts);
  final warped = cv.warpPerspective(
    src,
    m,
    (outW, outH),
    flags: cv.INTER_LINEAR,
    borderMode: cv.BORDER_REPLICATE,
  );
  final warpMs = _lap(sw);
  final enhanced = enhanceA(warped);
  final enhanceMs = _lap(sw);
  final (_, encoded) = cv.imencode('.jpg', enhanced);
  final encodeMs = _lap(sw);
  final mean = cv.mean(enhanced);
  final result = StillResult(
    decodeMs: decodeMs,
    warpMs: warpMs,
    enhanceMs: enhanceMs,
    encodeMs: encodeMs,
    mean: (mean.val1 + mean.val2 + mean.val3) / 3,
    jpeg: encoded,
  );
  for (final d in [src, m, warped, enhanced]) {
    d.dispose();
  }
  srcPts.dispose();
  dstPts.dispose();
  return result;
}

/// Shadow division: estimate the paper background on a 1/4 copy and divide.
cv.Mat enhanceA(cv.Mat img) {
  final small = cv.resize(img, (
    img.cols ~/ 4,
    img.rows ~/ 4,
  ), interpolation: cv.INTER_AREA);
  final k = (math.min(small.cols, small.rows) ~/ 20) | 1;
  final kernel = cv.getStructuringElement(cv.MORPH_ELLIPSE, (k, k));
  final bg = cv.morphologyEx(
    small,
    cv.MORPH_CLOSE,
    kernel,
    borderType: cv.BORDER_REPLICATE,
  );
  final bgBlur = cv.gaussianBlur(bg, (k, k), 0);
  final bgFull = cv.resize(bgBlur, (
    img.cols,
    img.rows,
  ), interpolation: cv.INTER_LINEAR);
  final out = cv.divide(img, bgFull, scale: 255);
  for (final m in [small, kernel, bg, bgBlur, bgFull]) {
    m.dispose();
  }
  return out;
}

String buildInfoA() => cv.getBuildInformation();

int numThreadsA() => cv.getNumThreads();

double _lap(Stopwatch sw) {
  final ms = sw.elapsedMicroseconds / 1000;
  sw.reset();
  return ms;
}
