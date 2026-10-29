import 'dart:io';

import 'package:specstone_core/src/doc_model/doc_splice.dart' show withKeyBlock;
import 'package:specstone_core/src/document_writing/new_doc.dart'
    show skeletonOf;
import 'package:specstone_core/src/document_writing/rewrite_refs.dart'
    show PathMove;
import 'package:specstone_core/src/index_query/index_store.dart'
    show specstoneGitignoreLines;
import 'package:specstone_core/src/rendering/formatter.dart' show headerKey;
import 'package:specstone_core/src/setup_migration/carried_packs.dart';
import 'package:specstone_core/src/setup_migration/first_fingerprints.dart';
import 'package:specstone_core/src/setup_migration/legacy_moves.dart';
import 'package:specstone_core/src/setup_migration/legacy_rewrites.dart';
import 'package:specstone_core/src/setup_migration/legacy_tree.dart';
import 'package:specstone_core/src/setup_migration/project_files.dart';
import 'package:specstone_core/src/setup_migration/project_root.dart';
import 'package:specstone_core/src/setup_migration/run_plan.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/project_config.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';

const _docsFolder = 'docs/';
const _specIndexPath = 'specs/INDEX.md';
final _gitignoreText = '${specstoneGitignoreLines.join('\n')}\n';
const _gnfrId = 'gnfr';
const _commit1Message = 'move legacy docs to their new paths';

/// The message of a legacy migration's second commit.
const legacyCommit2Message =
    'rewrite titles, keys, and links; add project configuration';

/// What an applied or resumed migration prints after its commit lines.
const legacyClosingLine = 'run specstone check to list what is left to fill';

final _frFile = RegExp(r'/functional_requirements/fr\d+_[^/]+\.md$');

/// Plans the legacy migration of the project at [root].
///
/// Reads the files under `docs/prds` and `docs/specs`, the carried packs, and
/// nothing else; writes nothing. Throws `MigrateFault` `group_slug_duplicate`
/// and a `TemplateFault` before it returns, so a refused run prints nothing.
/// [homeDirectory] is the personal pack home, or null.
RunPlan planLegacyRun(
  Directory root, {
  required TemplateResolver templates,
  required Directory? homeDirectory,
}) {
  final docsRoot = Directory.fromUri(root.uri.resolve(_docsFolder));
  final docPaths = _docPathsOf(docsRoot)..sort(compareCodePoints);
  final specMap = _specMapOf(docsRoot, docPaths);
  final features = scanLegacyFeatures(docPaths);
  refuseDuplicateGroups(features);
  final legacy = planLegacyMoves(
    docPaths,
    specMap: specMap,
    features: features,
  );

  final carried = templates.resolveCarried(
    packNames: carriedPacks,
    homeDirectory: homeDirectory,
  );
  final gnfr = carried.lookup(_gnfrId);
  final carriedGnfr = <String>{
    if (gnfr != null)
      for (final section in gnfr.sections) section.header,
  };
  final carriedGnfrIds = <String>{
    if (gnfr != null)
      for (final section in gnfr.sections) section.id,
  };

  final rewrites = _rewritesOf(
    docsRoot,
    docPaths,
    legacy: legacy,
    specMap: specMap,
    features: features,
    carriedGnfr: carriedGnfr,
  );
  final overrides = _overridesOf(
    features,
    rewrites.gnfrSections,
    carriedGnfrIds,
  );
  final (set: projectSet, :pins) = templates.resolveCarriedPinned(
    packNames: carriedPacks,
    homeDirectory: homeDirectory,
    projectLayers: parseOverrides(overrides),
  );

  final config = File.fromUri(root.uri.resolve(projectConfigPath));
  final configRewrite = config.existsSync()
      ? _configRewriteOf(root, config, pins)
      : null;

  return RunPlan(
    header: 'legacy migration: ${root.path} ($legacyContextPath)',
    moves: legacy.moves,
    prunes: prunesOf(legacy.moves),
    rewrites: [...rewrites.planned, ?configRewrite],
    creates: [
      if (!config.existsSync())
        PlannedCreate(
          path: projectConfigPath,
          text: configText(pins),
          note: ': ${_pinList(pins)}',
        ),
      if (!File.fromUri(root.uri.resolve(specstoneGitignorePath)).existsSync())
        PlannedCreate(path: specstoneGitignorePath, text: _gitignoreText),
      for (final path in overrides.keys.toList()..sort(compareCodePoints))
        PlannedCreate(path: path, text: overrides[path]!),
      ..._draftsOf(projectSet, docPaths, legacy.moves),
    ],
    left: legacy.left,
    commit1Message: _commit1Message,
    commit2Message: legacyCommit2Message,
    closingLine: legacyClosingLine,
  );
}

/// Returns the DocPath of every file under `prds/` and `specs/`.
List<String> _docPathsOf(Directory docsRoot) {
  // A file URI path always uses `/`, so no platform separator is split on.
  final prefixLength = docsRoot.uri.path.length;
  final paths = <String>[];
  for (final folder in const ['prds', 'specs']) {
    final dir = Directory.fromUri(docsRoot.uri.resolve('$folder/'));
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      paths.add(Uri.decodeComponent(entity.uri.path.substring(prefixLength)));
    }
  }
  return paths;
}

List<SpecMapRow> _specMapOf(Directory docsRoot, List<String> docPaths) {
  if (!docPaths.contains(_specIndexPath)) return const [];
  final index = File.fromUri(docsRoot.uri.resolve(_specIndexPath));
  return readSpecMap(readDocText(index.readAsBytesSync()).lf);
}

typedef _Rewrites = ({List<PlannedRewrite> planned, List<String> gnfrSections});

/// One markdown doc on its way to commit 2.
final class _Work {
  new(this.legacyPath, this.newPath, this.kind, this.original)
    : lf = original.lf;

  final String legacyPath;
  final String newPath;
  final LegacyKind? kind;
  final DocText original;
  String lf;
  final List<String> changes = [];
  String note = '';

  /// Whether the doc is an API doc renamed to `API.md`, whose fingerprints
  /// need the rewritten FR texts.
  bool get awaitsFingerprints =>
      kind == LegacyKind.api &&
      legacyPath != newPath &&
      newPath.endsWith('/API.md');
}

/// Plans the rewrite of every markdown doc the run places or leaves.
///
/// Only `.md` files are read; any other file moves untouched. A doc left in
/// place gets the link rewrite and nothing else. The first fingerprints hash
/// each FR as the run writes it, so the FR docs are rewritten first.
_Rewrites _rewritesOf(
  Directory docsRoot,
  List<String> docPaths, {
  required LegacyMoves legacy,
  required List<SpecMapRow> specMap,
  required LegacyFeatures features,
  required Set<String> carriedGnfr,
}) {
  final carriedKeys = {for (final header in carriedGnfr) headerKey(header)};
  final newOf = {
    for (final MapEntry(key: newPath, value: legacyPath)
        in legacy.fromOf.entries)
      legacyPath: newPath,
  };
  final works = [
    for (final legacyPath in docPaths)
      if (legacyPath.endsWith('.md') &&
          (newOf.containsKey(legacyPath) || legacy.left.contains(legacyPath)))
        _Work(
          legacyPath,
          newOf[legacyPath] ?? legacyPath,
          legacy.kindOf[newOf[legacyPath]],
          readDocText(
            File.fromUri(docsRoot.uri.resolve(legacyPath)).readAsBytesSync(),
          ),
        ),
  ];

  final gnfrSections = <String>[];
  final seenKeys = <String>{};
  for (final work in works) {
    final kind = work.kind;
    if (kind == null) continue;
    final rewrite = rewriteLegacyDoc(work.lf, kind, gnfrHeaders: carriedGnfr);
    work.lf = rewrite.lf;
    work.changes.addAll(rewrite.changes);
    final missing = [
      for (final header in rewrite.gnfrSections)
        if (!carriedKeys.contains(headerKey(header)) &&
            seenKeys.add(headerKey(header)))
          header,
    ];
    if (missing.isNotEmpty) {
      gnfrSections.addAll(missing);
      work.note =
          '; project-layer section${missing.length == 1 ? '' : 's'} '
          '${missing.join(', ')}';
    }
    if (work.legacyPath != work.newPath && kind == LegacyKind.architecture) {
      final covers = coversOf(_folderOf(work.legacyPath), specMap);
      if (covers != null) {
        work.lf = withKeyBlock(work.lf, 'covers', covers.block);
        work.changes.add(covers.label);
      }
    }
  }

  final textOf = {for (final work in works) work.legacyPath: work};
  for (final work in works) {
    if (work.awaitsFingerprints) continue;
    _rewriteLinks(work, legacy.moves);
  }
  for (final work in works.where((work) => work.awaitsFingerprints)) {
    final fingerprints = writeFirstFingerprints(
      work.lf,
      featureFrs: _featureFrsOf(features, work.newPath, rewritten: textOf),
    );
    work.lf = fingerprints.lf;
    final label = fingerprints.label;
    if (label != null) work.changes.add(label);
    _rewriteLinks(work, legacy.moves);
  }

  return (
    planned: [
      for (final work in works)
        if (work.changes.isNotEmpty)
          PlannedRewrite(
            path: '$_docsFolder${work.newPath}',
            text: writtenText(work.original, work.lf),
            changes: work.changes,
            note: work.note,
          ),
    ],
    gnfrSections: gnfrSections,
  );
}

void _rewriteLinks(_Work work, List<PathMove> moves) {
  final links = rewriteLinks(work.lf, docPath: work.legacyPath, moves: moves);
  work.lf = links.lf;
  final label = links.label;
  if (label != null) work.changes.add(label);
}

/// Returns the config rewrite that sets the carried [pins] and keeps every
/// other pin of the existing [config], or null when the text stays.
PlannedRewrite? _configRewriteOf(
  Directory root,
  File config,
  Map<String, PackVersion> pins,
) {
  final text = configText({...ProjectConfig.read(root).pins, ...pins});
  if (text == config.readAsStringSync()) return null;
  return PlannedRewrite(path: projectConfigPath, text: text, changes: ['pins']);
}

String _folderOf(String docPath) =>
    docPath.substring(0, docPath.lastIndexOf('/') + 1);

/// Returns the LF text of each FR file of the feature that holds the API doc
/// at [apiPath] (`specs/<FeaturePath>/API.md`), by legacy DocPath.
///
/// The text is the one the run writes, taken from [rewritten] by legacy
/// DocPath.
Map<String, String> _featureFrsOf(
  LegacyFeatures features,
  String apiPath, {
  required Map<String, _Work> rewritten,
}) {
  final featurePath = _folderOf(apiPath)
      .substring('specs/'.length)
      .replaceFirst(RegExp(r'/$'), '');
  final folder = features.features
      .where((feature) => feature.featurePath == featurePath)
      .map((feature) => feature.folder)
      .firstOrNull;
  if (folder == null) return const {};
  return {
    for (final MapEntry(:key, :value) in rewritten.entries)
      if (key.startsWith(folder) && _frFile.hasMatch(key)) key: value.lf,
  };
}

/// Returns the project-layer files the moved tree needs, by ProjectPath.
Map<String, String> _overridesOf(
  LegacyFeatures features,
  List<String> gnfrSections,
  Set<String> carriedGnfrIds,
) {
  final gnfr = gnfrOverride(gnfrSections, carriedIds: carriedGnfrIds);
  return {
    if (features.grouped) ...groupedPathOverrides(),
    if (gnfr != null) gnfr.key: gnfr.value,
  };
}

/// Returns the folders the moves empty, the deepest first, as ProjectPaths.
List<String> prunesOf(List<PathMove> moves) => {
  for (final move in moves)
    '$_docsFolder${move.from.substring(0, move.from.lastIndexOf('/'))}',
}.toList()..sort((a, b) => compareCodePoints(b, a));

/// Returns a draft for each singular doc type whose path the moved tree
/// lacks.
List<PlannedCreate> _draftsOf(
  MergedSet set,
  List<String> docPaths,
  List<PathMove> moves,
) {
  final moved = {for (final move in moves) move.from: move.to};
  final present = {for (final path in docPaths) moved[path] ?? path};
  return [
    for (final docType in singularDocTypes(set))
      if (!present.contains(docType.path))
        PlannedCreate(
          path: '$_docsFolder${docType.path}',
          text: skeletonOf(docType, docType.id),
          note: ' (draft)',
        ),
  ];
}

String _pinList(Map<String, PackVersion> pins) => [
  for (final name in pins.keys.toList()..sort(compareCodePoints))
    '$name ${pins[name]}',
].join(', ');
