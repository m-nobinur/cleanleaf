class Document(
  final String id, {
  required final String title,
  required final DateTime createdAt,
  required final DateTime updatedAt,
  final String? folderId,
});
