import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/setup_migration/migration_chain.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/layer_source.dart'
    show projectSharedFileName, projectTemplatesFolder;
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/models/migration_step.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/shared_entry.dart';

const _editThenMigrate = 'edit the override, then run specstone migrate again';

/// Throws `override_dangling` when a project-layer override names a section,
/// field, or doc type that the upgrade target no longer defines, or when a
/// `shared.yaml` line in [sharedLines] does.
///
/// [target] is the listed packs at their target versions with no project
/// layer. An entry is spared when a selected step in [upgrades] renames it. A
/// layer that writes `path:` for a doc type no pack defines defines its own
/// and is skipped; one for a pack doc type is still checked. A layer of a
/// doc type in `target.foldedDocTypes` or `target.droppedDocTypes` is
/// skipped, `path:` or not. A shared line dangles on its id when the target
/// defines no line of that id and either it is no complete new entry or a
/// selected `drop_shared_lines` step names the id; it dangles on each
/// `for_doc_types` id that neither the target nor a layer that writes `path:`
/// defines. The fault is the first dangling entry; `more` holds the rest in
/// file order, then entry order.
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
  final renamedSections = _RenamedIds();
  for (final step in steps.whereType<RenameSection>()) {
    renamedSections.add(step.docType, step.fromId);
  }
  final renamedFields = _RenamedIds();
  for (final step in steps.whereType<RenameField>()) {
    renamedFields.add(step.docType, step.from);
  }

  bool isLeftBehind(DocTypeLayer layer) =>
      target.foldedDocTypes.containsKey(layer.docTypeId) ||
      target.droppedDocTypes.contains(layer.docTypeId);

  final sharedFaults = _sharedDanglingOf(
    sharedLines,
    target: target,
    layerDefined: {
      for (final layer in overrides)
        if (layer.path != null && !isLeftBehind(layer)) layer.docTypeId,
    },
    droppedIds: {
      for (final step in steps.whereType<DropSharedLines>()) ...step.ids,
    },
  );
  const sharedFile = '$projectTemplatesFolder/$projectSharedFileName';
  bool followsShared(DocTypeLayer layer) =>
      compareCodePoints(layer.file, sharedFile) > 0;
  List<MigrateFault> danglingOf(DocTypeLayer layer) => isLeftBehind(layer)
      ? const []
      : target.lookup(layer.docTypeId) != null || layer.path == null
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
  required _RenamedIds renamedSections,
  required _RenamedIds renamedFields,
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
          !renamedSections.holds(docTypeId, section.id))
        fault('section', section.id),
    for (final field in layer.fields)
      if ((field.disabled || field.type == null) &&
          !fieldIds.contains(field.id) &&
          !renamedFields.holds(docTypeId, field.id))
        fault('field', field.id),
  ];
}

/// Returns one fault per dangling entry of [lines], in file order.
///
/// A line dangles on its id when [target] defines no line of that id and
/// either the line is no complete new entry (one with `text`, not disabled)
/// or a selected step names the id in [droppedIds]. It dangles on each
/// `for_doc_types` id that neither [target] nor [layerDefined] defines.
List<MigrateFault> _sharedDanglingOf(
  List<SharedLine> lines, {
  required MergedSet target,
  required Set<String> layerDefined,
  required Set<String> droppedIds,
}) {
  final definedIds = {
    for (final line in target.shared.lines) line.id,
    ...target.shared.disabledLineIds,
  };
  MigrateFault fault(SharedLine line, String key, String message) =>
      MigrateFault(
        MigrateFaultCode.overrideDangling,
        '$message; $_editThenMigrate',
        file: line.file,
        key: key,
      );

  return [
    for (final line in lines) ...[
      if ((line.disabled ||
              line.text == null ||
              droppedIds.contains(line.id)) &&
          !definedIds.contains(line.id))
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

/// A doc type id and the id of one of its entries.
final class _RenamedId {
  const new({required this.docTypeId, required this.id});

  final String docTypeId;
  final String id;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is _RenamedId && other.docTypeId == docTypeId && other.id == id;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(docTypeId, id);
}

/// The (doc type id, entry id) pairs a selected step renames.
final class _RenamedIds {
  new();

  final _ids = <_RenamedId>{};

  void add(String docTypeId, String id) {
    _ids.add(_RenamedId(docTypeId: docTypeId, id: id));
  }

  bool holds(String docTypeId, String id) =>
      _ids.contains(_RenamedId(docTypeId: docTypeId, id: id));
}
