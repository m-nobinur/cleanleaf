import 'dart:ui';

import 'package:cleanleaf/features/capture/presentation/preview_transform.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A 20:9 phone's preview area: taller than 3:4, so the sides are cropped.
  const portrait = Size(412, 690);
  const frame = Size(300, 400);

  test('cover-crops the sides of a 3:4 frame in a tall view', () {
    final t = PreviewTransform(frame: frame, view: portrait);
    expect(t.frameRect.height, closeTo(690, 1e-9));
    expect(t.frameRect.width, closeTo(517.5, 1e-9));
    expect(t.frameRect.left, closeTo(-52.75, 1e-9));
    expect(t.frameRect.top, 0);
    // About 20% of the width is hidden, split between the two sides (D-48).
    expect(portrait.width / t.frameRect.width, closeTo(0.796, 0.001));
  });

  test('frame corners land outside the view, the centre at its centre', () {
    final t = PreviewTransform(frame: frame, view: portrait);
    expect(t.toView((x: 0.5, y: 0.5)), const Offset(206, 345));
    expect(t.toView((x: 0, y: 0)).dx, closeTo(-52.75, 1e-9));
    expect(t.toView((x: 1, y: 1)).dx, closeTo(464.75, 1e-9));
    expect(t.toView((x: 1, y: 1)).dy, closeTo(690, 1e-9));
  });

  test('a tap on the view edge focuses inside the frame, not on its edge', () {
    final t = PreviewTransform(frame: frame, view: portrait);
    final left = t.toFrame(const Offset(0, 345));
    final right = t.toFrame(const Offset(412, 345));
    expect(left.x, closeTo(0.102, 0.001));
    expect(right.x, closeTo(0.898, 0.001));
    expect(left.y, closeTo(0.5, 1e-9));
  });

  test('round-trips points in both directions', () {
    final t = PreviewTransform(frame: frame, view: portrait);
    for (final p in [(x: 0.2, y: 0.3), (x: 0.75, y: 0.9), (x: 0.0, y: 1.0)]) {
      final back = t.toFrame(t.toView(p));
      expect(back.x, closeTo(p.x, 1e-9));
      expect(back.y, closeTo(p.y, 1e-9));
    }
  });

  test('a wide view crops top and bottom instead', () {
    final t = PreviewTransform(frame: frame, view: const Size(600, 400));
    expect(t.frameRect.width, 600);
    expect(t.frameRect.top, closeTo(-200, 1e-9));
    expect(t.toFrame(const Offset(300, 0)).y, closeTo(0.25, 1e-9));
  });

  test('a sideways sensor maps by its upright size, not its raw one', () {
    // A 4:3 landscape sensor at 90° reaches Dart as an upright 3:4 preview
    // (PigeonDocumentCamera swaps the sides), so it maps like any 3:4 frame.
    const rawSensor = Size(400, 300);
    final upright = Size(rawSensor.height, rawSensor.width);
    final t = PreviewTransform(frame: upright, view: portrait);
    expect(
      t.frameRect,
      PreviewTransform(frame: frame, view: portrait).frameRect,
    );
    // The page's top-left corner stays top-left after mapping.
    final topLeft = t.toView((x: 0.2, y: 0.1));
    expect(topLeft.dx, lessThan(portrait.width / 2));
    expect(topLeft.dy, lessThan(portrait.height / 2));
  });
}
