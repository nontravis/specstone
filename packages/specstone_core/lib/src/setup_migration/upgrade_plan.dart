import 'dart:io';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart' show withKeyBlock;
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/doc_model/path_pattern.dart';
import 'package:specstone_core/src/setup_migration/dangling_overrides.dart';
import 'package:specstone_core/src/setup_migration/legacy_plan.dart'
    show prunesOf;
import 'package:specstone_core/src/setup_migration/legacy_rewrites.dart';
import 'package:specstone_core/src/setup_migration/migration_chain.dart';
import 'package:specstone_core/src/setup_migration/project_files.dart';
import 'package:specstone_core/src/setup_migration/run_plan.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/layer_source.dart';
import 'package:specstone_core/src/templates/pack_migration.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/project_config.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:yaml/yaml.dart';

const _docsFolder = 'docs/';
const _commit1Message = 'move docs to their new pack paths';
const _commit2Message = 'upgrade pack pins';

typedef _Step = ({PackVersion from, MigrationStep step});

/// Plans the pack upgrade of the project at [root].
///
/// Selects every pinned pack's steps, refuses an override the new versions
/// leave dangling, then plans the moves, the section and field renames in the
/// docs and the overrides, the link rewrites, and the new pins. Writes
/// nothing. Throws `MigrateFault` `override_dangling` and a `TemplateFault`
/// before it returns, so a refused run prints nothing. [homeDirectory] is the
/// personal pack home, or null.
RunPlan planUpgradeRun(
  Directory root, {
  required TemplateResolver templates,
  required Directory? homeDirectory,
}) {
  final pins = ProjectConfig.read(root).pins;
  final available = templates.availableManifests(
    pins.keys,
    homeDirectory: homeDirectory,
  );
  final upgrades = selectUpgrades(pins, available);
  final overrides = loadProjectTemplates(root);
  refuseDanglingOverrides(
    overrides,
    target: templates.resolveCarried(
      packNames: pins.keys,
      homeDirectory: homeDirectory,
    ),
    targetVersions: {
      for (final entry in available.entries) entry.key: entry.value.version,
    },
    upgrades: upgrades,
  );

  final steps = [for (final upgrade in upgrades) ...upgrade.steps];
  final overrideFiles = _renamedOverrides(root, overrides, steps);
  final finalSet = templates.resolveCarried(
    packNames: pins.keys,
    homeDirectory: homeDirectory,
    projectLayers: parseOverrides({
      for (final file in overrideFiles) file.path: file.lf,
    }),
  );

  final docsRoot = Directory.fromUri(root.uri.resolve(_docsFolder));
  final docPaths = _docPathsOf(docsRoot)..sort(compareCodePoints);
  final (:planned, :movedAt) = _plannedPaths(docPaths, steps);
  final moves = [
    for (final path in docPaths)
      if (planned[path] != path) (from: path, to: planned[path]!),
  ];

  final matcher = DocTypeMatcher(finalSet);
  final docRewrites = <PlannedRewrite>[];
  final changedAt = <int, List<String>>{};
  final linkLines = <String>[];
  for (final path in docPaths) {
    final plannedPath = planned[path]!;
    final original = readDocText(
      File.fromUri(docsRoot.uri.resolve(path)).readAsBytesSync(),
    );
    final match = matcher.match(plannedPath);
    final docTypeId = match is MatchedDocType ? match.docType.id : null;
    var lf = original.lf;
    final changes = <String>[];
    for (final (index, (:step, from: _)) in steps.indexed) {
      if (step.docType != docTypeId) continue;
      final renamed = switch (step) {
        RenameSection() => withHeaderRenamed(
          lf,
          step.fromHeader,
          step.toHeader,
        ),
        RenameField() => _withKeyRenamed(lf, step.from, step.to),
        MoveFile() => lf,
      };
      if (renamed == lf) continue;
      lf = renamed;
      changes.add(_describe(step));
      (changedAt[index] ??= []).add(plannedPath);
    }
    if (moves.isNotEmpty) {
      final links = rewriteLinks(lf, docPath: path, moves: moves);
      lf = links.lf;
      final label = links.label;
      if (label != null) {
        changes.add(label);
        linkLines.add('$plannedPath: $label');
      }
    }
    if (lf == original.lf) continue;
    docRewrites.add(
      PlannedRewrite(
        path: '$_docsFolder$plannedPath',
        text: writtenText(original, lf),
        changes: changes,
      ),
    );
  }

  final overrideRewrites = [
    for (final file in overrideFiles)
      if (file.changedBy.isNotEmpty)
        PlannedRewrite(
          path: file.path,
          text: writtenText(file.original, file.lf),
          changes: [
            for (final index in file.changedBy) _describe(steps[index].step),
          ],
        ),
  ];
  final configRewrite = _configRewriteOf(root, upgrades);

  String shownAt(int index) {
    final docs = (steps[index].step is MoveFile ? movedAt : changedAt)[index];
    return _shownPaths(
      docs: docs ?? const [],
      overrides: [
        for (final file in overrideFiles)
          if (file.changedBy.contains(index)) file.path,
      ],
    );
  }

  final stepLines = [
    for (final (index, (:from, :step)) in steps.indexed)
      'from $from: ${_describe(step)}: ${shownAt(index)}',
  ];
  final upgraded = [
    for (final upgrade in upgrades)
      '${upgrade.pack} ${upgrade.pin} -> ${upgrade.target}',
  ];
  final pinned = [
    for (final upgrade in upgrades) '${upgrade.pack} ${upgrade.target}',
  ];

  return RunPlan(
    header: 'pack upgrade: ${upgraded.join(', ')}',
    moves: moves,
    prunes: prunesOf(moves),
    rewrites: [...docRewrites, ...overrideRewrites, configRewrite],
    creates: const [],
    left: const [],
    commit1Message: _commit1Message,
    commit2Message: _commit2Message,
    rewriteLines: [
      ...stepLines,
      ...linkLines,
      '$projectConfigPath: ${pinned.join(', ')}',
    ],
  );
}

/// One override file, with the text the selected steps leave it.
final class _OverrideFile {
  new(this.path, this.original) : lf = original.lf;

  /// The ProjectPath of the file.
  final String path;

  /// The file as read.
  final DocText original;

  /// The LF text after the steps applied so far.
  String lf;

  /// The indexes of the steps that changed the file.
  final changedBy = <int>[];
}

/// Returns the override files with every step applied in order.
///
/// A `rename_section` step of a doc type replaces the scalar `sections[i].id`
/// and any `sections[i].after` equal to the old id; a `rename_field` step
/// replaces `fields[i].id` equal to the old name. Every other byte stays.
List<_OverrideFile> _renamedOverrides(
  Directory root,
  List<DocTypeLayer> layers,
  List<_Step> steps,
) {
  final files = <_OverrideFile>[];
  for (final layer in layers) {
    final file = _OverrideFile(
      layer.file,
      readDocText(File.fromUri(root.uri.resolve(layer.file)).readAsBytesSync()),
    );
    for (final (index, (:step, from: _)) in steps.indexed) {
      if (step.docType != layer.docTypeId) continue;
      final renamed = switch (step) {
        RenameSection() => _withScalarsRenamed(
          file.lf,
          list: 'sections',
          keys: const ['id', 'after'],
          from: step.fromId,
          to: step.toId,
        ),
        RenameField() => _withScalarsRenamed(
          file.lf,
          list: 'fields',
          keys: const ['id'],
          from: step.from,
          to: step.to,
        ),
        MoveFile() => file.lf,
      };
      if (renamed == file.lf) continue;
      file.lf = renamed;
      file.changedBy.add(index);
    }
    files.add(file);
  }
  return files;
}

/// Returns [lf] with each [keys] scalar of a [list] entry equal to [from]
/// replaced by [to], keeping quotes and every other byte.
String _withScalarsRenamed(
  String lf, {
  required String list,
  required List<String> keys,
  required String from,
  required String to,
}) {
  final root = loadYamlNode(lf);
  if (root is! YamlMap) return lf;
  final entries = root.nodes[list];
  if (entries is! YamlList) return lf;
  return _withScalarsReplaced(lf, [
    for (final entry in entries.nodes)
      if (entry is YamlMap)
        for (final key in keys)
          if (entry.nodes[key] case final YamlScalar scalar
              when scalar.value == from)
            (scalar, to),
  ]);
}

/// Returns [lf] with each scalar of [edits] replaced by its new text, written
/// in the quote style the scalar had.
String _withScalarsReplaced(String lf, List<(YamlScalar, String)> edits) {
  final ordered = [...edits]
    ..sort((a, b) => b.$1.span.start.offset.compareTo(a.$1.span.start.offset));
  var text = lf;
  for (final (scalar, replacement) in ordered) {
    final start = scalar.span.start.offset;
    final end = scalar.span.end.offset;
    final quote = switch (text[start]) {
      '"' => '"',
      "'" => "'",
      _ => '',
    };
    text = text.replaceRange(start, end, '$quote$replacement$quote');
  }
  return text;
}

PlannedRewrite _configRewriteOf(Directory root, List<PackUpgrade> upgrades) {
  final original = readDocText(
    File.fromUri(root.uri.resolve(projectConfigPath)).readAsBytesSync(),
  );
  final packs =
      (loadYamlNode(original.lf) as YamlMap).nodes['packs']! as YamlMap;
  final text = _withScalarsReplaced(original.lf, [
    for (final upgrade in upgrades)
      (packs.nodes[upgrade.pack]! as YamlScalar, '${upgrade.target}'),
  ]);
  return PlannedRewrite(
    path: projectConfigPath,
    text: writtenText(original, text),
    changes: ['pins'],
  );
}

/// Returns where each doc of [docPaths] sits after every `move_file` step, and
/// the paths each move step leaves its docs at.
({Map<String, String> planned, Map<int, List<String>> movedAt}) _plannedPaths(
  List<String> docPaths,
  List<_Step> steps,
) {
  final planned = {for (final path in docPaths) path: path};
  final movedAt = <int, List<String>>{};
  for (final (index, (:step, from: _)) in steps.indexed) {
    if (step is! MoveFile) continue;
    final from = PathPattern(step.from);
    final to = PathPattern(step.to);
    for (final entry in planned.entries) {
      final values = from.valuesOf(entry.value);
      if (values == null) continue;
      final moved = to.fill(values);
      if (moved == entry.value) continue;
      (movedAt[index] ??= []).add(moved);
      planned[entry.key] = moved;
    }
  }
  return (planned: planned, movedAt: movedAt);
}

/// Returns [lf] with the frontmatter key [from] written as [to], its value
/// kept, or [lf] when it has no such key.
String _withKeyRenamed(String lf, String from, String to) {
  final block = Doc.parse(lf).frontmatter
      ?.where((block) => block.name == from)
      .firstOrNull;
  if (block == null) return lf;
  final renamed = block.text.replaceFirst(
    RegExp('^${RegExp.escape(block.key)}(?=\\s*:)', multiLine: true),
    to,
  );
  return withKeyBlock(lf, from, renamed);
}

/// Returns `<kind> <doc_type> <old> -> <new>`, the ids for a section, the
/// keys for a field, the patterns for a move.
String _describe(MigrationStep step) => switch (step) {
  RenameSection() =>
    '${step.kind} ${step.docType} ${step.fromId} -> ${step.toId}',
  RenameField() => '${step.kind} ${step.docType} ${step.from} -> ${step.to}',
  MoveFile() => '${step.kind} ${step.docType} ${step.from} -> ${step.to}',
};

/// Returns the doc paths in code point order, then the override paths in the
/// same order, or `no doc changes` when both are empty.
String _shownPaths({
  required List<String> docs,
  required List<String> overrides,
}) {
  final shown = [
    ...[...docs]..sort(compareCodePoints),
    ...[...overrides]..sort(compareCodePoints),
  ];
  return shown.isEmpty ? 'no doc changes' : shown.join(', ');
}

/// Returns the DocPath of every Markdown file under [docsRoot].
List<String> _docPathsOf(Directory docsRoot) {
  if (!docsRoot.existsSync()) return [];
  // A file URI path always uses `/`, so no platform separator is split on.
  final prefixLength = docsRoot.uri.path.length;
  return [
    for (final entity in docsRoot.listSync(recursive: true, followLinks: false))
      if (entity is File && entity.path.endsWith('.md'))
        Uri.decodeComponent(entity.uri.path.substring(prefixLength)),
  ];
}
