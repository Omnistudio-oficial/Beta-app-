class DocumentItem {
  final String id;
  final String title;
  final String category;
  final String updatedAt;
  final String content;

  const DocumentItem({
    required this.id,
    required this.title,
    required this.category,
    required this.updatedAt,
    required this.content,
  });
}
