import 'dart:convert';

import '../../../core/geometry/quad.dart';
import '../../../core/storage/app_database.dart';
import '../domain/document_page.dart';

List<double> _point(Point p) => [p.x, p.y];

Point _parsePoint(Object? json) {
  final [x, y] = (json! as List<Object?>).cast<num>();
  return (x: x.toDouble(), y: y.toDouble());
}

String encodeCorners(Quad q) => jsonEncode(q.corners.map(_point).toList());

Quad decodeCorners(String json) {
  final [tl, tr, br, bl] = (jsonDecode(json) as List<Object?>)
      .map(_parsePoint)
      .toList();
  return (topLeft: tl, topRight: tr, bottomRight: br, bottomLeft: bl);
}

String encodeAnchors(EdgeAnchors anchors) =>
    jsonEncode([for (final edge in anchors) edge.map(_point).toList()]);

EdgeAnchors decodeAnchors(String json) => [
  for (final edge in jsonDecode(json) as List<Object?>)
    (edge! as List<Object?>).map(_parsePoint).toList(),
];

String encodeFilterParams(Map<String, double> params) => jsonEncode(params);

Map<String, double> decodeFilterParams(String json) => {
  for (final MapEntry(:key, :value)
      in (jsonDecode(json) as Map<String, Object?>).entries)
    key: (value! as num).toDouble(),
};

DocumentPage pageFromRow(PageRow r) => DocumentPage(
  r.id,
  documentId: r.documentId,
  index: r.pageIndex,
  originalPath: r.originalPath,
  corners: decodeCorners(r.corners),
  detectedCorners: r.detectedCorners == null
      ? null
      : decodeCorners(r.detectedCorners!),
  source: PageSource.values.byName(r.source),
  anchors: decodeAnchors(r.anchors),
  rotation: r.rotation,
  filter: PageFilter.values.byName(r.filter),
  filterParams: decodeFilterParams(r.filterParams),
  renderPath: r.renderPath,
  thumbPath: r.thumbPath,
);
