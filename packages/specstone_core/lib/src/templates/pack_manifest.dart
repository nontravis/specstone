import 'package:specstone_core/src/templates/merged_set_checks.dart';
import 'package:specstone_core/src/templates/models/migration_step.dart';
import 'package:specstone_core/src/templates/pack_migration.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/shared_entry.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/yaml_reader.dart';

const _keys = {
  'name',
  'version',
  'extends',
  'migrations',
  'shared_lines',
  'shared_fields',
};

const _entitiesSection = 'entities';
const _invariantsSection = 'invariants';

/// The `pack.yaml` of one pack: its name, version, and optional base pack.
final class PackManifest {
  new _({
    required this.name,
    required this.version,
    required this.extendsPack,
    required this.migrations,
    required this.shared,
    required this.file,
  });

  /// Parses the text of a `pack.yaml` read from [file].
  ///
  /// `name` and `version` are required (`missing_key`); a key outside `name`,
  /// `version`, `extends`, `migrations`, `shared_lines`, and `shared_fields` is
  /// `unknown_key`.
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
    final extendsPack = optionalValue<String>(map, 'extends', file: file);
    final migrations = parseMigrations(map.nodes['migrations'], file: file);
    final shared = parseSharedEntries(map, file: file, format: 'pack');
    _checkDropsOfOwnLines(migrations, {
      for (final line in shared.lines) line.id,
    }, file: file);
    return PackManifest._(
      name: name,
      version: version,
      extendsPack: extendsPack,
      migrations: migrations,
      shared: shared,
      file: file,
    );
  }

  /// Throws `unknown_value` for the first `drop_shared_lines` id that
  /// [declared] holds.
  ///
  /// The key is `migrations[<i>].steps[<j>].drop_shared_lines.ids`.
  static void _checkDropsOfOwnLines(
    List<PackMigration> migrations,
    Set<String> declared, {
    required String file,
  }) {
    for (final (i, migration) in migrations.indexed) {
      for (final (j, step) in migration.steps.indexed) {
        if (step is! DropSharedLines) continue;
        for (final id in step.ids) {
          if (!declared.contains(id)) continue;
          throw TemplateFault(
            FaultCode.unknownValue,
            'drop_shared_lines names a line the pack defines: $id',
            file: file,
            key: 'migrations[$i].steps[$j].drop_shared_lines.ids',
          );
        }
      }
    }
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

  /// Throws `unknown_value` for the first `mark_retrim` id that names no doc
  /// type of [layerLists] or no section any layer of a listed type or of its
  /// `extends` chain defines, a layer that disables the section included.
  ///
  /// The key is `migrations[<i>].steps[<j>].mark_retrim.doc_types[<k>]` or
  /// `migrations[<i>].steps[<j>].mark_retrim.sections[<k>]`.
  void checkMarkRetrimTargets(Map<String, DocTypeLayers> layerLists) {
    for (final (i, migration) in migrations.indexed) {
      for (final (j, step) in migration.steps.indexed) {
        if (step is! MarkRetrim) continue;
        final key = 'migrations[$i].steps[$j].mark_retrim';
        for (final (k, docType) in step.docTypes.indexed) {
          if (layerLists.containsKey(docType)) continue;
          throw TemplateFault(
            FaultCode.unknownValue,
            'the mark_retrim doc type $docType is not a doc type the packs '
            'define',
            file: file,
            key: '$key.doc_types[$k]',
          );
        }
        final defined = {
          for (final docType in step.docTypes)
            ..._definedSectionIds(docType, layerLists),
        };
        for (final (k, section) in step.sections.indexed) {
          if (defined.contains(section)) continue;
          throw TemplateFault(
            FaultCode.unknownValue,
            'the mark_retrim section $section is not a section of '
            '${step.docTypes.join(', ')}',
            file: file,
            key: '$key.sections[$k]',
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
    final defined = _definedSectionIds(docType, layerLists);
    for (final section in const [_entitiesSection, _invariantsSection]) {
      if (!defined.contains(section)) {
        return 'the drop_default_lines doc type $docType has no $section '
            'section';
      }
    }
    return null;
  }

  /// Returns the section ids any layer of [docType] or of its `extends` chain
  /// defines, a layer that disables the section included.
  Set<String> _definedSectionIds(
    String docType,
    Map<String, DocTypeLayers> layerLists,
  ) {
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
    return defined;
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

  /// The pack's shared lines and fields, in file order; empty when absent.
  final SharedEntries shared;

  /// The file this manifest was read from.
  final String file;
}
