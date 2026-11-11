enum ScanMode {
  document,
  idCard,
  passport,
  receipt,
  book,
  qrCode,
  barcode;

  /// The codes a code mode reads; null for modes that produce a page.
  CodeFamily? get codeFamily => switch (this) {
    qrCode => CodeFamily.matrix,
    barcode => CodeFamily.linear,
    _ => null,
  };

  /// Reads a `?mode=` value; unknown modes fall back to document.
  static ScanMode parse(String? name) =>
      ScanMode.values.asNameMap()[name] ?? document;
}

/// QR and other 2D codes, or 1D barcodes.
enum CodeFamily { matrix, linear }
