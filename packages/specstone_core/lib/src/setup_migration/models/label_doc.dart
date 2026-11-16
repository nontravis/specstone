/// A doc the label pass reads: its DocPath and its LF text.
final class LabelDoc {
  const new({required this.docPath, required this.lf});

  final String docPath;
  final String lf;
}

/// A doc of a legacy tree: its final DocPath, its legacy path, and its LF
/// text.
final class LegacyLabelDoc {
  const new({
    required this.docPath,
    required this.legacyPath,
    required this.lf,
  });

  final String docPath;
  final String legacyPath;
  final String lf;
}
