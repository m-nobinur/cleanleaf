import '../../../core/geometry/quad.dart';

enum PageFilter { original, enhancedColor, grayscale, blackWhite }

enum PageSource { camera, gallery, googleScanner }

// Edge order: top, right, bottom, left.
typedef EdgeAnchors = List<List<Point>>;

const EdgeAnchors noAnchors = [[], [], [], []];

const Quad fullFrame = (
  topLeft: (x: 0, y: 0),
  topRight: (x: 1, y: 0),
  bottomRight: (x: 1, y: 1),
  bottomLeft: (x: 0, y: 1),
);

// Paths are relative to the file store root.
class DocumentPage(
  final String id, {
  required final String documentId,
  required final int index,
  required final String originalPath,
  required final Quad corners,
  final Quad? detectedCorners,
  final PageSource source = PageSource.camera,
  final EdgeAnchors anchors = noAnchors,
  final int rotation = 0,
  final PageFilter filter = PageFilter.enhancedColor,
  final Map<String, double> filterParams = const {},
  final String? renderPath,
  final String? thumbPath,
}) {
  DocumentPage copyWith({
    Quad? corners,
    EdgeAnchors? anchors,
    int? rotation,
    PageFilter? filter,
    Map<String, double>? filterParams,
  }) => DocumentPage(
    id,
    documentId: documentId,
    index: index,
    originalPath: originalPath,
    corners: corners ?? this.corners,
    detectedCorners: detectedCorners,
    source: source,
    anchors: anchors ?? this.anchors,
    rotation: rotation ?? this.rotation,
    filter: filter ?? this.filter,
    filterParams: filterParams ?? this.filterParams,
    renderPath: renderPath,
    thumbPath: thumbPath,
  );
}
