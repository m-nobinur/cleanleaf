import '../../features/capture/domain/scan_mode.dart';

abstract final class AppRoutes {
  static const library = '/';
  static const capture = '/capture';
  static String captureIn(ScanMode mode) => '$capture?mode=${mode.name}';
  static String confirm(String pageId) => '/confirm/$pageId';
  static String editor(String pageId) => '/editor/$pageId';
  static String enhance(String pageId) => '/enhance/$pageId';
}
