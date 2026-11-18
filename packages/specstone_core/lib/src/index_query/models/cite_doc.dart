/// A doc a cite can name.
final class CiteDoc {
  const new({
    required this.docPath,
    required this.docTypeId,
    required this.name,
  });

  final String docPath;
  final String? docTypeId;
  final String name;
}
