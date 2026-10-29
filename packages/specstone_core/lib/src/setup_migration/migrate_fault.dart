import 'package:specstone_core/src/fault.dart';

/// A setup and migration fault code from the `s05_errors.md` catalog.
///
/// [wire] is the snake_case code printed in the error envelope; [exitStatus]
/// is the process exit status for the fault.
enum MigrateFaultCode {
  workingTreeDirty('working_tree_dirty', 75),
  gitWorkTreeRequired('git_work_tree_required', 78),
  groupSlugDuplicate('group_slug_duplicate', 65),
  upgradeCollision('upgrade_collision', 65),
  overrideDangling('override_dangling', 78),
  configExists('config_exists', 64),
  gitFailed('git_failed', 75);

  new(this.wire, this.exitStatus);

  /// The snake_case code printed in the error envelope.
  final String wire;

  /// The process exit status for the fault.
  final int exitStatus;
}

/// The one fault `specstone migrate` and `specstone setup` raise for a refused
/// run.
///
/// [message] is plain text with no location prefix.
final class MigrateFault implements SpecstoneFault {
  new(
    this.code,
    this.message, {
    this.file,
    this.key,
    this.relatedFiles = const [],
    this.more = const [],
  });

  /// The catalog code of this fault.
  final MigrateFaultCode code;

  /// Plain human text with no location prefix.
  final String message;

  /// The path the fault concerns, relative to the project root.
  final String? file;

  /// The key the fault concerns inside [file], when one applies.
  final String? key;

  /// The other paths involved.
  final List<String> relatedFiles;

  /// The further entries of the same fault, such as every dangling override.
  final List<MigrateFault> more;

  @override
  int get exitStatus => code.exitStatus;

  /// Returns the JSON envelope `{'error': {...}}` of this entry; [more] is
  /// not part of it.
  ///
  /// `file` and `key` appear when set; `relatedFiles` appears when not empty.
  @override
  Map<String, Object> toJson() => {
    'error': {
      'code': code.wire,
      'message': message,
      'file': ?file,
      'key': ?key,
      if (relatedFiles.isNotEmpty) 'relatedFiles': relatedFiles,
    },
  };

  /// Returns this entry's line, then each of [more] on its own line.
  ///
  /// An entry reads [message] alone without a file, else
  /// `<file>[: <key>]: <message>[; also <f1>, <f2>]`.
  @override
  String toText() =>
      [_entryText(), for (final next in more) next.toText()].join('\n');

  String _entryText() {
    final file = this.file;
    if (file == null) return message;
    final located = key == null ? '$file: $message' : '$file: $key: $message';
    return relatedFiles.isEmpty
        ? located
        : '$located; also ${relatedFiles.join(', ')}';
  }

  @override
  String toString() => 'MigrateFault(${code.wire}): ${toText()}';
}
