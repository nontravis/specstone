import 'package:specstone_core/src/index_query/models/file_stat_key.dart';

/// What `check` keeps of one code file between runs; [stat] vouches for it.
///
/// A fact is null or empty until a rule that reads it has seen the file.
final class CodeFileFacts {
  new({
    required this.stat,
    this.fingerprint,
    this.mentionTexts,
    Set<String>? resolved,
  }) : resolved = resolved ?? {};

  /// The stat key of the file when the facts were read.
  final FileStatKey stat;

  /// The file's `fileCodeFingerprint`.
  String? fingerprint;

  /// The distinct texts of the doc mentions the file holds, in first-seen
  /// order; null before a scan.
  List<String>? mentionTexts;

  /// The `implements` entries whose Symbol resolved in the file.
  final Set<String> resolved;
}
