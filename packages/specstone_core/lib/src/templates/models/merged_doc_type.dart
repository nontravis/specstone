import 'package:specstone_core/src/templates/models/merged_field.dart';
import 'package:specstone_core/src/templates/models/merged_lint.dart';
import 'package:specstone_core/src/templates/models/merged_section.dart';
import 'package:specstone_core/src/templates/models/merged_shared_line.dart';
import 'package:specstone_core/src/templates/models/reference_entry.dart';

/// A doc type with its layers folded into one, disabled entries dropped.
final class MergedDocType {
  const new({
    required this.id,
    required this.fields,
    required this.sections,
    required this.lint,
    required this.files,
    this.description,
    this.parent,
    this.extendsId,
    this.extendsChain = const [],
    this.path,
    this.title,
    this.maxDepth,
    this.isPerTarget = false,
    this.fixedNumbers = false,
    this.nestedPaths,
    this.bundle,
    this.bundleRefs,
    this.summaryFor,
    this.generators,
    this.reference,
    this.pack,
    this.sharedLines = const [],
    this.disabledFieldIds = const {},
    this.disabledSectionIds = const {},
  });

  /// The doc type id.
  final String id;

  /// The shared lines that reach this doc type, in print order.
  ///
  /// They stay out of [description], which holds the type's own text.
  final List<MergedSharedLine> sharedLines;

  /// The own description, then each shared line, one per line; null when none
  /// holds text.
  ///
  /// The JSON schema prints it whole. A many-type text guide leaves out the
  /// lines shared by all its types.
  String? get descriptionWithSharedLines => _descriptionWithout(const {});

  /// Returns [descriptionWithSharedLines] without the lines whose ids are in
  /// [sharedOut].
  String? _descriptionWithout(Set<String> sharedOut) {
    final lines = [
      ?_trimmedOrNull(description),
      for (final line in sharedLines)
        if (!sharedOut.contains(line.id)) line.text,
    ];
    return lines.isEmpty ? null : lines.join('\n');
  }

  /// The ids of fields a lower layer defined and a layer then disabled.
  ///
  /// A later `disabled: true` on one of them leaves the doc type as it is.
  final Set<String> disabledFieldIds;

  /// The ids of sections a lower layer defined and a layer then disabled.
  ///
  /// A later `disabled: true` on one of them leaves the doc type as it is.
  final Set<String> disabledSectionIds;

  /// What the doc type is for.
  final String? description;

  /// The id of the doc type this one nests under.
  final String? parent;

  /// The id of the doc type this one builds on.
  final String? extendsId;

  /// The ids this doc type builds on, nearest target first; empty without
  /// `extends`.
  final List<String> extendsChain;

  /// Whether this doc type is [docTypeId] or builds on it.
  bool buildsOn(String docTypeId) =>
      id == docTypeId || extendsChain.contains(docTypeId);

  /// The doc path pattern.
  final String? path;

  /// The fixed text of every doc's `# ` line; null when no layer sets it.
  final String? title;

  /// How many more times the doc type's own folder segment may repeat; null
  /// when no layer sets it.
  final int? maxDepth;

  /// Whether the doc type reads its patterns once per target.
  final bool isPerTarget;

  /// Whether a doc's number never changes, so `reorder` refuses the type.
  final bool fixedNumbers;

  /// Whether the doc type's own folder segment may repeat.
  bool get nests => (maxDepth ?? 0) > 0;

  /// One path pattern per depth, from 0 to the nesting type's `max_depth`;
  /// null when the doc type's path holds no nesting segment.
  ///
  /// A `MergedSet` derives it from [path], the [parent] chain, and the nesting
  /// type's `max_depth`, so [copyWith] keeps it unless one of those is given.
  final List<String>? nestedPaths;

  /// The path patterns a doc of this type matches: [nestedPaths], else [path],
  /// else none.
  List<String> get paths => nestedPaths ?? [?path];

  /// The bundle modes the doc type takes part in; null when no layer sets it.
  final List<String>? bundle;

  /// Whether the bundle join of this doc type goes to the refs file of an
  /// `implement` or `design` bundle `--out` writes; null when no layer sets it.
  final bool? bundleRefs;

  /// The doc type ids of the bundle targets whose bundles print this doc type
  /// in summary; null when no layer sets it.
  final List<String>? summaryFor;

  /// Whether a bundle whose target has the doc type [targetTypeId] prints a
  /// cited doc of this type in summary, not as its naming line alone.
  ///
  /// A null [targetTypeId] stands for a target with no doc type.
  bool printsSummaryFor(String? targetTypeId) =>
      summaryFor == null ||
      (targetTypeId != null && summaryFor!.contains(targetTypeId));

  /// The generated-block kinds the doc type lists; null when no layer sets it.
  ///
  /// Null differs from empty: a plain list merges only over null.
  final List<String>? generators;

  /// The generated-block kinds the doc type lists, empty when none is set.
  List<String> get listedGenerators => generators ?? const [];

  /// The enabled fields, built-ins first.
  final List<MergedField> fields;

  /// Whether this is the record doc type, the one holding a `record_status`
  /// field; every rule on records finds it by that field alone.
  bool get isRecordType => fields.any((f) => f.type == FieldType.recordStatus);

  /// The enabled sections in merged order.
  final List<MergedSection> sections;

  /// The doc-level lint settings.
  final MergedLint lint;

  /// The cited sources; null when no layer defines the list.
  final List<ReferenceEntry>? reference;

  /// The pack that supplied the doc type.
  final String? pack;

  /// The layer files that wrote this doc type, lowest layer first.
  final List<String> files;

  /// Returns a copy with each non-null argument replacing its property.
  ///
  /// [nestedPaths] stays unless [path], [parent], or [maxDepth] is given, since
  /// a new value of any makes the old list stale.
  MergedDocType copyWith({
    String? description,
    String? parent,
    String? extendsId,
    List<String>? extendsChain,
    String? path,
    String? title,
    int? maxDepth,
    bool? isPerTarget,
    bool? fixedNumbers,
    List<String>? nestedPaths,
    List<String>? bundle,
    bool? bundleRefs,
    List<String>? summaryFor,
    List<String>? generators,
    List<MergedField>? fields,
    List<MergedSection>? sections,
    MergedLint? lint,
    List<ReferenceEntry>? reference,
    String? pack,
    List<MergedSharedLine>? sharedLines,
    List<String>? files,
    Set<String>? disabledFieldIds,
    Set<String>? disabledSectionIds,
  }) => MergedDocType(
    id: id,
    description: description ?? this.description,
    parent: parent ?? this.parent,
    extendsId: extendsId ?? this.extendsId,
    extendsChain: extendsChain ?? this.extendsChain,
    path: path ?? this.path,
    title: title ?? this.title,
    maxDepth: maxDepth ?? this.maxDepth,
    isPerTarget: isPerTarget ?? this.isPerTarget,
    fixedNumbers: fixedNumbers ?? this.fixedNumbers,
    nestedPaths:
        nestedPaths ??
        (path == null && parent == null && maxDepth == null
            ? this.nestedPaths
            : null),
    bundle: bundle ?? this.bundle,
    bundleRefs: bundleRefs ?? this.bundleRefs,
    summaryFor: summaryFor ?? this.summaryFor,
    generators: generators ?? this.generators,
    fields: fields ?? this.fields,
    sections: sections ?? this.sections,
    lint: lint ?? this.lint,
    reference: reference ?? this.reference,
    pack: pack ?? this.pack,
    sharedLines: sharedLines ?? this.sharedLines,
    files: files ?? this.files,
    disabledFieldIds: disabledFieldIds ?? this.disabledFieldIds,
    disabledSectionIds: disabledSectionIds ?? this.disabledSectionIds,
  );

  /// Returns the JSON object of the merged schema with only the keys set.
  ///
  /// Keys follow the s02 `specstone guide <type> --json` order; `lint` is
  /// absent when no layer sets a limit or a word list.
  Map<String, Object> toJson() {
    final lintJson = lint.toJson();
    return {
      'id': id,
      'description': ?descriptionWithSharedLines,
      'parent': ?parent,
      'extends': ?extendsId,
      'path': ?path,
      'title': ?title,
      'maxDepth': ?maxDepth,
      if (isPerTarget) 'perTarget': true,
      'bundle': ?bundle,
      'bundleRefs': ?bundleRefs,
      'summaryFor': ?summaryFor,
      'fields': [for (final field in fields) field.toJson()],
      'sections': [for (final section in sections) section.toJson()],
      if (lintJson.isNotEmpty) 'lint': lintJson,
      if (reference != null)
        'reference': [for (final entry in reference!) entry.toJson()],
    };
  }

  /// Returns [text] without trailing whitespace, or null when nothing is left.
  static String? _trimmedOrNull(String? text) {
    final trimmed = text?.trimRight();
    return trimmed == null || trimmed.trim().isEmpty ? null : trimmed;
  }
}
