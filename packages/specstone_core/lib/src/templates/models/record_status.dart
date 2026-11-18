/// The status a `record_status` line gives its item.
enum RecordStatus {
  planned('planned'),
  implemented('implemented'),
  deprecated('deprecated'),
  skipped('skipped');

  new(this.wire);

  /// The name the record format uses for this status.
  final String wire;

  /// Whether the item has code or tests to resolve: it is `implemented` or
  /// `deprecated`.
  bool get isBuilt => this == implemented || this == deprecated;

  /// Returns the status named [wire], or null when [wire] names none.
  static RecordStatus? byWire(String wire) =>
      values.where((s) => s.wire == wire).firstOrNull;
}
