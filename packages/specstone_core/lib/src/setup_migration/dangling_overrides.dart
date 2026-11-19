import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/setup_migration/migration_chain.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/pack_migration.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/shared_entry.dart';

const _editThenMigrate = 'edit the override, then run specstone migrate again';
const _architectureType = 'architecture';
const _slugPlaceholder = '{slug}';
const _slugNamed =
    'no layer sets the record path, and architecture names its file by the '
    "feature's slug, so no folder holds a feature's record";
const _layerWithoutPath =
    'the record override sets no path, and its folder differs from the '
    "architecture folder, so no rule gives each feature's record its folder";

/// Throws `override_dangling` when a project-layer override names a section,
/// field, or doc type that the upgrade target no longer defines, when a
/// `shared.yaml` line in [sharedLines] does, or when a selected
/// `move_to_record` step needs a record override the run cannot write
/// ([recordPathOverrideOf]).
///
/// [target] is the listed packs at their target versions with no project
/// layer. An entry is spared when a selected step in [upgrades] renames it. A
/// layer that writes `path:` for a doc type no pack defines defines its own
/// and is skipped; one for a pack doc type is still checked. A shared line
/// dangles when it is no complete new entry and the target defines no line of
/// its id, and for each `for_doc_types` id that neither the target nor a layer
/// that writes `path:` defines. The fault is the first dangling entry; `more`
/// holds the rest in file order, then entry order, the record override last.
void refuseDanglingOverrides(
  List<DocTypeLayer> overrides, {
  required MergedSet target,
  required Map<String, PackVersion> targetVersions,
  required List<PackUpgrade> upgrades,
  List<SharedLine> sharedLines = const [],
}) {
  final steps = [
    for (final upgrade in upgrades)
      for (final entry in upgrade.steps) entry.step,
  ];
  final renamedSections = {
    for (final step in steps.whereType<RenameSection>())
      (step.docType, step.fromId),
  };
  final renamedFields = {
    for (final step in steps.whereType<RenameField>())
      (step.docType, step.from),
  };

  final sharedFaults = _sharedDanglingOf(
    sharedLines,
    target: target,
    layerDefined: {
      for (final layer in overrides)
        if (layer.path != null) layer.docTypeId,
    },
  );
  final sharedFile = sharedLines.firstOrNull?.file;
  bool followsShared(DocTypeLayer layer) =>
      sharedFile != null && compareCodePoints(layer.file, sharedFile) > 0;
  List<MigrateFault> danglingOf(DocTypeLayer layer) =>
      target.lookup(layer.docTypeId) != null || layer.path == null
      ? _danglingOf(
          layer,
          target.lookup(layer.docTypeId),
          targetVersions,
          renamedSections: renamedSections,
          renamedFields: renamedFields,
        )
      : const [];

  final faults = <MigrateFault>[
    for (final layer in overrides.where((layer) => !followsShared(layer)))
      ...danglingOf(layer),
    ...sharedFaults,
    for (final layer in overrides.where(followsShared)) ...danglingOf(layer),
    ..._recordOverrideFaults(
      recordPathOverrideOf(steps, overrides: overrides, target: target),
    ),
  ];
  if (faults.isEmpty) return;
  final first = faults.first;
  throw MigrateFault(
    first.code,
    first.message,
    file: first.file,
    key: first.key,
    more: faults.sublist(1),
  );
}

List<MigrateFault> _danglingOf(
  DocTypeLayer layer,
  MergedDocType? defined,
  Map<String, PackVersion> targetVersions, {
  required Set<(String, String)> renamedSections,
  required Set<(String, String)> renamedFields,
}) {
  final docTypeId = layer.docTypeId;
  if (defined == null) {
    return [
      MigrateFault(
        MigrateFaultCode.overrideDangling,
        'no pack defines the doc type $docTypeId and no step renames it; '
        '$_editThenMigrate',
        file: layer.file,
      ),
    ];
  }
  final pack = defined.pack;
  final version = pack == null ? null : targetVersions[pack];
  final owner = ['pack', ?pack, ?version].join(' ');
  MigrateFault fault(String kind, String id) => MigrateFault(
    MigrateFaultCode.overrideDangling,
    '$owner defines no $kind $id and no step renames it; '
    '$_editThenMigrate',
    file: layer.file,
    key: '${kind}s.$id',
  );

  final sectionIds = {for (final section in defined.sections) section.id};
  final fieldIds = {for (final field in defined.fields) field.id};
  return [
    for (final section in layer.sections)
      if ((section.disabled || section.header == null) &&
          !sectionIds.contains(section.id) &&
          !renamedSections.contains((docTypeId, section.id)))
        fault('section', section.id),
    for (final field in layer.fields)
      if ((field.disabled || field.type == null) &&
          !fieldIds.contains(field.id) &&
          !renamedFields.contains((docTypeId, field.id)))
        fault('field', field.id),
  ];
}

/// Returns one fault per dangling entry of [lines], in file order.
///
/// A line dangles on its id when it is no complete new entry, one with `text`
/// and not disabled, and [target] defines no line of that id. It dangles on
/// each `for_doc_types` id that neither [target] nor [layerDefined] defines.
List<MigrateFault> _sharedDanglingOf(
  List<SharedLine> lines, {
  required MergedSet target,
  required Set<String> layerDefined,
}) {
  final definedIds = {for (final line in target.shared.lines) line.id};
  MigrateFault fault(SharedLine line, String key, String message) =>
      MigrateFault(
        MigrateFaultCode.overrideDangling,
        '$message; $_editThenMigrate',
        file: line.file,
        key: key,
      );

  return [
    for (final line in lines) ...[
      if ((line.disabled || line.text == null) && !definedIds.contains(line.id))
        fault(
          line,
          'shared_lines.${line.id}',
          'no pack defines the shared line ${line.id}',
        ),
      for (final docTypeId in line.forDocTypes ?? const <String>[])
        if (target.lookup(docTypeId) == null &&
            !layerDefined.contains(docTypeId))
          fault(
            line,
            'shared_lines.${line.id}.for_doc_types',
            'no pack defines the doc type $docTypeId that shared line '
                '${line.id} names',
          ),
    ],
  ];
}

/// The `path:` override a selected `move_to_record` step needs for its record
/// doc type, so each record lies in its feature's spec folder.
final class RecordPathOverride {
  const new(this.file, this.path, this.why);

  /// The ProjectPath of the project-layer file that holds the override.
  final String file;

  /// The `path:` to write, or null when only the Owner can choose it.
  final String? path;

  /// Why only the Owner can choose the path; empty when [path] is set.
  final String why;

  /// Whether the run cannot write the override itself.
  bool get isUnwritable => path == null;
}

/// Returns the record override [steps] need, or null when none is needed.
///
/// The record doc type is the one with a `record_status` field. None is needed
/// without a `move_to_record` step, once a project layer sets the record's
/// `path`, when no project layer sets an `architecture` path, or when the
/// folder of that `architecture` path is the folder the record's own path
/// already names. Otherwise the override names the `architecture` folder plus
/// the record file name of [target]. It is unwritable when the `architecture`
/// file is named by the feature's `{slug}`, since that folder holds no
/// feature's own record, or when a layer for the record doc type exists
/// without a `path`.
RecordPathOverride? recordPathOverrideOf(
  List<MigrationStep> steps, {
  required List<DocTypeLayer> overrides,
  required MergedSet target,
}) {
  final recordId = target.recordDocType?.id;
  if (recordId == null || !steps.any((step) => step is MoveToRecord)) {
    return null;
  }
  final recordLayer = overrides
      .where((layer) => layer.docTypeId == recordId)
      .firstOrNull;
  if (recordLayer?.path != null) return null;
  final architecture = overrides
      .where((layer) => layer.docTypeId == _architectureType)
      .map((layer) => layer.path)
      .nonNulls
      .firstOrNull;
  final recordPath = target.lookup(recordId)?.path;
  if (architecture == null || recordPath == null) return null;
  final file = '.specstone/templates/$recordId.yaml';
  final folderEnd = architecture.lastIndexOf('/') + 1;
  if (architecture.substring(folderEnd).contains(_slugPlaceholder)) {
    return RecordPathOverride(file, null, _slugNamed);
  }
  final wanted =
      '${architecture.substring(0, folderEnd)}${recordPath.split('/').last}';
  if (wanted == recordPath) return null;
  return recordLayer == null
      ? RecordPathOverride(file, wanted, '')
      : RecordPathOverride(file, null, _layerWithoutPath);
}

List<MigrateFault> _recordOverrideFaults(RecordPathOverride? override) =>
    override == null || !override.isUnwritable
    ? const []
    : [
        MigrateFault(
          MigrateFaultCode.overrideDangling,
          '${override.why}; write the override with a path, then run '
          'specstone migrate again',
          file: override.file,
          key: 'path',
        ),
      ];
