import 'dart:io';

import 'package:specstone_core/src/consistency_check/doc_lines.dart';
import 'package:specstone_core/src/consistency_check/implements_entry.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart' show withKeyBlock;
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/document_writing/approval.dart'
    show withApprovalHash;
import 'package:specstone_core/src/document_writing/move_journal.dart'
    show textHashOf;
import 'package:specstone_core/src/document_writing/new_doc.dart'
    show skeletonOf;
import 'package:specstone_core/src/document_writing/rewrite_refs.dart'
    show PathMove;
import 'package:specstone_core/src/index_query/index_store.dart'
    show specstoneGitignoreLines;
import 'package:specstone_core/src/rendering/formatter.dart'
    show headerKey, layOutDoc;
import 'package:specstone_core/src/setup_migration/agent_targets.dart';
import 'package:specstone_core/src/setup_migration/carried_packs.dart';
import 'package:specstone_core/src/setup_migration/first_fingerprints.dart';
import 'package:specstone_core/src/setup_migration/label_pass.dart'
    show LabelTree, numberLabelsPlanLine;
import 'package:specstone_core/src/setup_migration/legacy_moves.dart';
import 'package:specstone_core/src/setup_migration/legacy_rewrites.dart';
import 'package:specstone_core/src/setup_migration/legacy_tree.dart';
import 'package:specstone_core/src/setup_migration/project_files.dart';
import 'package:specstone_core/src/setup_migration/project_root.dart';
import 'package:specstone_core/src/setup_migration/run_plan.dart';
import 'package:specstone_core/src/setup_migration/stamp_pass.dart'
    show stampsPlanLine;
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart'
    show MergedDocType;
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/project_config.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:specstone_core/src/version.dart';

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
/// A created config names [linkFolder] as its `code_root` when more legacy
/// `implements` paths name a file from there than from [root].
///
/// - [homeDirectory]: the personal pack home, or null.
/// - [linkFolder]: the canonical folder whose `docs` link led to [root], or
///   null.
RunPlan planLegacyRun(
  Directory root, {
  required TemplateResolver templates,
  required Directory? homeDirectory,
  Directory? linkFolder,
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

  final originals = _originalsOf(docsRoot, docPaths);
  final titled = _titledWorksOf(
    originals,
    legacy: legacy,
    specMap: specMap,
    carriedGnfr: carriedGnfr,
  );
  final overrides = _overridesOf(features, titled.gnfrSections, carriedGnfrIds);
  final (set: projectSet, :pins) = templates.resolveCarriedPinned(
    packNames: carriedPacks,
    homeDirectory: homeDirectory,
    projectLayers: parseOverrides(overrides),
  );
  final rewrites = _rewritesOf(
    titled.works,
    projectSet: projectSet,
    legacy: legacy,
    features: features,
    exists: (path) => _existsIn(docsRoot, path),
  );

  final config = File.fromUri(root.uri.resolve(projectConfigPath));
  final existing = config.existsSync() ? ProjectConfig.read(root) : null;
  final codeRoot =
      existing?.codeRoot ??
      (linkFolder == null
          ? '.'
          : _codeRootOf(root, linkFolder, originals.values));
  final agentFiles = _agentFilesOf(
    root,
    codeRoot: codeRoot,
    agentFileRoots: existing?.agentFileRoots ?? const [],
  );
  final configRewrite = existing == null
      ? null
      : _configRewriteOf(
          config,
          existing,
          pins,
          agentFileRoots: agentFiles.agentFileRoots,
        );

  return RunPlan(
    header: 'legacy migration: ${root.path} ($legacyContextPath)',
    moves: legacy.moves,
    prunes: prunesOf(legacy.moves),
    rewrites: [...rewrites.planned, ?configRewrite],
    rewriteLines: [
      for (final rewrite in rewrites.planned)
        if (rewrite.changes.isNotEmpty) _rewriteLineOf(rewrite),
      ?rewrites.labelsLine,
      ?formatLayoutLine(rewrites.layoutOnly),
      ?rewrites.stampsLine,
      if (configRewrite != null) _rewriteLineOf(configRewrite),
    ],
    creates: [
      if (existing == null)
        PlannedCreate(
          path: projectConfigPath,
          text: configText(
            pins,
            codeRoot: codeRoot,
            agentFileRoots: agentFiles.agentFileRoots,
          ),
          note:
              ': ${_pinList(pins)}'
              '${codeRoot == '.' ? '' : '; code_root $codeRoot'}',
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
    agentFiles: agentFiles,
  );
}

/// Plans the agent files of the legacy run: the full upsert at the root and at
/// each unlisted repository top.
///
/// The legacy tree holds no `code:` entry, so the code roots are the config's
/// `code_root` alone.
AgentWritePlan _agentFilesOf(
  Directory root, {
  required String codeRoot,
  required List<String> agentFileRoots,
}) {
  final projectRoot = Directory(root.resolveSymbolicLinksSync());
  return planAgentWrites(
    AgentFileInputs(
      projectRoot: projectRoot,
      cliVersion: specstoneVersion,
      codeRootFolders: codeRootFolders(
        projectRoot,
        codeRoot: codeRoot,
        codeEntries: const [],
      ),
      agentFileRoots: agentFileRoots,
    ),
    full: true,
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
  final text = readDocFile(index, docPath: _specIndexPath);
  return text == null ? const [] : readSpecMap(text.lf);
}

typedef _Titled = ({List<_Work> works, List<String> gnfrSections});

/// The planned rewrites, and the DocPaths of the typed docs whose only change
/// is their layout.
///
/// `labelsLine` and `stampsLine` are the upgrade's `number labels:` and
/// `stamps:` plan lines, null when the run has nothing to say.
typedef _Rewrites = ({
  List<PlannedRewrite> planned,
  List<String> layoutOnly,
  String? labelsLine,
  String? stampsLine,
});

/// One markdown doc on its way to commit 2.
final class _Work {
  new(this.legacyPath, this.newPath, this.kind, this.original)
    : lf = original.lf;

  final String legacyPath;
  final String newPath;
  final LegacyKind? kind;
  final DocText original;
  String lf;

  /// The text before the approval stamp, the last write of the doc.
  String laidOut = '';

  /// Whether a legacy ID or number label of the doc became a name.
  bool hasNamedLabels = false;
  final List<String> changes = [];
  String note = '';

  /// Whether the doc is an API doc renamed to `API.md`, whose fingerprints
  /// need the rewritten FR texts.
  bool get awaitsFingerprints =>
      kind == LegacyKind.api &&
      legacyPath != newPath &&
      newPath.endsWith('/API.md');
}

/// Returns the text of every `.md` doc of [docPaths] that is UTF-8, by
/// legacy DocPath in [docPaths] order; any other file moves untouched.
Map<String, DocText> _originalsOf(Directory docsRoot, List<String> docPaths) =>
    {
      for (final docPath in docPaths)
        if (docPath.endsWith('.md'))
          docPath: ?readDocFile(docFileOf(docsRoot, docPath), docPath: docPath),
    };

/// Returns the code root of a created config: [linkFolder] from [root] when
/// more `implements` entries of [originals] name a file from it, else `.`.
///
/// An entry counts by [ImplementsEntry.namesFileFrom], the rule `check`
/// resolves it by. A tie keeps `.`, as does a [linkFolder] whose path from
/// [root] the config reader would refuse or no relative path reaches.
String _codeRootOf(
  Directory root,
  Directory linkFolder,
  Iterable<DocText> originals,
) {
  var fromRoot = 0;
  var fromLink = 0;
  for (final original in originals) {
    for (final (:value, line: _, text: _) in DocLines.of(
      original.lf,
    ).entriesOf(implementsField)) {
      if (value is! String) continue;
      final entry = ImplementsEntry(value);
      if (entry.namesFileFrom(root)) fromRoot++;
      if (entry.namesFileFrom(linkFolder)) fromLink++;
    }
  }
  if (fromLink <= fromRoot) return '.';
  final relative = relativeFolderPath(root, linkFolder);
  return relative != null && isCodeRootValue(relative) ? relative : '.';
}

/// Applies the title, key, and covers rewrites to every markdown doc the run
/// places or leaves.
///
/// Only the [originals] are rewritten. The project set needs the GNFR
/// sections this returns, so the links, first fingerprints, and layout wait
/// for [_rewritesOf].
_Titled _titledWorksOf(
  Map<String, DocText> originals, {
  required LegacyMoves legacy,
  required List<SpecMapRow> specMap,
  required Set<String> carriedGnfr,
}) {
  final carriedKeys = {for (final header in carriedGnfr) headerKey(header)};
  final newOf = {
    for (final MapEntry(key: newPath, value: legacyPath)
        in legacy.fromOf.entries)
      legacyPath: newPath,
  };
  final works = [
    for (final MapEntry(key: legacyPath, value: original) in originals.entries)
      if (newOf.containsKey(legacyPath) || legacy.left.contains(legacyPath))
        _Work(
          legacyPath,
          newOf[legacyPath] ?? legacyPath,
          legacy.kindOf[newOf[legacyPath]],
          original,
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

  return (works: works, gnfrSections: gnfrSections);
}

/// Plans the link rewrites, first fingerprints, and layout of [works].
///
/// A doc left in place gets the link rewrite and the layout. The first
/// fingerprints hash each FR as the run writes it, laid out, so the FR docs
/// are rewritten first.
_Rewrites _rewritesOf(
  List<_Work> works, {
  required MergedSet projectSet,
  required LegacyMoves legacy,
  required LegacyFeatures features,
  required bool Function(String path) exists,
}) {
  final matcher = DocTypeMatcher(projectSet);
  var approvals = 0;
  var fingerprintEntries = 0;
  MergedDocType? typeOf(_Work work) => switch (matcher.match(work.newPath)) {
    MatchedDocType(:final docType) => docType,
    _ => null,
  };
  // The stamp is the last write of a doc, so the hash covers its final text
  // (`show_plan_and_apply_on_yes` E07).
  void layOut(_Work work) {
    final type = typeOf(work);
    work.lf = layOutDoc(work.lf, type);
    work.laidOut = work.lf;
    if (type != null) {
      work.lf = withApprovalHash(withKeyBlock(work.lf, 'draft', null), type);
      approvals++;
    }
  }

  final tree = _convertLabels(works, typeOf, features);
  final textOf = {for (final work in works) work.legacyPath: work};
  for (final work in works) {
    if (work.awaitsFingerprints) continue;
    _rewriteRefs(work, legacy.moves, exists);
    layOut(work);
  }
  for (final work in works.where((work) => work.awaitsFingerprints)) {
    final fingerprints = writeFirstFingerprints(
      work.lf,
      featureFrs: _featureFrsOf(features, work.newPath, rewritten: textOf),
    );
    work.lf = fingerprints.lf;
    fingerprintEntries += fingerprints.entries;
    final label = fingerprints.label;
    if (label != null) work.changes.add(label);
    _rewriteRefs(work, legacy.moves, exists);
    layOut(work);
  }

  final written = [
    for (final work in works)
      if (work.changes.isNotEmpty || work.lf != work.original.lf) work,
  ];
  final byPath = [...works]
    ..sort((a, b) => compareCodePoints(a.newPath, b.newPath));
  return (
    planned: [
      for (final work in written)
        PlannedRewrite(
          path: '$_docsFolder${work.newPath}',
          text: writtenText(work.original, work.lf),
          before: work.original.hash,
          changes: work.changes,
          note: work.note,
        ),
    ],
    layoutOnly: [
      for (final work in written)
        if (work.changes.isEmpty &&
            !work.hasNamedLabels &&
            work.laidOut != work.original.lf)
          work.newPath,
    ],
    labelsLine: numberLabelsPlanLine(
      converted: [
        for (final work in byPath)
          if (work.hasNamedLabels) work.newPath,
      ],
      kept: _keptLabelsOf(tree, byPath),
    ),
    stampsLine: stampsPlanLine(approvals, fingerprintEntries),
  );
}

/// Converts the legacy IDs and number labels of [works] that name one moved
/// doc to its name (`rewrite_titles_keys_and_links` E18, E19).
///
/// The tree is read before any conversion, from the texts the title and key
/// rewrites left; a doc cites from its legacy path. Returns the tree.
LabelTree _convertLabels(
  List<_Work> works,
  MergedDocType? Function(_Work work) typeOf,
  LegacyFeatures features,
) {
  final tree = LabelTree.legacy(
    [
      for (final work in works)
        (docPath: work.newPath, legacyPath: work.legacyPath, lf: work.lf),
    ],
    docTypes: {for (final work in works) work.newPath: ?typeOf(work)},
    featurePaths: {
      for (final feature in features.features)
        feature.folder: ?feature.featurePath,
    },
  );
  for (final work in works) {
    final converted = convertLegacyLabels(
      tree,
      legacyPath: work.legacyPath,
      lf: work.lf,
    );
    work.hasNamedLabels = converted.lf != work.lf;
    work.lf = converted.lf;
  }
  return tree;
}

/// Returns the labels left in the written text of [works] as
/// `<DocPath>:<line> <label>`.
///
/// Read from the text the run writes, so each line is the line of the file.
List<String> _keptLabelsOf(LabelTree tree, List<_Work> works) => [
  for (final work in works)
    for (final (:line, :label) in convertLegacyLabels(
      tree,
      legacyPath: work.legacyPath,
      lf: work.lf,
    ).kept)
      '${work.newPath}:$line $label',
];

/// Points the links and path mentions of [work] at the paths [moves] leave
/// their files at, labelling each kind that changes.
void _rewriteRefs(
  _Work work,
  List<PathMove> moves,
  bool Function(String path) exists,
) {
  final links = rewriteLinks(work.lf, docPath: work.legacyPath, moves: moves);
  work.lf = links.lf;
  final linkLabel = links.label;
  if (linkLabel != null) work.changes.add(linkLabel);
  final mentions = rewriteMentions(
    work.lf,
    docPath: work.legacyPath,
    moves: moves,
    exists: exists,
  );
  work.lf = mentions.lf;
  final mentionLabel = mentions.label;
  if (mentionLabel != null) work.changes.add(mentionLabel);
}

/// Whether [path], from [docsRoot] and possibly leaving it, names a file or
/// folder of the legacy tree.
bool _existsIn(Directory docsRoot, String path) =>
    FileSystemEntity.typeSync(docFileOf(docsRoot, path).path) !=
    FileSystemEntityType.notFound;

/// Returns the config rewrite that sets the carried [pins] and keeps every
/// other pin and the code root of the [existing] config, or null when the
/// text stays.
///
/// [agentFileRoots] is the full list the run leaves in the config.
PlannedRewrite? _configRewriteOf(
  File config,
  ProjectConfig existing,
  Map<String, PackVersion> pins, {
  required List<String> agentFileRoots,
}) {
  final text = configText(
    {...existing.pins, ...pins},
    codeRoot: existing.codeRoot,
    agentFileRoots: agentFileRoots,
  );
  final current = config.readAsStringSync();
  if (text == current) return null;
  return PlannedRewrite(
    path: projectConfigPath,
    text: text,
    before: textHashOf(current),
    changes: ['pins'],
  );
}

/// Returns the plan line of [rewrite]: its path from the docs root, or from
/// the project root for a config file, then its changes.
String _rewriteLineOf(PlannedRewrite rewrite) {
  final shown = rewrite.path.startsWith(_docsFolder)
      ? rewrite.path.substring(_docsFolder.length)
      : rewrite.path;
  return '$shown: ${rewrite.changes.join(', ')}${rewrite.note}';
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
