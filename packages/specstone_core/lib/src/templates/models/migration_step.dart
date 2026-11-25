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

/// A `relink_merged_docs` step: `migrate` repairs the links an earlier
/// `merge_doc`, `drop_section`, or `rename_section` step of its pack left
/// behind; the step takes no keys.
///
/// It reaches no doc type: the plan runs it after every doc took its steps.
final class RelinkMergedDocs extends MigrationStep {
  const new();

  @override
  bool touches(String docTypeId) => false;

  @override
  String get kind => 'relink_merged_docs';
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

/// A `drop_section` step: the section [sectionId], headed [sectionHeader],
/// leaves the docs of [docTypes] whose merged type no longer defines it.
final class DropSection extends MigrationStep {
  const new({
    required this.docTypes,
    required this.sectionId,
    required this.sectionHeader,
  });

  /// The ids of the doc types whose docs this step rewrites.
  final List<String> docTypes;

  /// The id of the section this step removes.
  final String sectionId;

  /// The heading text of the section this step removes, as written.
  final String sectionHeader;

  @override
  bool touches(String docTypeId) => docTypes.contains(docTypeId);

  @override
  String get kind => 'drop_section';
}

/// One section a [MergeDoc] maps: the `from` doc's section [fromId], headed
/// [fromHeader], lands in the `to` doc's section [toId].
final class MergeSection {
  const new({
    required this.fromId,
    required this.fromHeader,
    required this.toId,
  });

  /// The id of the `from` doc type's section, as written.
  final String fromId;

  /// The heading text of the `from` doc type's section, as written.
  final String fromHeader;

  /// The id of the `to` doc type's section that takes it.
  final String toId;
}

/// A `merge_doc` step: the docs of the dropped doc type [fromId] fold into the
/// docs of the doc type [toId].
///
/// The `from` type is in no merged set after the upgrade, so the step carries
/// its path pattern [fromPath]; it touches the `to` type alone.
final class MergeDoc extends MigrationStep {
  const new({
    required this.fromId,
    required this.fromPath,
    required this.toId,
    required this.sections,
  });

  /// The id of the doc type the pack drops.
  final String fromId;

  /// The path pattern of the dropped doc type, as written.
  final String fromPath;

  /// The id of the doc type that takes the docs over.
  final String toId;

  /// The section mappings, in file order.
  final List<MergeSection> sections;

  @override
  bool touches(String docTypeId) => docTypeId == toId;

  @override
  String get kind => 'merge_doc';
}

/// A `drop_doc_type` step: the doc type [id] leaves the pack with no
/// `merge_doc` step, so its docs stay as written.
///
/// The `id` type is in no merged set after the upgrade, so the step carries
/// its path pattern [path]. It reaches no doc: the plan reads it only to keep
/// the project layer files of the type.
final class DropDocType extends MigrationStep {
  const new({required this.id, required this.path});

  /// The id of the doc type the pack drops.
  final String id;

  /// The path pattern of the dropped doc type, as written.
  final String path;

  @override
  bool touches(String docTypeId) => false;

  @override
  String get kind => 'drop_doc_type';
}
