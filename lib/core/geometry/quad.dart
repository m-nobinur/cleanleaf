/// A 2D point. Page corners use normalized image coordinates (0..1).
/// Import `dart:math` with a prefix to avoid clashing with its `Point`.
typedef Point = ({double x, double y});

/// A document outline, corners clockwise from the top-left.
typedef Quad = ({
  Point topLeft,
  Point topRight,
  Point bottomRight,
  Point bottomLeft,
});

extension QuadCorners on Quad {
  List<Point> get corners => [topLeft, topRight, bottomRight, bottomLeft];
}
