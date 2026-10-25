import 'package:specstone_core/src/fault.dart';

/// An index query fault code from the `s05_errors.md` catalog.
///
/// Values follow catalog order. [wire] is the snake_case code printed in the
/// JSON `error.code`; [exitStatus] is the process exit status for the fault.
enum IndexFaultCode {
  argumentMissing('argument_missing', 64),
  argumentConflict('argument_conflict', 64),
  argumentInvalid('argument_invalid', 64),
  docNotFound('doc_not_found', 64),
  sectionNotFound('section_not_found', 64),
  untypedTarget('untyped_target', 64),
  codePathNotFound('code_path_not_found', 64),
  codePathOutsideProject('code_path_outside_project', 64),
  queryTooShort('query_too_short', 64),
  indexNotWritable('index_not_writable', 73),
  indexBusy('index_busy', 75);

  new(this.wire, this.exitStatus);

  /// The snake_case code printed in the JSON envelope.
  final String wire;

  /// The process exit status for the fault.
  final int exitStatus;
}

/// The one fault `get`, `search`, and `context` raise for a failed query.
///
/// [message] is plain text with no location prefix.
final class IndexFault implements SpecstoneFault {
  new(this.code, this.message);

  /// The catalog code of this fault.
  final IndexFaultCode code;

  /// Plain human text with no location prefix.
  final String message;

  @override
  int get exitStatus => code.exitStatus;

  /// Returns the JSON envelope `{'error': {...}}`.
  @override
  Map<String, Object> toJson() => {
    'error': {'code': code.wire, 'message': message},
  };

  /// Returns [message].
  @override
  String toText() => message;

  @override
  String toString() => toText();
}
