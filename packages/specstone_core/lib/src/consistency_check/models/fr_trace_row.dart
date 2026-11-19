/// One tracked row of an FR trace table: its first cell and file line.
final class FrTraceRow {
  const new({required this.cell, required this.line});

  final String cell;
  final int line;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is FrTraceRow && other.cell == cell && other.line == line;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(cell, line);
}
