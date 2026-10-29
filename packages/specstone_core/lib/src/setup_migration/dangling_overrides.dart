import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/setup_migration/migration_chain.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/pack_migration.dart';
import 'package:specstone_core/src/templates/pack_version.dart';

const _editThenMigrate = 'edit the override, then run specstone migrate again';

/// Throws `override_dangling` when a project-layer override names a section,
/// field, or doc type that the upgrade target no longer defines (INV-11).
///
/// [target] is the listed packs at their target versions with no project
/// layer. An entry is spared when a selected step in [upgrades] renames it. A
/// layer that writes `path:` defines its own doc type and is skipped. The
/// fault is the first dangling entry; `more` holds the rest in file order,
/// then entry order.
void refuseDanglingOverrides(
  List<DocTypeLayer> overrides, {
  required MergedSet target,
  required Map<String, PackVersion> targetVersions,
  required List<PackUpgrade> upgrades,
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

  final faults = <MigrateFault>[
    for (final layer in overrides)
      if (layer.path == null)
        ..._danglingOf(
          layer,
          target.lookup(layer.docTypeId),
          targetVersions,
          renamedSections: renamedSections,
          renamedFields: renamedFields,
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
  final owner = [?pack, ?version].join(' ');
  MigrateFault fault(String kind, String id) => MigrateFault(
    MigrateFaultCode.overrideDangling,
    'pack $owner defines no $kind $id and no step renames it; '
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
