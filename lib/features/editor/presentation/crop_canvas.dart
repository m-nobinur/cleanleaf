import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/geometry/quad.dart';
import '../domain/quad_geometry.dart';

typedef _HandleSpec = ({
  String Function(int quarterTurns) label,
  bool corner,
  Point Function(Quad quad) at,
  Quad Function(Quad start, Point delta) drag,
});

const _cornerNames = ['Top left', 'Top right', 'Bottom right', 'Bottom left'];
const _edgeNames = ['Top', 'Right', 'Bottom', 'Left'];

final List<_HandleSpec> _handles = [
  // Labels name the on-screen position, so they follow the rotation.
  // Phase 2 (CRP-4) adds each edge's anchor handles next to its midpoint.
  for (var e = 0; e < 4; e++)
    (
      label: (t) => '${_edgeNames[(e + t) % 4]} edge',
      corner: false,
      at: (q) => edgeMidpoint(q, e),
      drag: (q, d) => moveEdge(q, e, d),
    ),
  // Corners last so they win hit tests where they overlap a midpoint.
  for (var i = 0; i < 4; i++)
    (
      label: (t) => '${_cornerNames[(i + t) % 4]} corner',
      corner: true,
      at: (q) => q.corners[i],
      drag: (q, d) {
        final c = q.corners[i];
        return moveCorner(q, i, (x: c.x + d.x, y: c.y + d.y));
      },
    ),
];

/// The page image with the editable quad. Corners stay in unrotated image
/// space; [quarterTurns] only rotates the view.
class CropCanvas extends StatefulWidget {
  const CropCanvas({
    super.key,
    required this.image,
    required this.imageSize,
    required this.quarterTurns,
    required this.quad,
  });

  final ImageProvider image;
  final Size imageSize;
  final int quarterTurns;
  final ValueNotifier<Quad> quad;

  @override
  State<CropCanvas> createState() => _CropCanvasState();
}

class _CropCanvasState extends State<CropCanvas> {
  static const _handleSize = kMinInteractiveDimension;
  static const _pad = _handleSize / 2;
  static const _loupeSize = 112.0;
  static const _loupeLift = 96.0;

  final _stackKey = GlobalKey();
  final _imageKey = GlobalKey();
  final _loupeAt = ValueNotifier<Offset?>(null);
  Quad? _startQuad;
  Point? _startPointer;

  @override
  void dispose() {
    _loupeAt.dispose();
    super.dispose();
  }

  RenderBox _box(GlobalKey key) =>
      key.currentContext!.findRenderObject()! as RenderBox;

  Point _toImage(Offset global) {
    final box = _box(_imageKey);
    final local = box.globalToLocal(global);
    return (x: local.dx / box.size.width, y: local.dy / box.size.height);
  }

  void _showLoupe(Point p) {
    final box = _box(_imageKey);
    final global = box.localToGlobal(
      Offset(p.x * box.size.width, p.y * box.size.height),
    );
    _loupeAt.value = _box(_stackKey).globalToLocal(global);
  }

  void _onDragStart(_HandleSpec h, DragStartDetails d) {
    _startQuad = widget.quad.value;
    _startPointer = _toImage(d.globalPosition);
    _showLoupe(h.at(_startQuad!));
  }

  void _onDragUpdate(_HandleSpec h, DragUpdateDetails d) {
    final now = _toImage(d.globalPosition);
    final delta = (x: now.x - _startPointer!.x, y: now.y - _startPointer!.y);
    final quad = h.drag(_startQuad!, delta);
    widget.quad.value = quad;
    _showLoupe(h.at(quad));
  }

  void _onDragEnd() => _loupeAt.value = null;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final turned = widget.quarterTurns.isOdd;
        final available = Size(
          math.max(0, constraints.maxWidth - 2 * _pad),
          math.max(0, constraints.maxHeight - 2 * _pad),
        );
        final shown = applyBoxFit(
          BoxFit.contain,
          turned ? widget.imageSize.flipped : widget.imageSize,
          available,
        ).destination;
        final size = turned ? shown.flipped : shown;
        return Stack(
          key: _stackKey,
          fit: StackFit.expand,
          children: [
            Center(
              child: RotatedBox(
                quarterTurns: widget.quarterTurns,
                child: SizedBox(
                  width: size.width + 2 * _pad,
                  height: size.height + 2 * _pad,
                  child: Stack(
                    children: [
                      Positioned(
                        left: _pad,
                        top: _pad,
                        width: size.width,
                        height: size.height,
                        child: RepaintBoundary(
                          child: Image(
                            key: _imageKey,
                            image: widget.image,
                            fit: BoxFit.fill,
                            filterQuality: FilterQuality.medium,
                            gaplessPlayback: true,
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: ValueListenableBuilder(
                          valueListenable: widget.quad,
                          builder: (context, quad, _) =>
                              _overlay(context, quad, size),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ValueListenableBuilder(
              valueListenable: _loupeAt,
              builder: (context, at, _) => at == null
                  ? const SizedBox.shrink()
                  : _loupe(context, at, constraints.biggest),
            ),
          ],
        );
      },
    );
  }

  Widget _overlay(BuildContext context, Quad quad, Size size) {
    final colors = ShadTheme.of(context).colorScheme;
    return Stack(
      children: [
        Positioned(
          left: _pad,
          top: _pad,
          width: size.width,
          height: size.height,
          child: IgnorePointer(
            child: CustomPaint(
              painter: _QuadPainter(
                quad: quad,
                line: isValidQuad(quad) ? colors.primary : colors.destructive,
                scrim: colors.background.withValues(alpha: 0.55),
              ),
            ),
          ),
        ),
        for (final h in _handles)
          Positioned(
            // _pad is half a handle, so the image offset and centering cancel.
            left: h.at(quad).x * size.width,
            top: h.at(quad).y * size.height,
            width: _handleSize,
            height: _handleSize,
            child: Semantics(
              label: h.label(widget.quarterTurns),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                dragStartBehavior: DragStartBehavior.down,
                onPanStart: (d) => _onDragStart(h, d),
                onPanUpdate: (d) => _onDragUpdate(h, d),
                onPanEnd: (_) => _onDragEnd(),
                onPanCancel: _onDragEnd,
                child: Center(child: _HandleDot(corner: h.corner)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _loupe(BuildContext context, Offset at, Size area) {
    final colors = ShadTheme.of(context).colorScheme;
    const r = _loupeSize / 2;
    var center = at.translate(0, -_loupeLift);
    // No room above: beside the finger, toward the middle, never under it.
    if (center.dy < r) {
      center = at.translate(
        at.dx < area.width / 2 ? _loupeLift : -_loupeLift,
        0,
      );
    }
    center = Offset(
      center.dx.clamp(r, math.max(r, area.width - r)),
      center.dy.clamp(r, math.max(r, area.height - r)),
    );
    return Positioned(
      left: center.dx - r,
      top: center.dy - r,
      child: IgnorePointer(
        child: RawMagnifier(
          size: const Size.square(_loupeSize),
          magnificationScale: 2,
          focalPointOffset: at - center,
          decoration: MagnifierDecoration(
            shape: CircleBorder(
              side: BorderSide(color: colors.primary, width: 2),
            ),
          ),
        ),
      ),
    );
  }
}

class _HandleDot extends StatelessWidget {
  const _HandleDot({required this.corner});

  final bool corner;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    // Corner rings stay hollow so the loupe shows the image under them.
    return Container(
      width: corner ? 20 : 12,
      height: corner ? 20 : 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: corner ? null : colors.primary,
        border: Border.all(
          color: corner ? colors.primary : colors.foreground,
          width: corner ? 2.5 : 1.5,
        ),
      ),
    );
  }
}

class _QuadPainter extends CustomPainter {
  const _QuadPainter({
    required this.quad,
    required this.line,
    required this.scrim,
  });

  final Quad quad;
  final Color line;
  final Color scrim;

  @override
  void paint(Canvas canvas, Size size) {
    final points = [
      for (final p in quad.corners) Offset(p.x * size.width, p.y * size.height),
    ];
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addPolygon(points, true),
      Paint()..color = scrim,
    );
    canvas.drawPath(
      Path()..addPolygon(points, true),
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_QuadPainter old) =>
      old.quad != quad || old.line != line || old.scrim != scrim;
}
