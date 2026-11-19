import 'package:specstone_core/src/templates/merged_set_checks.dart';
import 'package:specstone_core/src/templates/pack_migration.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/yaml_reader.dart';

const _keys = {'name', 'version', 'extends', 'migrations'};

const _entitiesSection = 'entities';
const _invariantsSection = 'invariants';

/// The `pack.yaml` of one pack: its name, version, and optional base pack.
final class PackManifest {
  new _({
    required this.name,
    required this.version,
    required this.extendsPack,
    required this.migrations,
    required this.file,
  });

  /// Parses the text of a `pack.yaml` read from [file].
  ///
  /// `name` and `version` are required (`missing_key`); a key outside `name`,
  /// `version`, `extends`, and `migrations` is `unknown_key`.
  static PackManifest parse(String text, {required String file}) {
    final map = readYamlMap(text, file: file);
    checkKeys(map, _keys, file: file, format: 'pack');
    final name = requireValue<String>(map, 'name', file: file);
    requireValue<Object>(map, 'version', file: file);
    final version = PackVersion.fromYaml(
      map.nodes['version']!,
      file: file,
      key: 'version',
    );
    return PackManifest._(
      name: name,
      version: version,
      extendsPack: optionalValue<String>(map, 'extends', file: file),
      migrations: parseMigrations(map.nodes['migrations'], file: file),
      file: file,
    );
  }

  /// Throws `unknown_value` for the first `move_to_record` step whose `to`
  /// is outside [docTypeIds].
  ///
  /// The key is `migrations[<i>].steps[<j>].move_to_record.to`.
  void checkRecordTargets(Set<String> docTypeIds) {
    for (final (i, migration) in migrations.indexed) {
      for (final (j, step) in migration.steps.indexed) {
        if (step is! MoveToRecord || docTypeIds.contains(step.to)) continue;
        throw TemplateFault(
          FaultCode.unknownValue,
          'the move_to_record target ${step.to} is not a doc type the pack '
          'defines',
          file: file,
          key: 'migrations[$i].steps[$j].move_to_record.to',
        );
      }
    }
  }

  /// Throws `unknown_value` for the first `bullet_lines` step whose `doc_type`
  /// is outside [layerLists] or whose `section` no layer of that doc type
  /// defines, a layer that disables the section included.
  ///
  /// The key is `migrations[<i>].steps[<j>].bullet_lines.<doc_type|section>`.
  void checkBulletLineTargets(Map<String, DocTypeLayers> layerLists) {
    for (final (i, migration) in migrations.indexed) {
      for (final (j, step) in migration.steps.indexed) {
        if (step is! BulletLines) continue;
        final key = 'migrations[$i].steps[$j].bullet_lines';
        final layers = layerLists[step.docType];
        if (layers == null) {
          throw TemplateFault(
            FaultCode.unknownValue,
            'the bullet_lines doc type ${step.docType} is not a doc type '
            'the packs define',
            file: file,
            key: '$key.doc_type',
          );
        }
        final defined = layers.any(
          (entry) => entry.layer.sections.any((s) => s.id == step.section),
        );
        if (defined) continue;
        throw TemplateFault(
          FaultCode.unknownValue,
          'the bullet_lines section ${step.section} is not a section of '
          '${step.docType}',
          file: file,
          key: '$key.section',
        );
      }
    }
  }

  /// Throws `unknown_value` for the first `drop_default_lines` doc type that
  /// [layerLists] lacks, or whose `extends` chain defines no `entities` or no
  /// `invariants` section, a layer that disables the section included.
  ///
  /// The key is `migrations[<i>].steps[<j>].drop_default_lines.doc_types`.
  void checkDropDefaultLineTargets(Map<String, DocTypeLayers> layerLists) {
    for (final (i, migration) in migrations.indexed) {
      for (final (j, step) in migration.steps.indexed) {
        if (step is! DropDefaultLines) continue;
        for (final docType in step.docTypes) {
          final problem = _dropTargetProblem(docType, layerLists);
          if (problem == null) continue;
          throw TemplateFault(
            FaultCode.unknownValue,
            problem,
            file: file,
            key: 'migrations[$i].steps[$j].drop_default_lines.doc_types',
          );
        }
      }
    }
  }

  String? _dropTargetProblem(
    String docType,
    Map<String, DocTypeLayers> layerLists,
  ) {
    if (!layerLists.containsKey(docType)) {
      return 'the drop_default_lines doc type $docType is not a doc type '
          'the packs define';
    }
    final defined = <String>{};
    final visited = <String>{};
    var layers = layerLists[docType];
    while (layers != null) {
      if (!visited.add(layers.first.layer.docTypeId)) break;
      for (final entry in layers) {
        defined.addAll(entry.layer.sections.map((s) => s.id));
      }
      layers = _extendsTargetLayers(layers, layerLists);
    }
    for (final section in const [_entitiesSection, _invariantsSection]) {
      if (!defined.contains(section)) {
        return 'the drop_default_lines doc type $docType has no $section '
            'section';
      }
    }
    return null;
  }

  DocTypeLayers? _extendsTargetLayers(
    DocTypeLayers layers,
    Map<String, DocTypeLayers> layerLists,
  ) {
    final target = topMostWriter(layers, wroteExtends)?.extendsId;
    return target == null ? null : layerLists[target];
  }

  /// The pack name.
  final String name;

  /// The pack version.
  final PackVersion version;

  /// The name of the pack this pack extends, when written.
  final String? extendsPack;

  /// The pack's migrations, in file order; empty when the key is absent.
  final List<PackMigration> migrations;

  /// The file this manifest was read from.
  final String file;
}
