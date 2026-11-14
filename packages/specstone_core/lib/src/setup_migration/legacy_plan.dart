import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/doc_lines.dart';
import 'package:specstone_core/src/consistency_check/implements_entry.dart';
import 'package:specstone_core/src/doc_model/doc.dart' show Doc, KeyBlock;
import 'package:specstone_core/src/doc_model/doc_splice.dart' show withKeyBlock;
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/doc_model/path_pattern.dart';
import 'package:specstone_core/src/document_writing/approval.dart'
    show withApprovalHash;
import 'package:specstone_core/src/document_writing/move_journal.dart'
    show textHashOf;
import 'package:specstone_core/src/document_writing/new_doc.dart'
    show skeletonOf;
import 'package:specstone_core/src/document_writing/rewrite_refs.dart'
    show PathMove;
import 'package:specstone_core/src/document_writing/stale_mentions.dart'
    show MentionScope, StaleMention, staleMentionsIn;
import 'package:specstone_core/src/index_query/index_store.dart'
    show specstoneGitignoreLines;
import 'package:specstone_core/src/index_query/indexed_doc.dart'
    show IndexedDoc;
import 'package:specstone_core/src/plan_hash.dart';
import 'package:specstone_core/src/rendering/formatter.dart'
    show headerKey, layOutDoc;
import 'package:specstone_core/src/setup_migration/agent_targets.dart';
import 'package:specstone_core/src/setup_migration/carried_packs.dart';
import 'package:specstone_core/src/setup_migration/code_root_inference.dart';
import 'package:specstone_core/src/setup_migration/first_fingerprints.dart';
import 'package:specstone_core/src/setup_migration/label_pass.dart'
    show LabelTree, numberLabelsPlanLine, withLabelAnchorsMoved;
import 'package:specstone_core/src/setup_migration/legacy_moves.dart';
import 'package:specstone_core/src/setup_migration/legacy_rewrites.dart';
import 'package:specstone_core/src/setup_migration/legacy_tree.dart';
import 'package:specstone_core/src/setup_migration/project_files.dart';
import 'package:specstone_core/src/setup_migration/project_root.dart';
import 'package:specstone_core/src/setup_migration/record_placement.dart';
import 'package:specstone_core/src/setup_migration/run_plan.dart';
import 'package:specstone_core/src/setup_migration/stamp_pass.dart'
    show stampsPlanLine;
import 'package:specstone_core/src/setup_migration/test_name_pass.dart';
import 'package:specstone_core/src/setup_migration/tree_move.dart'
    show treeMovesOf;
import 'package:specstone_core/src/setup_migration/upgrade_plan.dart'
    show orderedMoves;
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/code_target.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart'
    show MergedDocType;
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/pack_manifest.dart'
    show PackManifest;
import 'package:specstone_core/src/templates/pack_migration.dart'
    show MoveToRecord;
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/project_config.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:specstone_core/src/version.dart';

const _docsFolder = 'docs/';
const _specIndexPath = 'specs/INDEX.md';
final _gitignoreText = '${specstoneGitignoreLines.join('\n')}\n';
const _gnfrId = 'gnfr';
const _appliesToField = 'applies_to';
const _coversField = 'covers';
const _toRecord = 'to record';
const _recordEdit = 'add record entries';
const _testsEdit = 'add test lines';
const _commit1Message = 'move legacy docs to their new paths';

/// The message of a legacy migration's second commit.
const legacyCommit2Message =
    'rewrite titles, keys, and links; add project configuration';

final _frFile = RegExp(r'/functional_requirements/fr\d+_[^/]+\.md$');

/// Plans the legacy migration of the project at [root].
///
/// Reads the files under `docs/prds` and `docs/specs`, the carried packs, and
/// nothing else; writes nothing. Throws `MigrateFault` `group_slug_duplicate`,
/// `legacy_collision`, or `value_unplaced` (every value no record takes, or
/// else every create onto a taken path, [RunPlan.refuseTakenCreates]) and a
/// `TemplateFault` before it returns, so a refused run prints nothing. The
/// plan's `inputs` hold every file it read.
/// A created config, or a rewritten one with no `code_root:` key, names the
/// folder from which the most cited code paths exist as its `code_root`
/// (`write_project_files` E11).
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
  final inputs = PlanInputs(root);
  return inputs.collect(
    () => _legacyRunOf(
      root,
      templates: templates,
      homeDirectory: homeDirectory,
      linkFolder: linkFolder,
      inputs: inputs,
    ),
  )..refuseTakenCreates(root);
}

/// Plans the legacy run of [root] while [inputs] records each file read.
RunPlan _legacyRunOf(
  Directory root, {
  required TemplateResolver templates,
  required Directory? homeDirectory,
  required Directory? linkFolder,
  required PlanInputs inputs,
}) {
  final docsRoot = Directory.fromUri(root.uri.resolve(_docsFolder));
  final docPaths = _docPathsOf(docsRoot)..sort(compareCodePoints);
  final specMap = _specMapOf(docsRoot, docPaths);
  final features = scanLegacyFeatures(docPaths);
  refuseDuplicateGroups(features);
  final placed = planLegacyMoves(
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
    legacy: placed,
    specMap: specMap,
    carriedGnfr: carriedGnfr,
  );
  final overrides = _overridesOf(features, titled.gnfrSections, carriedGnfrIds);
  final (set: projectSet, :pins) = templates.resolveCarriedPinned(
    packNames: carriedPacks,
    homeDirectory: homeDirectory,
    projectLayers: parseOverrides(overrides),
  );
  final config = File.fromUri(root.uri.resolve(projectConfigPath));
  final existing = config.existsSync() ? ProjectConfig.read(root) : null;
  // A config that holds its roots, `code_root:` or `targets:`, keeps them
  // (`write_project_files` E10, E15).
  final keepsCodeRoots =
      existing != null &&
      (existing.hasCodeRoot || existing.targetNames.isNotEmpty);
  final targetNames = existing?.targetNames ?? const <String>[];
  final treeMoves = treeMovesOf(
    [...placed.fromOf.keys, ...placed.left],
    projectSet,
    targetNames: targetNames,
  );
  final (:moves, :left) = _inFirstTarget(placed, treeMoves, docPaths: docPaths);
  final landing = {for (final move in treeMoves) move.from: move.to};
  for (final work in titled.works) {
    work.newPath = landing[work.newPath] ?? work.newPath;
  }
  final inferred = keepsCodeRoots
      ? null
      : inferCodeRoot(
          root,
          linkFolder: linkFolder,
          implementsEntries: [
            for (final original in originals.values)
              ..._entriesOf(original.lf, implementsField),
          ],
          coversEntries: [for (final work in titled.works) ...work.citedCovers],
        );
  final codeRoot = inferred?.value ?? existing?.codeRoot ?? '.';
  final codeRootNote = _codeRootNoteOf(inferred);
  final taken = takenAfterMoves(root, moves);
  final targets = inferred == null && existing != null
      ? existing.targets
      : [CodeTarget(null, codeRoot: codeRoot)];
  final rewrites = _rewritesOf(
    titled.works,
    projectSet: projectSet,
    moves: moves,
    features: features,
    targetNames: targetNames,
    recordSteps: _recordStepsOf(
      templates.availableManifests(carriedPacks, homeDirectory: homeDirectory),
    ),
    exists: (path) => _existsIn(docsRoot, path),
    isTaken: (docPath) => taken('$_docsFolder$docPath'),
    testNames: projectSet.recordDocType != null
        ? (
            root: Directory(root.resolveSymbolicLinksSync()),
            targets: targets,
            agentFileRoots: existing?.agentFileRoots ?? const [],
          )
        : null,
  );

  final agentFiles = _agentFilesOf(
    root,
    targets: targets,
    agentFileRoots: existing?.agentFileRoots ?? const [],
  );
  final mentions = _staleMentionsOf(
    root,
    set: projectSet,
    targets: existing?.targets ?? [CodeTarget(null, codeRoot: codeRoot)],
    agentFileRoots: existing?.agentFileRoots ?? const [],
    docPaths: docPaths,
    moves: moves,
  );
  final configRewrite = existing == null
      ? null
      : _configRewriteOf(
          config,
          existing,
          pins,
          codeRoot: codeRoot,
          note: codeRootNote,
          agentFileRoots: agentFiles.agentFileRoots,
        );

  final plan = RunPlan(
    header: 'legacy migration: ${root.path} ($legacyContextPath)',
    moves: moves,
    prunes: prunesOf(moves),
    rewrites: [...rewrites.planned, ...rewrites.testFiles, ?configRewrite],
    rewriteLines: [
      for (final rewrite in rewrites.planned)
        if (rewrite.changes.isNotEmpty) _rewriteLineOf(rewrite),
      ?rewrites.labelsLine,
      ?rewrites.testsLine,
      ?formatLayoutLine(rewrites.layoutOnly),
      ?rewrites.stampsLine,
      ?mentionsLine(mentions),
      if (configRewrite != null) _rewriteLineOf(configRewrite),
    ],
    lists: PlanLists(
      formatLayout: [...rewrites.layoutOnly]..sort(compareCodePoints),
      numberLabelsRewritten: rewrites.labelsRewritten,
      numberLabelsLeft: rewrites.labelsLeft,
      agentFiles: agentFiles.paths,
      mentions: mentions,
      tests: rewrites.tests?.json,
    ),
    creates: [
      if (existing == null)
        PlannedCreate(
          path: projectConfigPath,
          text: configText(
            pins,
            codeRoot: codeRoot,
            agentFileRoots: agentFiles.agentFileRoots,
          ),
          note: ': ${_pinList(pins)}$codeRootNote',
        ),
      if (!File.fromUri(root.uri.resolve(specstoneGitignorePath)).existsSync())
        PlannedCreate(path: specstoneGitignorePath, text: _gitignoreText),
      for (final path in overrides.keys.toList()..sort(compareCodePoints))
        PlannedCreate(path: path, text: overrides[path]!),
      ..._draftsOf(projectSet, docPaths, moves, targetNames),
      ...rewrites.records,
    ],
    left: left,
    commit1Message: _commit1Message,
    commit2Message: legacyCommit2Message,
    inputs: inputs,
    agentFiles: agentFiles,
  );
  return plan;
}

/// Returns the mentions in code and agent files that the run's [moves] stop
/// resolving.
///
/// The scan opens no index, so the plan writes nothing; the docs are the ones
/// the plan read, before the moves.
List<StaleMention> _staleMentionsOf(
  Directory root, {
  required MergedSet set,
  required List<CodeTarget> targets,
  required List<String> agentFileRoots,
  required List<String> docPaths,
  required List<PathMove> moves,
}) {
  if (moves.isEmpty) return const [];
  final projectRoot = Directory(root.resolveSymbolicLinksSync());
  return staleMentionsIn(
    MentionScope(
      projectRoot: projectRoot,
      docsRoot: Directory.fromUri(projectRoot.uri.resolve(_docsFolder)),
      set: set,
      targets: targets,
      agentFileRoots: agentFileRoots,
      docs: [
        for (final docPath in docPaths)
          IndexedDoc(
            docPath: docPath,
            name: docPath,
            frontmatter: const {},
            tokens: 0,
          ),
      ],
    ),
    moves,
    namesChange: false,
  );
}

/// Plans the agent files of the legacy run: the full upsert at the root and at
/// each unlisted repository top inside the project root.
///
/// The legacy tree holds no `code:` entry, so the code roots are those of
/// [targets] alone.
AgentWritePlan _agentFilesOf(
  Directory root, {
  required List<CodeTarget> targets,
  required List<String> agentFileRoots,
}) {
  final projectRoot = Directory(root.resolveSymbolicLinksSync());
  return planAgentWrites(
    AgentFileInputs(
      projectRoot: projectRoot,
      cliVersion: specstoneVersion,
      codeRootFolders: [
        for (final target in targets)
          ...codeRootFolders(
            projectRoot,
            codeRoot: target.codeRoot,
            codeEntries: const [],
          ),
      ],
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
/// `stamps:` plan lines, null when the run has nothing to say, and
/// `labelsRewritten` and `labelsLeft` the lists the first counts; `records`
/// are the draft records the run creates, in path order.
typedef _Rewrites = ({
  List<PlannedRewrite> planned,
  List<PlannedRewrite> testFiles,
  List<String> layoutOnly,
  List<PlannedCreate> records,
  String? labelsLine,
  String? testsLine,
  TestNamePass? tests,
  List<String> labelsRewritten,
  List<String> labelsLeft,
  String? stampsLine,
});

/// What the test-name pass reads of a legacy run: the project root, the code
/// targets, and the tops of the other repositories.
typedef _TestNameScope = ({
  Directory root,
  List<CodeTarget> targets,
  List<String> agentFileRoots,
});

/// One markdown doc on its way to commit 2.
final class _Work {
  new(this.legacyPath, String placed, this.kind, this.original)
    : placedPath = placed,
      newPath = placed,
      lf = original.lf;

  final String legacyPath;

  /// The path the legacy moves give the doc, before the first target's folder.
  final String placedPath;

  /// The path the run writes the doc at.
  String newPath;
  final LegacyKind? kind;
  final DocText original;
  String lf;

  /// The text before the approval stamp, the last write of the doc.
  String laidOut = '';

  /// Whether a legacy ID or number label of the doc became a name.
  bool hasNamedLabels = false;

  /// How many legacy IDs and number labels of the doc became a name.
  int labelRewrites = 0;
  final List<String> changes = [];
  String note = '';

  /// The `covers:` entries the run writes for the doc: a topic's legacy
  /// `applies_to:` entries, an architecture doc's Spec map Code paths.
  List<String> citedCovers = const [];

  /// Whether the doc is an API doc renamed to `API.md`, whose fingerprints
  /// need the rewritten FR texts.
  bool get awaitsFingerprints =>
      kind == LegacyKind.api &&
      legacyPath != placedPath &&
      placedPath.endsWith('/API.md');
}

/// Returns the text of every `.md` doc of [docPaths] that is UTF-8, by
/// legacy DocPath in [docPaths] order; any other file moves untouched.
Map<String, DocText> _originalsOf(Directory docsRoot, List<String> docPaths) =>
    {
      for (final docPath in docPaths)
        if (docPath.endsWith('.md'))
          docPath: ?readDocFile(docFileOf(docsRoot, docPath), docPath: docPath),
    };

/// Returns the plan line part naming [inferred], empty when the run cited no
/// code path or inferred none.
String _codeRootNoteOf(CodeRootChoice? inferred) =>
    inferred == null || inferred.cited == 0
    ? ''
    : '; code_root ${inferred.value} '
          '(${inferred.found} of ${inferred.cited} paths)';

/// Returns the string entries of the frontmatter field [field] of [lf].
List<String> _entriesOf(String lf, String field) => [
  for (final (:value, line: _, text: _) in DocLines.of(lf).entriesOf(field))
    if (value is String) value,
];

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
    if (kind == LegacyKind.topic) {
      work.citedCovers = _entriesOf(work.lf, _appliesToField);
    }
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
        work.citedCovers = _entriesOf(work.lf, _coversField);
        work.changes.add(covers.label);
      }
    }
  }

  return (works: works, gnfrSections: gnfrSections);
}

/// Plans the record writes, link rewrites, first fingerprints, and layout of
/// [works].
///
/// A doc left in place gets the link rewrite and the layout. The first
/// fingerprints hash each FR as the run writes it, laid out, so the FR docs
/// are rewritten first. [targetNames] are the config's named targets;
/// [recordSteps] are the carried packs' `move_to_record` steps; [isTaken]
/// tells whether a record's DocPath holds an entry once [moves] ran.
_Rewrites _rewritesOf(
  List<_Work> works, {
  required MergedSet projectSet,
  required List<PathMove> moves,
  required LegacyFeatures features,
  required List<String> targetNames,
  required List<MoveToRecord> recordSteps,
  required bool Function(String path) exists,
  required bool Function(String docPath) isTaken,
  required _TestNameScope? testNames,
}) {
  final matcher = DocTypeMatcher(projectSet, targetNames: targetNames);
  var fingerprintEntries = 0;
  MatchedDocType? matchOf(_Work work) => switch (matcher.match(work.newPath)) {
    final MatchedDocType matched => matched,
    _ => null,
  };
  MergedDocType? typeOf(_Work work) => matchOf(work)?.docType;
  // The stamp is the last write of a doc, so the hash covers its final text
  // (`show_plan_and_apply_on_yes` E07).
  void layOut(_Work work) {
    final type = typeOf(work);
    work.lf = layOutDoc(work.lf, type);
    work.laidOut = work.lf;
    if (type != null) {
      work.lf = withApprovalHash(withKeyBlock(work.lf, 'draft', null), type);
    }
  }

  final tree = _convertLabels(works, typeOf, features);
  final moved = _moveToRecords(
    works,
    matchOf,
    set: projectSet,
    steps: recordSteps,
    firstTarget: twinNamesOf(targetNames).firstOrNull,
    isTaken: isTaken,
  );
  final tests = testNames == null
      ? null
      : _testNamesOf(
          testNames,
          works,
          matchOf,
          tree: tree,
          set: projectSet,
          recordCreates: moved,
          isTaken: isTaken,
        );
  final records = tests?.recordsOver(moved) ?? moved;
  final textOf = {for (final work in works) work.legacyPath: work};
  for (final work in works) {
    if (work.awaitsFingerprints) continue;
    _rewriteRefs(work, moves, exists);
    layOut(work);
  }
  for (final work in works.where((work) => work.awaitsFingerprints)) {
    final fingerprints = writeFirstFingerprints(
      work.lf,
      featureFrs: _featureFrsOf(features, work.placedPath, rewritten: textOf),
    );
    work.lf = fingerprints.lf;
    fingerprintEntries += fingerprints.entries;
    final label = fingerprints.label;
    if (label != null) work.changes.add(label);
    _rewriteRefs(work, moves, exists);
    layOut(work);
  }

  final written = [
    for (final work in works)
      if (work.changes.isNotEmpty || work.lf != work.original.lf) work,
  ];
  final byPath = [...works]
    ..sort((a, b) => compareCodePoints(a.newPath, b.newPath));
  final labelsRewritten = [
    for (final work in byPath)
      if (work.hasNamedLabels) work.newPath,
  ];
  final labelsLeft = _keptLabelsOf(tree, byPath);
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
    testFiles: tests?.fileRewrites ?? const [],
    layoutOnly: [
      for (final work in written)
        if (work.changes.isEmpty &&
            !work.hasNamedLabels &&
            work.laidOut != work.original.lf)
          work.newPath,
    ],
    records: records,
    testsLine: tests?.planLine,
    tests: tests,
    labelsLine: numberLabelsPlanLine(
      rewrites: works.fold(0, (sum, work) => sum + work.labelRewrites),
      files: labelsRewritten.length,
      left: labelsLeft.length,
    ),
    labelsRewritten: labelsRewritten,
    labelsLeft: labelsLeft,
    stampsLine: stampsPlanLine(
      written
          .where(
            (work) =>
                typeOf(work) != null &&
                _approvedBlockOf(work.lf) != _approvedBlockOf(work.original.lf),
          )
          .length,
      fingerprintEntries,
    ),
  );
}

/// The text of the `approved` key block of [lf], empty when it has none; read
/// as text so a frontmatter that is no valid YAML still counts.
String _approvedBlockOf(String lf) => [
  for (final block in Doc.parse(lf).frontmatter ?? const <KeyBlock>[])
    if (block.name == 'approved') block.text,
].join();

/// Moves the status and code paths of each story and FR of [works] into the
/// draft record of its feature (`write_project_files` E14), and returns the
/// records the run creates, in path order.
///
/// It is the upgrade's `move_to_record` step, placed by the same builder, so
/// both paths write the same record. A record the tree already holds gains
/// the entries in its own work. [firstTarget] is the target a record lands
/// in, null for a project with fewer than two targets; [isTaken] is as
/// [RecordMoves.place] reads it. Throws `MigrateFault` `value_unplaced` when a
/// value has no place.
List<PlannedCreate> _moveToRecords(
  List<_Work> works,
  MatchedDocType? Function(_Work work) matchOf, {
  required MergedSet set,
  required List<MoveToRecord> steps,
  required String? firstTarget,
  required bool Function(String docPath) isTaken,
}) {
  final recordType = set.recordDocType;
  if (recordType == null) return const [];
  final matches = [for (final work in works) matchOf(work)];
  final moves = RecordMoves();
  for (final step in steps) {
    for (final (index, work) in works.indexed) {
      final type = matches[index]?.docType;
      if (type == null || !step.touches(type.id)) continue;
      final taken = moves.take(
        docPath: work.legacyPath,
        plannedPath: work.newPath,
        type: type,
        step: step,
        lf: work.lf,
      );
      if (taken == work.lf) continue;
      work.changes.add('${_keysLost(work.lf, taken)} $_toRecord');
      work.lf = taken;
    }
  }
  final placement = moves.place(
    set: set,
    recordType: recordType,
    firstTarget: firstTarget,
    isTaken: isTaken,
    docs: [
      for (final (index, work) in works.indexed)
        (
          plannedPath: work.newPath,
          type: matches[index]?.docType,
          target: matches[index]?.target,
          lf: work.lf,
        ),
    ],
  );
  throwFaultsPerDoc(placement.unplaced);
  for (final work in works) {
    final edited = placement.edits[work.newPath];
    if (edited == null) continue;
    work.lf = edited;
    work.changes.add(_recordEdit);
  }
  return recordCreatesOf(placement);
}

/// Plans the test-name pass over [works] as the label conversion and the
/// record moves left them, and writes the lines it adds into the records of
/// the tree; [recordCreates] are the records the run already creates.
///
/// A name's label resolves through [tree], from no doc, so a partial label
/// names nothing.
TestNamePass _testNamesOf(
  _TestNameScope scope,
  List<_Work> works,
  MatchedDocType? Function(_Work work) matchOf, {
  required LabelTree tree,
  required MergedSet set,
  required List<PlannedCreate> recordCreates,
  required bool Function(String docPath) isTaken,
}) {
  final pass = TestNamePass.plan(
    root: scope.root,
    set: set,
    targets: scope.targets,
    agentFileRoots: scope.agentFileRoots,
    docs: [
      for (final work in works)
        (
          plannedPath: work.newPath,
          type: matchOf(work)?.docType,
          target: matchOf(work)?.target,
          lf: work.lf,
        ),
    ],
    resolveLabel: (label) => tree.resolve(label, citingDocPath: ''),
    isTaken: isTaken,
    pendingCreates: recordCreates,
  );
  for (final work in works) {
    final edited = pass.recordEdits[work.newPath];
    if (edited == null) continue;
    work.lf = edited;
    work.changes.add(_testsEdit);
  }
  return pass;
}

/// Returns the `move_to_record` steps of the carried packs' migrations, the
/// ones the upgrade runs, so both runs move one field set.
List<MoveToRecord> _recordStepsOf(Map<String, PackManifest> manifests) => [
  for (final manifest in manifests.values)
    for (final migration in manifest.migrations)
      ...migration.steps.whereType<MoveToRecord>(),
];

/// Returns the frontmatter keys of [before] that [after] no longer holds,
/// joined in file order.
String _keysLost(String before, String after) {
  Set<String> keysOf(String lf) => {
    for (final block in Doc.parse(lf).frontmatter ?? const <KeyBlock>[])
      block.name,
  };
  final kept = keysOf(after);
  return [
    for (final key in keysOf(before))
      if (!kept.contains(key)) key,
  ].join(', ');
}

/// Converts the legacy IDs and number labels of [works] that name one moved
/// doc to its name (`rewrite_titles_keys_and_links` E18, E19), and moves the
/// anchors of links to a heading whose slug a conversion changed.
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
  final before = [
    for (final work in works) (docPath: work.legacyPath, lf: work.lf),
  ];
  final conversions = {
    for (final work in works)
      work.legacyPath: convertLegacyLabels(
        tree,
        legacyPath: work.legacyPath,
        lf: work.lf,
      ),
  };
  final texts = withLabelAnchorsMoved(
    before,
    {for (final MapEntry(:key, :value) in conversions.entries) key: value.lf},
    {for (final work in works) work.legacyPath: ?typeOf(work)},
  );
  for (final work in works) {
    work.labelRewrites = conversions[work.legacyPath]!.rewrites;
    final text = texts[work.legacyPath];
    if (text == null) continue;
    work
      ..hasNamedLabels = true
      ..lf = text;
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

/// Returns the config rewrite that sets the carried [pins] and the [codeRoot]
/// and keeps every other pin and the `targets:` map of the [existing] config,
/// or null when the text stays.
///
/// [codeRoot] is the config's own value, or the one inferred for a config with
/// no key; a config that holds the key keeps its line, `.` included, and one
/// that holds `targets:` has no such line. [note] ends the plan line.
/// [agentFileRoots] is the full list the run leaves in the config.
PlannedRewrite? _configRewriteOf(
  File config,
  ProjectConfig existing,
  Map<String, PackVersion> pins, {
  required String codeRoot,
  required String note,
  required List<String> agentFileRoots,
}) {
  final targets = [
    for (final target in existing.targets)
      if (target.name != null) target,
  ];
  final text = configText(
    {...existing.pins, ...pins},
    codeRoot: targets.isEmpty ? codeRoot : '.',
    keepCodeRootKey: existing.hasCodeRoot,
    targets: targets,
    agentFileRoots: agentFileRoots,
  );
  final current = utf8.decode(readPlanInput(config));
  if (text == current) return null;
  return PlannedRewrite(
    path: projectConfigPath,
    text: text,
    before: textHashOf(current),
    changes: ['pins'],
    note: note,
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

/// Returns the renames and the files left in place once [treeMoves] are
/// folded into [placed]: a doc the legacy moves place lands in the first
/// target's folder, and a doc they keep or leave moves there from its own
/// path.
///
/// Throws `legacy_collision` when a folded move lands on another doc;
/// [docPaths] are every file the run reads.
({List<PathMove> moves, List<String> left}) _inFirstTarget(
  LegacyMoves placed,
  List<PathMove> treeMoves, {
  required List<String> docPaths,
}) {
  if (treeMoves.isEmpty) return (moves: placed.moves, left: placed.left);
  final landing = {for (final move in treeMoves) move.from: move.to};
  final placedAt = {for (final move in placed.moves) move.to};
  final moves = [
    for (final move in placed.moves)
      (from: move.from, to: landing[move.to] ?? move.to),
    for (final move in treeMoves)
      if (!placedAt.contains(move.from)) move,
  ];
  refuseCollisions(docPaths, moves);
  return (
    moves: orderedMoves(moves, keyOf: caseBlindPath),
    left: [
      for (final path in placed.left)
        if (!landing.containsKey(path)) path,
    ],
  );
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
///
/// With two or more [targetNames] a per-target doc type's path is read in the
/// first target's folder.
List<PlannedCreate> _draftsOf(
  MergedSet set,
  List<String> docPaths,
  List<PathMove> moves,
  List<String> targetNames,
) {
  final moved = {for (final move in moves) move.from: move.to};
  final present = {for (final path in docPaths) moved[path] ?? path};
  return [
    for (final docType in singularDocTypes(set))
      if (_draftPathOf(docType, targetNames) case final path?
          when !present.contains(path))
        PlannedCreate(
          path: '$_docsFolder$path',
          text: skeletonOf(docType, docType.id),
          note: draftNote,
        ),
  ];
}

String? _draftPathOf(MergedDocType docType, List<String> targetNames) {
  final path = docType.path;
  final first = twinNamesOf(targetNames).firstOrNull;
  if (path == null || !docType.isPerTarget || first == null) return path;
  return PathPattern(path).forTarget(first).source;
}

String _pinList(Map<String, PackVersion> pins) => [
  for (final name in pins.keys.toList()..sort(compareCodePoints))
    '$name ${pins[name]}',
].join(', ');
