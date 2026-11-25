import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/doc_model/default_enforcer.dart'
    show ancestorTwinPaths;
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_anchors.dart'
    show anchorsOfBody;
import 'package:specstone_core/src/doc_model/doc_splice.dart' show withKeyBlock;
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/doc_model/path_pattern.dart';
import 'package:specstone_core/src/doc_model/records_root.dart';
import 'package:specstone_core/src/document_writing/approval.dart'
    show statusesOutsideApproval;
import 'package:specstone_core/src/document_writing/models/path_move.dart';
import 'package:specstone_core/src/document_writing/rewrite_refs.dart'
    show rebaseDocLinks;
import 'package:specstone_core/src/document_writing/set_doc.dart'
    show markDraft;
import 'package:specstone_core/src/document_writing/stale_mentions.dart'
    show MentionScope, StaleMention, staleMentionsIn;
import 'package:specstone_core/src/index_query/indexed_doc.dart'
    show IndexedDoc, docNameOf;
import 'package:specstone_core/src/index_query/item_words.dart'
    show itemIdPrefixesOf;
import 'package:specstone_core/src/plan_hash.dart';
import 'package:specstone_core/src/release_version.dart' show ReleaseVersion;
import 'package:specstone_core/src/rendering/formatter.dart'
    show headerKey, layOutDoc;
import 'package:specstone_core/src/rendering/models/line_ending.dart';
import 'package:specstone_core/src/setup_migration/agent_targets.dart';
import 'package:specstone_core/src/setup_migration/bullet_lines_step.dart';
import 'package:specstone_core/src/setup_migration/cite_pass.dart';
import 'package:specstone_core/src/setup_migration/code_stamp_step.dart';
import 'package:specstone_core/src/setup_migration/dangling_overrides.dart';
import 'package:specstone_core/src/setup_migration/drop_default_lines_step.dart';
import 'package:specstone_core/src/setup_migration/drop_section_step.dart';
import 'package:specstone_core/src/setup_migration/followed_links.dart';
import 'package:specstone_core/src/setup_migration/heading_ledger.dart';
import 'package:specstone_core/src/setup_migration/label_pass.dart';
import 'package:specstone_core/src/setup_migration/legacy_moves.dart'
    show caseBlindPath;
import 'package:specstone_core/src/setup_migration/legacy_plan.dart'
    show prunesOf;
import 'package:specstone_core/src/setup_migration/legacy_rewrites.dart';
import 'package:specstone_core/src/setup_migration/mark_retrim_step.dart';
import 'package:specstone_core/src/setup_migration/matrix_fold_pass.dart';
import 'package:specstone_core/src/setup_migration/merge_doc_step.dart';
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/setup_migration/migration_chain.dart';
import 'package:specstone_core/src/setup_migration/models/code_stamp_doc.dart';
import 'package:specstone_core/src/setup_migration/models/doc_text.dart';
import 'package:specstone_core/src/setup_migration/models/label_doc.dart'
    show LabelDoc;
import 'package:specstone_core/src/setup_migration/models/label_tree.dart'
    show LabelTree;
import 'package:specstone_core/src/setup_migration/models/pack_step.dart';
import 'package:specstone_core/src/setup_migration/models/placement_doc.dart';
import 'package:specstone_core/src/setup_migration/models/stamp_doc.dart';
import 'package:specstone_core/src/setup_migration/project_files.dart';
import 'package:specstone_core/src/setup_migration/record_placement.dart';
import 'package:specstone_core/src/setup_migration/relink_links.dart';
import 'package:specstone_core/src/setup_migration/renumber_pass.dart';
import 'package:specstone_core/src/setup_migration/run_plan.dart';
import 'package:specstone_core/src/setup_migration/shared_copies_step.dart';
import 'package:specstone_core/src/setup_migration/skill_agent_files.dart'
    show shipsSkillFiles;
import 'package:specstone_core/src/setup_migration/stamp_pass.dart';
import 'package:specstone_core/src/setup_migration/test_name_pass.dart';
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
import 'package:specstone_core/src/templates/pack_manifest.dart'
    show PackManifest;
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
const _renumberChange = 'renumber ids';
const _layersKeptPrefix = 'layers kept: ';
const _labelChange = 'convert number labels';
const _draftChange = 'draft flag';
const _stampChange = 'stamp approvals';
const _recordChange = 'add record entries';
const _testsChange = 'add test lines';
const _matrixRowsChange = 'fold matrix rows';
const _codeStampChange = 'stamp code fingerprints';
const _codeRestampChange = 'restamp code fingerprints';
const _citeChange = 'convert cites';
const _invariantsSectionId = 'invariants';
const _entitiesSectionId = 'entities';
const _enforcerField = 'Enforcer';
const _consistencyField = 'Consistency';
const _immediateValue = 'immediate';

/// Plans the pack upgrade of the project at [root].
///
/// Selects every pinned pack's steps, refuses an override the new versions
/// leave dangling, then plans the tree move under the first code target when
/// two or more are listed, the pack's moves, the section and field renames in
/// the docs and the overrides, the link and path mention rewrites, the
/// renumber pass, the label pass, the values a `move_to_record` step moves
/// into the records it adds to or creates, the test-name pass, the cite pass,
/// each typed doc laid out as `format` lays it out, the agent files step, and
/// the new pins. With every
/// pin equal the plan holds the layout pass, the agent files step, and the
/// tree move alone. Writes nothing. Throws `MigrateFault` `override_dangling`,
/// `MigrateFault` `upgrade_collision` listing every move and rename collision
/// at once, `value_unplaced` listing every value no record takes at once, or
/// else every create onto a taken path ([RunPlan.refuseTakenCreates]),
/// `agent_block_malformed`, and a `TemplateFault` before it returns, so a
/// refused run prints nothing. When [runsOneTimePasses] holds, the renumber
/// and label passes run and the agent files step is the full upsert;
/// otherwise the step refreshes what exists. When [runsTestNamePass] holds and
/// the merged set holds the record doc type, the test-name pass runs too, and
/// when [runsCitePass] holds, the cite pass. [homeDirectory] is the personal
/// pack home, or null. The plan's `inputs` hold every file it read.
///
/// Each of [addedPacks], sorted with no repeat, joins the pins at the version
/// its pack carries: the `packs:` form is checked first, then the merged set
/// with the added packs loads, so a refused add prints nothing. Throws a
/// `TemplateFault` `unknown_value` at `packs` for a form the add cannot write.
RunPlan planUpgradeRun(
  Directory root, {
  required TemplateResolver templates,
  required Directory? homeDirectory,
  List<String> addedPacks = const [],
}) {
  final inputs = PlanInputs(root);
  return inputs.collect(
    () => _upgradeRunOf(
      root,
      templates: templates,
      homeDirectory: homeDirectory,
      addedPacks: addedPacks,
      inputs: inputs,
    ),
  )..refuseTakenCreates(root);
}

/// Plans the upgrade of [root] while [inputs] records each file read.
RunPlan _upgradeRunOf(
  Directory root, {
  required TemplateResolver templates,
  required Directory? homeDirectory,
  required List<String> addedPacks,
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

  final selected = [for (final upgrade in upgrades) ...upgrade.steps];
  final recordOverride = recordPathOverrideOf(
    [for (final entry in selected) entry.step],
    overrides: overrides,
    target: targetSet,
  );
  // One record path per plan: a record the run moves lands where the record
  // override types it.
  final steps = [
    for (final PackStep(:from, :step, :relinkRules) in selected)
      PackStep(
        from: from,
        step: recordOverride?.landed(step) ?? step,
        relinkRules: relinkRules,
      ),
  ];
  final stepKinds = [for (final entry in steps) entry.step];
  final overrideFiles = _renamedOverrides(root, overrides, steps);
  final overrideCreates = [
    if (recordOverride case RecordPathOverride(:final file, path: final path?))
      PlannedCreate(path: file, text: 'path: $path\n'),
  ];
  List<DocTypeLayer> layersOf(Map<String, String> overrideTexts) =>
      parseOverrides({
        ...overrideTexts,
        for (final create in overrideCreates) create.path: create.text,
      });
  MergedSet resolveLayers(List<DocTypeLayer> layers) =>
      templates.resolveCarried(
        packNames: packNames,
        homeDirectory: homeDirectory,
        projectLayers: layers,
        projectSharedLines: projectSharedLines,
      );
  MergedSet resolveWith(Map<String, String> overrideTexts) =>
      resolveLayers(layersOf(overrideTexts));
  final projectLayers = layersOf({
    for (final file in overrideFiles) file.path: file.lf,
  });
  final finalSet = resolveLayers(projectLayers);
  final stripIndex = stepKinds.indexWhere((step) => step is StripSharedCopies);
  final sharedCopies = stripIndex < 0
      ? null
      : _sharedCopiesOf(
          overrideFiles,
          stripIndex: stripIndex,
          target: finalSet,
          personalFiles: _personalFilesOf([
            ...available.values,
            ...addedManifests.values,
          ], homeDirectory),
          resolveWith: resolveWith,
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
  if (recordOverride != null) {
    _refuseStrandedRecords(recordOverride, movedBy: movedBy, steps: steps);
  }
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
  final recordMoves = RecordMoves();
  final works = <_DocWork>[];
  final changedAt = <int, List<String>>{};
  final linkLines = <String>[];
  // Each doc's text after its steps, before the run's link rewrites.
  final steppedTexts = <String, String>{};
  final renameCollisions = <MigrateFault>[];
  final originals = {
    for (final path in docPaths)
      path: readDocFile(
        fileOfDocPath(path, docsRoot: docsRoot, projectRoot: root),
        docPath: path,
      ),
  };
  // The pre-run text under the planned path: no step reads a twin another
  // step has already rewritten, so the result needs no doc order.
  final preRunTexts = {
    for (final MapEntry(:key, :value) in originals.entries)
      if (value != null) planned[key]!: value.lf,
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
  final frozenTypeByPlannedPath = {
    for (final MapEntry(:key, :value) in frozenFromDocs.entries)
      planned[key]!: value.match,
  };
  final steppedTextByDocPath = <String, String>{};
  final ledger = HeadingLedger();
  DocTypeMatch typeAt(String plannedPath) =>
      frozenTypeByPlannedPath[plannedPath] ?? matcher.match(plannedPath);
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
        renameCollisions.add(
          _foldCollision(step, source, header: header, file: path),
        );
        return lf;
      }
      if (merged.isLeadUnplaced) {
        renameCollisions.add(_leadFault(step, source, file: path));
        return lf;
      }
      if (merged.unmergedFields.isNotEmpty) {
        renameCollisions.add(
          _unmergedFault(step, source, merged.unmergedFields, file: path),
        );
        return lf;
      }
      ledger.folded(
        fromPath: planned[source.fromPath] ?? source.fromPath,
        fromLf: fromLf,
        toPath: plannedPath,
        toBefore: text,
        toAfter: merged.text,
        groups: merged.sectionGroups,
      );
      text = merged.text;
    }
    return text;
  }

  /// Returns [text], the doc at [path] planned at [plannedPath], with each step
  /// from [firstStep] up to [endStep] that touches [docType] applied, adding
  /// each change to [changes] and each refused rename to `renameCollisions`.
  String stepped(
    String text, {
    required String path,
    required String plannedPath,
    required MergedDocType docType,
    required String? target,
    required int firstStep,
    required int endStep,
    required List<String> changes,
  }) {
    var lf = text;
    for (final (index, PackStep(:step)) in steps.indexed) {
      if (index < firstStep || index >= endStep) continue;
      if (!step.touches(docType.id)) continue;
      final renamed = switch (step) {
        RenameSection() => withHeaderRenamed(
          lf,
          step.fromHeader,
          step.toHeader,
        ),
        RenameField() => _withKeyRenamed(lf, step.from, step.to),
        MoveFile() => lf,
        MoveToRecord() => recordMoves.take(
          docPath: path,
          plannedPath: plannedPath,
          type: docType,
          step: step,
          lf: lf,
        ),
        StampCodeFingerprints() => lf,
        RestampCodeFingerprints() => lf,
        RelinkMergedDocs() => lf,
        StripSharedCopies() => lf,
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
        DropDefaultLines() => _withDefaultLinesDropped(
          lf,
          docType: docType,
          plannedPath: plannedPath,
          target: target,
          typeAt: typeAt,
          preRunTexts: preRunTexts,
        ),
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
          MoveToRecord() => false,
          StampCodeFingerprints() => false,
          RestampCodeFingerprints() => false,
          RelinkMergedDocs() => false,
          StripSharedCopies() => false,
          DropSharedLines() => false,
          BulletLines() => false,
          DropDefaultLines() => false,
          MarkRetrim() => false,
          DropSection() => false,
          MergeDoc() => false,
          DropDocType() => false,
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
            MoveToRecord() => '',
            StampCodeFingerprints() => '',
            RestampCodeFingerprints() => '',
            RelinkMergedDocs() => '',
            StripSharedCopies() => '',
            DropSharedLines() => '',
            BulletLines() => '',
            DropDefaultLines() => '',
            MarkRetrim() => '',
            DropSection() => '',
            MergeDoc() => '',
            DropDocType() => '',
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
        lf = renamed;
        changes.add(_describe(step));
        (changedAt[index] ??= []).add(plannedPath);
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
      target: doc.match.target,
      firstStep: doc.packStart,
      endStep: doc.foldIndex,
      changes: <String>[],
    );
  }

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
    if (original == null || folds.fromPaths.contains(plannedPath)) continue;
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
        target: target,
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
      steppedTexts[plannedPath] = rewriteMentions(
        lf,
        docPath: path,
        moves: moves,
        exists: exists,
      ).lf;
      final links = rewriteLinks(lf, docPath: path, moves: moves);
      final mentions = rewriteMentions(
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
  throwFaultsPerDoc([...moveCollisions, ...renameCollisions]);
  final taken = takenAfterMoves(root, moves);
  final placement = recordMoves.place(
    set: finalSet,
    recordType: finalSet.recordDocType,
    firstTarget: firstTarget,
    isTaken: (docPath) => taken(projectPathOfDocPath(docPath)),
    docs: [
      for (final work in works)
        PlacementDoc(
          plannedPath: work.plannedPath,
          type: work.docType,
          target: work.target,
          lf: work.lf,
        ),
    ],
  );
  throwFaultsPerDoc(placement.unplaced);
  for (final work in works) {
    if (placement.edits[work.plannedPath] case final edited?) {
      work.lf = edited;
      work.changes.add(_recordChange);
    }
  }
  final codeStamp = stepKinds.any((step) => step is StampCodeFingerprints)
      ? _codeStampOf(
          root,
          config,
          set: finalSet,
          works: works,
          recordCreates: recordCreatesOf(placement),
          firstTarget: firstTarget,
        )
      : null;
  final codeRestamp = stepKinds.any((step) => step is RestampCodeFingerprints)
      ? _codeStampOf(
          root,
          config,
          set: finalSet,
          works: works,
          recordCreates: recordCreatesOf(placement),
          firstTarget: firstTarget,
          restamp: true,
          after: codeStamp?.rewrites ?? const {},
        )
      : null;
  final codeRewrites = {...?codeStamp?.rewrites, ...?codeRestamp?.rewrites};
  final recordCreates = [
    for (final create in recordCreatesOf(placement))
      PlannedCreate(
        path: create.path,
        text: codeRewrites[docPathOfProjectPath(create.path)] ?? create.text,
        note: create.note,
      ),
  ];
  for (final work in works) {
    if (codeRewrites[work.plannedPath] case final stamped?) {
      work.lf = stamped;
      if (codeStamp?.rewrites.containsKey(work.plannedPath) ?? false) {
        work.changes.add(_codeStampChange);
      }
      if (codeRestamp?.rewrites.containsKey(work.plannedPath) ?? false) {
        work.changes.add(_codeRestampChange);
      }
    }
  }

  // The passes read every doc's text after the steps and link rewrites.
  final isOneTime = runsOneTimePasses(upgrades);
  final renumber = isOneTime ? _renumberPassOf(works) : null;
  final renumbered = <String>[];
  for (final work in works) {
    final lf = renumber?.apply(work.plannedPath, work.lf) ?? work.lf;
    if (lf != work.lf) work.changes.add(_renumberChange);
    renumbered.add(lf);
  }
  final agentInputs = _agentInputsOf(root, config, set: finalSet);
  final agentFiles = planAgentWrites(
    agentInputs,
    full: runsOneTimePasses(upgrades),
    shipsSkills: shipsSkillFiles(upgrades),
  );
  final labels = isOneTime
      ? LabelPass.plan(
          [
            for (final (index, work) in works.indexed)
              LabelDoc(docPath: work.plannedPath, lf: renumbered[index]),
          ],
          set: finalSet,
          docTypes: {for (final work in works) work.plannedPath: ?work.docType},
        )
      : null;
  final converted = <String>[];
  for (final (index, work) in works.indexed) {
    final lf = renumbered[index];
    final text = labels?.apply(work.plannedPath, lf) ?? lf;
    if (text != lf) work.changes.add(_labelChange);
    converted.add(text);
  }
  final tests = runsTestNamePass(upgrades) && finalSet.recordDocType != null
      ? _testNamesOf(
          root,
          config,
          set: finalSet,
          works: works,
          texts: converted,
          recordCreates: recordCreates,
          isTaken: (docPath) => taken(projectPathOfDocPath(docPath)),
        )
      : null;
  final tested = <String>[];
  for (final (index, work) in works.indexed) {
    var text = converted[index];
    if (tests?.recordEdits[work.plannedPath] case final edited?) {
      text = edited;
      work.changes.add(_testsChange);
    }
    tested.add(text);
  }
  final matrixFold = MatrixFoldPass.plan(config.matrixMode, finalSet, [
    for (final (index, work) in works.indexed)
      MatrixFoldDoc(
        plannedPath: work.plannedPath,
        type: work.docType,
        target: work.target,
        lf: tested[index],
      ),
  ]);
  final recorded = <String>[];
  for (final (index, work) in works.indexed) {
    var text = tested[index];
    if (matrixFold?.recordEdits[work.plannedPath] case final edited?) {
      text = edited;
      work.changes.add(_matrixRowsChange);
    }
    recorded.add(text);
  }
  final cites = runsCitePass(upgrades)
      ? CitePass.plan(
          [
            for (final (index, work) in works.indexed)
              (
                docPath: work.plannedPath,
                lf: recorded[index],
                type: work.docType,
                target: work.target,
              ),
          ],
          idPrefixes: itemIdPrefixesOf(finalSet.docTypes),
          layoutPaths: singularLayoutPathsOf(
            finalSet,
            twinNames: twinNamesOf(config.targetNames),
          ),
        )
      : null;
  final citedFrom = <String, String>{};
  final laidOutPaths = <String>[];
  final laidOut = <String>[];
  for (final (index, work) in works.indexed) {
    final text =
        cites?.apply(work.plannedPath, recorded[index]) ?? recorded[index];
    if (text != recorded[index]) {
      citedFrom[work.plannedPath] = recorded[index];
      work.changes.add(_citeChange);
    }
    final lf = layOutDoc(text, work.docType);
    if (lf != text) laidOutPaths.add(work.plannedPath);
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
                statusesOutside: statusesOutsideApproval(pins),
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
    pins: pins,
    pinsAfter: {
      ...pins,
      for (final upgrade in upgrades) upgrade.pack: upgrade.target,
    },
    restampsFingerprints: isOneTime,
    citedFrom: citedFrom,
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
      if (step is StampCodeFingerprints && codeStamp != null)
        codeStamp.stepLine(from: '$from', step: _describe(step))
      else if (step is RestampCodeFingerprints && codeRestamp != null)
        codeRestamp.stepLine(from: '$from', step: _describe(step))
      else if (index == stripIndex)
        UpgradeStepLine(
          from: '$from',
          step: _describe(step),
          paths: pathsAt(index),
          nextLine: sharedCopies?.leftLine,
        )
      else if (index == lastKeepIndex && keptLayers.isNotEmpty)
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
    prunes: prunesOf(moves),
    rewrites: [
      ...docRewrites,
      ...?tests?.fileRewrites,
      ...overrideRewrites,
      ?configRewrite,
    ],
    creates: [
      ...overrideCreates,
      ...(tests?.recordsOver(recordCreates) ?? recordCreates),
      ...mergeCreates..sort((a, b) => compareCodePoints(a.path, b.path)),
    ],
    left: const [],
    commit1Message: _commit1Message,
    commit2Message: commit2Message,
    inputs: inputs,
    rewriteLines: [
      for (final line in stepLines) ...[line.text, ?line.nextLine],
      ...linkLines,
      ?renumber?.planLine,
      ?labels?.planLine,
      ?tests?.planLine,
      ?matrixFold?.planLine,
      ?cites?.planLine,
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
      for (final path in folds.fromPaths.toList()..sort(compareCodePoints))
        projectPathOfDocPath(planned[path]!),
    ],
    lists: PlanLists(
      formatLayout: [...laidOutPaths]..sort(compareCodePoints),
      numberLabelsRewritten: labels?.pathsOn(writtenLf) ?? const [],
      numberLabelsLeft: labels?.leftOn(writtenLf) ?? const [],
      citesRewritten: cites?.paths ?? const [],
      citesLeft: cites?.leftOn(writtenLf) ?? const [],
      renumberIds: renumber?.paths ?? const [],
      agentFiles: agentFiles.listed,
      stampsSkipped: stamps.paths,
      steps: stepLines,
      mentions: mentions,
      addedPins: addedPins,
      typedByAdd: [...typedByAdd]..sort(compareCodePoints),
      tests: tests?.json,
      sharedCopies: switch (sharedCopies) {
        final step? => SharedCopiesLists(
          stripped: step.stripped,
          left: step.left,
        ),
        null => null,
      },
      matrixRows: matrixFold?.json,
      keptLayers: keptLayers,
    ),
  );
  return plan;
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

/// Plans the `stamp_code_fingerprints` step, or with [restamp] the
/// `restamp_code_fingerprints` step, over the [works] and the [recordCreates]
/// the steps before it left, each record created in [firstTarget].
///
/// A doc in [after], by DocPath, is read as that text, the stamp the restamp
/// follows having already rewritten it.
CodeStampStep _codeStampOf(
  Directory root,
  ProjectConfig config, {
  required MergedSet set,
  required List<_DocWork> works,
  required List<PlannedCreate> recordCreates,
  required String? firstTarget,
  bool restamp = false,
  Map<String, String> after = const {},
}) => CodeStampStep.plan(
  [
    for (final work in works)
      CodeStampDoc(
        docPath: work.plannedPath,
        lf: after[work.plannedPath] ?? work.lf,
        type: work.docType,
        target: work.target,
      ),
    for (final create in recordCreates)
      if (docPathOfProjectPath(create.path) case final docPath?)
        CodeStampDoc(
          docPath: docPath,
          lf: after[docPath] ?? create.text,
          type: set.recordDocType,
          target: firstTarget,
        ),
  ],
  projectRoot: Directory(root.resolveSymbolicLinksSync()),
  set: set,
  targets: config.targets,
  restamp: restamp,
);

/// Plans the test-name pass over the typed [works] as the earlier passes left
/// them in [texts], and the [recordCreates] a step of the run already makes.
TestNamePass _testNamesOf(
  Directory root,
  ProjectConfig config, {
  required MergedSet set,
  required List<_DocWork> works,
  required List<String> texts,
  required List<PlannedCreate> recordCreates,
  required bool Function(String docPath) isTaken,
}) {
  final tree = LabelTree.of(
    [
      for (final (index, work) in works.indexed)
        LabelDoc(docPath: work.plannedPath, lf: texts[index]),
    ],
    set: set,
    docTypes: {for (final work in works) work.plannedPath: ?work.docType},
  );
  return TestNamePass.plan(
    root: Directory(root.resolveSymbolicLinksSync()),
    set: set,
    targets: config.targets,
    agentFileRoots: config.agentFileRoots,
    docs: [
      for (final (index, work) in works.indexed)
        (
          plannedPath: work.plannedPath,
          type: work.docType,
          target: work.target,
          lf: texts[index],
        ),
    ],
    resolveLabel: (label) => tree.resolve(label, citingDocPath: ''),
    isTaken: isTaken,
    pendingCreates: recordCreates,
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
      readDocText(readPlanInput(File.fromUri(root.uri.resolve(layer.file)))),
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
        MoveToRecord() => file.lf,
        StampCodeFingerprints() => file.lf,
        RestampCodeFingerprints() => file.lf,
        RelinkMergedDocs() => file.lf,
        StripSharedCopies() => file.lf,
        DropSharedLines() => file.lf,
        BulletLines() => file.lf,
        DropDefaultLines() => file.lf,
        MarkRetrim() => file.lf,
        DropSection() => file.lf,
        MergeDoc() => file.lf,
        DropDocType() => file.lf,
      };
      if (renamed == file.lf) continue;
      file.lf = renamed;
      file.changedBy.add(index);
    }
    files.add(file);
  }
  return files;
}

/// Plans the `strip_shared_copies` step over [files], as the renames left
/// them, and writes the stripped text into each file it changes, which then
/// counts as changed by the step at [stripIndex].
SharedCopiesStep _sharedCopiesOf(
  List<_OverrideFile> files, {
  required int stripIndex,
  required MergedSet target,
  required List<PersonalPackFile> personalFiles,
  required MergedSet Function(Map<String, String> overrideTexts) resolveWith,
}) {
  final step = planSharedCopies(
    projectFiles: [
      for (final file in files) ProjectLayerFile(path: file.path, lf: file.lf),
    ],
    target: target,
    personalFiles: personalFiles,
    resolveWith: resolveWith,
  );
  for (final file in files) {
    if (step.rewrites[file.path] case final text?) {
      file.lf = text;
      file.changedBy.add(stripIndex);
    }
  }
  return step;
}

/// Returns the doc-type files of each personal pack among [manifests], read
/// from [home].
List<PersonalPackFile> _personalFilesOf(
  Iterable<PackManifest> manifests,
  Directory? home,
) => [
  for (final pack in loadPersonalPacks(manifests, home: home))
    for (final MapEntry(:key, :value) in pack.docTypeTexts().entries)
      PersonalPackFile(path: '${pack.displayFolder}/$key', lf: value),
];

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

/// Whether [upgrades] move a prd-core or software-tech pin from below its
/// fixed `agentFilesSince` version, whatever version the pin moves to: the one
/// trigger of every one-time pass, the label pass among them.
bool runsOneTimePasses(List<PackUpgrade> upgrades) =>
    upgrades.any((upgrade) => isBelowSince(upgrade, agentFilesSince));

/// Plans the renumber pass over every doc of [works], typed or not.
RenumberPass _renumberPassOf(List<_DocWork> works) => RenumberPass.plan([
  for (final work in works)
    (docPath: work.plannedPath, lf: work.lf, type: work.docType),
]);

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

  /// The LF text after the steps and link rewrites, and any record entries
  /// the `move_to_record` step adds to a record doc.
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
  final original = readDocText(
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
    text: writtenText(original, text),
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
  final original = readDocText(
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

/// Throws `override_dangling` at [override]'s file, one fault per record, when
/// a record doc a `move_file` step of [steps] moves, as [movedBy] gives, lands
/// outside the override path, since the two paths hold different placeholders.
void _refuseStrandedRecords(
  RecordPathOverride override, {
  required Map<String, int> movedBy,
  required List<PackStep> steps,
}) {
  final stranded = [
    for (final MapEntry(key: docPath, value: index) in movedBy.entries)
      if (override.strands(steps[index].step)) docPath,
  ]..sort(compareCodePoints);
  final faults = [
    for (final docPath in stranded)
      MigrateFault(
        MigrateFaultCode.overrideDangling,
        'the record $docPath cannot move to the record override path '
        '${override.path}, whose placeholders differ; move each record '
        'beside its architecture doc, then run specstone migrate again',
        file: override.file,
        key: 'path',
      ),
  ];
  if (faults.isEmpty) return;
  final first = faults.first;
  throw MigrateFault(
    first.code,
    first.message,
    file: first.file,
    key: first.key,
    more: faults.sublist(1),
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
    final at = caseBlindPath(destination);
    // A stayer holds its ground: the mover's destination is its own path.
    final stayer = docPaths.any(
      (path) => caseBlindPath(path) == at && !isMoved(path),
    );
    // Another mover with the same final path: each fault names the other. A
    // stayer never counts; it is the stayer fault below.
    final rivals = docPaths.where(
      (path) =>
          path != source &&
          isMoved(path) &&
          caseBlindPath(planned[path]!) == at,
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
  MoveToRecord() =>
    '${step.kind} ${step.docTypes.join(', ')} ${step.fields.join(', ')} '
        '-> ${step.to}',
  StampCodeFingerprints() => step.kind,
  RestampCodeFingerprints() => step.kind,
  RelinkMergedDocs() => step.kind,
  StripSharedCopies() => step.kind,
  DropSharedLines() => step.kind,
  BulletLines() => '${step.kind} ${step.docType} ${step.section}',
  DropDefaultLines() => step.kind,
  MarkRetrim() => step.kind,
  DropSection() => '${step.kind} ${step.docTypes.join(', ')} ${step.sectionId}',
  MergeDoc() => '${step.kind} ${step.fromId} -> ${step.toId}',
  DropDocType() => '${step.kind} ${step.id}',
};

/// Returns [lf] of the doc at [plannedPath] without the default lines of its
/// invariants.
///
/// The default enforcer comes from the pre-run text of the doc and of each
/// ancestor twin, nearest first, kept only when it has the doc's own type and
/// target, so a project domain never feeds a feature domain. An Enforcer line
/// goes only while the merged `Enforcer` entry holds `default_from`, and a
/// Consistency line only while the merged `Consistency` entry is optional and
/// lists no `immediate`.
String _withDefaultLinesDropped(
  String lf, {
  required MergedDocType docType,
  required String plannedPath,
  required String? target,
  required DocTypeMatch Function(String plannedPath) typeAt,
  required Map<String, String> preRunTexts,
}) {
  final invariants = docType.sections
      .where((section) => section.id == _invariantsSectionId)
      .firstOrNull;
  if (invariants == null) return lf;
  final entities = docType.sections
      .where((section) => section.id == _entitiesSectionId)
      .firstOrNull;
  final twinTexts = [
    for (final path in ancestorTwinPaths(plannedPath))
      if (typeAt(path)
          case MatchedDocType(
            docType: MergedDocType(:final id),
            target: final twinTarget,
          )
          when id == docType.id && twinTarget == target)
        ?preRunTexts[path],
  ];
  final fields = invariants.itemFields ?? const <ItemFieldLint>[];
  final enforcer = fields.where((f) => f.field == _enforcerField).firstOrNull;
  final consistency = fields
      .where((f) => f.field == _consistencyField)
      .firstOrNull;
  return withDefaultLinesDropped(
    lf,
    invariantsHeader: invariants.header,
    defaultEnforcer: entities == null || enforcer?.defaultFrom == null
        ? null
        : defaultEnforcerAmong([
            lf,
            ...twinTexts,
          ], entitiesHeader: entities.header),
    dropsConsistency:
        consistency != null &&
        consistency.optional &&
        !(consistency.values?.contains(_immediateValue) ?? false),
  );
}

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
