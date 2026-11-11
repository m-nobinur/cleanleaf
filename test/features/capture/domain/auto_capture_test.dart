import 'package:cleanleaf/core/geometry/quad.dart';
import 'package:cleanleaf/features/capture/domain/auto_capture.dart';
import 'package:cleanleaf/features/capture/domain/document_camera.dart';
import 'package:flutter_test/flutter_test.dart';

Quad page({double dx = 0}) => (
  topLeft: (x: 0.2 + dx, y: 0.2),
  topRight: (x: 0.8 + dx, y: 0.2),
  bottomRight: (x: 0.8 + dx, y: 0.8),
  bottomLeft: (x: 0.2 + dx, y: 0.8),
);

LiveDetection seen(Quad? quad, {bool stable = false}) =>
    (quad: quad, confidence: quad == null ? 0 : 0.9, isStable: stable);

void main() {
  test('fires on the first stable frame of a page, then not again', () {
    final auto = AutoCapture();
    expect(auto.onDetection(seen(page())), isFalse);
    expect(auto.onDetection(seen(page(), stable: true)), isTrue);
    expect(auto.isArmed, isFalse);
    expect(auto.onDetection(seen(page(), stable: true)), isFalse);
    // Hand jitter breaks stability but it is still the same page.
    expect(auto.onDetection(seen(page(dx: 0.03))), isFalse);
    expect(auto.onDetection(seen(page(dx: 0.03), stable: true)), isFalse);
  });

  test('re-arms when the page moves to a clearly different place', () {
    final auto = AutoCapture();
    auto.onDetection(seen(page(), stable: true));
    expect(auto.onDetection(seen(page(dx: 0.15))), isFalse);
    expect(auto.isArmed, isTrue);
    expect(auto.onDetection(seen(page(dx: 0.15), stable: true)), isTrue);
  });

  test('re-arms only after the page is gone for several frames', () {
    final auto = AutoCapture(missingFrames: 3);
    auto.onDetection(seen(page(), stable: true));
    auto
      ..onDetection(seen(null))
      ..onDetection(seen(null));
    // A two-frame dropout is detector flicker, not a new page.
    expect(auto.onDetection(seen(page(), stable: true)), isFalse);
    for (var i = 0; i < 3; i++) {
      auto.onDetection(seen(null));
    }
    expect(auto.onDetection(seen(page(), stable: true)), isTrue);
  });

  test('a manual shot of a page counts as its shot', () {
    final auto = AutoCapture()..markShot(page());
    expect(auto.onDetection(seen(page(), stable: true)), isFalse);
  });

  test('a manual shot without a page leaves it armed', () {
    final auto = AutoCapture()..markShot(null);
    expect(auto.onDetection(seen(page(), stable: true)), isTrue);
  });
}
