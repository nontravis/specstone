import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/format_keys.dart';
import 'package:specstone_core/src/templates/leftover_home.dart';
import 'package:specstone_core/src/templates/merged_set_checks.dart';
import 'package:specstone_core/src/templates/models/migration_step.dart';
import 'package:specstone_core/src/templates/pack_migration.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/shared_entry.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/yaml_reader.dart';

/// The `pack.yaml` of one pack: its name, version, and optional base pack.
final class PackManifest {
  new _({
    required this.name,
    required this.version,
    required this.extendsPack,
    required this.migrations,
    required this.leftoverHomes,
    required this.shared,
    required this.file,
  });

  /// Parses the text of a `pack.yaml` read from [file].
  ///
  /// `name` and `version` are required (`missing_key`); a key outside `name`,
  /// `version`, `extends`, `migrations`, `leftover_homes`, and the four shared
  /// lists is `unknown_key`.
  static PackManifest parse(String text, {required String file}) {
    final map = readYamlMap(text, file: file);
    checkKeys(
      map,
      formatKeysAt(packFileFormat, ''),
      file: file,
      format: 'pack',
    );
    final name = requireValue<String>(map, 'name', file: file);
    requireValue<Object>(map, 'version', file: file);
    final version = PackVersion.fromYaml(
      map.nodes['version']!,
      file: file,
      key: 'version',
    );
    final extendsPack = optionalValue<String>(map, 'extends', file: file);
    final migrations = parseMigrations(map.nodes['migrations'], file: file);
    final leftoverHomes = LeftoverHome.parseList(
      map.nodes['leftover_homes'],
      file: file,
    );
    final shared = parseSharedEntries(map, file: file, format: 'pack');
    _checkDropsOfOwnLines(migrations, {
      for (final line in shared.lines) line.id,
    }, file: file);
    return PackManifest._(
      name: name,
      version: version,
      extendsPack: extendsPack,
      migrations: migrations,
      leftoverHomes: leftoverHomes,
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

  /// Throws `unknown_value` for the first `merge_doc` step whose `to` is
  /// outside [docTypeIds].
  ///
  /// The key is `migrations[<i>].steps[<j>].merge_doc.to`.
  void checkRecordTargets(Set<String> docTypeIds) {
    for (final (i, migration) in migrations.indexed) {
      for (final (j, step) in migration.steps.indexed) {
        if (step is! MergeDoc || docTypeIds.contains(step.toId)) continue;
        throw TemplateFault(
          FaultCode.unknownValue,
          'the ${step.kind} target ${step.toId} is not a doc type the pack '
          'defines',
          file: file,
          key: 'migrations[$i].steps[$j].${step.kind}.to',
        );
      }
    }
  }

  /// Throws `unknown_value` for the first `leftover_homes` `to` or `doc_types`
  /// type outside [docTypeIds].
  ///
  /// The key is `leftover_homes[<i>].to` or `leftover_homes[<i>].doc_types`.
  void checkLeftoverHomes(Set<String> docTypeIds) {
    for (final (i, entry) in leftoverHomes.indexed) {
      for (final (key, types) in [
        ('to', entry.to),
        ('doc_types', entry.docTypes),
      ]) {
        final unknown = types.where((id) => !docTypeIds.contains(id));
        if (unknown.isEmpty) continue;
        throw TemplateFault(
          FaultCode.unknownValue,
          'the leftover_homes $key ${unknown.first} is not a doc type',
          file: file,
          key: 'leftover_homes[$i].$key',
        );
      }
    }
  }

  /// Throws `unknown_value` for the first `merge_doc` section whose `to` id no
  /// layer of the `to` doc type or of its `extends` chain defines, a layer that
  /// disables the section included.
  ///
  /// The `from` side is not read. The key is
  /// `migrations[<i>].steps[<j>].merge_doc.sections[<k>].to`.
  void checkMergeDocTargets(Map<String, DocTypeLayers> layerLists) {
    for (final (i, migration) in migrations.indexed) {
      for (final (j, step) in migration.steps.indexed) {
        if (step is! MergeDoc) continue;
        final defined = _definedSectionIds(step.toId, layerLists);
        for (final (k, section) in step.sections.indexed) {
          if (defined.contains(section.toId)) continue;
          throw TemplateFault(
            FaultCode.unknownValue,
            'the merge_doc section ${section.toId} is not a section of '
            '${step.toId}',
            file: file,
            key: 'migrations[$i].steps[$j].merge_doc.sections[$k].to',
          );
        }
      }
    }
  }

  /// The file index of each `migrations` entry in chain order: ascending
  /// `from`, entries of one `from` in file order. A run applies the steps in
  /// this order, each entry's steps in list order.
  List<int> get chainOrder =>
      // List.sort is not stable; the file index keeps equal `from` in file
      // order.
      [for (final (index, _) in migrations.indexed) index]..sort((a, b) {
        final byFrom = migrations[a].from.compareTo(migrations[b].from);
        return byFrom != 0 ? byFrom : a.compareTo(b);
      });

  /// The `from` ids of the `merge_doc` steps after step [stepIndex] of
  /// migration [migrationIndex], in [chainOrder].
  ///
  /// An earlier step may name such a type, which the merged set no longer
  /// holds.
  Set<String> laterFoldedIds(int migrationIndex, int stepIndex) {
    final order = chainOrder;
    final rank = order.indexOf(migrationIndex);
    return {
      for (final (at, i) in order.indexed)
        if (at >= rank)
          for (final (j, step) in migrations[i].steps.indexed)
            if (step is MergeDoc && (at > rank || j > stepIndex)) step.fromId,
    };
  }

  /// Throws `missing_key` at `<frozenFolder>/<id>.yaml` for the first doc type
  /// id a step names that a later `merge_doc` step folds, when [frozenIds]
  /// lacks it: those steps type its docs by the pack's frozen copy.
  void checkFrozenDocTypes(
    Set<String> frozenIds, {
    required String frozenFolder,
  }) {
    for (final (i, migration) in migrations.indexed) {
      for (final (j, step) in migration.steps.indexed) {
        for (final id in laterFoldedIds(i, j)) {
          if (!step.touches(id) || frozenIds.contains(id)) continue;
          throw TemplateFault(
            FaultCode.missingKey,
            'the file does not exist and must hold the doc type $id as it '
            'stood before a merge_doc folds it, since '
            'migrations[$i].steps[$j] names it',
            file: '$frozenFolder/$id.yaml',
            key: 'id',
          );
        }
      }
    }
  }

  /// Throws `unknown_value` for the first `drop_doc_type` step whose `id` a
  /// layer of [ownLayers] defines.
  ///
  /// The key is `migrations[<i>].steps[<j>].drop_doc_type.id`.
  void checkDropDocTypeTargets(Map<String, DocTypeLayer> ownLayers) {
    for (final (i, migration) in migrations.indexed) {
      for (final (j, step) in migration.steps.indexed) {
        if (step is! DropDocType || !ownLayers.containsKey(step.id)) continue;
        throw TemplateFault(
          FaultCode.unknownValue,
          'drop_doc_type names a doc type the pack defines: ${step.id}',
          file: file,
          key: 'migrations[$i].steps[$j].drop_doc_type.id',
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
        if (laterFoldedIds(i, j).contains(step.docType)) continue;
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
        final folded = laterFoldedIds(i, j);
        for (final (k, docType) in step.docTypes.indexed) {
          if (layerLists.containsKey(docType) || folded.contains(docType)) {
            continue;
          }
          throw TemplateFault(
            FaultCode.unknownValue,
            'the mark_retrim doc type $docType is not a doc type the packs '
            'define',
            file: file,
            key: '$key.doc_types[$k]',
          );
        }
        final read = step.docTypes.where((id) => !folded.contains(id));
        if (read.isEmpty) continue;
        final defined = {
          for (final docType in read)
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

  /// Throws `unknown_value` for the first `regenerate` generator outside
  /// [kinds].
  ///
  /// The key is `migrations[<i>].steps[<j>].regenerate.generators`.
  void checkRegenerateKinds(Set<String> kinds) {
    for (final (i, migration) in migrations.indexed) {
      for (final (j, step) in migration.steps.indexed) {
        if (step is! Regenerate) continue;
        for (final generator in step.generators) {
          if (kinds.contains(generator)) continue;
          throw TemplateFault(
            FaultCode.unknownValue,
            'the regenerate generator $generator is not a generator kind',
            file: file,
            key: 'migrations[$i].steps[$j].regenerate.generators',
          );
        }
      }
    }
  }

  /// Throws `unknown_value` for the first `drop_section` step whose
  /// `doc_types` entry is outside [layerLists] and no later `merge_doc` folds
  /// it, or whose `section.id` a layer
  /// of [ownLayers] for a listed doc type defines.
  ///
  /// A layer defines an id by an entry not marked `disabled: true`. The key is
  /// `migrations[<i>].steps[<j>].drop_section.doc_types` or
  /// `migrations[<i>].steps[<j>].drop_section.section`.
  void checkDropSectionTargets(
    Map<String, DocTypeLayers> layerLists, {
    required Map<String, DocTypeLayer> ownLayers,
  }) {
    for (final (i, migration) in migrations.indexed) {
      for (final (j, step) in migration.steps.indexed) {
        if (step is! DropSection) continue;
        final fault = _dropSectionFault(
          step,
          key: 'migrations[$i].steps[$j].drop_section',
          folded: laterFoldedIds(i, j),
          layerLists: layerLists,
          ownLayers: ownLayers,
        );
        if (fault != null) throw fault;
      }
    }
  }

  TemplateFault? _dropSectionFault(
    DropSection step, {
    required String key,
    required Set<String> folded,
    required Map<String, DocTypeLayers> layerLists,
    required Map<String, DocTypeLayer> ownLayers,
  }) {
    for (final docType in step.docTypes) {
      if (layerLists.containsKey(docType) || folded.contains(docType)) {
        continue;
      }
      return TemplateFault(
        FaultCode.unknownValue,
        'the drop_section doc type $docType is not a doc type the packs '
        'define',
        file: file,
        key: '$key.doc_types',
      );
    }
    final isDefined = step.docTypes.any(
      (docType) =>
          ownLayers[docType]?.sections.any(
            (s) => s.id == step.sectionId && !s.disabled,
          ) ??
          false,
    );
    if (!isDefined) return null;
    return TemplateFault(
      FaultCode.unknownValue,
      'drop_section names a section the pack defines: ${step.sectionId}',
      file: file,
      key: '$key.section',
    );
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

  /// The pack's leftover homes, in file order; empty when the key is absent.
  final List<LeftoverHome> leftoverHomes;

  /// The pack's shared lines, fields, and patterns; empty when absent.
  final SharedEntries shared;

  /// The file this manifest was read from.
  final String file;
}
