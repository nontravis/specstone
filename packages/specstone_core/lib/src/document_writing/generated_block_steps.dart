import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/records_root.dart'
    show docPathOfProjectPath, fileOfDocPath, projectPathOfDocPath;
import 'package:specstone_core/src/document_writing/journal_bounds.dart'
    show requireWritableTarget;
import 'package:specstone_core/src/document_writing/models/path_move.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/moved_paths.dart'
    show movedPath;
import 'package:specstone_core/src/document_writing/root_trust.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_words.dart'
    show itemIdPrefixesOf;
import 'package:specstone_core/src/rendering/doc_reader.dart';
import 'package:specstone_core/src/rendering/doc_tree.dart' show DocFile;
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/format_run.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/rendering/models/line_ending.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

// MARK: - Models

/// The docs one write leaves, as the block refresh reads them.
final class WrittenDocs {
  const new({this.texts = const {}, this.removed = const {}});

  /// The LF text of each doc the write writes or creates, by DocPath.
  final Map<String, String> texts;

  /// Each DocPath the write moves away or deletes; a move also holds its doc's
  /// text at the new DocPath in [texts].
  final Set<String> removed;

  bool get isEmpty => texts.isEmpty && removed.isEmpty;
}

/// What one write adds so that no generated block it makes stale stays so.
final class BlockRefresh {
  const new({
    required this.steps,
    required this.ownTexts,
    required this.docPaths,
    required this.deletedPaths,
    required this.refused,
  });

  /// A refresh that changes nothing.
  static const none = BlockRefresh(
    steps: [],
    ownTexts: {},
    docPaths: [],
    deletedPaths: [],
    refused: [],
  );

  /// The journal steps that write the docs the command does not write itself.
  final List<JournalStep> steps;

  /// The filled LF text of each doc the command writes whose blocks change,
  /// by DocPath; it replaces the command's own text.
  final Map<String, String> ownTexts;

  /// Each doc a step or an own text writes or creates beyond the command's own
  /// change, in tree order.
  final List<String> docPaths;

  /// Each doc a step moves to the trash, as `format` deletes an emptied
  /// group's features doc, in tree order.
  final List<String> deletedPaths;

  /// One warning line per doc `format` refuses or skips unread; such a doc
  /// keeps its bytes.
  final List<String> refused;

  /// The reply's JSON keys: `rewritten` for [docPaths], `deleted` for
  /// [deletedPaths].
  Map<String, List<String>> get json => {
    'rewritten': docPaths,
    'deleted': deletedPaths,
  };

  /// Returns one `rewrote` line per doc of [docPaths], then one `deleted` line
  /// per doc of [deletedPaths]; `rewrites` and `deletes` under [dryRun].
  String linesOf({bool dryRun = false}) => [
    for (final docPath in docPaths)
      '${dryRun ? 'rewrites' : 'rewrote'} $docPath\n',
    for (final docPath in deletedPaths)
      '${dryRun ? 'deletes' : 'deleted'} $docPath\n',
  ].join();
}

/// A move's own rewrite and create steps once a [BlockRefresh] filled them.
final class RefreshedMoveSteps {
  const new({required this.rewrites, required this.creates});

  /// The move's rewrites in their order, each own text in, then a rewrite of
  /// each moved doc only the refresh changes.
  final List<WriteStep> rewrites;

  /// The move's creates in their order, each own text in.
  final List<CreateStep> creates;
}

// MARK: - Planning

/// Returns the refresh of the generated blocks the write of [written] makes
/// stale, planned under [session]'s lock before its journal runs.
///
/// Every doc whose type lists generators is planned, each written one from
/// [written], the rest from disk, through the plan `format` makes, so a
/// grouped features doc brings its companions. Only the generated blocks of a
/// doc change: a doc whose only drift is its layout is left as it is. An empty
/// [generators] plans nothing.
/// Throws [RenderFault] `output_not_writable` before any file changes for a
/// path a step writes, creates, moves to the trash, or prunes that leads
/// outside the project or below `.git`, a read-only doc a step writes, and a
/// create whose path is taken; under [dryRun], which writes nothing, never for
/// roots the Owner's trust record does not cover.
BlockRefresh blockRefreshOf(
  WriteSession session,
  GeneratorRegistry<DocIndex> generators,
  WrittenDocs written, {
  bool dryRun = false,
}) => _plannedRefresh(
  session.project,
  session.index,
  generators,
  written,
  trust: dryRun ? null : session.project.trust,
);

/// Returns the refresh a dry run of [blockRefreshOf] plans, read through
/// [index] and [project] alone, so a read-session dry run plans and checks it
/// alike; it never refuses for a missing trust record.
BlockRefresh planBlockRefresh(
  DocsProject project,
  DocIndex index,
  GeneratorRegistry<DocIndex> generators,
  WrittenDocs written,
) => _plannedRefresh(project, index, generators, written, trust: null);

/// Returns the refresh of [written], each step checked writable under [trust];
/// a null [trust] checks the bounds and read-only marks alone.
BlockRefresh _plannedRefresh(
  DocsProject project,
  DocIndex index,
  GeneratorRegistry<DocIndex> generators,
  WrittenDocs written, {
  required RootTrust? trust,
}) {
  final hasGenerators = index.set.docTypes.any(
    (type) => type.listedGenerators.any(generators.kinds.contains),
  );
  if (written.isEmpty || !hasGenerators) return BlockRefresh.none;
  final after = _indexAfter(project, index, written);
  final reads = [
    for (final doc in after.docs)
      if (after.typeOf(doc) case final type?
          when type.listedGenerators.isNotEmpty)
        _readOf(project, doc.docPath, type, written.texts[doc.docPath]),
  ];
  if (reads.isEmpty) return BlockRefresh.none;
  final plan = planFormatWrites(
    project,
    reads,
    generators,
    after,
    gone: written.removed,
  );
  final refresh = _Refresh(project, generators, after, written, reads).of(plan);
  for (final step in refresh.steps) {
    _requireWritable(project, step, trust);
  }
  return refresh;
}

/// Returns [index] as [written] leaves it.
DocIndex _indexAfter(DocsProject project, DocIndex index, WrittenDocs written) {
  final targets = project.targets;
  final singleTarget = targets.length == 1 ? targets.single.name : null;
  final prefixes = itemIdPrefixesOf(project.set.docTypes);
  final parsed = [
    for (final MapEntry(key: docPath, value: lf) in written.texts.entries)
      parseIndexedDoc(
        docPath: docPath,
        bytes: utf8.encode(lf),
        match: project.matcher.match(docPath),
        codeTarget: singleTarget,
        idPrefixes: prefixes,
      ),
  ];
  return index.withWritten(
    [for (final doc in parsed) doc.doc],
    contents: {for (final doc in parsed) doc.doc.docPath: doc.content},
    removed: written.removed,
  );
}

/// Returns the read of [docPath]: [lf] when the write gives it, else the file.
DocRead _readOf(
  DocsProject project,
  String docPath,
  MergedDocType type,
  String? lf,
) {
  final file = fileOfDocPath(
    docPath,
    docsRoot: project.docsRoot,
    projectRoot: project.projectRoot,
  );
  if (lf == null) return readDoc(project, DocFile(file, docPath));
  return ReadableDoc(
    file,
    projectPathOfDocPath(docPath),
    docPath: docPath,
    text: lf,
    lineEnding: LineEnding.lf,
    hasBom: false,
    docType: type,
    doc: Doc.parse(lf),
  );
}

/// Splits a format plan into the texts of the docs a write holds and the steps
/// of every other doc, each rewrite filling only the generated blocks.
final class _Refresh {
  new(this._project, this._generators, this._after, this._written, this._reads);

  final DocsProject _project;
  final GeneratorRegistry<DocIndex> _generators;
  final DocIndex _after;
  final WrittenDocs _written;
  final List<DocRead> _reads;

  late final Map<String, ReadableDoc> _readByPath = {
    for (final read in _reads.whereType<ReadableDoc>()) read.path: read,
  };

  BlockRefresh of(FormatWritePlan plan) {
    final ownTexts = <String, String>{};
    final rewrites = <WriteStep>[];
    final changed = <String>{};
    for (final path in plan.rewrites.keys) {
      final source = _sourceAt(path);
      if (source == null) continue;
      final lf = _written.texts[source.docPath] ?? toLf(source.text);
      final filled = fillGeneratedBlocks(
        lf,
        source.docType,
        _generators,
        _after,
        docPath: source.docPath,
      );
      if (filled == lf) continue;
      changed.add(source.docPath);
      if (_written.texts.containsKey(source.docPath)) {
        ownTexts[source.docPath] = filled;
      } else {
        rewrites.add(
          WriteStep(
            path,
            _inFormOf(_withBom(source), filled),
            before: textHashOf(source.text),
          ),
        );
      }
    }
    // A delete goes even when the command writes the doc too: its trash step
    // runs after the command's own write.
    final created = [
      for (final path in plan.creates.keys)
        if (!_written.texts.containsKey(_docPathOf(path))) path,
    ];
    changed.addAll(created.map(_docPathOf));
    final deleted = {for (final path in plan.deletes) _docPathOf(path)};
    return BlockRefresh(
      steps: [
        ...rewrites,
        ...plan.stepsFor({...created, ...plan.deletes}),
      ],
      ownTexts: ownTexts,
      docPaths: _after.inTreeOrder(changed.difference(deleted)),
      deletedPaths: _after.inTreeOrder(deleted),
      refused: [
        for (final read in _reads) ?_skippedWarningOf(read),
        for (final result in plan.blocked) _refusedLineOf(result),
        ...plan.warnings,
      ],
    );
  }

  /// Returns the read the plan rewrote at [path]: the run's own, else a
  /// companion's from disk.
  ReadableDoc? _sourceAt(String path) {
    if (_readByPath[path] case final read?) return read;
    final docPath = _docPathOf(path);
    final read = readDoc(
      _project,
      DocFile(
        fileOfDocPath(
          docPath,
          docsRoot: _project.docsRoot,
          projectRoot: _project.projectRoot,
        ),
        docPath,
      ),
    );
    return read is ReadableDoc ? read : null;
  }

  static String _docPathOf(String path) => docPathOfProjectPath(path) ?? path;

  static String _withBom(ReadableDoc read) =>
      '${read.hasBom ? byteOrderMark : ''}${read.text}';
}

/// Returns the warning of a doc of the run that `format` skips unread, as its
/// own run warns; the plan leaves such a doc out.
String? _skippedWarningOf(DocRead read) => switch (read) {
  UnmatchedDoc(:final warning) ||
  NotUtf8Doc(:final warning) ||
  UnreadableDoc(:final warning) => warning,
  AmbiguousDoc() || ReadableDoc() => null,
};

String _refusedLineOf(FileResult result) =>
    '${result.path} cannot be written by format: ${result.reasons}; '
    'left as it was';

/// Throws [RenderFault] `output_not_writable` when [step] could not run as
/// planned under [trust], so the journal never starts.
///
/// Every path a step touches is judged as the journal judges it: inside the
/// project or docs root, below no `.git` entry. A write's file is followed
/// through links, as the write follows them; a create's new file through its
/// folders; a trash move's source and a pruned folder by their folder alone,
/// since the journal moves a link itself.
void _requireWritable(DocsProject project, JournalStep step, RootTrust? trust) {
  void requireInBounds(String projectPath) => requireWritableTarget(
    _onDisk(project, projectPath),
    projectRoot: project.projectRoot,
    docsRoot: project.docsRoot,
    trust: trust,
  );
  switch (step) {
    case WriteStep(:final path):
      requireInBounds(path);
      requireNotReadOnly(
        File(_onDisk(project, path)),
        docPathOfProjectPath(path) ?? path,
      );
    case CreateStep(:final path):
      if (FileSystemEntity.typeSync(
            _onDisk(project, path),
            followLinks: false,
          ) !=
          FileSystemEntityType.notFound) {
        throw RenderFault(
          RenderFaultCode.outputNotWritable,
          'cannot create ${docPathOfProjectPath(path) ?? path}: a file is '
          'there',
        );
      }
      requireInBounds(path);
    case MoveStep(:final from):
      requireInBounds(_folderOf(from));
    case PruneStep(:final folder):
      requireInBounds(_folderOf(folder));
    // A commit touches no path of the docs; a refresh plans none.
    case CommitStep():
      break;
  }
}

/// Returns the folder that holds [projectPath], a path from the project root.
String _folderOf(String projectPath) =>
    projectPath.substring(0, projectPath.lastIndexOf('/'));

/// Returns [projectPath], a path from the project root, on disk.
String _onDisk(DocsProject project, String projectPath) => [
  project.projectRoot.path,
  ...projectPath.split('/'),
].join(Platform.pathSeparator);

// MARK: - Moves

/// Returns what a move of [moves] leaves: each doc under a move at its new
/// DocPath, holding the text [rewrites] or [creates] give it, else its own,
/// and each DocPath it leaves.
WrittenDocs movedDocsOf(
  WriteSession session,
  List<PathMove> moves, {
  List<WriteStep> rewrites = const [],
  List<CreateStep> creates = const [],
}) {
  final texts = <String, String>{};
  final removed = <String>{};
  for (final doc in session.index.docs) {
    final landed = movedPath(doc.docPath, moves);
    if (landed == doc.docPath) continue;
    removed.add(doc.docPath);
    texts[landed] = _lfOf(session.index.contentOf(doc).text);
  }
  for (final step in rewrites) {
    texts[session.listedPathOf(step.path)] = _lfOf(step.text);
  }
  for (final step in creates) {
    texts[session.listedPathOf(step.path)] = _lfOf(step.text);
  }
  return WrittenDocs(texts: texts, removed: removed);
}

/// Returns [rewrites] and [creates] with each own text of [refresh] in, in
/// the line ending and byte order mark each step writes, and a rewrite of
/// each moved doc whose own text no step of the move writes.
RefreshedMoveSteps withOwnTexts(
  WriteSession session,
  BlockRefresh refresh,
  List<PathMove> moves, {
  List<WriteStep> rewrites = const [],
  List<CreateStep> creates = const [],
}) {
  final left = {...refresh.ownTexts};
  final filledRewrites = [
    for (final step in rewrites)
      switch (left.remove(session.listedPathOf(step.path))) {
        final lf? => _rewriteWith(step, _inFormOf(step.text, lf)),
        null => step,
      },
  ];
  final filledCreates = [
    for (final step in creates)
      switch (left.remove(session.listedPathOf(step.path))) {
        final lf? => CreateStep(step.path, _inFormOf(step.text, lf)),
        null => step,
      },
  ];
  return RefreshedMoveSteps(
    rewrites: [
      ...filledRewrites,
      for (final MapEntry(key: docPath, value: lf) in left.entries)
        _movedRewriteOf(session, moves, docPath, lf),
    ],
    creates: filledCreates,
  );
}

/// Returns the rewrite of the doc a move lands at [docPath] to [lf], guarded
/// by the text its file holds before the move.
///
/// Throws [RenderFault] `output_not_writable` when that file is read-only.
WriteStep _movedRewriteOf(
  WriteSession session,
  List<PathMove> moves,
  String docPath,
  String lf,
) {
  final source = session.index.docs.firstWhere(
    (doc) => movedPath(doc.docPath, moves) == docPath,
    orElse: () => throw StateError('no doc of the move lands at $docPath'),
  );
  final bytes =
      session.readDocBytes(source.docPath) ??
      (throw RenderFault(
        RenderFaultCode.outputNotWritable,
        'cannot write $docPath: ${source.docPath} is gone',
      ));
  // The journal skips a read-only file's write, which would leave its block
  // stale after the move: the move refuses before it starts instead.
  requireNotReadOnly(session.fileOf(source.docPath), source.docPath);
  return session.docWriteStep(docPath, lf, bytes);
}

WriteStep _rewriteWith(WriteStep step, String text) => switch (step.before) {
  final before? => WriteStep(
    step.path,
    text,
    before: before,
    keepsApprovedCopy: step.keepsApprovedCopy,
  ),
  null => WriteStep.unguarded(step.path, text),
};

/// Returns [lf] in the line ending and byte order mark of [text].
String _inFormOf(String text, String lf) {
  final bom = text.startsWith(byteOrderMark) ? byteOrderMark : '';
  return '$bom${LineEnding.of(text).apply(lf)}';
}

String _lfOf(String text) =>
    toLf(text.startsWith(byteOrderMark) ? text.substring(1) : text);
