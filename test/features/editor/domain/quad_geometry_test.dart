import 'package:cleanleaf/core/geometry/quad.dart';
import 'package:cleanleaf/features/editor/domain/quad_geometry.dart';
import 'package:cleanleaf/features/library/domain/document_page.dart';
import 'package:flutter_test/flutter_test.dart';

const Quad inset = (
  topLeft: (x: 0.2, y: 0.2),
  topRight: (x: 0.8, y: 0.2),
  bottomRight: (x: 0.8, y: 0.8),
  bottomLeft: (x: 0.2, y: 0.8),
);

void main() {
  group('moveCorner', () {
    test('moves only the given corner', () {
      final q = moveCorner(inset, 2, (x: 0.9, y: 0.7));
      expect(q.bottomRight, (x: 0.9, y: 0.7));
      expect(q.topLeft, inset.topLeft);
      expect(q.topRight, inset.topRight);
      expect(q.bottomLeft, inset.bottomLeft);
    });

    test('clamps to the image', () {
      final q = moveCorner(inset, 0, (x: -0.3, y: 1.4));
      expect(q.topLeft, (x: 0.0, y: 1.0));
    });
  });

  group('moveEdge', () {
    test('translates both ends of the edge', () {
      final q = moveEdge(inset, 1, (x: 0.1, y: 0.05));
      expect(q.topRight.x, closeTo(0.9, 1e-9));
      expect(q.topRight.y, closeTo(0.25, 1e-9));
      expect(q.bottomRight.x, closeTo(0.9, 1e-9));
      expect(q.bottomRight.y, closeTo(0.85, 1e-9));
      expect(q.topLeft, inset.topLeft);
      expect(q.bottomLeft, inset.bottomLeft);
    });

    test('limits the delta so the edge keeps its shape at the border', () {
      const Quad slanted = (
        topLeft: (x: 0.1, y: 0.3),
        topRight: (x: 0.7, y: 0.1),
        bottomRight: (x: 0.8, y: 0.8),
        bottomLeft: (x: 0.2, y: 0.9),
      );
      final q = moveEdge(slanted, 0, (x: -0.5, y: -0.5));
      expect(q.topLeft.x, closeTo(0, 1e-9));
      expect(q.topLeft.y, closeTo(0.2, 1e-9));
      expect(q.topRight.x, closeTo(0.6, 1e-9));
      expect(q.topRight.y, closeTo(0, 1e-9));
    });

    test('the left edge wraps from bottom-left to top-left', () {
      final q = moveEdge(inset, 3, (x: -0.1, y: 0));
      expect(q.bottomLeft.x, closeTo(0.1, 1e-9));
      expect(q.topLeft.x, closeTo(0.1, 1e-9));
      expect(q.topRight, inset.topRight);
    });
  });

  test('edgeMidpoint', () {
    expect(edgeMidpoint(inset, 0), (x: 0.5, y: 0.2));
    expect(edgeMidpoint(inset, 3), (x: 0.2, y: 0.5));
  });

  group('isValidQuad', () {
    test('accepts convex clockwise quads', () {
      expect(isValidQuad(inset), isTrue);
      expect(isValidQuad(fullFrame), isTrue);
    });

    test('rejects a concave quad', () {
      expect(isValidQuad(moveCorner(inset, 0, (x: 0.6, y: 0.6))), isFalse);
    });

    test('rejects a self-intersecting quad', () {
      expect(isValidQuad(moveCorner(inset, 0, (x: 0.9, y: 0.9))), isFalse);
    });

    test('rejects a mirrored (counter-clockwise) quad', () {
      final mirrored = quadFromCorners(inset.corners.reversed.toList());
      expect(isValidQuad(mirrored), isFalse);
    });

    test('rejects a degenerate quad', () {
      expect(isValidQuad(moveCorner(inset, 1, (x: 0.5, y: 0.5))), isFalse);
    });
  });
}
