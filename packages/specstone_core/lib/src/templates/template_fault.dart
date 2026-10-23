/// A template, pack, or config fault code from the `s05_errors.md` catalog.
///
/// Values follow catalog order. [wire] is the snake_case code printed in the
/// JSON `error.code`; [exitStatus] is the process exit status for the fault.
enum FaultCode {
  yamlSyntax('yaml_syntax', 78),
  unknownKey('unknown_key', 78),
  unknownValue('unknown_value', 78),
  missingKey('missing_key', 78),
  docTypeIdMismatch('doc_type_id_mismatch', 78),
  docTypePathConflict('doc_type_path_conflict', 78),
  overrideIdNotFound('override_id_not_found', 78),
  lintWordNotFound('lint_word_not_found', 78),
  listOverrideNeedsAddRemove('list_override_needs_add_remove', 78),
  afterIdNotFound('after_id_not_found', 78),
  extendsCycle('extends_cycle', 78),
  parentCycle('parent_cycle', 78),
  extendsTargetUnknown('extends_target_unknown', 78),
  extendsInOverride('extends_in_override', 78),
  docTypeDuplicate('doc_type_duplicate', 78),
  lockedFieldDisabled('locked_field_disabled', 78),
  referenceLinkConflict('reference_link_conflict', 78),
  referenceFileMissing('reference_file_missing', 78),
  referenceFileOutside('reference_file_outside', 78),
  referenceDocOutsideProject('reference_doc_outside_project', 78),
  referenceTitleNotFound('reference_title_not_found', 78),
  packNotFound('pack_not_found', 78),
  packVersionInvalid('pack_version_invalid', 78),
  packNameMismatch('pack_name_mismatch', 78),
  personalPackConflict('personal_pack_conflict', 78),
  personalPackVersionDiffers('personal_pack_version_differs', 78),
  packPinOlder('pack_pin_older', 78),
  packPinNewer('pack_pin_newer', 78),
  prdCoreMissing('prd_core_missing', 78),
  docTypeUnknown('doc_type_unknown', 64);

  new(this.wire, this.exitStatus);

  /// The snake_case code printed in the JSON envelope.
  final String wire;

  /// The process exit status: 78 for every fault except `doc_type_unknown`.
  final int exitStatus;
}

/// The one fault the engine raises for a bad template, pack, or config.
///
/// [message] is plain text with no file, line, or key prefix; the location
/// lives in [file], [line], [key], and [relatedFiles].
final class TemplateFault implements Exception {
  new(
    this.code,
    this.message, {
    this.file,
    this.key,
    this.line,
    this.relatedFiles = const [],
  });

  /// The catalog code of this fault.
  final FaultCode code;

  /// Plain human text with no location prefix.
  final String message;

  /// The file to fix, with `/` separators, or null when no file applies.
  final String? file;

  /// The dotted key path the fault names, or null when no key applies.
  final String? key;

  /// The 1-based line in [file], or null when unknown.
  final int? line;

  /// The other files the fault names, in load order.
  final List<String> relatedFiles;

  /// The process exit status for this fault.
  int get exitStatus => code.exitStatus;

  /// Returns the JSON envelope `{'error': {...}}`.
  ///
  /// `file`, `key`, `line`, and `relatedFiles` appear only when set.
  Map<String, Object> toJson() => {
    'error': {
      'code': code.wire,
      'message': message,
      'file': ?file,
      'key': ?key,
      'line': ?line,
      if (relatedFiles.isNotEmpty) 'relatedFiles': relatedFiles,
    },
  };

  /// Returns the stderr form `<file>[:<line>][: <key>]: <message>`.
  ///
  /// Appends `; also <f1>, <f2>` for [relatedFiles]; returns [message] alone
  /// when [file] is null.
  String toText() {
    final file = this.file;
    if (file == null) return message;
    final location = line == null ? file : '$file:$line';
    final keyPart = key == null ? '' : ': $key';
    final also = relatedFiles.isEmpty
        ? ''
        : '; also ${relatedFiles.join(', ')}';
    return '$location$keyPart: $message$also';
  }

  @override
  String toString() => toText();
}
