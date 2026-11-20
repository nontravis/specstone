/// An LF text after a rewrite, and the label naming what changed; null when
/// nothing did.
final class LabeledRewrite {
  const new({required this.lf, required this.label});

  final String lf;
  final String? label;
}
