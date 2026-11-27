import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/atomic_write.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart' show docsFolderName;
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/doc_model/records_root.dart'
    show docPathOfProjectPath;
import 'package:specstone_core/src/document_writing/approval.dart'
    show withApprovalHash;
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/rendering/doc_reader.dart';
import 'package:specstone_core/src/rendering/doc_tree.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/formatter.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/rendering/models/opened_resolver.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// What a format run did with one doc.
enum FileStatus {
  /// Changed, or under `check` would change.
  formatted,

  /// Already matches its template, line endings aside.
  unchanged,

  /// Not a doc the run can work on; a warning says why.
  skipped,

  /// Left alone because its headers or doc types are ambiguous.
  refused,

  /// A group doc the run wrote that did not exist; never listed under `check`.
  created,

  /// A group doc the run removed, or under `check` would remove.
  deleted,
}

/// The outcome of one doc in a [FormatReport].
final class FileResult {
  const new({
    required this.path,
    required this.status,
    this.unknownHeaders = const [],
    this.duplicateHeaders = const [],
    this.docTypes = const [],
    this.unclosedFence = false,
    this.openBlock,
    this.openBlockKind,
    this.changesStructure = false,
    this.unreadable = false,
    this.misplaced = false,
  });

  /// The doc's path, relative to the project root.
  final String path;

  /// What the run did with the doc.
  final FileStatus status;

  /// Headers the template does not define, as written.
  final List<String> unknownHeaders;

  /// Headers that occur more than once, in template form.
  final List<String> duplicateHeaders;

  /// The doc types its path matches, when two or more do.
  final List<String> docTypes;

  /// Whether the doc ends inside a fenced code block.
  final bool unclosedFence;

  /// The opening marker, as written, of a generated block with no end marker.
  final String? openBlock;

  /// The generator kind that [openBlock] names.
  final String? openBlockKind;

  /// Whether laying the doc out would change its frontmatter or its sections.
  final bool changesStructure;

  /// Whether a listed companion's path holds a file that is no readable doc of
  /// its type, so the group it belongs to is not written.
  final bool unreadable;

  /// Whether a listed companion's path is no path of its own doc type under
  /// the docs root, so the group it belongs to is not written.
  final bool misplaced;

  /// Returns the wire form; `path` is the docs-root path for a doc and the
  /// project path for a record. A list prints only when it is not empty,
  /// `unclosedFence`, `changesStructure`, `unreadable`, and `misplaced` only
  /// when true, and `openBlock` only when set.
  Map<String, Object> toJson() => {
    'path': docPathOfProjectPath(path) ?? path,
    'status': status.name,
    if (unknownHeaders.isNotEmpty) 'unknownHeaders': unknownHeaders,
    if (duplicateHeaders.isNotEmpty) 'duplicateHeaders': duplicateHeaders,
    if (docTypes.isNotEmpty) 'docTypes': docTypes,
    if (unclosedFence) 'unclosedFence': true,
    'openBlock': ?openBlock,
    if (changesStructure) 'changesStructure': true,
    if (unreadable) 'unreadable': true,
    if (misplaced) 'misplaced': true,
  };

  /// Why the doc is refused: each reason, joined by `; `.
  String get reasons => [
    for (final header in unknownHeaders) 'unknown header "$header"',
    for (final header in duplicateHeaders) 'duplicate header "$header"',
    if (docTypes.isNotEmpty) 'doc types ${docTypes.join(', ')} match this path',
    if (unclosedFence) 'unclosed code fence',
    if (openBlockKind != null) 'open generated block $openBlockKind',
    if (changesStructure) 'layout would change the doc structure',
    if (unreadable) 'cannot be read as a doc',
    if (misplaced) 'not a path of its doc type under the docs root',
  ].join('; ');
}

/// The result of a format run, in tree order.
final class FormatReport {
  const new({required this.check, required this.files, required this.warnings});

  /// Whether the run only checked and wrote nothing.
  final bool check;

  /// Every doc the run visited.
  final List<FileResult> files;

  /// Warnings as plain message text.
  final List<String> warnings;

  /// 1 when a doc is refused, or under [check] a doc would change or go; else
  /// 0.
  int get exitStatus {
    final failed = files.any(
      (file) => switch (file.status) {
        FileStatus.refused => true,
        FileStatus.formatted || FileStatus.deleted => check,
        FileStatus.created ||
        FileStatus.unchanged ||
        FileStatus.skipped => false,
      },
    );
    return failed ? 1 : 0;
  }

  /// Returns one line per changed, created, deleted, or refused file, `''`
  /// when none.
  ///
  /// Under [check] a file that would change or go prints as its bare path.
  String toText() {
    final out = StringBuffer();
    for (final file in files) {
      switch (file.status) {
        case FileStatus.formatted:
          out.writeln(check ? file.path : '${file.path}: formatted');
        case FileStatus.created:
          out.writeln('${file.path}: created');
        case FileStatus.deleted:
          out.writeln(check ? file.path : '${file.path}: deleted');
        case FileStatus.refused:
          out.writeln('${file.path}: refused: ${file.reasons}');
        case FileStatus.unchanged || FileStatus.skipped:
          break;
      }
    }
    return out.toString();
  }

  /// Returns the `--json` object: every file and the warnings.
  Map<String, Object> toJson() => {
    'files': [for (final file in files) file.toJson()],
    'warnings': warnings,
  };
}

/// The generators of a format run and the way to open what they read from.
final class GeneratorRun<R> {
  const new({required this.registry, required this.open, this.finishJournal});

  /// The generators, keyed by kind.
  final GeneratorRegistry<R> registry;

  /// Finishes an unfinished move journal, as a write command does before it
  /// reads.
  ///
  /// Called through [finishPendingJournal], before any doc is read, only when
  /// a trash folder is pending. Null leaves the journal to the next write
  /// command.
  final void Function()? finishJournal;

  /// Finishes the move journal of [project] when one is pending, through
  /// [finishJournal].
  ///
  /// [runFormat] calls it before it reads; a caller that resolves its target
  /// from a path calls it first, since the journal may move that path.
  void finishPendingJournal(DocsProject project) {
    if (MoveJournal.pending(project.projectRoot)) finishJournal?.call();
  }

  /// Opens the resolver the generators read from.
  ///
  /// Called at most once per run, and only when a doc under the target has a
  /// doc type that lists generators. `close` runs after the last write.
  final OpenedResolver<R> Function() open;
}

/// Formats the docs under [target] to their templates; a [target] that is the
/// docs root takes in the records root too.
///
/// A doc is written, atomically and in its own line-ending style, only when
/// its formatted text differs from its LF text and [check] is false. With
/// [generators], a doc whose type lists generators also gets its generated
/// blocks written; the resolver opens before the first write.
///
/// A doc whose generator keeps companion docs ([CompanionDocs]) is written with
/// them as one group: a missing companion is created, a stale one rewritten,
/// and an existing doc of their type that the list leaves out deleted, wherever
/// under the docs root it sits. A group that changes two or more files, or
/// creates or deletes one, is written through a [MoveJournal] kept under
/// [homeDirectory], all or nothing; any other doc is written alone.
///
/// A journaled group runs inside [OpenedResolver.lockWrites], after
/// [GeneratorRun.finishPendingJournal] finished any pending journal, and
/// before any other doc is written. A listed
/// companion path that holds a file no readable doc of the type, a doc that
/// changed since the run read it, a read-only doc, a pending journal, and a
/// missing home folder each refuse the write before the journal starts.
///
/// Throws a [RenderFault] `output_not_writable` naming the doc when a write
/// fails; files written before it stay written. A step of a group's journal
/// that fails leaves the steps before it applied and the journal pending, for
/// the next write run to finish, `format` included, as it starts. A fault from
/// [GeneratorRun.open] propagates and no doc is written.
FormatReport runFormat<R>(
  DocsProject project,
  Target target, {
  required bool check,
  GeneratorRun<R>? generators,
  Directory? homeDirectory,
}) {
  final targets = [target, if (target.isDocsRoot) ?project.recordsTarget];
  final run = generators;
  // A pending journal may move or rewrite docs, so it is finished before the
  // first doc is read, and the plan sees the tree it leaves.
  if (!check) run?.finishPendingJournal(project);
  final reads = [
    for (final target in targets)
      for (final entry in collectDocEntries(target, project.matcher))
        readDoc(project, entry),
  ];
  final needsResolver = reads.whereType<ReadableDoc>().any(
    (read) => read.docType.listedGenerators.isNotEmpty,
  );
  final opened = run != null && needsResolver ? run.open() : null;
  try {
    final plan = _planWrites(
      project,
      reads,
      run == null || opened == null
          ? null
          : _Blocks(registry: run.registry, resolver: opened.resolver),
    );
    final journalWarnings = <String>[];
    if (!check) {
      _applyPlan(
        project,
        plan,
        homeDirectory: homeDirectory,
        lockWrites: opened?.lockWrites,
        warn: journalWarnings.add,
      );
    }
    return FormatReport(
      check: check,
      files: check ? _checkedFiles(plan) : plan.results,
      warnings: [..._warningsOf(reads), ...plan.warnings, ...journalWarnings],
    );
  } finally {
    opened?.close();
  }
}

/// The files a format run would write for one features doc and its companions.
final class FormatWriteGroup {
  const new({required this.featuresPath, required this.paths});

  /// The features doc's path, relative to the project root.
  final String featuresPath;

  /// The paths of the group that change, in write order: the features doc when
  /// its own text changes, each companion rewritten or created, then each one
  /// deleted.
  final Set<String> paths;
}

/// What a format run would write, planned with no file touched.
final class FormatWritePlan {
  const new({
    required this.rewrites,
    required this.creates,
    required this.deletes,
    required this.results,
    required this.groups,
    required this.blocked,
    required this.warnings,
    required Map<String, ReadableDoc> sources,
  }) : _sources = sources;

  /// The LF text of each doc that changes, by path from the project root.
  final Map<String, String> rewrites;

  /// The LF text of each companion doc that does not exist yet, by path.
  final Map<String, String> creates;

  /// The paths of the companion docs the run removes.
  final List<String> deletes;

  /// What the run did with each doc, in report order.
  final List<FileResult> results;

  /// The companion groups that change something.
  final List<FormatWriteGroup> groups;

  /// The refused results that stop a write: a refused doc whose type lists a
  /// generator kind of the registry, and each refused member of a group a
  /// refusal blocks.
  final List<FileResult> blocked;

  /// The warnings of group docs the run reads that [results] lists and no read
  /// of the run holds.
  final List<String> warnings;

  final Map<String, ReadableDoc> _sources;

  /// Returns the journal steps that write [paths]: each rewrite, each create,
  /// each delete into the trash, then the prune of each folder a delete may
  /// leave empty.
  ///
  /// A rewrite keeps its doc's line ending and byte order mark and is guarded
  /// by the hash of the text it was planned from.
  List<JournalStep> stepsFor(Set<String> paths) => [
    for (final path in paths)
      if (rewrites[path] case final text?)
        WriteStep(
          path,
          _writtenText(_sources[path]!, text),
          before: textHashOf(_sources[path]!.text),
        ),
    for (final path in paths)
      if (creates[path] case final text?) CreateStep(path, text),
    for (final path in paths)
      if (deletes.contains(path))
        MoveStep(path, '${MoveJournal.trashPath}/files/$path'),
    for (final folder in {
      for (final path in paths)
        if (deletes.contains(path)) path.substring(0, path.lastIndexOf('/')),
    })
      PruneStep(folder),
  ];

  bool _isJournaled(FormatWriteGroup group) =>
      group.paths.length >= 2 ||
      group.paths.any(
        (path) => creates.containsKey(path) || deletes.contains(path),
      );
}

/// Plans the writes of [reads] with the generators of [registry] and
/// [resolver].
///
/// Writes no file, so a caller can count the changes or apply them as it
/// pleases. A doc whose generator keeps companions plans them with it, as
/// [runFormat] describes.
///
/// A caller planning the tree a write leaves passes the DocPaths the write
/// moves away or deletes as [gone] and each doc it writes among [reads]; the
/// companions are then found in that tree, not on disk as it is.
FormatWritePlan planFormatWrites<R>(
  DocsProject project,
  List<DocRead> reads,
  GeneratorRegistry<R> registry,
  R resolver, {
  Set<String> gone = const {},
}) => _Planner(
  project,
  reads,
  _Blocks(registry: registry, resolver: resolver),
  gone: gone,
).plan();

/// What a format run would do with the companions of one features doc.
enum CompanionsState {
  /// No companion would be created, rewritten, or deleted.
  current,

  /// A companion would be created, rewritten, or deleted.
  lagging,

  /// A refusal of the features doc or of a companion stops the whole group,
  /// so the run writes none of its docs.
  blocked,
}

/// Returns what a format run would do with the companions of the features
/// doc at [docPath].
///
/// It reads the companions through the plan `runFormat` makes, so `format
/// --check` and a caller agree. [outcome] is what [formatDoc] gives the
/// features doc, for a caller that already laid it out; null lays it out
/// here. A doc with no companions and a [docPath] that is no readable doc
/// give [CompanionsState.current].
CompanionsState companionsStateOf<R>(
  DocsProject project,
  String docPath,
  GeneratorRegistry<R> registry,
  R resolver, {
  FormatOutcome? outcome,
}) {
  final file = File(
    [project.docsRoot.path, ...docPath.split('/')].join(Platform.pathSeparator),
  );
  final read = readDoc(project, DocFile(file, docPath));
  if (read is! ReadableDoc) return CompanionsState.current;
  final planner = _Planner(project, [
    read,
  ], _Blocks(registry: registry, resolver: resolver));
  final group = planner._groupOf(read);
  if (group == null) return CompanionsState.current;
  final own = outcome ?? formatDoc(read.doc, read.docType);
  if (group.isBlocked(refusesFeatures: own is Refused)) {
    return CompanionsState.blocked;
  }
  final lags =
      group.deletes.isNotEmpty ||
      group.companions.any((companion) => companion.text != null);
  return lags ? CompanionsState.lagging : CompanionsState.current;
}

FormatWritePlan _planWrites<R>(
  DocsProject project,
  List<DocRead> reads,
  _Blocks<R>? blocks,
) => _Planner(project, reads, blocks).plan();

/// Plans one run: each doc laid out and filled, each companion group beside
/// its features doc.
final class _Planner<R> {
  new(this._project, this._reads, this._blocks, {Set<String> gone = const {}})
    : _gone = gone;

  final DocsProject _project;
  final List<DocRead> _reads;
  final _Blocks<R>? _blocks;

  /// The DocPaths a write the run plans after takes away from the tree.
  final Set<String> _gone;

  final _warnings = <String>[];

  // Late so a run with no companions never walks the docs root.
  late final List<DocEntry> _docsRootEntries = collectDocEntries(
    Target(_project.docsRoot, ''),
    _project.matcher,
  );

  FormatWritePlan plan() {
    final groupOf = <ReadableDoc, _Group>{};
    for (final read in _reads.whereType<ReadableDoc>()) {
      final group = _groupOf(read);
      if (group != null) groupOf[read] = group;
    }
    final handled = {for (final group in groupOf.values) ...group.handledPaths};
    final builder = _PlanBuilder();
    for (final read in _reads) {
      if (handled.contains(read.path)) continue;
      switch (read) {
        case UnmatchedDoc(:final path):
          builder.results.add(
            FileResult(path: path, status: FileStatus.skipped),
          );
        case NotUtf8Doc(:final path):
          builder.results.add(
            FileResult(path: path, status: FileStatus.skipped),
          );
        case UnreadableDoc(:final path, :final isFolder):
          // A folder has no file entry, only its warning (s02_api_format).
          if (!isFolder) {
            builder.results.add(
              FileResult(path: path, status: FileStatus.skipped),
            );
          }
        case AmbiguousDoc(:final path, :final docTypeIds):
          builder.results.add(
            FileResult(
              path: path,
              status: FileStatus.refused,
              docTypes: docTypeIds,
            ),
          );
        case final ReadableDoc doc:
          builder.addDoc(
            doc,
            _planDoc(doc),
            groupOf[doc],
            fillsBlocks: _fillsBlocks(doc.docType),
          );
      }
    }
    return builder.build(_warnings);
  }

  late final Set<String> _kinds = _blocks?.registry.kinds ?? const {};

  /// Whether the run fills a generated block of a kind [type] lists.
  bool _fillsBlocks(MergedDocType type) =>
      type.listedGenerators.any(_kinds.contains);

  /// Formats [read]; a doc the layout refuses is never written.
  _DocPlan _planDoc(ReadableDoc read) {
    switch (formatDoc(read.doc, read.docType)) {
      case final Refused refused:
        return _DocPlan(_refusedResult(read.path, refused));
      case Formatted(:final text):
        var finalText = text;
        final blocks = _blocks;
        if (blocks != null && read.docType.listedGenerators.isNotEmpty) {
          // The formatted text is laid out, and the inserted pair carries its
          // own layout whitespace, so no second layout pass runs here.
          finalText = fillGeneratedBlocks(
            text,
            read.docType,
            blocks.registry,
            blocks.resolver,
            docPath: read.docPath,
          );
        }
        if (finalText == toLf(read.text)) {
          return _DocPlan(
            FileResult(path: read.path, status: FileStatus.unchanged),
          );
        }
        return _DocPlan(
          FileResult(path: read.path, status: FileStatus.formatted),
          finalText,
        );
    }
  }

  /// Returns the companions of [features], or null when its generators keep
  /// none and no doc of their type exists.
  _Group? _groupOf(ReadableDoc features) {
    final blocks = _blocks;
    if (blocks == null) return null;
    final companions = <_CompanionPlan>[];
    final deletes = <ReadableDoc>[];
    final unlisted = <FileResult>[];
    final handledPaths = <String>{};
    for (final kind in features.docType.listedGenerators) {
      final companionsOf = blocks.registry.companionsOf(kind);
      if (companionsOf == null) continue;
      final listed = companionsOf(
        features.docPath,
        features.docType,
        blocks.resolver,
      );
      final type = listed.docTypeId.isEmpty
          ? null
          : _project.set.lookup(listed.docTypeId);
      if (type == null) continue;
      final kept = {for (final doc in listed.docs) doc.docPath};
      // A doc the list leaves out is the group's to delete only when it
      // carries the type's own file name; any other doc of the type stays an
      // ordinary doc.
      final docs = _docsOfType(type);
      final groupDocs = {
        for (final MapEntry(:key, :value) in docs.readable.entries)
          if (kept.contains(key) || key.split('/').last == type.file)
            key: value,
      };
      handledPaths.addAll(groupDocs.values.map((doc) => doc.path));
      for (final doc in listed.docs) {
        final companion = switch (docs.readable[doc.docPath]) {
          _ when !_isOwnPath(doc.docPath, type) => _misplacedCompanion(doc),
          final current? => _existingCompanion(current),
          null when _isOccupied(doc.docPath) => _occupiedCompanion(doc),
          null => _createdCompanion(doc, type),
        };
        companions.add(companion);
        if (companion.isOccupied) handledPaths.add(companion.path);
      }
      deletes.addAll([
        for (final MapEntry(:key, :value) in groupDocs.entries)
          if (!kept.contains(key)) value,
      ]);
      unlisted.addAll([
        for (final MapEntry(:key, :value) in docs.unreadable.entries)
          if (!kept.contains(key)) ?_skippedOutsideRun(value),
      ]);
    }
    if (companions.isEmpty && deletes.isEmpty && unlisted.isEmpty) return null;
    return _Group(
      companions: companions,
      deletes: deletes,
      unlisted: unlisted,
      handledPaths: handledPaths,
    );
  }

  /// Returns the readable docs of [type] in the tree the run plans and the
  /// files of the type that cannot be read, each by DocPath: the docs root in
  /// tree order without [_gone], then each doc of the type only [_reads]
  /// holds.
  _TypeDocs _docsOfType(MergedDocType type) {
    final readByDocPath = {
      for (final read in _reads.whereType<ReadableDoc>()) read.docPath: read,
    };
    final readable = <String, ReadableDoc>{};
    final unreadable = <String, DocRead>{};
    for (final entry in _docsRootEntries.whereType<DocFile>()) {
      if (_gone.contains(entry.docPath)) continue;
      final match = _project.matcher.match(entry.docPath);
      if (match is! MatchedDocType || match.docType.id != type.id) continue;
      final read = readByDocPath[entry.docPath] ?? readDoc(_project, entry);
      if (read is ReadableDoc) {
        readable[entry.docPath] = read;
      } else {
        unreadable[entry.docPath] = read;
      }
    }
    for (final MapEntry(key: docPath, value: read) in readByDocPath.entries) {
      if (read.docType.id == type.id) readable.putIfAbsent(docPath, () => read);
    }
    return _TypeDocs(readable: readable, unreadable: unreadable);
  }

  /// Whether [docPath] lies under the docs root and is a path of [type]: no
  /// empty, `.`, or `..` segment, no backslash or colon, and the project's
  /// matcher gives it to [type] alone.
  ///
  /// The list of companions is the generator owner's, so each path is checked
  /// before any plan reads, creates, rewrites, or deletes it.
  bool _isOwnPath(String docPath, MergedDocType type) {
    final isPlain = docPath
        .split('/')
        .every(
          (segment) =>
              segment.isNotEmpty &&
              segment != '.' &&
              segment != '..' &&
              !segment.contains(r'\') &&
              !segment.contains(':'),
        );
    return isPlain &&
        switch (_project.matcher.match(docPath)) {
          MatchedDocType(:final docType) => docType.id == type.id,
          _ => false,
        };
  }

  /// Plans a listed path that is no path of its doc type under the docs root:
  /// it refuses the group, so nothing is written at it.
  _CompanionPlan _misplacedCompanion(CompanionDoc doc) {
    final path = '$docsFolderName/${doc.docPath}';
    return _CompanionPlan(
      path: path,
      result: FileResult(
        path: path,
        status: FileStatus.refused,
        misplaced: true,
      ),
    );
  }

  /// Whether anything, a link included, sits at [docPath] under the docs root.
  bool _isOccupied(String docPath) =>
      FileSystemEntity.typeSync(
        [
          _project.docsRoot.path,
          ...docPath.split('/'),
        ].join(Platform.pathSeparator),
        followLinks: false,
      ) !=
      FileSystemEntityType.notFound;

  /// Returns the skipped result of [read], a file of a companion type that
  /// cannot be read, and keeps its warning, unless the run reads it itself.
  FileResult? _skippedOutsideRun(DocRead read) {
    if (_reads.any((other) => other.path == read.path)) return null;
    if (_warningOf(read) case final warning?) _warnings.add(warning);
    return FileResult(path: read.path, status: FileStatus.skipped);
  }

  /// Plans a listed path that holds a file no readable doc of the type: it
  /// refuses the group, so no create runs over it.
  _CompanionPlan _occupiedCompanion(CompanionDoc doc) {
    final path = '$docsFolderName/${doc.docPath}';
    return _CompanionPlan(
      path: path,
      result: FileResult(
        path: path,
        status: FileStatus.refused,
        unreadable: true,
      ),
      isOccupied: true,
    );
  }

  _CompanionPlan _existingCompanion(ReadableDoc current) {
    final plan = _planDoc(current);
    return _CompanionPlan(
      path: current.path,
      result: plan.result,
      source: current,
      text: plan.text,
    );
  }

  /// Plans a doc that does not exist: its seed laid out, filled, and approved.
  _CompanionPlan _createdCompanion(CompanionDoc doc, MergedDocType type) {
    final path = '$docsFolderName/${doc.docPath}';
    switch (formatDoc(Doc.parse(doc.seedText), type)) {
      case final Refused refused:
        return _CompanionPlan(
          path: path,
          result: _refusedResult(path, refused),
        );
      case Formatted(:final text):
        final blocks = _blocks;
        final filled = blocks == null || type.listedGenerators.isEmpty
            ? text
            : fillGeneratedBlocks(
                text,
                type,
                blocks.registry,
                blocks.resolver,
                docPath: doc.docPath,
              );
        return _CompanionPlan(
          path: path,
          result: FileResult(path: path, status: FileStatus.created),
          text: withApprovalHash(filled, type),
        );
    }
  }
}

FileResult _refusedResult(String path, Refused refused) => FileResult(
  path: path,
  status: FileStatus.refused,
  unknownHeaders: refused.unknownHeaders,
  duplicateHeaders: refused.duplicateHeaders,
  unclosedFence: refused.unclosedFence,
  openBlock: refused.openBlock,
  openBlockKind: refused.openBlockKind,
  changesStructure: refused.changesStructure,
);

/// One doc laid out and filled: what the run did with it, and its new LF text
/// when it changes.
final class _DocPlan {
  const new(this.result, [this.text]);

  final FileResult result;
  final String? text;
}

/// One companion doc: its result, and the LF text to write when it changes or
/// is created. [source] is the doc on disk; null for a created doc.
final class _CompanionPlan {
  const new({
    required this.path,
    required this.result,
    this.source,
    this.text,
    this.isOccupied = false,
  });

  final String path;
  final FileResult result;
  final ReadableDoc? source;
  final String? text;

  /// Whether the path holds a file that is no readable doc of the type.
  final bool isOccupied;
}

/// The docs of one type under the docs root.
final class _TypeDocs {
  const new({required this.readable, required this.unreadable});

  final Map<String, ReadableDoc> readable;

  /// The files of the type that cannot be read, as the walk read them.
  final Map<String, DocRead> unreadable;
}

/// Collects what a run plans, doc by doc.
final class _PlanBuilder {
  final results = <FileResult>[];
  final _rewrites = <String, String>{};
  final _creates = <String, String>{};
  final _deletes = <String>[];
  final _groups = <FormatWriteGroup>[];
  final _blocked = <FileResult>[];
  final _sources = <String, ReadableDoc>{};

  /// Adds [doc], planned as [own], and its companions [group] when it has
  /// them; [fillsBlocks] is whether the run fills a block of [doc].
  ///
  /// A refusal in a group, [doc]'s own included, leaves the whole group
  /// unwritten.
  void addDoc(
    ReadableDoc doc,
    _DocPlan own,
    _Group? group, {
    required bool fillsBlocks,
  }) {
    if (group == null) {
      results.add(own.result);
      if (fillsBlocks && own.result.status == FileStatus.refused) {
        _blocked.add(own.result);
      }
      _addRewrite(doc, own.text);
    } else if (group.isBlocked(
      refusesFeatures: own.result.status == FileStatus.refused,
    )) {
      final blockedResults = group.blockedResults(doc, own);
      results.addAll(blockedResults);
      _blocked.addAll(
        blockedResults.where((result) => result.status == FileStatus.refused),
      );
    } else {
      _addGroup(doc, own, group);
    }
  }

  void _addRewrite(ReadableDoc doc, String? text) {
    if (text == null) return;
    _rewrites[doc.path] = text;
    _sources[doc.path] = doc;
  }

  void _addGroup(ReadableDoc doc, _DocPlan own, _Group group) {
    final paths = <String>{if (own.text != null) doc.path};
    results.add(own.result);
    _addRewrite(doc, own.text);
    for (final companion in group.companions) {
      results.add(companion.result);
      final text = companion.text;
      if (text == null) continue;
      paths.add(companion.path);
      if (companion.source case final source?) {
        _rewrites[companion.path] = text;
        _sources[companion.path] = source;
      } else {
        _creates[companion.path] = text;
      }
    }
    for (final doomed in group.deletes) {
      results.add(FileResult(path: doomed.path, status: FileStatus.deleted));
      _deletes.add(doomed.path);
      _sources[doomed.path] = doomed;
      paths.add(doomed.path);
    }
    results.addAll(group.unlisted);
    if (paths.isNotEmpty) {
      _groups.add(FormatWriteGroup(featuresPath: doc.path, paths: paths));
    }
  }

  FormatWritePlan build(List<String> warnings) => FormatWritePlan(
    rewrites: _rewrites,
    creates: _creates,
    deletes: _deletes,
    results: results,
    groups: _groups,
    blocked: _blocked,
    warnings: warnings,
    sources: _sources,
  );
}

/// The companions of one features doc and the docs of their type it deletes.
final class _Group {
  const new({
    required this.companions,
    required this.deletes,
    required this.unlisted,
    required this.handledPaths,
  });

  /// The listed companions, in list order.
  final List<_CompanionPlan> companions;

  /// The existing docs of the companion type that the list leaves out.
  final List<ReadableDoc> deletes;

  /// The skipped results of files of the companion type that cannot be read,
  /// that the list leaves out, and that the run does not read itself.
  final List<FileResult> unlisted;

  /// The paths of every readable doc of the companion type under the docs
  /// root, and of each listed path another file holds; the group plans these,
  /// and the per-doc pass skips them.
  final Set<String> handledPaths;

  /// Whether a refusal of the features doc, which [refusesFeatures] gives, or
  /// of a companion stops the whole group.
  bool isBlocked({required bool refusesFeatures}) =>
      refusesFeatures ||
      companions.any((doc) => doc.result.status == FileStatus.refused);

  /// Returns the results of a blocked group: each refusal as it is, every other
  /// existing doc unchanged, and nothing for a doc the group would create or
  /// delete, as no byte moved.
  List<FileResult> blockedResults(ReadableDoc features, _DocPlan own) => [
    if (own.result.status == FileStatus.refused)
      own.result
    else
      FileResult(path: features.path, status: FileStatus.unchanged),
    for (final doc in companions)
      if (doc.result.status == FileStatus.refused)
        doc.result
      else if (doc.source != null)
        FileResult(path: doc.path, status: FileStatus.unchanged),
    ...unlisted,
  ];
}

/// Returns the warnings of [reads] a run skips.
List<String> _warningsOf(List<DocRead> reads) => [
  for (final read in reads) ?_warningOf(read),
];

String? _warningOf(DocRead read) => switch (read) {
  UnmatchedDoc(:final warning) => warning,
  NotUtf8Doc(:final warning) => warning,
  UnreadableDoc(:final warning) => warning,
  AmbiguousDoc() || ReadableDoc() => null,
};

/// Returns what `check` lists: a created doc is no listed file, and a features
/// doc whose group changes is listed though its own text holds.
List<FileResult> _checkedFiles(FormatWritePlan plan) {
  final changing = {for (final group in plan.groups) group.featuresPath};
  return [
    for (final file in plan.results)
      if (file.status != FileStatus.created)
        if (file.status == FileStatus.unchanged && changing.contains(file.path))
          FileResult(path: file.path, status: FileStatus.formatted)
        else
          file,
  ];
}

/// Writes what [plan] holds: first each group that goes through a journal, so
/// a refused journal leaves every doc as it was, then every other doc alone.
///
/// The journaled groups run inside [lockWrites], none when null. [warn] takes
/// each warning the journal raises.
void _applyPlan(
  DocsProject project,
  FormatWritePlan plan, {
  required Directory? homeDirectory,
  required void Function(void Function() write)? lockWrites,
  required void Function(String line) warn,
}) {
  final journaled = [
    for (final group in plan.groups)
      if (plan._isJournaled(group)) group,
  ];
  _applyJournaled(
    project,
    plan,
    journaled,
    homeDirectory: homeDirectory,
    lockWrites: lockWrites ?? (write) => write(),
    warn: warn,
  );
  final inJournal = {for (final group in journaled) ...group.paths};
  for (final MapEntry(:key, :value) in plan.rewrites.entries) {
    if (!inJournal.contains(key)) _write(project, plan._sources[key]!, value);
  }
}

void _applyJournaled(
  DocsProject project,
  FormatWritePlan plan,
  List<FormatWriteGroup> groups, {
  required Directory? homeDirectory,
  required void Function(void Function() write) lockWrites,
  required void Function(String line) warn,
}) {
  if (groups.isEmpty) return;
  final target = JournalTarget.of(
    project,
    homeDirectory: homeDirectory,
    warn: warn,
  )..requireTrusted();
  MoveJournal.requireHomeFolder(homeDirectory, project.projectRoot);
  lockWrites(() {
    // Every check runs before the first journal, so a refusal leaves each
    // group as it was.
    for (final group in groups) {
      for (final path in group.paths) {
        _requireStillPlanned(project, plan, path);
      }
    }
    for (final group in groups) {
      MoveJournal(plan.stepsFor(group.paths)).run(target);
    }
  });
}

/// Throws [RenderFault] `output_not_writable` unless the tree still holds what
/// the plan read at [path]: a rewrite or a delete finds its doc unchanged, a
/// rewrite writable, and a create finds nothing there.
void _requireStillPlanned(
  DocsProject project,
  FormatWritePlan plan,
  String path,
) {
  if (plan.creates.containsKey(path)) {
    final under = path.substring(docsFolderName.length + 1);
    final taken = FileSystemEntity.typeSync(
      [project.docsRoot.path, ...under.split('/')].join(Platform.pathSeparator),
      followLinks: false,
    );
    if (taken != FileSystemEntityType.notFound) {
      throw RenderFault(
        RenderFaultCode.outputNotWritable,
        'a file appeared where the run would create the doc',
        file: path,
      );
    }
    return;
  }
  final source = plan._sources[path]!;
  if (plan.rewrites.containsKey(path)) _requireWritable(project, source);
  _requireUnchanged(source);
}

/// Throws [RenderFault] `output_not_writable` when [read]'s file no longer
/// holds the text the run read, so its journal step would skip it and leave
/// the group half written.
void _requireUnchanged(ReadableDoc read) {
  final String current;
  try {
    current = read.file.readAsStringSync();
  } on FileSystemException {
    throw _changedSinceRead(read);
  } on FormatException {
    throw _changedSinceRead(read);
  }
  if (textHashOf(current) != textHashOf(read.text)) {
    throw _changedSinceRead(read);
  }
}

RenderFault _changedSinceRead(ReadableDoc read) => RenderFault(
  RenderFaultCode.outputNotWritable,
  'the doc changed since the run read it',
  file: read.path,
);

/// Returns [lf] as the file holds it: the doc's line ending, its byte order
/// mark first.
String _writtenText(ReadableDoc read, String lf) =>
    '${read.hasBom ? byteOrderMark : ''}${read.lineEnding.apply(lf)}';

void _requireWritable(DocsProject project, ReadableDoc read) {
  project.requireWritablePath(read.file.path);
  if (isReadOnly(read.file)) {
    throw RenderFault(
      RenderFaultCode.outputNotWritable,
      'the doc is read-only',
      file: read.path,
    );
  }
}

void _write(DocsProject project, ReadableDoc read, String text) {
  _requireWritable(project, read);
  try {
    final bytes = utf8.encode(read.lineEnding.apply(text));
    writeFileAtomic(read.file, [if (read.hasBom) ...utf8Bom, ...bytes]);
  } on FileSystemException catch (error) {
    final reason = error.osError?.message ?? error.message;
    throw RenderFault(
      RenderFaultCode.outputNotWritable,
      'cannot write the formatted doc: $reason',
      file: read.path,
    );
  }
}

/// The generators of a run and the resolver they read from.
final class _Blocks<R> {
  const new({required this.registry, required this.resolver});

  final GeneratorRegistry<R> registry;
  final R resolver;
}
