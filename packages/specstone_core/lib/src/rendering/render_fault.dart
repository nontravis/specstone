import 'package:specstone_core/src/fault.dart';

/// A rendering fault code from the `s05_errors.md` catalog.
///
/// Values follow catalog order. [wire] is the snake_case code printed in the
/// JSON `error.code`; [exitStatus] is the process exit status for the fault.
enum RenderFaultCode {
  projectNotFound('project_not_found', 78),
  targetMissing('target_missing', 64),
  targetNotFound('target_not_found', 64),
  targetOutsideDocsRoot('target_outside_docs_root', 64),
  argumentInvalid('argument_invalid', 64),
  outputNotWritable('output_not_writable', 73);

  new(this.wire, this.exitStatus);

  /// The snake_case code printed in the JSON envelope.
  final String wire;

  /// The process exit status for the fault.
  final int exitStatus;
}

/// The one fault `format` and `build` raise for a rendering failure.
///
/// [message] is plain text with no location prefix; [file] is set for
/// `output_not_writable` only.
final class RenderFault implements SpecstoneFault {
  new(this.code, this.message, {this.file});

  /// The catalog code of this fault.
  final RenderFaultCode code;

  /// Plain human text with no location prefix.
  final String message;

  /// The path to fix, relative to the project root with `/` separators.
  final String? file;

  @override
  int get exitStatus => code.exitStatus;

  /// Returns the JSON envelope `{'error': {...}}`; `file` appears when set.
  @override
  Map<String, Object> toJson() => {
    'error': {'code': code.wire, 'message': message, 'file': ?file},
  };

  /// Returns [message], prefixed by `<file>: ` when [file] is set.
  @override
  String toText() => file == null ? message : '$file: $message';

  @override
  String toString() => toText();
}
