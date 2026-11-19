import 'package:specstone_core/src/templates/merged_set_checks.dart';
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
    return PackManifest._(
      name: name,
      version: version,
      extendsPack: optionalValue<String>(map, 'extends', file: file),
      migrations: parseMigrations(map.nodes['migrations'], file: file),
      shared: parseSharedEntries(map, file: file, allowsFields: true),
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
