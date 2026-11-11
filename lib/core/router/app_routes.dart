abstract final class AppRoutes {
  static const library = '/';
  static const capture = '/capture';
  static String editor(String pageId) => '/editor/$pageId';
  static String enhance(String pageId) => '/enhance/$pageId';
}
