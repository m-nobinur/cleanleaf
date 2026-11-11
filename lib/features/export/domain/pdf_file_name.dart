const _maxLength = 80;
final _unsafe = RegExp(r'[\\/:*?"<>|\x00-\x1f]+');

/// A title made safe as a file name for the share sheet, without extension.
String pdfFileName(String title) {
  final cleaned = title
      .replaceAll(_unsafe, '_')
      .trim()
      .replaceFirst(RegExp(r'^\.+'), '');
  if (cleaned.isEmpty) return 'Scan';
  return cleaned.length > _maxLength
      ? cleaned.substring(0, _maxLength).trim()
      : cleaned;
}
