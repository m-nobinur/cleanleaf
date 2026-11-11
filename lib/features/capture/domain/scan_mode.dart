enum ScanMode {
  document,
  idCard,
  passport,
  receipt,
  book,
  qrCode,
  barcode;

  // Code modes ship with the decoder (T-029); book captures one spread as one
  // page until Phase 2 adds split and dewarp.
  bool get isAvailable => this != qrCode && this != barcode;

  /// Code modes decode text; the rest produce a document page.
  bool get producesPage => this != qrCode && this != barcode;

  /// Reads a `?mode=` value; unknown or unavailable modes fall back to document.
  static ScanMode parse(String? name) {
    final mode = ScanMode.values.asNameMap()[name];
    return mode != null && mode.isAvailable ? mode : document;
  }
}
