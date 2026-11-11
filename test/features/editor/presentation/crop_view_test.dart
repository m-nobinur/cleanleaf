import 'dart:ui';

import 'package:cleanleaf/features/editor/presentation/crop_view.dart';
import 'package:flutter_test/flutter_test.dart';

const image = Size(400, 300);
const area = Rect.fromLTWH(0, 0, 200, 300);

void main() {
  test('without a focus the whole photo is fitted and centred', () {
    expect(fitView(image, area), const Rect.fromLTWH(0, 75, 200, 150));
  });

  test('zooms so the grown focus fills the area, centred on it', () {
    // Middle half of the width; 10% margin per side grows it to 0.6.
    final view = fitView(
      image,
      area,
      focus: const Rect.fromLTRB(0.25, 0.25, 0.75, 0.75),
      margin: 0.1,
    );
    expect(view.width, closeTo(200 / (0.6 * 400) * 400, 1e-9));
    expect(view.center.dx, closeTo(area.center.dx, 1e-9));
  });

  test('zoom is capped at maxZoom times the whole-photo fit', () {
    final view = fitView(
      image,
      area,
      focus: const Rect.fromLTWH(0.5, 0.5, 0.001, 0.001),
    );
    expect(view.width, 200 * maxZoom);
  });

  test('a zoomed view keeps the area covered when clamped', () {
    final view = clampView(const Rect.fromLTWH(50, -900, 800, 600), area);
    expect(view.left, 0);
    expect(view.top, -300);
  });

  test('pinching never zooms out past the whole photo', () {
    final view = zoomView(
      const Rect.fromLTWH(-100, 0, 400, 300),
      image,
      area,
      scale: 0.1,
      from: Offset.zero,
      to: Offset.zero,
    );
    expect(view, fitView(image, area));
  });

  test('a pan follows the focal point', () {
    final view = zoomView(
      const Rect.fromLTWH(-100, 0, 400, 300),
      image,
      area,
      scale: 1,
      from: const Offset(100, 100),
      to: const Offset(150, 100),
    );
    expect(view.left, -50);
  });

  test('reveal pans just enough to bring a point inside', () {
    final view = revealView(
      const Rect.fromLTWH(-100, 0, 400, 300),
      area,
      const Offset(230, 100),
    );
    expect(view.left, -130);
  });
}
