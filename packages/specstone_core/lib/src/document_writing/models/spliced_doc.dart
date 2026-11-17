/// A doc's LF text with one part spliced in.
final class SplicedDoc {
  const new({required this.lfText, required this.marksDraft});

  final String lfText;

  /// Whether the write marks the doc a draft.
  final bool marksDraft;
}
