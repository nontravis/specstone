/// A label a file keeps: its 1-based [line] and the [label] as written.
final class KeptLabel {
  const new({required this.line, required this.label});

  final int line;
  final String label;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is KeptLabel && other.line == line && other.label == label;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(line, label);
}

/// A doc text with its labels converted, how many it replaced, and the
/// labels it keeps.
final class LabelConversion {
  const new({required this.lf, required this.rewrites, required this.kept});

  final String lf;
  final int rewrites;
  final List<KeptLabel> kept;
}
