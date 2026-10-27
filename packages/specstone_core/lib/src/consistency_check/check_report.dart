import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';

/// Orders findings by path (code points), line, kind wire, then message.
int compareFindings(Finding a, Finding b) {
  final byPath = compareCodePoints(a.path, b.path);
  if (byPath != 0) return byPath;
  final byLine = a.line.compareTo(b.line);
  if (byLine != 0) return byLine;
  final byKind = compareCodePoints(a.kind.wire, b.kind.wire);
  if (byKind != 0) return byKind;
  return compareCodePoints(a.message, b.message);
}

/// The sorted findings and warnings of one check run.
final class CheckReport {
  new({required List<Finding> findings, this.warnings = const []})
    : findings = List<Finding>.unmodifiable(
        <Finding>[...findings]..sort(compareFindings),
      );

  /// The findings in [compareFindings] order.
  final List<Finding> findings;

  /// Notes that are no finding and do not change [exitStatus].
  final List<String> warnings;

  /// Each finding's text line, then the count line; every line ends in `\n`.
  String get text {
    final count = findings.length;
    final summary = count == 1 ? '1 finding' : '$count findings';
    return [
      for (final f in findings) f.textLine,
      summary,
    ].map((l) => '$l\n').join();
  }

  /// The JSON object: `findings`, `count`, and `warnings` when non-empty.
  Map<String, Object> get json => {
    'findings': [for (final f in findings) f.toJson()],
    'count': findings.length,
    if (warnings.isNotEmpty) 'warnings': warnings,
  };

  /// 1 when any finding exists, else 0.
  int get exitStatus => findings.isEmpty ? 0 : 1;
}
