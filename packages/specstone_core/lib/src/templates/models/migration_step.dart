/// One step of a `PackMigration`, named by its YAML [kind] key.
sealed class MigrationStep {
  const new();

  /// Whether this step reaches docs of the doc type [docTypeId].
  bool touches(String docTypeId);

  /// The YAML key that names this step's kind.
  String get kind;
}

/// A `rename_section` step: a section id and header move to new values.
final class RenameSection extends MigrationStep {
  const new({
    required this.docType,
    required this.fromId,
    required this.fromHeader,
    required this.toId,
    required this.toHeader,
  });

  /// The id of the doc type this step touches.
  final String docType;

  /// The section id before this step.
  final String fromId;

  /// The section header before this step.
  final String fromHeader;

  /// The section id after this step.
  final String toId;

  /// The section header after this step.
  final String toHeader;

  @override
  bool touches(String docTypeId) => docTypeId == docType;

  @override
  String get kind => 'rename_section';
}

/// A `rename_field` step: a field of one doc type moves to a new name.
final class RenameField extends MigrationStep {
  const new({required this.docType, required this.from, required this.to});

  /// The id of the doc type this step touches.
  final String docType;

  /// The field name before this step.
  final String from;

  /// The field name after this step.
  final String to;

  @override
  bool touches(String docTypeId) => docTypeId == docType;

  @override
  String get kind => 'rename_field';
}

/// A `move_file` step: a doc file moves to a new path pattern.
final class MoveFile extends MigrationStep {
  const new({required this.docType, required this.from, required this.to});

  /// The id of the doc type this step touches.
  final String docType;

  /// The path pattern before this step, as written.
  final String from;

  /// The path pattern after this step, as written.
  final String to;

  @override
  bool touches(String docTypeId) => docTypeId == docType;

  @override
  String get kind => 'move_file';
}

/// A `move_to_record` step: the [fields] of the docs of [docTypes] move into
/// their entries of the record doc type [to].
final class MoveToRecord extends MigrationStep {
  const new({required this.docTypes, required this.fields, required this.to});

  /// The ids of the doc types whose values move.
  final List<String> docTypes;

  /// The ids of the fields that move.
  final List<String> fields;

  /// The id of the record doc type that receives the values.
  final String to;

  @override
  bool touches(String docTypeId) => docTypes.contains(docTypeId);

  @override
  String get kind => 'move_to_record';
}

/// A `stamp_code_fingerprints` step: `migrate` writes the current code
/// fingerprint on each code link it picks; the step takes no keys.
final class StampCodeFingerprints extends MigrationStep {
  const new();

  @override
  bool touches(String docTypeId) => false;

  @override
  String get kind => 'stamp_code_fingerprints';
}

/// A `restamp_code_fingerprints` step: `migrate` rewrites the code
/// fingerprint of each code link stamped under the rule before comment and
/// blank lines were dropped; the step takes no keys.
final class RestampCodeFingerprints extends MigrationStep {
  const new();

  @override
  bool touches(String docTypeId) => false;

  @override
  String get kind => 'restamp_code_fingerprints';
}

/// A `bullet_lines` step: each line of one section that opens with a listed
/// prefix becomes a markdown bullet.
final class BulletLines extends MigrationStep {
  const new({
    required this.docType,
    required this.section,
    required this.prefixes,
  });

  /// The id of the doc type this step touches.
  final String docType;

  /// The id of the section whose lines this step bullets.
  final String section;

  /// The non-empty line openings that mark a line to bullet.
  final List<String> prefixes;

  @override
  bool touches(String docTypeId) => docTypeId == docType;

  @override
  String get kind => 'bullet_lines';
}

/// A `drop_default_lines` step: each invariant's nested line that states only
/// the default the guide prints leaves the docs of [docTypes].
final class DropDefaultLines extends MigrationStep {
  const new({required this.docTypes});

  /// The ids of the doc types whose docs this step rewrites.
  final List<String> docTypes;

  @override
  bool touches(String docTypeId) => docTypes.contains(docTypeId);

  @override
  String get kind => 'drop_default_lines';
}

/// A `strip_shared_copies` step: `migrate` removes each project layer line and
/// field that equals a merged shared entry reaching its doc type; the step
/// takes no keys.
///
/// It reaches no doc: the plan strips the project layer files as a whole.
final class StripSharedCopies extends MigrationStep {
  const new();

  @override
  bool touches(String docTypeId) => false;

  @override
  String get kind => 'strip_shared_copies';
}

/// A `drop_shared_lines` step: the shared line [ids] this pack version no
/// longer defines.
///
/// It reaches no doc: the plan reads it only to refuse a dangling override.
final class DropSharedLines extends MigrationStep {
  const new({required this.ids});

  /// The ids of the shared lines the pack drops, as written.
  final List<String> ids;

  @override
  bool touches(String docTypeId) => false;

  @override
  String get kind => 'drop_shared_lines';
}

/// A `mark_retrim` step: the docs of [docTypes] take [sections] in their
/// `retrim` field.
final class MarkRetrim extends MigrationStep {
  const new({required this.docTypes, required this.sections});

  /// The ids of the doc types whose docs this step marks.
  final List<String> docTypes;

  /// The ids of the sections this step marks for a trim.
  final List<String> sections;

  @override
  bool touches(String docTypeId) => docTypes.contains(docTypeId);

  @override
  String get kind => 'mark_retrim';
}
