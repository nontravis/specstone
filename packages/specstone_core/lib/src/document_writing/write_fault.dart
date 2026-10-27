import 'package:specstone_core/src/fault.dart';

/// A document writing fault code from the `s05_errors.md` catalog.
///
/// Values follow catalog order. [wire] is the snake_case code printed in the
/// JSON `error.code`; [exitStatus] is the process exit status for the fault.
enum WriteFaultCode {
  baseMismatch('base_mismatch', 75),
  fieldUnknown('field_unknown', 64),
  fieldValueInvalid('field_value_invalid', 64),
  fieldNotWritable('field_not_writable', 64),
  requiredTarget('required_target', 64),
  docExists('doc_exists', 64),
  docReferenced('doc_referenced', 64),
  positionOutOfRange('position_out_of_range', 64),
  docTypeNotMovable('doc_type_not_movable', 64),
  ownerTerminalRequired('owner_terminal_required', 77);

  new(this.wire, this.exitStatus);

  /// The snake_case code printed in the JSON envelope.
  final String wire;

  /// The process exit status for the fault.
  final int exitStatus;
}

/// The current text and base hash of a target a write found changed.
///
/// A `base_mismatch` carries it so the caller can retry without a `get`.
final class CurrentTarget {
  const new({required this.heading, required this.text, required this.base});

  /// `get`'s naming line with the base, printed only in text mode.
  final String heading;

  /// The target's current text.
  final String text;

  /// The base hash of [text].
  final String base;
}

/// The one fault the six write commands raise for a refused write.
///
/// [message] is plain text with no location prefix.
final class WriteFault implements SpecstoneFault {
  new(
    this.code,
    this.message, {
    this.file,
    this.key,
    this.relatedFiles = const [],
    this.current,
  });

  /// The catalog code of this fault.
  final WriteFaultCode code;

  /// Plain human text with no location prefix.
  final String message;

  /// The DocPath the fault concerns, when it concerns one.
  final String? file;

  /// The section key, field id, or other target key, when one applies.
  final String? key;

  /// The other DocPaths involved, such as the docs that link into a delete.
  final List<String> relatedFiles;

  /// The target's current text and base, for `base_mismatch`.
  final CurrentTarget? current;

  @override
  int get exitStatus => code.exitStatus;

  /// Returns the JSON envelope `{'error': {...}}`.
  ///
  /// `file`, `key`, and `current` appear when set; `relatedFiles` appears when
  /// not empty.
  @override
  Map<String, Object> toJson() => {
    'error': {
      'code': code.wire,
      'message': message,
      'file': ?file,
      'key': ?key,
      if (relatedFiles.isNotEmpty) 'relatedFiles': relatedFiles,
      if (current case final current?)
        'current': {'text': current.text, 'base': current.base},
    },
  };

  /// Returns [message] alone without a file, else
  /// `<file>[: <key>]: <message>[; also <f1>, <f2>]`.
  @override
  String toText() {
    final file = this.file;
    if (file == null) return message;
    final located = key == null ? '$file: $message' : '$file: $key: $message';
    return relatedFiles.isEmpty
        ? located
        : '$located; also ${relatedFiles.join(', ')}';
  }

  @override
  String toString() => toText();
}
