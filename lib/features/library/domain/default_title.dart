String defaultDocumentTitle(DateTime time) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'Scan ${time.year}-${two(time.month)}-${two(time.day)} '
      '${two(time.hour)}.${two(time.minute)}';
}
