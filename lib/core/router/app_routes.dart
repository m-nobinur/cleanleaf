import '../../features/capture/domain/scan_mode.dart';

abstract final class AppRoutes {
  static const library = '/';
  static const capture = '/capture';
  static String captureIn(ScanMode mode) => '$capture?mode=${mode.name}';
  static String editor(String pageId, {bool fresh = false}) =>
      '/editor/$pageId${fresh ? '?fresh=1' : ''}';
  static String enhance(String pageId) => '/enhance/$pageId';
  static String document(String docId) => '/document/$docId';
}
