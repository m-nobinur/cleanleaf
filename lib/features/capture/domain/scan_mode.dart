enum ScanMode {
  document,
  idCard,
  receipt,
  book;

  // Book needs dewarping (Phase 2).
  bool get isAvailable => this != book;

  /// Reads a `?mode=` value; unknown or unavailable modes fall back to document.
  static ScanMode parse(String? name) {
    final mode = ScanMode.values.asNameMap()[name];
    return mode != null && mode.isAvailable ? mode : document;
  }
}
