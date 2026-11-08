import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart' show withKeyBlock;
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/doc_model/path_pattern.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart'
    show textHashOf;
import 'package:specstone_core/src/document_writing/rewrite_refs.dart'
    show PathMove;
import 'package:specstone_core/src/git_process.dart';
import 'package:specstone_core/src/index_query/code_root_files.dart'
    show codeRootFiles;
import 'package:specstone_core/src/rendering/doc_reader.dart'
    show startsWithUtf8Bom;
import 'package:specstone_core/src/rendering/formatter.dart' show layOutDoc;
import 'package:specstone_core/src/setup_migration/agent_targets.dart';
import 'package:specstone_core/src/setup_migration/dangling_overrides.dart';
import 'package:specstone_core/src/setup_migration/label_pass.dart';
import 'package:specstone_core/src/setup_migration/legacy_plan.dart'
    show prunesOf;
import 'package:specstone_core/src/setup_migration/legacy_rewrites.dart';
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/setup_migration/migration_chain.dart';
import 'package:specstone_core/src/setup_migration/project_files.dart';
import 'package:specstone_core/src/setup_migration/renumber_pass.dart';
import 'package:specstone_core/src/setup_migration/run_plan.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/layer_source.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/pack_migration.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/project_config.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:specstone_core/src/version.dart';
import 'package:yaml/yaml.dart';

const _docsFolder = 'docs/';
const _commit1Message = 'move docs to their new pack paths';
const _commit2Message = 'upgrade pack pins';
const _layoutOnlyHeader = 'pack upgrade: pins unchanged, layout only';
const _layoutOnlyCommit2Message = 'lay docs out as format writes them';
const _agentOnlyHeader = 'pack upgrade: pins unchanged, agent files only';
const _agentOnlyCommit2Message = 'refresh the Specstone agent files';
const _layoutAndAgentHeader =
    'pack upgrade: pins unchanged, layout and agent files';
const _layoutAndAgentCommit2Message =
    'lay docs out and refresh the Specstone agent files';
const _agentFileRootsKey = 'agent_file_roots';
const _renumberChange = 'renumber ids';
const _labelChange = 'convert number labels';

/// The byte-order mark as the one character a written text starts with.
const _bom = '\uFEFF';

typedef _Step = ({PackVersion from, MigrationStep step});

/// Plans the pack upgrade of the project at [root].
///
/// Selects every pinned pack's steps, refuses an override the new versions
/// leave dangling, then plans the moves, the section and field renames in the
/// docs and the overrides, the link rewrites, the renumber pass, the label
/// pass, each typed doc laid out as `format` lays it out, the agent files
/// step, and the new pins. With every pin equal the plan holds the layout pass
/// and the agent files step alone. Writes nothing. Throws `MigrateFault`
/// `override_dangling`, `MigrateFault` `upgrade_collision` listing every move
/// and rename collision at once, `agent_block_malformed`, and a
/// `TemplateFault` before it returns, so a refused run prints nothing. When
/// [runsOneTimePasses] holds, the renumber and label passes run and the agent
/// files step is the full upsert; otherwise the step refreshes what exists.
/// [homeDirectory] is the personal pack home, or null. [runGit] lists the
/// files the project's git tracks, which the label pass reads under the
/// `code:` roots.
RunPlan planUpgradeRun(
  Directory root, {
  required TemplateResolver templates,
  required Directory? homeDirectory,
  RunGit runGit = runRealGit,
}) {
  final config = ProjectConfig.read(root);
  final pins = config.pins;
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
  final (:planned, :movedAt, :movedBy) = _plannedPaths(docPaths, steps);
  final moveCollisions = _moveCollisions(
    docPaths,
    planned: planned,
    movedBy: movedBy,
    steps: steps,
  );
  final moves = orderedMoves([
    for (final path in docPaths)
      if (planned[path] != path) (from: path, to: planned[path]!),
  ]);

  final matcher = DocTypeMatcher(finalSet);
  final works = <_DocWork>[];
  final changedAt = <int, List<String>>{};
  final linkLines = <String>[];
  final renameCollisions = <MigrateFault>[];
  for (final path in docPaths) {
    final plannedPath = planned[path]!;
    final original = readDocFile(docFileOf(docsRoot, path), docPath: path);
    if (original == null) continue;
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
      if (renamed != lf) {
        // Held is read from the text before the rename: `renamed` holds the
        // target by construction.
        final held = switch (step) {
          RenameSection() => Doc.parse(
            lf,
          ).sections.any((section) => section.headerText == step.toHeader),
          RenameField() =>
            Doc.parse(lf).frontmatter?.any((block) => block.name == step.to) ??
                false,
          MoveFile() => false,
        };
        if (held) {
          final message = switch (step) {
            RenameSection() =>
              'rename_section of ${step.docType} renames ${step.fromHeader} '
                  'to ${step.toHeader}, which the doc already holds; '
                  '$_resolveCollision',
            RenameField() =>
              'rename_field of ${step.docType} renames ${step.from} to '
                  '${step.to}, which the doc already holds; '
                  '$_resolveCollision',
            MoveFile() => '',
          };
          renameCollisions.add(
            MigrateFault(
              MigrateFaultCode.upgradeCollision,
              message,
              file: path,
            ),
          );
          continue;
        }
        lf = renamed;
        changes.add(_describe(step));
        (changedAt[index] ??= []).add(plannedPath);
      }
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
    works.add(
      _DocWork(
        plannedPath,
        original,
        match is MatchedDocType ? match.docType : null,
        lf,
        changes,
      ),
    );
  }
  _throwCollisions([...moveCollisions, ...renameCollisions]);

  // The passes read every doc's text after the steps and link rewrites (P5).
  final isOneTime = runsOneTimePasses(upgrades);
  final renumber = isOneTime ? _renumberPassOf(works) : null;
  final renumbered = <String>[];
  for (final work in works) {
    final lf = renumber?.apply(work.plannedPath, work.lf) ?? work.lf;
    if (lf != work.lf) work.changes.add(_renumberChange);
    renumbered.add(lf);
  }
  final labels = isOneTime
      ? _planLabelPass(
          root,
          config: config,
          set: finalSet,
          docs: [
            for (final (index, work) in works.indexed)
              (docPath: work.plannedPath, lf: renumbered[index]),
          ],
          runGit: runGit,
          docTypes: {for (final work in works) work.plannedPath: ?work.docType},
        )
      : null;
  final docRewrites = <PlannedRewrite>[];
  final laidOutPaths = <String>[];
  for (final (index, work) in works.indexed) {
    var lf = renumbered[index];
    final converted = labels?.pass.apply(work.plannedPath, lf) ?? lf;
    if (converted != lf) work.changes.add(_labelChange);
    lf = converted;
    final laidOut = layOutDoc(lf, work.docType);
    if (laidOut != lf) laidOutPaths.add(work.plannedPath);
    lf = laidOut;
    if (lf == work.original.lf) continue;
    docRewrites.add(
      PlannedRewrite(
        path: '$_docsFolder${work.plannedPath}',
        text: writtenText(work.original, lf),
        before: work.original.hash,
        changes: work.changes,
      ),
    );
  }

  final overrideRewrites = [
    for (final file in overrideFiles)
      if (file.changedBy.isNotEmpty)
        PlannedRewrite(
          path: file.path,
          text: writtenText(file.original, file.lf),
          before: file.original.hash,
          changes: [
            for (final index in file.changedBy) _describe(steps[index].step),
          ],
        ),
  ];
  final agentFiles = _agentFilesOf(root, upgrades, set: finalSet);
  final configRewrite = _configRewriteOf(
    root,
    upgrades,
    agentFileRoots: agentFiles.addedRoots.isEmpty
        ? null
        : agentFiles.agentFileRoots,
  );

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

  final arePinsUnchanged = upgrades.isEmpty;
  final (:header, :commit2Message) = arePinsUnchanged
      ? _pinsUnchangedTitles(
          laysOut: laidOutPaths.isNotEmpty,
          writesAgentFiles: !agentFiles.isEmpty,
        )
      : (
          header: 'pack upgrade: ${upgraded.join(', ')}',
          commit2Message: _commit2Message,
        );
  return RunPlan(
    header: header,
    moves: moves,
    prunes: prunesOf(moves),
    rewrites: [
      ...docRewrites,
      ...?labels?.codeRewrites,
      ...overrideRewrites,
      ?configRewrite,
    ],
    creates: const [],
    left: const [],
    commit1Message: _commit1Message,
    commit2Message: commit2Message,
    rewriteLines: [
      ...stepLines,
      ...linkLines,
      ?renumber?.planLine,
      ?labels?.pass.planLine,
      ?formatLayoutLine(laidOutPaths),
      if (agentFiles.line.isNotEmpty) agentFiles.line,
      if (!arePinsUnchanged) '$projectConfigPath: ${pinned.join(', ')}',
    ],
    agentFiles: agentFiles,
  );
}

/// Returns the plan header and commit 2 message of a run that moves no pin.
///
/// A run with neither the layout pass nor an agent file write is titled as
/// layout only.
({String header, String commit2Message}) _pinsUnchangedTitles({
  required bool laysOut,
  required bool writesAgentFiles,
}) => switch ((laysOut, writesAgentFiles)) {
  (true, true) => (
    header: _layoutAndAgentHeader,
    commit2Message: _layoutAndAgentCommit2Message,
  ),
  (false, true) => (
    header: _agentOnlyHeader,
    commit2Message: _agentOnlyCommit2Message,
  ),
  (_, false) => (
    header: _layoutOnlyHeader,
    commit2Message: _layoutOnlyCommit2Message,
  ),
};

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

/// Plans the agent files step of the upgrade of [root] to [upgrades].
AgentWritePlan _agentFilesOf(
  Directory root,
  List<PackUpgrade> upgrades, {
  required MergedSet set,
}) {
  final projectRoot = Directory(root.resolveSymbolicLinksSync());
  final config = ProjectConfig.read(projectRoot);
  return planAgentWrites(
    AgentFileInputs(
      projectRoot: projectRoot,
      cliVersion: specstoneVersion,
      codeRootFolders: codeFoldersOf(
        projectRoot,
        set,
        codeRoot: config.codeRoot,
      ),
      agentFileRoots: config.agentFileRoots,
    ),
    full: runsOneTimePasses(upgrades),
  );
}

/// Whether [upgrades] move a prd-core or software-tech pin up from below the
/// version this binary carries: the one trigger of every one-time pass
/// (apply_steps_and_pins E14, E18); group 3's D18 pass reads it too (R54).
bool runsOneTimePasses(List<PackUpgrade> upgrades) => upgrades.any((upgrade) {
  final since = agentFilesSince[upgrade.pack];
  return since != null && upgrade.pin.compareTo(since) < 0;
});

/// Plans the renumber pass over every doc of [works], typed or not.
RenumberPass _renumberPassOf(List<_DocWork> works) => RenumberPass.plan([
  for (final work in works)
    (docPath: work.plannedPath, lf: work.lf, type: work.docType),
]);

/// The label pass of a run and the rewrites of the code files it changes.
typedef _LabelPlan = ({LabelPass pass, List<PlannedRewrite> codeRewrites});

/// Plans the label pass over [docs], the run's docs after the renumber pass,
/// and the files under the `code:` roots that hold a label.
///
/// A code file converts only when the project's git tracks it and its path
/// lies inside the project root, since commit 2 holds nothing else; a label in
/// any other file stays and is listed (E27). Git is asked only when a code
/// file holds a label. A file that is no UTF-8 text is skipped.
_LabelPlan _planLabelPass(
  Directory root, {
  required ProjectConfig config,
  required MergedSet set,
  required List<({String docPath, String lf})> docs,
  required RunGit runGit,
  required Map<String, MergedDocType> docTypes,
}) {
  final projectRoot = Directory(root.resolveSymbolicLinksSync());
  final codeRoot = codeRootFolders(
    projectRoot,
    codeRoot: config.codeRoot,
    codeEntries: const [],
  ).first;
  final entries = codeEntriesOnDisk(projectRoot, set);
  final labelled = <String, _CodeFile>{};
  for (final codePath in codeRootFiles(codeRoot, entries)) {
    final projectPath = _projectPathOf(config.codeRoot, codePath);
    if (projectPath.startsWith(_docsFolder)) continue;
    final original = _readCodeFile(codeRoot, codePath);
    if (original != null && holdsNumberLabel(projectPath, original.text)) {
      labelled[projectPath] = original;
    }
  }
  // A path outside the project root is no path of the project's git, and
  // `ls-files` fails on it (E27).
  final pathspecs = [
    for (final entry in entries)
      if (_projectPathOf(config.codeRoot, entry) case final path
          when _isInsideProject(path))
        path,
  ];
  final tracked = labelled.isEmpty || pathspecs.isEmpty
      ? const <String>{}
      : _trackedPaths(projectRoot, pathspecs, runGit);
  final convertible = {
    for (final path in labelled.keys)
      if (tracked.contains(path) && _isInsideProject(path)) path,
  };
  final pass = LabelPass.plan(
    docs,
    [for (final path in convertible) (path: path, text: labelled[path]!.text)],
    untrackedCodeFiles: [
      for (final MapEntry(:key, :value) in labelled.entries)
        if (!convertible.contains(key)) (path: key, text: value.text),
    ],
    docTypes: docTypes,
  );
  return (
    pass: pass,
    codeRewrites: [
      for (final MapEntry(:key, :value) in pass.codeFiles.entries)
        PlannedRewrite(
          path: key,
          text: '${labelled[key]!.bom ? _bom : ''}$value',
          before: labelled[key]!.hash,
          changes: const [_labelChange],
        ),
    ],
  );
}

/// A code file as decoded: its text with every line end as written, whether
/// it began with a byte order mark, and the [textHashOf] of its text.
typedef _CodeFile = ({String text, bool bom, String hash});

/// Reads the code file at [codePath] under [codeRoot], or null when it cannot
/// be read or is no UTF-8 text.
_CodeFile? _readCodeFile(Directory codeRoot, String codePath) {
  final file = File(
    '${codeRoot.path}${Platform.pathSeparator}'
    '${codePath.split('/').join(Platform.pathSeparator)}',
  );
  try {
    final bytes = file.readAsBytesSync();
    final text = utf8.decode(bytes);
    return (text: text, bom: startsWithUtf8Bom(bytes), hash: textHashOf(text));
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  }
}

/// Whether [projectPath], a normalized path from the project root, lies
/// inside it.
bool _isInsideProject(String projectPath) =>
    projectPath != '..' && !projectPath.startsWith('../');

/// Returns [codePath], a path from the code root [codeRoot], as a path from
/// the project root: `/`-separated, `.` dropped, `..` applied where it can be.
String _projectPathOf(String codeRoot, String codePath) {
  final segments = <String>[];
  for (final segment in '$codeRoot/$codePath'.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..' && segments.isNotEmpty && segments.last != '..') {
      segments.removeLast();
    } else {
      segments.add(segment);
    }
  }
  return segments.join('/');
}

/// Returns the paths under [pathspecs], from [projectRoot], that the project's
/// git tracks; none when git cannot start or [projectRoot] is no work tree.
Set<String> _trackedPaths(
  Directory projectRoot,
  List<String> pathspecs,
  RunGit runGit,
) {
  try {
    final result = runGit([
      '--literal-pathspecs',
      'ls-files',
      '-z',
      '--',
      for (final pathspec in pathspecs.toSet())
        if (pathspec.isEmpty) '.' else pathspec,
    ], workingDirectory: projectRoot.path);
    if (result.exitCode != 0) return const {};
    return {
      for (final path in (result.stdout as String).split('\x00'))
        if (path.isNotEmpty) path,
    };
  } on ProcessException {
    return const {};
  }
}

/// One doc of the run, with its text after the steps and link rewrites.
final class _DocWork {
  new(this.plannedPath, this.original, this.docType, this.lf, this.changes);

  /// The DocPath after the moves.
  final String plannedPath;

  /// The file as read.
  final DocText original;

  final MergedDocType? docType;

  /// The LF text after the steps and link rewrites.
  final String lf;

  /// The labels of the changes made so far, in the order they apply.
  final List<String> changes;
}

/// Returns the rewrite of `config.yaml` that moves the pins of [upgrades] and
/// sets `agent_file_roots` to [agentFileRoots] when it is not null, every other
/// byte kept, or null when neither changes.
PlannedRewrite? _configRewriteOf(
  Directory root,
  List<PackUpgrade> upgrades, {
  required List<String>? agentFileRoots,
}) {
  if (upgrades.isEmpty && agentFileRoots == null) return null;
  final original = readDocText(
    File.fromUri(root.uri.resolve(projectConfigPath)).readAsBytesSync(),
  );
  final packs =
      (loadYamlNode(original.lf) as YamlMap).nodes['packs']! as YamlMap;
  var text = _withScalarsReplaced(original.lf, [
    for (final upgrade in upgrades)
      (packs.nodes[upgrade.pack]! as YamlScalar, '${upgrade.target}'),
  ]);
  if (agentFileRoots != null) text = _withAgentFileRoots(text, agentFileRoots);
  return PlannedRewrite(
    path: projectConfigPath,
    text: writtenText(original, text),
    before: original.hash,
    changes: [
      if (upgrades.isNotEmpty) 'pins',
      if (agentFileRoots != null) _agentFileRootsKey,
    ],
  );
}

/// Returns [text] with the `agent_file_roots` entry set to [roots]: replaced
/// in place when present, else appended.
///
/// The replacement covers through the end of the value's last line, so a null
/// value (the bare key) and an end-of-line comment on the value both leave a
/// valid list; the comment is dropped.
String _withAgentFileRoots(String text, List<String> roots) {
  final block = configText(
    const {},
    agentFileRoots: roots,
  ).substring('packs:\n'.length);
  final map = loadYamlNode(text) as YamlMap;
  final value = map.nodes[_agentFileRootsKey];
  if (value == null) return '${text.endsWith('\n') ? text : '$text\n'}$block';
  final key = map.nodes.keys.firstWhere(
    (key) => (key as YamlNode).value == _agentFileRootsKey,
  ) as YamlNode;
  var valueEnd = value.span.end.offset;
  if (valueEnd > 0 && text[valueEnd - 1] == '\n') {
    // A block-style list's span ends past its last newline.
    valueEnd -= 1;
  }
  final newline = text.indexOf('\n', valueEnd);
  return text.replaceRange(
    key.span.start.offset,
    newline == -1 ? text.length : newline + 1,
    block,
  );
}

/// Returns the final path of each doc of [docPaths], the final paths each
/// move step's docs end at, and the last move step that touched each doc.
///
/// Each `move_file` step, in step order, matches every doc at its CURRENT
/// path, the result of the earlier steps, so moves chain: a doc at `A` under
/// `A` → `B` then `B` → `C` ends at `C` (F6-D22, INV-10).
({
  Map<String, String> planned,
  Map<int, List<String>> movedAt,
  Map<String, int> movedBy,
})
_plannedPaths(List<String> docPaths, List<_Step> steps) {
  final planned = {for (final path in docPaths) path: path};
  final movedAt = <int, List<String>>{};
  final movedBy = <String, int>{};
  for (final (index, (:step, from: _)) in steps.indexed) {
    if (step is! MoveFile) continue;
    final from = PathPattern(step.from);
    final to = PathPattern(step.to);
    for (final entry in planned.entries.toList()) {
      final values = from.valuesOf(entry.value);
      if (values == null) continue;
      final moved = to.fill(values);
      if (moved == entry.value) continue;
      final touched = movedAt[index] ??= [];
      if (!touched.contains(moved)) touched.add(moved);
      planned[entry.key] = moved;
      movedBy[entry.key] = index;
    }
  }
  return (planned: planned, movedAt: movedAt, movedBy: movedBy);
}

const _resolveCollision =
    'move, rename, or merge each listed doc or entry so the step no longer '
    'lands on it, then run specstone migrate again';

/// Throws `upgrade_collision` for the first of [faults] on each doc, the
/// first as the fault and the rest chained through `more`.
///
/// A doc can collide once per rival and once per step; it is listed once
/// (INV-16).
void _throwCollisions(List<MigrateFault> faults) {
  final seen = <String?>{};
  final perDoc = [
    for (final fault in faults)
      if (seen.add(fault.file)) fault,
  ];
  if (perDoc.isEmpty) return;
  final first = perDoc.first;
  throw MigrateFault(
    first.code,
    first.message,
    file: first.file,
    key: first.key,
    more: perDoc.sublist(1),
  );
}

/// Returns an `upgrade_collision` fault for each `move_file` step that lands on
/// a path the Owner still holds: a doc no step moves, or a second doc of the
/// same move.
///
/// Two docs moved onto one path each fault on their own line. A move onto
/// another moved doc's old path is fine: [orderedMoves] orders those.
List<MigrateFault> _moveCollisions(
  List<String> docPaths, {
  required Map<String, String> planned,
  required Map<String, int> movedBy,
  required List<_Step> steps,
}) {
  final faults = <MigrateFault>[];
  for (final source in docPaths) {
    final destination = planned[source]!;
    if (destination == source) continue;
    final step = steps[movedBy[source]!].step;
    if (step is! MoveFile) continue;
    // A stayer holds its ground: the mover's destination is its own path.
    final stayer = docPaths.any(
      (path) => path == destination && movedBy[path] == null,
    );
    // Another mover with the same final path: each fault names the other. A
    // stayer never counts; it is the stayer fault below.
    final rivals = docPaths.where(
      (path) =>
          path != source &&
          movedBy[path] != null &&
          planned[path] == destination,
    );
    if (stayer) {
      faults.add(_collisionFault(step, source, 'the doc already there holds'));
    }
    for (final rival in rivals) {
      faults.add(_collisionFault(step, source, '$rival also moves to'));
    }
  }
  return faults;
}

MigrateFault _collisionFault(MoveFile step, String source, String holder) =>
    MigrateFault(
      MigrateFaultCode.upgradeCollision,
      'move_file of ${step.docType} moves ${step.from} to ${step.to}, '
      'which $holder; '
      '$_resolveCollision',
      file: source,
    );

/// Orders [moves] so a move whose target is another move's original path runs
/// after that move.
///
/// A cycle, such as two docs trading places, has no such order;
/// [RunPlan.journalSteps] parks one of its moves in the stage.
List<PathMove> orderedMoves(List<PathMove> moves) {
  final bySource = {for (final move in moves) move.from: move};
  final ordered = <PathMove>[];
  final placed = <String>{};
  void place(PathMove move) {
    if (!placed.add(move.from)) return;
    final blocker = bySource[move.to];
    if (blocker != null && blocker.from != move.from) place(blocker);
    ordered.add(move);
  }

  moves.forEach(place);
  return ordered;
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
