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

/// The faults of one `get` call whose names hold faults of two or more codes.
///
/// [faults] holds one fault per code, at least two, in the order of each
/// code's first name; the exit status and the JSON envelope are the first
/// fault's.
final class IndexFaults implements SpecstoneFault {
  const new(this.faults);

  /// The faults, one per code.
  final List<SpecstoneFault> faults;

  @override
  int get exitStatus => faults.first.exitStatus;

  /// Returns the first fault's envelope.
  @override
  Map<String, Object> toJson() => faults.first.toJson();

  /// Returns one line per fault.
  @override
  String toText() => faults.map((fault) => fault.toText()).join('\n');

  @override
  String toString() => toText();
}
