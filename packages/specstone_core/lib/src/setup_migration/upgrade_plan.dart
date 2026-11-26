import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_anchors.dart'
    show anchorsOfBody;
import 'package:specstone_core/src/doc_model/doc_splice.dart' show withKeyBlock;
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/doc_model/path_pattern.dart';
import 'package:specstone_core/src/doc_model/records_root.dart';
import 'package:specstone_core/src/document_writing/models/path_move.dart';
import 'package:specstone_core/src/document_writing/rewrite_refs.dart'
    show rebaseDocLinks;
import 'package:specstone_core/src/document_writing/set_doc.dart'
    show markDraft;
import 'package:specstone_core/src/document_writing/stale_mentions.dart'
    show MentionScope, StaleMention, staleMentionsIn;
import 'package:specstone_core/src/index_query/doc_index.dart' show DocIndex;
import 'package:specstone_core/src/index_query/index_store.dart'
    show IndexStore;
import 'package:specstone_core/src/index_query/indexed_doc.dart'
    show IndexedDoc, docNameOf;
import 'package:specstone_core/src/index_query/read_session.dart'
    show ReadSession;
import 'package:specstone_core/src/plan_hash.dart';
import 'package:specstone_core/src/release_version.dart' show ReleaseVersion;
import 'package:specstone_core/src/rendering/doc_reader.dart'
    show DocRead, ReadableDoc, readDoc;
import 'package:specstone_core/src/rendering/doc_tree.dart'
    show collectDocEntries;
import 'package:specstone_core/src/rendering/docs_project.dart'
    show DocsProject, Target;
import 'package:specstone_core/src/rendering/format_run.dart'
    show FileResult, planFormatWrites;
import 'package:specstone_core/src/rendering/formatter.dart'
    show headerKey, layOutDoc;
import 'package:specstone_core/src/rendering/generated_blocks.dart'
    show GeneratorRegistry, fillGeneratedBlocks;
import 'package:specstone_core/src/rendering/models/line_ending.dart';
import 'package:specstone_core/src/setup_migration/agent_targets.dart';
import 'package:specstone_core/src/setup_migration/bullet_lines_step.dart';
import 'package:specstone_core/src/setup_migration/dangling_overrides.dart';
import 'package:specstone_core/src/setup_migration/doc_file_text.dart';
import 'package:specstone_core/src/setup_migration/drop_section_step.dart';
import 'package:specstone_core/src/setup_migration/followed_links.dart';
import 'package:specstone_core/src/setup_migration/heading_ledger.dart';
import 'package:specstone_core/src/setup_migration/mark_retrim_step.dart';
import 'package:specstone_core/src/setup_migration/matrix_fold_pass.dart';
import 'package:specstone_core/src/setup_migration/merge_doc_step.dart';
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/setup_migration/migration_chain.dart';
import 'package:specstone_core/src/setup_migration/models/doc_text.dart';
import 'package:specstone_core/src/setup_migration/models/pack_step.dart';
import 'package:specstone_core/src/setup_migration/models/stamp_doc.dart';
import 'package:specstone_core/src/setup_migration/move_rewrites.dart';
import 'package:specstone_core/src/setup_migration/path_moves.dart';
import 'package:specstone_core/src/setup_migration/project_files.dart';
import 'package:specstone_core/src/setup_migration/relink_links.dart';
import 'package:specstone_core/src/setup_migration/run_plan.dart';
import 'package:specstone_core/src/setup_migration/stamp_pass.dart';
import 'package:specstone_core/src/setup_migration/tree_move.dart';
import 'package:specstone_core/src/setup_migration/type_before_steps.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/code_target.dart' show twinNamesOf;
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/layer_source.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/models/migration_step.dart';
import 'package:specstone_core/src/templates/models/pattern_move.dart';
import 'package:specstone_core/src/templates/nested_paths.dart'
    show movePatternsAtEveryDepth;
import 'package:specstone_core/src/templates/project_config.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:specstone_core/src/version.dart';
import 'package:yaml/yaml.dart';

export 'package:specstone_core/src/setup_migration/run_plan.dart'
    show UpgradeStepLine;

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
const _treeMoveCommit2Message = 'point links at the moved spec docs';
const _agentFileRootsKey = 'agent_file_roots';
const _agentFilesVersionKey = 'agent_files_version';
const _layersKeptPrefix = 'layers kept: ';
const _draftChange = 'draft flag';
const _stampChange = 'stamp approvals';
const _matrixRowsChange = 'fold matrix rows';

/// Plans the pack upgrade of the project at [root].
///
/// Selects every pinned pack's steps, refuses an override the new versions
/// leave dangling, then plans the tree move under the first code target when
/// two or more are listed, the pack's moves, the section and field renames in
/// the docs and the overrides, the link and path mention rewrites, each typed
/// doc laid out as `format` lays it out, the agent files step, and the new
/// pins. With every pin equal the plan holds the layout pass, the agent files
/// step, and the tree move alone. Writes nothing. Throws `MigrateFault`
/// `override_dangling`, `MigrateFault` `upgrade_collision` listing every move
/// and rename collision at once, or else every create onto a taken path
/// ([RunPlan.refuseTakenCreates]), `agent_block_malformed`, and a
/// `TemplateFault` before it returns, so a refused run prints nothing. The
/// agent files step refreshes what exists; an unlisted top still takes the
/// full upsert once.
/// [homeDirectory] is the personal pack home, or null. The plan's `inputs` hold
/// every file it read.
///
/// A `regenerate` step runs the [generators] it lists through the format write
/// at the version the run moves the pins to, so a pin below its carried
/// version plans. Each doc it changes takes its blocks on its text after the
/// earlier steps, at its path on disk, so a doc a `move_file` step of the same
/// run moves keeps its blocks until the next `format`. The generators read an
/// in-memory index of the docs as they stand on disk, so the plan writes no
/// index file, and a catalog cell lags a doc an earlier step of the same run
/// reshapes. A group doc the step creates or deletes joins the run's creates
/// or trashed docs. A doc the write cannot lay out, whether a features doc, a
/// group doc, or a companion path no doc holds, stays as it was with its whole
/// group, and the plan's [RunPlan.warnings] name the doc and why; the run goes
/// on and the pins move. Throws a `StateError` when a `regenerate` step names a
/// kind [generators] lacks.
///
/// [regenerationIndex] holds that index across plans: a run that shows a plan
/// and plans again before it applies passes one, so it builds the index once,
/// and closes it. With none, the plan builds its own and closes it. A reused
/// index describes the docs as the first plan read them; a doc edited since
/// changes the plan's inputs, which the second plan refuses.
///
/// Each of [addedPacks], sorted with no repeat, joins the pins at the version
/// its pack carries: the `packs:` form is checked first, then the merged set
/// with the added packs loads, so a refused add prints nothing. Throws a
/// `TemplateFault` `unknown_value` at `packs` for a form the add cannot write.
RunPlan planUpgradeRun(
  Directory root, {
  required TemplateResolver templates,
  required Directory? homeDirectory,
  required GeneratorRegistry<DocIndex> generators,
  List<String> addedPacks = const [],
  RegenerationIndex? regenerationIndex,
}) {
  final inputs = PlanInputs(root);
  final index = regenerationIndex ?? RegenerationIndex();
  try {
    return inputs.collect(
      () => _upgradeRunOf(
        root,
        templates: templates,
        homeDirectory: homeDirectory,
        addedPacks: addedPacks,
        generators: generators,
        regenerationIndex: index,
        inputs: inputs,
      ),
    )..refuseTakenCreates(root);
  } finally {
    if (regenerationIndex == null) index.close();
  }
}

/// Plans the upgrade of [root] while [inputs] records each file read.
///
/// A `regenerate` step reads its generators' index through [regenerationIndex],
/// which the caller closes.
RunPlan _upgradeRunOf(
  Directory root, {
  required TemplateResolver templates,
  required Directory? homeDirectory,
  required List<String> addedPacks,
  required GeneratorRegistry<DocIndex> generators,
  required RegenerationIndex regenerationIndex,
  required PlanInputs inputs,
}) {
  final config = ProjectConfig.read(root);
  final pins = config.pins;
  if (addedPacks.isNotEmpty) _requirePacksWritable(root);
  final addedManifests = templates.availableManifests(
    addedPacks,
    homeDirectory: homeDirectory,
  );
  final addedPins = [
    for (final MapEntry(:key, :value) in addedManifests.entries)
      AddedPin(pack: key, version: value.version),
  ];
  final packNames = [...pins.keys, for (final pin in addedPins) pin.pack];
  final available = templates.availableManifests(
    pins.keys,
    homeDirectory: homeDirectory,
  );
  final upgrades = selectUpgrades(pins, available);
  final targetSet = templates.resolveCarried(
    packNames: packNames,
    homeDirectory: homeDirectory,
  );
  final overrides = loadProjectTemplates(
    root,
    skippedIds: {
      ...targetSet.foldedDocTypes.keys,
      ...targetSet.droppedDocTypes,
    },
  );
  final projectSharedLines = loadProjectSharedLines(root);
  refuseDanglingOverrides(
    overrides,
    target: targetSet,
    targetVersions: {
      for (final entry in available.entries) entry.key: entry.value.version,
      for (final pin in addedPins) pin.pack: pin.version,
    },
    upgrades: upgrades,
    sharedLines: projectSharedLines,
  );

  final steps = [for (final upgrade in upgrades) ...upgrade.steps];
  final stepKinds = [for (final entry in steps) entry.step];
  final overrideFiles = _renamedOverrides(root, overrides, steps);
  final projectLayers = parseOverrides({
    for (final file in overrideFiles) file.path: file.lf,
  });
  final finalSet = templates.resolveCarried(
    packNames: packNames,
    homeDirectory: homeDirectory,
    projectLayers: projectLayers,
    projectSharedLines: projectSharedLines,
  );

  final docsRoot = Directory.fromUri(root.uri.resolve(_docsFolder));
  final docPaths = docPathsOf(docsRoot, root)..sort(compareCodePoints);
  // With two or more code targets the per-target docs sit in a target folder,
  // the first target's for a doc the run moves or creates.
  final firstTarget = twinNamesOf(config.targetNames).firstOrNull;
  final treeMoves = treeMovesOf(
    docPaths,
    finalSet,
    targetNames: config.targetNames,
    olderPatterns: [
      for (final PackStep(:step) in steps)
        if (step is MoveFile && _isPerTargetStep(step, finalSet, firstTarget))
          for (final pair in _movePatternsOf(step, finalSet)) pair.from,
    ],
  );
  final _PlannedPaths(:planned, :movedAt, :movedBy, :treeMoved) = _plannedPaths(
    docPaths,
    steps,
    treeMoves: treeMoves,
    set: finalSet,
    targetNames: config.targetNames,
  );
  final moveCollisions = _moveCollisions(
    docPaths,
    planned: planned,
    movedBy: movedBy,
    treeMoved: treeMoved,
    steps: steps,
    firstTarget: firstTarget,
  );
  final moves = orderedMoves([
    for (final path in docPaths)
      if (planned[path] != path) PathMove(from: path, to: planned[path]!),
  ]);

  final matcher = DocTypeMatcher(finalSet, targetNames: config.targetNames);
  // Without the adds, a doc the matcher leaves untyped and `matcher` types is
  // one the added packs newly type.
  final withoutAdds = addedPins.isEmpty
      ? null
      : DocTypeMatcher(
          _setWithoutAdds(
            templates,
            pins.keys,
            homeDirectory: homeDirectory,
            projectLayers: projectLayers,
          ),
          targetNames: config.targetNames,
        );
  final typedByAdd = <String>[];
  final works = <_DocWork>[];
  final changedAt = <int, List<String>>{};
  final linkLines = <String>[];
  // Each doc's text after its steps, before the run's link rewrites.
  final steppedTexts = <String, String>{};
  final renameCollisions = <MigrateFault>[];
  final originals = {
    for (final path in docPaths)
      path: DocFileText.readFile(
        fileOfDocPath(path, docsRoot: docsRoot, projectRoot: root),
        docPath: path,
      ),
  };
  final folds = _foldsOf(
    root,
    steps,
    docPaths: docPaths,
    originals: originals,
    planned: planned,
    set: finalSet,
    twinNames: twinNamesOf(config.targetNames),
  );
  renameCollisions.addAll(folds.collisions);
  final keptLayers = _keptLayersOf(root, stepKinds);
  // Each `regenerate` step's write, planned once the docs can be stepped.
  final regenerations = <int, _Regeneration>{};
  // The warnings of those writes, each once.
  final regenerationWarnings = <String>{};
  // Whether `stepped` reads a doc only, recording no change, ledger entry, or
  // collision.
  var isProbing = false;
  // A from doc an earlier step of the fold's pack names takes that pack's
  // steps before its fold, typed by its frozen doc type, and the fold merges
  // that stepped text.
  final frozenFromDocs = folds.fromPaths.isEmpty
      ? const <String, _FrozenFromDoc>{}
      : _frozenFromDocsOf(
          upgrades,
          folds,
          frozen: templates.frozenDocTypes(
            packNames: packNames,
            homeDirectory: homeDirectory,
          ),
          matcher: matcher,
        );
  final steppedTextByDocPath = <String, String>{};
  final ledger = HeadingLedger();
  void refuse(MigrateFault fault) {
    if (!isProbing) renameCollisions.add(fault);
  }

  String foldInto(
    int index,
    MergeDoc step, {
    required String path,
    required String plannedPath,
    required MergedDocType docType,
    required String lf,
  }) {
    var text = lf;
    for (final source in folds.byStep[index] ?? const <FoldSource>[]) {
      if (source.toPath != plannedPath) continue;
      final fromLf = _rebased(
        steppedTextByDocPath[source.fromPath] ?? originals[source.fromPath]!.lf,
        source.fromPath,
        path,
      );
      final merged = mergeDocInto(
        toLf: text,
        fromLf: fromLf,
        step: step,
        toHeaders: _headersOf(docType),
      );
      if (_heldHeader(text, merged.movedHeaders) case final header?) {
        refuse(_foldCollision(step, source, header: header, file: path));
        return lf;
      }
      if (merged.isLeadUnplaced) {
        refuse(_leadFault(step, source, file: path));
        return lf;
      }
      if (merged.unmergedFields.isNotEmpty) {
        refuse(_unmergedFault(step, source, merged.unmergedFields, file: path));
        return lf;
      }
      if (!isProbing) {
        ledger.folded(
          fromPath: planned[source.fromPath] ?? source.fromPath,
          fromLf: fromLf,
          toPath: plannedPath,
          toBefore: text,
          toAfter: merged.text,
          groups: merged.sectionGroups,
        );
      }
      text = merged.text;
    }
    return text;
  }

  /// Returns [text], the doc at [path] planned at [plannedPath], with each step
  /// from [firstStep] up to [endStep] that touches [docType] applied, adding
  /// each change to [changes] and each refused rename to `renameCollisions`
  /// unless `isProbing`.
  String stepped(
    String text, {
    required String path,
    required String plannedPath,
    required MergedDocType docType,
    required int firstStep,
    required int endStep,
    required List<String> changes,
  }) {
    var lf = text;
    for (final (index, PackStep(:step)) in steps.indexed) {
      if (index < firstStep || index >= endStep) continue;
      // A `regenerate` step reaches no doc type; its write names the docs.
      if (step is! Regenerate && !step.touches(docType.id)) continue;
      final renamed = switch (step) {
        RenameSection() => MoveRewrites.headerRenamed(
          lf,
          step.fromHeader,
          step.toHeader,
        ),
        RenameField() => _withKeyRenamed(lf, step.from, step.to),
        MoveFile() => lf,
        RelinkMergedDocs() => lf,
        DropSharedLines() => lf,
        BulletLines() => switch (docType.sections
            .where((section) => section.id == step.section)
            .firstOrNull) {
          final section? => withLinesBulleted(
            lf,
            header: section.header,
            prefixes: step.prefixes,
          ),
          null => lf,
        },
        MarkRetrim() => withRetrimMarked(
          lf,
          docType: docType,
          sections: step.sections,
        ),
        DropSection() when keepsDroppedSection(docType, step) => lf,
        DropSection() => withSectionDropped(lf, header: step.sectionHeader),
        MergeDoc() => foldInto(
          index,
          step,
          path: path,
          plannedPath: plannedPath,
          docType: docType,
          lf: lf,
        ),
        DropDocType() => lf,
        Regenerate() =>
          regenerations[index]?.fill(lf, path: path, docType: docType) ?? lf,
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
          RelinkMergedDocs() => false,
          DropSharedLines() => false,
          BulletLines() => false,
          MarkRetrim() => false,
          DropSection() => false,
          MergeDoc() => false,
          DropDocType() => false,
          Regenerate() => false,
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
            RelinkMergedDocs() => '',
            DropSharedLines() => '',
            BulletLines() => '',
            MarkRetrim() => '',
            DropSection() => '',
            MergeDoc() => '',
            DropDocType() => '',
            Regenerate() => '',
          };
          refuse(
            MigrateFault(
              MigrateFaultCode.upgradeCollision,
              message,
              file: path,
            ),
          );
          continue;
        }
        if (!isProbing) {
          if (step is RenameSection) {
            ledger.renamed(plannedPath, before: lf, after: renamed);
          } else if (step is DropSection) {
            ledger.dropped(
              plannedPath,
              before: lf,
              after: renamed,
              header: step.sectionHeader,
            );
          }
          (changedAt[index] ??= []).add(plannedPath);
        }
        lf = renamed;
        changes.add(_describe(step));
      }
    }
    return lf;
  }

  for (final MapEntry(key: path, value: doc) in frozenFromDocs.entries) {
    steppedTextByDocPath[path] = stepped(
      originals[path]!.lf,
      path: path,
      plannedPath: planned[path]!,
      docType: doc.match.docType,
      firstStep: doc.packStart,
      endStep: doc.foldIndex,
      changes: <String>[],
    );
  }

  // A `regenerate` step plans its write over each doc as the steps before it
  // leave it, read through `stepped` with no change recorded.
  final planner = _RegenerationPlanner(
    root: root,
    homeDirectory: homeDirectory,
    set: finalSet,
    generators: generators,
    index: regenerationIndex,
  );
  for (final (index, PackStep(:step)) in steps.indexed) {
    if (step is! Regenerate) continue;
    isProbing = true;
    final texts = {
      for (final path in docPaths)
        if (originals[path] case final original?)
          path: switch (matcher.match(planned[path]!)) {
            MatchedDocType(:final docType) => stepped(
              original.lf,
              path: path,
              plannedPath: planned[path]!,
              docType: docType,
              firstStep: 0,
              endStep: index,
              changes: <String>[],
            ),
            _ => original.lf,
          },
    };
    isProbing = false;
    final regeneration = planner.plan(step, texts);
    regenerationWarnings.addAll(regeneration.warnings);
    regenerations[index] = regeneration;
    (changedAt[index] ??= []).addAll([
      ...regeneration.creates.keys,
      for (final path in regeneration.deletes) planned[path] ?? path,
    ]);
  }
  final regeneratedAway = {
    for (final regeneration in regenerations.values) ...regeneration.deletes,
  };

  // A `to` doc the project lacks is a draft the merge steps create; it takes
  // the steps from its first merge on, as a doc the project holds does.
  final createdAt = _createdAtOf(
    steps,
    folds,
    held: {for (final path in docPaths) planned[path]!},
    set: finalSet,
  );
  final docs = [
    for (final path in docPaths)
      (path: path, original: originals[path], firstStep: 0),
    for (final MapEntry(:key, :value) in createdAt.entries)
      (path: key, original: _absentDoc, firstStep: value),
  ];
  for (final (:path, :original, :firstStep) in docs) {
    final isCreate = original == _absentDoc;
    final plannedPath = isCreate ? path : planned[path]!;
    if (original == null ||
        folds.fromPaths.contains(plannedPath) ||
        regeneratedAway.contains(path)) {
      continue;
    }
    final match = matcher.match(plannedPath);
    final docType = match is MatchedDocType ? match.docType : null;
    final target = match is MatchedDocType ? match.target : null;
    var lf = original.lf;
    final changes = <String>[];
    if (!isCreate &&
        docType != null &&
        withoutAdds != null &&
        withoutAdds.match(plannedPath) is! MatchedDocType) {
      typedByAdd.add(plannedPath);
      lf = markDraft(lf, docType);
      changes.add(_draftChange);
    }
    if (docType != null) {
      lf = stepped(
        lf,
        path: path,
        plannedPath: plannedPath,
        docType: docType,
        firstStep: firstStep,
        endStep: steps.length,
        changes: changes,
      );
    }
    steppedTexts[plannedPath] = lf;
    if (moves.isNotEmpty) {
      bool exists(String docPath) => _existsIn(docsRoot, root, docPath);
      // A mention rewrite is no link rewrite: the stamp pass reads the text
      // before the link rewrites with its mentions already moved.
      steppedTexts[plannedPath] = MoveRewrites.mentions(
        lf,
        docPath: path,
        moves: moves,
        exists: exists,
      ).lf;
      final links = MoveRewrites.links(lf, docPath: path, moves: moves);
      final mentions = MoveRewrites.mentions(
        links.lf,
        docPath: path,
        moves: moves,
        exists: exists,
      );
      lf = mentions.lf;
      final labels = [?links.label, ?mentions.label];
      if (labels.isNotEmpty) {
        changes.addAll(labels);
        linkLines.add('$plannedPath: ${labels.join(', ')}');
      }
    }
    works.add(
      _DocWork(
        plannedPath,
        original,
        docType,
        target,
        lf,
        changes,
        isCreate: isCreate,
      ),
    );
  }
  // A heading's final anchor is known only once every doc took its steps.
  final anchors = ledger.resolve({
    for (final work in works) work.plannedPath: work.lf,
  });
  final linkChanges = <String, Set<LinkChange>>{};
  if (!anchors.isEmpty || !folds.docs.isEmpty) {
    for (final work in works) {
      final followed = followLinks(
        work.lf,
        work.plannedPath,
        anchors: anchors,
        folds: folds.docs,
      );
      if (followed.lf == work.lf) continue;
      work.lf = followed.lf;
      _addLinkChanges(work, followed.changes, linkChanges);
    }
  }
  // The relink pass reads every doc as the run's own link pass leaves it, so
  // a link that pass set right is no broken link here.
  for (final (index, PackStep(:relinkRules)) in steps.indexed) {
    if (relinkRules == null || relinkRules.isEmpty) continue;
    final targets = _relinkTargetsOf(works);
    for (final work in works) {
      final relinked = relinkLinks(
        work.lf,
        work.plannedPath,
        rules: relinkRules,
        targets: targets,
      );
      if (relinked.lf == work.lf) continue;
      work.lf = relinked.lf;
      _addLinkChanges(work, relinked.changes, linkChanges);
      (changedAt[index] ??= []).add(work.plannedPath);
    }
  }
  for (final work in works) {
    if (linkChanges[work.plannedPath] case final changes?) {
      final labels = [
        for (final change in LinkChange.values)
          if (changes.contains(change)) change.label,
      ];
      linkLines.add('${work.plannedPath}: ${labels.join(', ')}');
    }
  }
  // The stamp pass tells a block the link rewrites alone changed by its text
  // before them.
  final linkedFrom = {
    for (final work in works)
      if (steppedTexts[work.plannedPath] case final text? when text != work.lf)
        work.plannedPath: text,
  };
  _throwFaultsPerDoc([...moveCollisions, ...renameCollisions]);

  final agentInputs = _agentInputsOf(root, config, set: finalSet);
  final agentFiles = planAgentWrites(agentInputs, full: false);
  final matrixFold = MatrixFoldPass.plan(config.matrixMode, finalSet, [
    for (final work in works)
      MatrixFoldDoc(
        plannedPath: work.plannedPath,
        type: work.docType,
        target: work.target,
        lf: work.lf,
      ),
  ]);
  final recorded = <String>[];
  for (final work in works) {
    var text = work.lf;
    if (matrixFold?.recordEdits[work.plannedPath] case final edited?) {
      text = edited;
      work.changes.add(_matrixRowsChange);
    }
    recorded.add(text);
  }
  final laidOutPaths = <String>[];
  final laidOut = <String>[];
  for (final (index, work) in works.indexed) {
    final lf = layOutDoc(recorded[index], work.docType);
    if (lf != recorded[index]) laidOutPaths.add(work.plannedPath);
    laidOut.add(lf);
  }
  final stamps = StampPass.plan(
    [
      for (final work in works)
        if (!work.isCreate)
          StampDoc(
            docPath: work.plannedPath,
            lf: work.original.lf,
            type: switch (work.docType) {
              final type? => typeBeforeSteps(
                type,
                stepKinds,
                lf: work.original.lf,
              ),
              null => null,
            },
            target: work.target,
          ),
    ],
    [
      for (final (index, work) in works.indexed)
        StampDoc(
          docPath: work.plannedPath,
          lf: laidOut[index],
          type: work.docType,
          target: work.target,
        ),
    ],
    typedByAdd: typedByAdd.toSet(),
    linkedFrom: linkedFrom,
  );
  final docRewrites = <PlannedRewrite>[];
  final mergeCreates = <PlannedCreate>[];
  final writtenLf = <String, String>{};
  for (final (index, work) in works.indexed) {
    final lf = stamps.apply(work.plannedPath, laidOut[index]);
    writtenLf[work.plannedPath] = lf;
    if (lf != laidOut[index]) work.changes.add(_stampChange);
    if (lf == work.original.lf) continue;
    if (work.isCreate) {
      mergeCreates.add(
        PlannedCreate(
          path: projectPathOfDocPath(work.plannedPath),
          text: lf,
          note: draftNote,
        ),
      );
      continue;
    }
    docRewrites.add(
      PlannedRewrite(
        path: projectPathOfDocPath(work.plannedPath),
        text: DocFileText.written(work.original, lf),
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
          text: DocFileText.written(file.original, file.lf),
          before: file.original.hash,
          changes: [
            for (final index in file.changedBy) _describe(steps[index].step),
          ],
        ),
  ];
  final configRewrite = _configRewriteOf(
    root,
    upgrades,
    addedPins: addedPins,
    agentFileRoots: agentFiles.addedRoots.isEmpty
        ? null
        : agentFiles.agentFileRoots,
    agentFilesVersion: _stampOf(
      agentInputs,
      agentFiles,
      config,
      isConfigWritten:
          upgrades.isNotEmpty || addedPins.isNotEmpty || !agentFiles.isEmpty,
    ),
  );

  List<String> pathsAt(int index) {
    final docs = (steps[index].step is MoveFile ? movedAt : changedAt)[index];
    return _sortedPaths(
      docs: docs ?? const [],
      overrides: [
        for (final file in overrideFiles)
          if (file.changedBy.contains(index)) file.path,
      ],
    );
  }

  final lastKeepIndex = stepKinds.lastIndexWhere(
    (step) => step is MergeDoc || step is DropDocType,
  );
  final stepLines = [
    for (final (index, PackStep(:from, :step)) in steps.indexed)
      if (index == lastKeepIndex && keptLayers.isNotEmpty)
        UpgradeStepLine(
          from: '$from',
          step: _describe(step),
          paths: pathsAt(index),
          nextLine: '$_layersKeptPrefix${keptLayers.length}',
        )
      else
        UpgradeStepLine(
          from: '$from',
          step: _describe(step),
          paths: pathsAt(index),
        ),
  ];
  final upgraded = [
    for (final upgrade in upgrades)
      '${upgrade.pack} ${upgrade.pin} -> ${upgrade.target}',
  ];
  final pinned = [
    for (final upgrade in upgrades) '${upgrade.pack} ${upgrade.target}',
  ];
  final added = [
    for (final pin in addedPins) '${pin.pack} ${pin.version} (added)',
  ];

  final mentions = _staleMentionsOf(
    root,
    config,
    set: finalSet,
    docPaths: docPaths,
    moves: moves,
  );
  final arePinsUnchanged = upgrades.isEmpty && addedPins.isEmpty;
  final treeMovesTo = treeMoves.isEmpty ? null : firstTarget;
  final headerParts = [
    ...added,
    ...upgraded,
    if (treeMovesTo != null) 'spec tree to $treeMovesTo',
  ];
  final _PlanTitles(:header, :commit2Message) = arePinsUnchanged
      ? _pinsUnchangedTitles(
          laysOut: laidOutPaths.isNotEmpty,
          writesAgentFiles: !agentFiles.isEmpty,
          treeMovesTo: treeMovesTo,
        )
      : _PlanTitles(
          header: 'pack upgrade: ${headerParts.join(', ')}',
          commit2Message: _commit2Message,
        );
  final plan = RunPlan(
    header: header,
    moves: moves,
    prunes: PathMoves.prunesOf(moves),
    rewrites: [...docRewrites, ...overrideRewrites, ?configRewrite],
    creates: [
      ...[
        ...mergeCreates,
        for (final regeneration in regenerations.values)
          for (final MapEntry(:key, :value) in regeneration.creates.entries)
            PlannedCreate(path: projectPathOfDocPath(key), text: value),
      ]..sort((a, b) => compareCodePoints(a.path, b.path)),
    ],
    left: const [],
    commit1Message: _commit1Message,
    commit2Message: commit2Message,
    inputs: inputs,
    rewriteLines: [
      for (final line in stepLines) ...[line.text, ?line.nextLine],
      ...linkLines,
      ?matrixFold?.planLine,
      ?typedByAddLine(typedByAdd),
      ?formatLayoutLine(laidOutPaths),
      ?stamps.planLine,
      if (agentFiles.line.isNotEmpty) agentFiles.line,
      ?mentionsLine(mentions),
      for (final line in added) '$projectConfigPath: $line',
      if (upgrades.isNotEmpty) '$projectConfigPath: ${pinned.join(', ')}',
    ],
    agentFiles: agentFiles,
    trashedDocs: [
      for (final path in {
        ...folds.fromPaths,
        ...regeneratedAway,
      }.toList()..sort(compareCodePoints))
        projectPathOfDocPath(planned[path] ?? path),
    ],
    warnings: [...regenerationWarnings],
    lists: PlanLists(
      formatLayout: [...laidOutPaths]..sort(compareCodePoints),
      agentFiles: agentFiles.listed,
      stampsSkipped: stamps.paths,
      steps: stepLines,
      mentions: mentions,
      addedPins: addedPins,
      typedByAdd: [...typedByAdd]..sort(compareCodePoints),
      matrixRows: matrixFold?.json,
      keptLayers: keptLayers,
    ),
  );
  return plan;
}

/// The in-memory read of the docs that the generators of a `regenerate` step
/// read from.
///
/// The first plan that reaches a `regenerate` step builds it; a later plan
/// given the same index reuses it, so one run builds it once. Its owner closes
/// it.
final class RegenerationIndex {
  ReadSession? _session;

  ReadSession _sessionOf(DocsProject project, Directory root) =>
      _session ??= ReadSession.readFrom(
        project,
        IndexStore.inMemory(),
        workingDirectory: root,
      );

  /// Closes the read; a later plan builds a new one.
  void close() {
    _session?.close();
    _session = null;
  }
}

/// The format write of one `regenerate` step, planned over the target-version
/// set and read from an in-memory index.
final class _Regeneration {
  const new({
    required this.registry,
    required this.session,
    required this.rewrites,
    required this.creates,
    required this.deletes,
    required this.warnings,
  });

  /// The generators the step lists.
  final GeneratorRegistry<DocIndex> registry;

  /// The in-memory read of the docs the generators read from.
  final ReadSession session;

  /// One line per doc the write leaves as it was, then the warnings of the
  /// docs it reads.
  final List<String> warnings;

  /// The DocPath of each doc the write changes.
  final Set<String> rewrites;

  /// The LF text of each group doc the write creates, by DocPath.
  final Map<String, String> creates;

  /// The DocPath of each group doc the write deletes.
  final List<String> deletes;

  /// Returns [lf], the doc at [path] after the steps before this one, with its
  /// generated blocks written when the write changes that doc.
  String fill(
    String lf, {
    required String path,
    required MergedDocType docType,
  }) => rewrites.contains(path)
      ? fillGeneratedBlocks(lf, docType, registry, session.index, docPath: path)
      : lf;
}

/// Plans the format write of each `regenerate` step over [set].
///
/// The docs are read once, and indexed in memory once through [index], for
/// every step. A write reads the docs as the steps before it leave them, so a
/// group doc an earlier step creates or deletes stays that step's: a later
/// step lists it no more.
final class _RegenerationPlanner {
  new({
    required this.root,
    required this.homeDirectory,
    required this.set,
    required this.generators,
    required this.index,
  });

  final Directory root;
  final Directory? homeDirectory;
  final MergedSet set;
  final GeneratorRegistry<DocIndex> generators;
  final RegenerationIndex index;

  final _taken = <String>{};
  DocsProject? _project;
  List<DocRead>? _reads;

  /// Returns the write of [step], planned over [lfByDocPath], the LF text of
  /// each doc by DocPath after the steps before [step]; a doc it holds no text
  /// for keeps its text on disk.
  ///
  /// Throws a [StateError] when [step] names a kind [generators] lacks.
  _Regeneration plan(Regenerate step, Map<String, String> lfByDocPath) {
    final missing = step.generators.where(
      (kind) => !generators.kinds.contains(kind),
    );
    if (missing.isNotEmpty) {
      throw StateError(
        'regenerate names ${missing.join(', ')}, which the generators the '
        'caller passed do not hold',
      );
    }
    final project = _project ??= DocsProject.onSet(
      set,
      workingDirectory: root,
      homeDirectory: homeDirectory,
    );
    final session = index._sessionOf(project, root);
    final reads = _reads ??= [
      for (final entry in collectDocEntries(
        Target(project.docsRoot, ''),
        project.matcher,
      ))
        readDoc(project, entry),
    ];
    final registry = generators.only(step.generators.toSet());
    final plan = planFormatWrites(
      project,
      [for (final read in reads) _withText(read, lfByDocPath)],
      registry,
      session.index,
    );
    final creates = {
      for (final MapEntry(:key, :value) in plan.creates.entries)
        if (docPathOfProjectPath(key) case final path?
            when !_taken.contains(path))
          path: value,
    };
    final deletes = [
      for (final path in plan.deletes)
        if (docPathOfProjectPath(path) case final docPath?
            when !_taken.contains(docPath))
          docPath,
    ];
    _taken
      ..addAll(creates.keys)
      ..addAll(deletes);
    return _Regeneration(
      registry: registry,
      session: session,
      rewrites: {
        for (final path in plan.rewrites.keys) ?docPathOfProjectPath(path),
      },
      creates: creates,
      deletes: deletes,
      warnings: [
        for (final result in plan.blocked) _leftLineOf(result),
        ...plan.warnings,
      ],
    );
  }

  static String _leftLineOf(FileResult result) =>
      '${result.path} cannot be written by regenerate: ${result.reasons}; '
      'left as it was';

  /// Returns [read] holding its text from [lfByDocPath], in its line ending,
  /// or [read] itself when it holds none.
  static DocRead _withText(DocRead read, Map<String, String> lfByDocPath) {
    if (read is! ReadableDoc) return read;
    final lf = lfByDocPath[read.docPath];
    if (lf == null) return read;
    return ReadableDoc(
      read.file,
      read.path,
      docPath: read.docPath,
      text: read.lineEnding.apply(lf),
      lineEnding: read.lineEnding,
      hasBom: read.hasBom,
      docType: read.docType,
      doc: Doc.parse(lf),
    );
  }
}

/// The docs the `merge_doc` steps of a run fold.
final class _Folds {
  const new({
    required this.byStep,
    required this.docs,
    required this.fromPaths,
    required this.collisions,
  });

  /// The docs each step, by its index, folds.
  final Map<int, List<FoldSource>> byStep;

  /// The links to the folded docs, followed to their `to` docs.
  final FoldedDocs docs;

  /// The DocPath of each doc a step folds, which the run moves to the trash.
  final Set<String> fromPaths;

  /// The collisions found while pairing docs, to refuse the run with.
  final List<MigrateFault> collisions;
}

/// Finds the docs of [docPaths] each `merge_doc` step of [steps] folds.
///
/// A `from` doc whose `to` doc is not UTF-8 text is not folded; the pair is
/// queued in [_Folds.collisions].
_Folds _foldsOf(
  Directory root,
  List<PackStep> steps, {
  required List<String> docPaths,
  required Map<String, DocText?> originals,
  required Map<String, String> planned,
  required MergedSet set,
  required List<String> twinNames,
}) {
  final unreadable = {
    for (final path in docPaths)
      if (originals[path] == null) planned[path]!: path,
  };
  final byStep = <int, List<FoldSource>>{};
  final docs = FoldedDocs();
  final fromPaths = <String>{};
  final collisions = <MigrateFault>[];
  for (final (index, PackStep(:step)) in steps.indexed) {
    if (step is! MergeDoc) continue;
    final toType = set.lookup(step.toId);
    if (toType == null) continue;
    final sources = [
      for (final source in foldSourcesOf(
        step,
        docPaths: docPaths,
        set: set,
        twinNames: twinNames,
        fromPattern: _layerPathOf(root, step.fromId),
      ))
        if (originals[source.fromPath] != null &&
            source.fromPath != source.toPath)
          source,
    ];
    byStep[index] = sources;
    for (final source in sources) {
      if (unreadable[source.toPath] case final toPath?) {
        collisions.add(
          MigrateFault(
            MigrateFaultCode.upgradeCollision,
            'merge_doc of ${step.fromId} into ${step.toId} cannot add '
            '${source.fromPath}, because $toPath is not UTF-8 text; '
            '$_resolveCollision',
            file: toPath,
          ),
        );
        continue;
      }
      docs.add(source, step, toHeaders: _headersOf(toType));
      fromPaths.add(source.fromPath);
    }
  }
  return _Folds(
    byStep: byStep,
    docs: docs,
    fromPaths: fromPaths,
    collisions: collisions,
  );
}

/// A `merge_doc` `from` doc that an earlier step of the fold's own pack
/// names: its frozen doc type with its target, and the run's step indexes
/// from the first step of that pack up to the step that first folds it.
final class _FrozenFromDoc {
  const new(this.match, {required this.packStart, required this.foldIndex});

  final MatchedDocType match;
  final int packStart;
  final int foldIndex;
}

/// Returns, by DocPath in step order, each doc of [folds] whose `from` id a
/// step of the same pack before its first fold names, typed by that id's doc
/// type in [frozen] and the target of its `to` doc.
///
/// [upgrades] hold the run's steps, each pack's selected steps together in its
/// chain order (`PackManifest.chainOrder`). A step of another pack never
/// counts. The pack load refuses a pack with a step that names an id a
/// `merge_doc` step after it in that same chain order folds, when the pack
/// ships no frozen copy; each selected step before the fold is such a step,
/// so [frozen] holds every id this reads.
Map<String, _FrozenFromDoc> _frozenFromDocsOf(
  List<PackUpgrade> upgrades,
  _Folds folds, {
  required Map<String, MergedDocType> frozen,
  required DocTypeMatcher matcher,
}) {
  final docs = <String, _FrozenFromDoc>{};
  var packStart = 0;
  for (final PackUpgrade(:steps) in upgrades) {
    for (final (offset, PackStep(:step)) in steps.indexed) {
      if (step is! MergeDoc) continue;
      final fromId = step.fromId;
      if (!steps.take(offset).any((earlier) => earlier.step.touches(fromId))) {
        continue;
      }
      // checkFrozenDocTypes refused the load when the pack ships no copy.
      final type = frozen[fromId]!;
      final index = packStart + offset;
      for (final source in folds.byStep[index] ?? const <FoldSource>[]) {
        if (!folds.fromPaths.contains(source.fromPath) ||
            docs.containsKey(source.fromPath)) {
          continue;
        }
        final to = matcher.match(source.toPath);
        docs[source.fromPath] = _FrozenFromDoc(
          MatchedDocType(type, target: to is MatchedDocType ? to.target : null),
          packStart: packStart,
          foldIndex: index,
        );
      }
    }
    packStart += steps.length;
  }
  return docs;
}

/// Returns the header of each section of [type], by section id.
Map<String, String> _headersOf(MergedDocType type) => {
  for (final section in type.sections) section.id: section.header,
};

/// Adds [changes], a link pass's changes to [work], to the doc's set in
/// [linkChanges] and each label new to it to the work's changes.
void _addLinkChanges(
  _DocWork work,
  List<LinkChange> changes,
  Map<String, Set<LinkChange>> linkChanges,
) {
  final held = linkChanges[work.plannedPath] ??= {};
  for (final change in changes) {
    if (held.add(change)) work.changes.add(change.label);
  }
}

/// Returns each typed doc of [works] as a relink pass reaches it, by planned
/// DocPath; a doc whose anchors do not parse is left out, so no link to it
/// changes.
RelinkTargets _relinkTargetsOf(List<_DocWork> works) => RelinkTargets({
  for (final work in works)
    if (work.docType case final type?)
      if (anchorsOfBody(Doc.parse(work.lf).afterFrontmatter)
          case final anchors?)
        work.plannedPath: RelinkDoc(
          typeId: type.id,
          name: docNameOf(work.plannedPath, type, target: work.target),
          headingSlugs: anchors.headingSlugs,
          sectionHeaders: _headersOf(type),
          htmlIds: anchors.htmlIds,
        ),
});

/// Returns the `path:` of the project layer file of doc type [id], or null
/// when the file is absent, holds no string `path:`, or is not valid YAML.
///
/// A folded type's layer file halts no command, so a fault in it is no fault
/// of the plan.
String? _layerPathOf(Directory root, String id) {
  final file = File.fromUri(
    root.uri.resolve('$projectTemplatesFolder/$id.yaml'),
  );
  if (!file.existsSync()) return null;
  try {
    final layer = loadYaml(utf8.decode(readPlanInput(file)));
    return layer is YamlMap && layer['path'] is String
        ? layer['path'] as String
        : null;
  } on YamlException {
    return null;
  } on FormatException {
    return null;
  }
}

/// Returns the path of the project layer file of each doc type a `merge_doc`
/// or `drop_doc_type` step of [steps] leaves behind, for each such file that
/// exists.
List<String> _keptLayersOf(Directory root, List<MigrationStep> steps) => [
  for (final id in {
    for (final step in steps)
      if (step is MergeDoc) step.fromId else if (step is DropDocType) step.id,
  })
    if (File.fromUri(root.uri.resolve('$projectTemplatesFolder/$id.yaml'))
        .existsSync())
      '$projectTemplatesFolder/$id.yaml',
];

/// Returns [lf], a doc at [fromPath], with its links set to reach their
/// targets from [toPath].
String _rebased(String lf, String fromPath, String toPath) {
  final body = Doc.parse(lf).afterFrontmatter;
  return lf.substring(0, lf.length - body.length) +
      rebaseDocLinks(body, fromDocPath: fromPath, toDocPath: toPath);
}

/// Returns the first of [headers] the doc [lf] already holds as a section.
String? _heldHeader(String lf, List<String> headers) {
  final held = {
    for (final section in Doc.parse(lf).sections) headerKey(section.headerText),
  };
  return headers
      .where((header) => held.contains(headerKey(header)))
      .firstOrNull;
}

MigrateFault _foldCollision(
  MergeDoc step,
  FoldSource source, {
  required String header,
  required String file,
}) => MigrateFault(
  MigrateFaultCode.upgradeCollision,
  'merge_doc of ${step.fromId} into ${step.toId} adds $header from '
  '${source.fromPath}, which the doc already holds; $_resolveCollision',
  file: file,
);

MigrateFault _leadFault(
  MergeDoc step,
  FoldSource source, {
  required String file,
}) => MigrateFault(
  MigrateFaultCode.upgradeCollision,
  'merge_doc of ${step.fromId} into ${step.toId} cannot place the opening '
  'text of ${source.fromPath}, because the doc holds no section to put it '
  'in; $_resolveCollision',
  file: file,
);

MigrateFault _unmergedFault(
  MergeDoc step,
  FoldSource source,
  List<String> fields, {
  required String file,
}) => MigrateFault(
  MigrateFaultCode.upgradeCollision,
  'merge_doc of ${step.fromId} into ${step.toId} cannot add the entries of '
  '${fields.join(', ')} from ${source.fromPath}, because the doc holds that '
  'field as no list; $_resolveCollision',
  file: file,
);

/// Returns, by DocPath, the step index of the first `merge_doc` step of
/// [steps] that folds a doc into each `to` doc no path of [held] names, sorted
/// by path.
Map<String, int> _createdAtOf(
  List<PackStep> steps,
  _Folds folds, {
  required Set<String> held,
  required MergedSet set,
}) {
  final created = <String, int>{};
  for (final (index, PackStep(:step)) in steps.indexed) {
    if (step is! MergeDoc || set.lookup(step.toId) == null) continue;
    for (final source in folds.byStep[index] ?? const <FoldSource>[]) {
      if (!held.contains(source.toPath)) {
        created.putIfAbsent(source.toPath, () => index);
      }
    }
  }
  return {
    for (final path in created.keys.toList()..sort(compareCodePoints))
      path: created[path]!,
  };
}

/// The text of a doc the project lacks, which a `merge_doc` step creates.
const _absentDoc = DocText(lf: '', ending: LineEnding.lf, bom: false, hash: '');

/// Resolves [pinned] with the [projectLayers] that stand without the added
/// packs: a layer of a type no pinned pack defines is kept only when it can
/// define the type itself, over a base the pins or another kept layer hold,
/// or none.
MergedSet _setWithoutAdds(
  TemplateResolver templates,
  Iterable<String> pinned, {
  required Directory? homeDirectory,
  required List<DocTypeLayer> projectLayers,
}) {
  final pinnedIds = {
    for (final type
        in templates
            .resolveCarried(packNames: pinned, homeDirectory: homeDirectory)
            .docTypes)
      type.id,
  };
  var kept = <DocTypeLayer>[];
  for (var grew = true; grew;) {
    final ids = {...pinnedIds, for (final layer in kept) layer.docTypeId};
    final next = [
      for (final layer in projectLayers)
        if (ids.contains(layer.docTypeId) ||
            (layer.missingNewDocTypeKey == null &&
                (layer.extendsId == null || ids.contains(layer.extendsId))))
          layer,
    ];
    grew = next.length > kept.length;
    kept = next;
  }
  return templates.resolveCarried(
    packNames: pinned,
    homeDirectory: homeDirectory,
    projectLayers: kept,
  );
}

/// Returns the mentions in code and agent files that [moves] stop resolving.
///
/// A pack upgrade keeps every doc's Name, since a move keeps its placeholder
/// values, so only a path mention can stop resolving. Reads no index, so the
/// plan writes nothing: the docs are the [docPaths] it read.
List<StaleMention> _staleMentionsOf(
  Directory root,
  ProjectConfig config, {
  required MergedSet set,
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
      targets: config.targets,
      agentFileRoots: config.agentFileRoots,
      docMoves: moves,
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

/// A plan's header and its commit 2 message.
final class _PlanTitles {
  const new({required this.header, required this.commit2Message});

  final String header;
  final String commit2Message;
}

/// Returns the plan header and commit 2 message of a run that moves no pin.
///
/// A run that moves the spec tree to [treeMovesTo] is titled by that move,
/// whatever else it writes; a run with neither the layout pass nor an agent
/// file write is titled as layout only.
_PlanTitles _pinsUnchangedTitles({
  required bool laysOut,
  required bool writesAgentFiles,
  required String? treeMovesTo,
}) => switch ((laysOut, writesAgentFiles)) {
  _ when treeMovesTo != null => _PlanTitles(
    header: 'pack upgrade: pins unchanged, spec tree to $treeMovesTo',
    commit2Message: _treeMoveCommit2Message,
  ),
  (true, true) => const _PlanTitles(
    header: _layoutAndAgentHeader,
    commit2Message: _layoutAndAgentCommit2Message,
  ),
  (false, true) => const _PlanTitles(
    header: _agentOnlyHeader,
    commit2Message: _agentOnlyCommit2Message,
  ),
  (_, false) => const _PlanTitles(
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
  List<PackStep> steps,
) {
  final files = <_OverrideFile>[];
  for (final layer in layers) {
    final file = _OverrideFile(
      layer.file,
      DocFileText.read(
        readPlanInput(File.fromUri(root.uri.resolve(layer.file))),
      ),
    );
    for (final (index, PackStep(:step)) in steps.indexed) {
      if (!step.touches(layer.docTypeId)) continue;
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
        RelinkMergedDocs() => file.lf,
        DropSharedLines() => file.lf,
        BulletLines() => file.lf,
        MarkRetrim() => file.lf,
        DropSection() => file.lf,
        MergeDoc() => file.lf,
        DropDocType() => file.lf,
        Regenerate() => file.lf,
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
            _ScalarEdit(scalar: scalar, replacement: to),
  ]);
}

/// A scalar of a YAML text, and the text that replaces it.
final class _ScalarEdit {
  const new({required this.scalar, required this.replacement});

  final YamlScalar scalar;
  final String replacement;
}

/// Returns [lf] with each scalar of [edits] replaced by its new text, written
/// in the quote style the scalar had.
String _withScalarsReplaced(String lf, List<_ScalarEdit> edits) {
  final ordered = [...edits]
    ..sort(
      (a, b) =>
          b.scalar.span.start.offset.compareTo(a.scalar.span.start.offset),
    );
  var text = lf;
  for (final _ScalarEdit(:scalar, :replacement) in ordered) {
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

/// Returns the agent file inputs of the upgrade of [root], whose [config] it
/// has read.
AgentFileInputs _agentInputsOf(
  Directory root,
  ProjectConfig config, {
  required MergedSet set,
}) {
  final projectRoot = Directory(root.resolveSymbolicLinksSync());
  return AgentFileInputs(
    projectRoot: projectRoot,
    cliVersion: specstoneVersion,
    codeRootFolders: codeFoldersOf(projectRoot, set, targets: config.targets),
    agentFileRoots: config.agentFileRoots,
  );
}

/// Returns the `agent_files_version` the run sets, or null when it leaves the
/// key: a run that writes no config, or one whose stamp [config] already holds.
ReleaseVersion? _stampOf(
  AgentFileInputs inputs,
  AgentWritePlan plan,
  ProjectConfig config, {
  required bool isConfigWritten,
}) {
  if (!isConfigWritten) return null;
  final held = config.agentFilesVersion;
  final stamp = agentFilesStampAfter(inputs, plan, current: held);
  if (stamp == null || (held != null && stamp.compareTo(held) == 0)) {
    return null;
  }
  return stamp;
}

/// One doc of the run, with its text after the steps and link rewrites.
final class _DocWork {
  new(
    this.plannedPath,
    this.original,
    this.docType,
    this.target,
    this.lf,
    this.changes, {
    required this.isCreate,
  });

  /// The DocPath after the moves.
  final String plannedPath;

  /// The file as read.
  final DocText original;

  final MergedDocType? docType;

  /// The code target whose pattern set matched [plannedPath]; null for a doc
  /// of a shared doc type or of no doc type.
  final String? target;

  /// The LF text after the steps and link rewrites.
  String lf;

  /// The labels of the changes made so far, in the order they apply.
  final List<String> changes;

  /// Whether the doc is a draft a `merge_doc` step creates, with no file yet.
  final bool isCreate;
}

/// Returns the rewrite of `config.yaml` that moves the pins of [upgrades],
/// appends [addedPins], and sets `agent_file_roots` to [agentFileRoots] and
/// `agent_files_version` to [agentFilesVersion] when each is not null, every
/// other byte kept, or null when none changes.
PlannedRewrite? _configRewriteOf(
  Directory root,
  List<PackUpgrade> upgrades, {
  required List<AddedPin> addedPins,
  required List<String>? agentFileRoots,
  required ReleaseVersion? agentFilesVersion,
}) {
  if (upgrades.isEmpty &&
      addedPins.isEmpty &&
      agentFileRoots == null &&
      agentFilesVersion == null) {
    return null;
  }
  final original = DocFileText.read(
    readPlanInput(File.fromUri(root.uri.resolve(projectConfigPath))),
  );
  final packs =
      (loadYamlNode(original.lf) as YamlMap).nodes['packs']! as YamlMap;
  var text = _withScalarsReplaced(original.lf, [
    for (final upgrade in upgrades)
      _ScalarEdit(
        scalar: packs.nodes[upgrade.pack]! as YamlScalar,
        replacement: '${upgrade.target}',
      ),
  ]);
  text = withPinsAppended(text, addedPins);
  if (agentFileRoots != null) text = _withAgentFileRoots(text, agentFileRoots);
  if (agentFilesVersion != null) {
    text = _withAgentFilesVersion(text, agentFilesVersion);
  }
  return PlannedRewrite(
    path: projectConfigPath,
    text: DocFileText.written(original, text),
    before: original.hash,
    changes: [
      if (upgrades.isNotEmpty || addedPins.isNotEmpty) 'pins',
      if (agentFileRoots != null) _agentFileRootsKey,
      if (agentFilesVersion != null) _agentFilesVersionKey,
    ],
  );
}

/// The forms of the `packs:` value that [withPinsAppended] writes.
enum _PacksForm { block, flow }

/// Returns the form of [packs], or null when it is neither a block map nor a
/// flow map on one line.
_PacksForm? _packsFormOf(YamlMap packs) => switch (packs.style) {
  CollectionStyle.BLOCK => _PacksForm.block,
  CollectionStyle.FLOW when packs.span.start.line == packs.span.end.line =>
    _PacksForm.flow,
  _ => null,
};

/// Throws `unknown_value` at `packs` when the config of [root] holds `packs:`
/// in a form [withPinsAppended] cannot write.
void _requirePacksWritable(Directory root) {
  final original = DocFileText.read(
    readPlanInput(File.fromUri(root.uri.resolve(projectConfigPath))),
  );
  final packs =
      (loadYamlNode(original.lf) as YamlMap).nodes['packs']! as YamlMap;
  if (_packsFormOf(packs) != null) return;
  throw TemplateFault(
    FaultCode.unknownValue,
    'migrate --add writes a packs block map or a one-line flow map; add the '
    'pin by hand',
    file: projectConfigPath,
    key: 'packs',
  );
}

/// Returns [lf] with each of [pins] appended to its `packs:` map, every other
/// byte kept.
///
/// A block map takes `pack: version` on a new line after its last entry's
/// line, at that entry's indent; a flow map on one line takes `, pack:
/// version` after its last entry, or `pack: version` when empty.
String withPinsAppended(String lf, List<AddedPin> pins) {
  if (pins.isEmpty) return lf;
  final packs = (loadYamlNode(lf) as YamlMap).nodes['packs']! as YamlMap;
  final entries = [for (final pin in pins) '${pin.pack}: ${pin.version}'];
  switch (_packsFormOf(packs)) {
    case _PacksForm.block:
      final last = packs.nodes.entries.last;
      final indent = ' ' * (last.key as YamlNode).span.start.column;
      final lineEnd = lf.indexOf('\n', last.value.span.end.offset);
      final at = lineEnd == -1 ? lf.length : lineEnd;
      return lf.replaceRange(at, at, '\n$indent${entries.join('\n$indent')}');
    case _PacksForm.flow when packs.nodes.isEmpty:
      final at = packs.span.start.offset + 1;
      return lf.replaceRange(at, at, entries.join(', '));
    case _PacksForm.flow:
      // A plain scalar's span runs through the spaces before the next token.
      var at = packs.nodes.entries.last.value.span.end.offset;
      while (lf[at - 1] == ' ') {
        at -= 1;
      }
      return lf.replaceRange(at, at, ', ${entries.join(', ')}');
    case null:
      throw ArgumentError.value(lf, 'lf', 'packs is not a writable map');
  }
}

/// Returns [text] with the `agent_file_roots` entry set to [roots]: replaced
/// in place when present, else appended.
String _withAgentFileRoots(String text, List<String> roots) => _withKeyBlock(
  text,
  _agentFileRootsKey,
  configText(const {}, agentFileRoots: roots).substring('packs:\n'.length),
);

/// Returns [text] with the `agent_files_version` entry set to [version]:
/// replaced in place when present, else appended.
String _withAgentFilesVersion(String text, ReleaseVersion version) =>
    _withKeyBlock(
      text,
      _agentFilesVersionKey,
      configText(
        const {},
        agentFilesVersion: version,
      ).substring('packs:\n'.length),
    );

/// Returns [text] with the top-level [key] set to [block], its whole lines:
/// replaced in place when present, else appended.
///
/// The replacement covers through the end of the value's last line, so a null
/// value (the bare key) and an end-of-line comment on the value both leave a
/// valid entry; the comment is dropped.
String _withKeyBlock(String text, String key, String block) {
  final map = loadYamlNode(text) as YamlMap;
  final value = map.nodes[key];
  if (value == null) return '${text.endsWith('\n') ? text : '$text\n'}$block';
  final keyNode = map.nodes.keys.firstWhere(
    (node) => (node as YamlNode).value == key,
  ) as YamlNode;
  var valueEnd = value.span.end.offset;
  if (valueEnd > 0 && text[valueEnd - 1] == '\n') {
    // A block-style list's span ends past its last newline.
    valueEnd -= 1;
  }
  final newline = text.indexOf('\n', valueEnd);
  return text.replaceRange(
    keyNode.span.start.offset,
    newline == -1 ? text.length : newline + 1,
    block,
  );
}

/// Whether [step] moves docs of a per-target doc type of [set] while the
/// project holds two or more targets, [firstTarget] set.
bool _isPerTargetStep(MoveFile step, MergedSet set, String? firstTarget) =>
    firstTarget != null && (set.lookup(step.docType)?.isPerTarget ?? false);

/// Returns the patterns [step] moves by: its `from` and `to`, repeated once per
/// nesting depth when its doc type nests in [set].
List<PatternMove> _movePatternsOf(MoveFile step, MergedSet set) {
  final nesting = set.nestingType;
  if (nesting == null || set.lookup(step.docType)?.nestedPaths == null) {
    return [PatternMove(from: step.from, to: step.to)];
  }
  return movePatternsAtEveryDepth(step.from, step.to, nesting);
}

/// The final path of each doc, the paths each move step's docs end at, the last
/// move step that touched each doc, and the docs the tree move moved.
final class _PlannedPaths {
  const new({
    required this.planned,
    required this.movedAt,
    required this.movedBy,
    required this.treeMoved,
  });

  final Map<String, String> planned;
  final Map<int, List<String>> movedAt;
  final Map<String, int> movedBy;
  final Set<String> treeMoved;
}

/// Returns the final path of each doc of [docPaths], the final paths each
/// move step's docs end at, the last move step that touched each doc, and the
/// docs the tree move moved.
///
/// The [treeMoves] come first. Each `move_file` step, in step order, then
/// matches every doc at its CURRENT path, the result of the earlier moves, so
/// moves chain: a doc at `A` under `A` → `B` then `B` → `C` ends at `C`.
/// With two or more [targetNames], a step of a per-target
/// doc type moves the docs of each target's folder by that target's patterns.
_PlannedPaths _plannedPaths(
  List<String> docPaths,
  List<PackStep> steps, {
  required List<PathMove> treeMoves,
  required MergedSet set,
  required List<String> targetNames,
}) {
  final planned = {for (final path in docPaths) path: path};
  final movedAt = <int, List<String>>{};
  final movedBy = <String, int>{};
  final treeMoved = <String>{};
  for (final PathMove(:from, :to) in treeMoves) {
    planned[from] = to;
    treeMoved.add(from);
  }
  final firstTarget = twinNamesOf(targetNames).firstOrNull;
  for (final (index, PackStep(:step)) in steps.indexed) {
    if (step is! MoveFile) continue;
    final patterns = [
      for (final target
          in _isPerTargetStep(step, set, firstTarget)
              ? targetNames
              : const <String?>[null])
        for (final pair in _movePatternsOf(step, set))
          (
            from: _patternIn(pair.from, target),
            to: _patternIn(pair.to, target),
          ),
    ];
    for (final (:from, :to) in patterns) {
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
  }
  return _PlannedPaths(
    planned: planned,
    movedAt: movedAt,
    movedBy: movedBy,
    treeMoved: treeMoved,
  );
}

PathPattern _patternIn(String pattern, String? target) => target == null
    ? PathPattern(pattern)
    : PathPattern(pattern).forTarget(target);

const _resolveCollision =
    'move, rename, or merge each listed doc or entry so the step no longer '
    'lands on it, then run specstone migrate again';

/// Returns an `upgrade_collision` fault for each move, the tree move or a
/// `move_file` step, that lands on a path the Owner still holds: a doc no move
/// touches, or a second doc of the same move.
///
/// Two docs moved onto one path each fault on their own line. A move onto
/// another moved doc's old path is fine: [orderedMoves] orders those.
/// [firstTarget] names the tree move's target. Destinations are compared
/// case-blind, as the legacy run's collisions are, so two docs whose new paths
/// differ only in letter case collide.
List<MigrateFault> _moveCollisions(
  List<String> docPaths, {
  required Map<String, String> planned,
  required Map<String, int> movedBy,
  required Set<String> treeMoved,
  required List<PackStep> steps,
  required String? firstTarget,
}) {
  bool isMoved(String path) =>
      movedBy.containsKey(path) || treeMoved.contains(path);
  final faults = <MigrateFault>[];
  for (final source in docPaths) {
    final destination = planned[source]!;
    if (destination == source) continue;
    final String what;
    if (movedBy[source] case final index?) {
      final step = steps[index].step;
      if (step is! MoveFile) continue;
      what = 'move_file of ${step.docType} moves ${step.from} to ${step.to}';
    } else {
      what = 'the spec tree move to $firstTarget moves $source to $destination';
    }
    final at = PathMoves.caseBlindPath(destination);
    // A stayer holds its ground: the mover's destination is its own path.
    final stayer = docPaths.any(
      (path) => PathMoves.caseBlindPath(path) == at && !isMoved(path),
    );
    // Another mover with the same final path: each fault names the other. A
    // stayer never counts; it is the stayer fault below.
    final rivals = docPaths.where(
      (path) =>
          path != source &&
          isMoved(path) &&
          PathMoves.caseBlindPath(planned[path]!) == at,
    );
    if (stayer) {
      faults.add(_collisionFault(what, source, 'the doc already there holds'));
    }
    for (final rival in rivals) {
      faults.add(_collisionFault(what, source, '$rival also moves to'));
    }
  }
  return faults;
}

MigrateFault _collisionFault(String what, String source, String holder) =>
    MigrateFault(
      MigrateFaultCode.upgradeCollision,
      '$what, which $holder; $_resolveCollision',
      file: source,
    );

String _exactPath(String path) => path;

/// Orders [moves] so a move whose target is another move's original path runs
/// after that move.
///
/// [keyOf] maps a path to the key two paths are compared by; a move waits for
/// every move whose original path has its target's key. A cycle, such as two
/// docs trading places, has no such order; [RunPlan.journalSteps] parks one of
/// its moves in the stage.
List<PathMove> orderedMoves(
  List<PathMove> moves, {
  String Function(String path) keyOf = _exactPath,
}) {
  final bySource = <String, List<PathMove>>{};
  for (final move in moves) {
    (bySource[keyOf(move.from)] ??= []).add(move);
  }
  final ordered = <PathMove>[];
  final placed = <String>{};
  void place(PathMove move) {
    if (!placed.add(move.from)) return;
    for (final blocker in bySource[keyOf(move.to)] ?? const <PathMove>[]) {
      if (blocker.from != move.from) place(blocker);
    }
    ordered.add(move);
  }

  moves.forEach(place);
  return ordered;
}

/// Throws the first of [faults] on each doc, the first as the fault and the
/// rest chained through `more`; nothing when [faults] is empty.
///
/// A doc can collide once per rival and once per step; it is listed once.
void _throwFaultsPerDoc(List<MigrateFault> faults) {
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
  RelinkMergedDocs() => step.kind,
  DropSharedLines() => step.kind,
  BulletLines() => '${step.kind} ${step.docType} ${step.section}',
  MarkRetrim() => step.kind,
  DropSection() => '${step.kind} ${step.docTypes.join(', ')} ${step.sectionId}',
  MergeDoc() => '${step.kind} ${step.fromId} -> ${step.toId}',
  DropDocType() => '${step.kind} ${step.id}',
  Regenerate() => '${step.kind}: ${step.generators.join(', ')}',
};

/// Returns the doc paths in code point order, then the override paths in the
/// same order.
List<String> _sortedPaths({
  required List<String> docs,
  required List<String> overrides,
}) => [
  ...[...docs]..sort(compareCodePoints),
  ...[...overrides]..sort(compareCodePoints),
];

/// Whether [path], from [docsRoot] or the records root of [projectRoot] and
/// possibly leaving it, names a file or folder of the tree as it stands before
/// the moves.
bool _existsIn(Directory docsRoot, Directory projectRoot, String path) =>
    FileSystemEntity.typeSync(
      fileOfDocPath(path, docsRoot: docsRoot, projectRoot: projectRoot).path,
    ) !=
    FileSystemEntityType.notFound;
