import 'dart:io';

import 'package:specstone_core/src/doc_model/default_enforcer.dart'
    show ancestorTwinPaths;
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart' show withKeyBlock;
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/doc_model/path_pattern.dart';
import 'package:specstone_core/src/doc_model/records_root.dart';
import 'package:specstone_core/src/document_writing/models/path_move.dart';
import 'package:specstone_core/src/document_writing/stale_mentions.dart'
    show MentionScope, StaleMention, staleMentionsIn;
import 'package:specstone_core/src/index_query/indexed_doc.dart'
    show IndexedDoc;
import 'package:specstone_core/src/index_query/item_words.dart'
    show itemIdPrefixesOf;
import 'package:specstone_core/src/plan_hash.dart';
import 'package:specstone_core/src/release_version.dart' show ReleaseVersion;
import 'package:specstone_core/src/rendering/formatter.dart' show layOutDoc;
import 'package:specstone_core/src/setup_migration/agent_targets.dart';
import 'package:specstone_core/src/setup_migration/bullet_lines_step.dart';
import 'package:specstone_core/src/setup_migration/cite_pass.dart';
import 'package:specstone_core/src/setup_migration/code_stamp_step.dart';
import 'package:specstone_core/src/setup_migration/dangling_overrides.dart';
import 'package:specstone_core/src/setup_migration/drop_default_lines_step.dart';
import 'package:specstone_core/src/setup_migration/label_pass.dart';
import 'package:specstone_core/src/setup_migration/legacy_moves.dart'
    show caseBlindPath;
import 'package:specstone_core/src/setup_migration/legacy_plan.dart'
    show prunesOf;
import 'package:specstone_core/src/setup_migration/legacy_rewrites.dart';
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/setup_migration/migration_chain.dart';
import 'package:specstone_core/src/setup_migration/models/label_doc.dart'
    show LabelDoc;
import 'package:specstone_core/src/setup_migration/models/label_tree.dart'
    show LabelTree;
import 'package:specstone_core/src/setup_migration/project_files.dart';
import 'package:specstone_core/src/setup_migration/record_placement.dart';
import 'package:specstone_core/src/setup_migration/renumber_pass.dart';
import 'package:specstone_core/src/setup_migration/run_plan.dart';
import 'package:specstone_core/src/setup_migration/skill_agent_files.dart'
    show shipsSkillFiles;
import 'package:specstone_core/src/setup_migration/stamp_pass.dart';
import 'package:specstone_core/src/setup_migration/test_name_pass.dart';
import 'package:specstone_core/src/setup_migration/tree_move.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/code_target.dart' show twinNamesOf;
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/layer_source.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/nested_paths.dart'
    show movePatternsAtEveryDepth;
import 'package:specstone_core/src/templates/pack_migration.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/project_config.dart';
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
const _labelChange = 'convert number labels';
const _stampChange = 'stamp approvals';
const _recordChange = 'add record entries';
const _testsChange = 'add test lines';
const _codeStampChange = 'stamp code fingerprints';
const _codeRestampChange = 'restamp code fingerprints';
const _citeChange = 'convert cites';
const _invariantsSectionId = 'invariants';
const _entitiesSectionId = 'entities';
const _enforcerField = 'Enforcer';
const _consistencyField = 'Consistency';
const _immediateValue = 'immediate';

typedef _Step = ({PackVersion from, MigrationStep step});

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
RunPlan planUpgradeRun(
  Directory root, {
  required TemplateResolver templates,
  required Directory? homeDirectory,
}) {
  final inputs = PlanInputs(root);
  return inputs.collect(
    () => _upgradeRunOf(
      root,
      templates: templates,
      homeDirectory: homeDirectory,
      inputs: inputs,
    ),
  )..refuseTakenCreates(root);
}

/// Plans the upgrade of [root] while [inputs] records each file read.
RunPlan _upgradeRunOf(
  Directory root, {
  required TemplateResolver templates,
  required Directory? homeDirectory,
  required PlanInputs inputs,
}) {
  final config = ProjectConfig.read(root);
  final pins = config.pins;
  final available = templates.availableManifests(
    pins.keys,
    homeDirectory: homeDirectory,
  );
  final upgrades = selectUpgrades(pins, available);
  final overrides = loadProjectTemplates(root);
  final targetSet = templates.resolveCarried(
    packNames: pins.keys,
    homeDirectory: homeDirectory,
  );
  refuseDanglingOverrides(
    overrides,
    target: targetSet,
    targetVersions: {
      for (final entry in available.entries) entry.key: entry.value.version,
    },
    upgrades: upgrades,
  );

  final steps = [for (final upgrade in upgrades) ...upgrade.steps];
  final stepKinds = [for (final entry in steps) entry.step];
  final overrideFiles = _renamedOverrides(root, overrides, steps);
  final overrideCreates = [
    if (recordPathOverrideOf(stepKinds, overrides: overrides, target: targetSet)
        case RecordPathOverride(:final file, path: final path?))
      PlannedCreate(path: file, text: 'path: $path\n'),
  ];
  final finalSet = templates.resolveCarried(
    packNames: pins.keys,
    homeDirectory: homeDirectory,
    projectLayers: parseOverrides({
      for (final file in overrideFiles) file.path: file.lf,
      for (final create in overrideCreates) create.path: create.text,
    }),
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
      for (final (:step, from: _) in steps)
        if (step is MoveFile && _isPerTargetStep(step, finalSet, firstTarget))
          for (final pair in _movePatternsOf(step, finalSet)) pair.from,
    ],
  );
  final (:planned, :movedAt, :movedBy, :treeMoved) = _plannedPaths(
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
  final recordMoves = RecordMoves();
  final works = <_DocWork>[];
  final changedAt = <int, List<String>>{};
  final linkLines = <String>[];
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
  for (final path in docPaths) {
    final plannedPath = planned[path]!;
    final original = originals[path];
    if (original == null) continue;
    final match = matcher.match(plannedPath);
    final docType = match is MatchedDocType ? match.docType : null;
    final target = match is MatchedDocType ? match.target : null;
    var lf = original.lf;
    final changes = <String>[];
    for (final (index, (:step, from: _)) in steps.indexed) {
      if (docType == null || !step.touches(docType.id)) continue;
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
          matcher: matcher,
          preRunTexts: preRunTexts,
        ),
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
          BulletLines() => false,
          DropDefaultLines() => false,
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
            BulletLines() => '',
            DropDefaultLines() => '',
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
      final mentions = rewriteMentions(
        links.lf,
        docPath: path,
        moves: moves,
        exists: (docPath) => _existsIn(docsRoot, root, docPath),
      );
      lf = mentions.lf;
      final labels = [?links.label, ?mentions.label];
      if (labels.isNotEmpty) {
        changes.addAll(labels);
        linkLines.add('$plannedPath: ${labels.join(', ')}');
      }
    }
    works.add(_DocWork(plannedPath, original, docType, target, lf, changes));
  }
  throwFaultsPerDoc([...moveCollisions, ...renameCollisions]);
  final taken = takenAfterMoves(root, moves);
  final placement = recordMoves.place(
    set: finalSet,
    recordType: finalSet.recordDocType,
    firstTarget: firstTarget,
    isTaken: (docPath) => taken(projectPathOfDocPath(docPath)),
    docs: [
      for (final work in works)
        (
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
  final recorded = <String>[];
  for (final (index, work) in works.indexed) {
    var text = converted[index];
    if (tests?.recordEdits[work.plannedPath] case final edited?) {
      text = edited;
      work.changes.add(_testsChange);
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
        (
          docPath: work.plannedPath,
          lf: work.original.lf,
          type: switch (work.docType) {
            final type? => typeBeforeMoves(type, stepKinds),
            null => null,
          },
        ),
    ],
    [
      for (final (index, work) in works.indexed)
        (docPath: work.plannedPath, lf: laidOut[index], type: work.docType),
    ],
    pins: pins,
    pinsAfter: {
      ...pins,
      for (final upgrade in upgrades) upgrade.pack: upgrade.target,
    },
    restampsFingerprints: isOneTime,
    citedFrom: citedFrom,
  );
  final docRewrites = <PlannedRewrite>[];
  final writtenLf = <String, String>{};
  for (final (index, work) in works.indexed) {
    final lf = stamps.apply(work.plannedPath, laidOut[index]);
    writtenLf[work.plannedPath] = lf;
    if (lf != laidOut[index]) work.changes.add(_stampChange);
    if (lf == work.original.lf) continue;
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
    agentFileRoots: agentFiles.addedRoots.isEmpty
        ? null
        : agentFiles.agentFileRoots,
    agentFilesVersion: _stampOf(
      agentInputs,
      agentFiles,
      config,
      isConfigWritten: upgrades.isNotEmpty || !agentFiles.isEmpty,
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

  final stepLines = [
    for (final (index, (:from, :step)) in steps.indexed)
      if (step is StampCodeFingerprints && codeStamp != null)
        codeStamp.stepLine(from: '$from', step: _describe(step))
      else if (step is RestampCodeFingerprints && codeRestamp != null)
        codeRestamp.stepLine(from: '$from', step: _describe(step))
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

  final mentions = _staleMentionsOf(
    root,
    config,
    set: finalSet,
    docPaths: docPaths,
    moves: moves,
  );
  final arePinsUnchanged = upgrades.isEmpty;
  final (:header, :commit2Message) = arePinsUnchanged
      ? _pinsUnchangedTitles(
          laysOut: laidOutPaths.isNotEmpty,
          writesAgentFiles: !agentFiles.isEmpty,
          treeMovesTo: treeMoves.isEmpty ? null : firstTarget,
        )
      : (
          header: 'pack upgrade: ${upgraded.join(', ')}',
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
    ],
    left: const [],
    commit1Message: _commit1Message,
    commit2Message: commit2Message,
    inputs: inputs,
    rewriteLines: [
      for (final line in stepLines) line.text,
      ...linkLines,
      ?renumber?.planLine,
      ?labels?.planLine,
      ?tests?.planLine,
      ?cites?.planLine,
      ?formatLayoutLine(laidOutPaths),
      ?stamps.planLine,
      if (agentFiles.line.isNotEmpty) agentFiles.line,
      ?mentionsLine(mentions),
      if (!arePinsUnchanged) '$projectConfigPath: ${pinned.join(', ')}',
    ],
    agentFiles: agentFiles,
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
      tests: tests?.json,
    ),
  );
  return plan;
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
      (
        docPath: work.plannedPath,
        lf: after[work.plannedPath] ?? work.lf,
        type: work.docType,
        target: work.target,
      ),
    for (final create in recordCreates)
      if (docPathOfProjectPath(create.path) case final docPath?)
        (
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

/// Returns the plan header and commit 2 message of a run that moves no pin.
///
/// A run that moves the spec tree to [treeMovesTo] is titled by that move,
/// whatever else it writes; a run with neither the layout pass nor an agent
/// file write is titled as layout only.
({String header, String commit2Message}) _pinsUnchangedTitles({
  required bool laysOut,
  required bool writesAgentFiles,
  required String? treeMovesTo,
}) => switch ((laysOut, writesAgentFiles)) {
  _ when treeMovesTo != null => (
    header: 'pack upgrade: pins unchanged, spec tree to $treeMovesTo',
    commit2Message: _treeMoveCommit2Message,
  ),
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
      readDocText(readPlanInput(File.fromUri(root.uri.resolve(layer.file)))),
    );
    for (final (index, (:step, from: _)) in steps.indexed) {
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
        BulletLines() => file.lf,
        DropDefaultLines() => file.lf,
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
    this.changes,
  );

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
}

/// Returns the rewrite of `config.yaml` that moves the pins of [upgrades] and
/// sets `agent_file_roots` to [agentFileRoots] and `agent_files_version` to
/// [agentFilesVersion] when each is not null, every other byte kept, or null
/// when none changes.
PlannedRewrite? _configRewriteOf(
  Directory root,
  List<PackUpgrade> upgrades, {
  required List<String>? agentFileRoots,
  required ReleaseVersion? agentFilesVersion,
}) {
  if (upgrades.isEmpty && agentFileRoots == null && agentFilesVersion == null) {
    return null;
  }
  final original = readDocText(
    readPlanInput(File.fromUri(root.uri.resolve(projectConfigPath))),
  );
  final packs =
      (loadYamlNode(original.lf) as YamlMap).nodes['packs']! as YamlMap;
  var text = _withScalarsReplaced(original.lf, [
    for (final upgrade in upgrades)
      (packs.nodes[upgrade.pack]! as YamlScalar, '${upgrade.target}'),
  ]);
  if (agentFileRoots != null) text = _withAgentFileRoots(text, agentFileRoots);
  if (agentFilesVersion != null) {
    text = _withAgentFilesVersion(text, agentFilesVersion);
  }
  return PlannedRewrite(
    path: projectConfigPath,
    text: writtenText(original, text),
    before: original.hash,
    changes: [
      if (upgrades.isNotEmpty) 'pins',
      if (agentFileRoots != null) _agentFileRootsKey,
      if (agentFilesVersion != null) _agentFilesVersionKey,
    ],
  );
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
List<({String from, String to})> _movePatternsOf(MoveFile step, MergedSet set) {
  final nesting = set.nestingType;
  if (nesting == null || set.lookup(step.docType)?.nestedPaths == null) {
    return [(from: step.from, to: step.to)];
  }
  return movePatternsAtEveryDepth(step.from, step.to, nesting);
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
({
  Map<String, String> planned,
  Map<int, List<String>> movedAt,
  Map<String, int> movedBy,
  Set<String> treeMoved,
})
_plannedPaths(
  List<String> docPaths,
  List<_Step> steps, {
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
  for (final (index, (:step, from: _)) in steps.indexed) {
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
  return (
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
  required List<_Step> steps,
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
  BulletLines() => '${step.kind} ${step.docType} ${step.section}',
  DropDefaultLines() => step.kind,
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
  required DocTypeMatcher matcher,
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
      if (matcher.match(path)
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
