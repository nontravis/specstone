/// A section's `summary_rows` as a layer writes it: a row count, or off.
///
/// A later layer's value replaces a lower one, so the off state stays apart
/// from the unset state, which a null [SummaryRows] stands for.
final class SummaryRows {
  /// A summary doc prints the section's first [count] table rows.
  const new rows(int this.count);

  /// The layer writes `false`, which clears a lower layer's count.
  const new off() : count = null;

  /// The body rows a summary doc prints; null when off.
  final int? count;

  /// Returns the count, or `false` when off, as the schema prints it.
  Object toJson() => count ?? false;
}
