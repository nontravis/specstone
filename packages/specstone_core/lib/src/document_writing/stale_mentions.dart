import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/doc_model/name_mentions.dart'
    show NameMention, docMentionsInFile, readsNameMentions;
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show DocAddress;
import 'package:specstone_core/src/document_writing/agent_file_walk.dart';
import 'package:specstone_core/src/document_writing/moved_paths.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/git_process.dart' show RunGit, runRealGit;
import 'package:specstone_core/src/index_query/code_root_files.dart'
    show ProjectPathReader;
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/plan_hash.dart' show readPlanInput;
import 'package:specstone_core/src/rendering/doc_reader.dart'
    show byteOrderMark;
import 'package:specstone_core/src/rendering/line_ending.dart' show toLf;
import 'package:specstone_core/src/setup_migration/agent_targets.dart'
    show codeFilesOf;
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/code_target.dart' show CodeTarget;
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/project_config.dart';

const _separator = '/';

/// The docs root as a ProjectPath begins.
const _docsPrefix = 'docs/';

/// The `to` of a [PathMove] that removes the doc at its `from`.
const removedPath = '';

/// A mention in a code file or an agent file that a change stops resolving:
/// the file's path from the project root, the 1-based line, and the mention
/// as written.
typedef StaleMention = ({String path, int line, String mention});

/// What a mention scan reads of a project: its docs, and the roots of the
/// code files and agent files it scans.
///
/// A write command takes it from its session ([MentionScope.of]); a plan that
/// opens no index builds it from the docs it read.
final class MentionScope {
  const new({
    required this.projectRoot,
    required this.docsRoot,
    required this.set,
    required this.targets,
    required this.agentFileRoots,
    required this.docs,
    this.hasTwins = false,
    this.docMoves = const [],
    this.runGit = runRealGit,
  });

  /// The scope of the project [session] writes.
  factory of(WriteSession session) => MentionScope(
    projectRoot: session.project.projectRoot,
    docsRoot: session.project.docsRoot,
    set: session.project.set,
    targets: session.project.targets,
    agentFileRoots: ProjectConfig.read(session.project.projectRoot)
        .agentFileRoots,
    docs: session.index.docs,
    hasTwins: session.index.hasTwins,
  );

  /// The canonical project root.
  final Directory projectRoot;

  /// The canonical docs root.
  final Directory docsRoot;

  /// The merged doc types of the project.
  final MergedSet set;

  /// The config's code targets, in config order.
  final List<CodeTarget> targets;

  /// The repository tops, from the project root, whose agent files the scan
  /// reads beside the project root's.
  final List<String> agentFileRoots;

  /// Every doc, as the mentions read them.
  final List<IndexedDoc> docs;

  /// Whether the project holds two or more named code targets.
  final bool hasTwins;

  /// The moves of a plan that has not run yet, so a doc is read for its
  /// `code:` entries where the plan puts it; none for a command that has.
  final List<PathMove> docMoves;

  /// Starts the `git` that lists the agent files.
  final RunGit runGit;

  /// Returns [projectPath] as a doc is listed: a doc by its DocPath, any
  /// other file by its project path.
  String listedPathOf(String projectPath) => projectPath.startsWith(_docsPrefix)
      ? projectPath.substring(_docsPrefix.length)
      : projectPath;
}

/// Returns the mentions in code files and agent files that the change
/// described by [moves] stops resolving, by file path, then line.
///
/// A mention counts only once it stops resolving: it names a doc now and
/// names none after the moves. A Name mention counts when [namesChange] holds
/// and no doc carries the Name after the moves; a path mention, read from the
/// docs root or the project root, counts when no doc sits at the path after
/// the moves. A move to [removedPath] removes the doc. Files are the ones the
/// `code:` roots list and the agent files of the walk; none is written.
List<StaleMention> staleMentions(
  WriteSession session,
  List<PathMove> moves, {
  required bool namesChange,
}) =>
    staleMentionsIn(MentionScope.of(session), moves, namesChange: namesChange);

/// Returns the mentions [staleMentions] returns for the project [scope]
/// describes.
///
/// Each file read is recorded as a plan input when a plan collects.
List<StaleMention> staleMentionsIn(
  MentionScope scope,
  List<PathMove> moves, {
  required bool namesChange,
}) {
  if (moves.isEmpty) return const [];
  final stopsResolving = _stopsResolvingTest(
    scope,
    moves,
    namesChange: namesChange,
  );
  final files = _filesToRead(scope);
  final stale = <StaleMention>[];
  for (final projectPath in files.keys.toList()..sort(compareCodePoints)) {
    final lf = _lfTextOf(files[projectPath]!);
    if (lf == null) continue;
    for (final mention in docMentionsInFile(lf, _extensionOf(projectPath))) {
      if (!stopsResolving(mention)) continue;
      stale.add((path: projectPath, line: mention.line, mention: mention.text));
    }
  }
  return stale;
}

/// Returns the text line that lists [mention]:
/// `mentions <path>:<line> <mention>`, ended by a line feed.
String mentionLineOf(StaleMention mention) =>
    'mentions ${mention.path}:${mention.line} ${mention.mention}\n';

/// Returns [mentions] as the JSON array a command prints under `mentions`.
List<Map<String, Object>> mentionsJsonOf(List<StaleMention> mentions) => [
  for (final (:path, :line, :mention) in mentions)
    {'path': path, 'line': line, 'mention': mention},
];

/// Returns the names that change under [moves], each typed doc under a
/// moved path mapped from `(doc type id, old name)` to its new name.
///
/// A per-target doc sits in its target's folder only with two or more targets,
/// and its name drops that folder, so the twins of the targets share it. A doc
/// moved to [removedPath] gets no new name.
Map<(String, String), String> renamedNamesOf(
  WriteSession session,
  List<PathMove> moves,
) => renamedNamesIn(MentionScope.of(session), moves);

/// Returns the names that change under [moves] in the project [scope]
/// describes, as [renamedNamesOf] does.
Map<(String, String), String> renamedNamesIn(
  MentionScope scope,
  List<PathMove> moves,
) {
  final inTargetFolder = scope.hasTwins;
  final renamed = <(String, String), String>{};
  for (final doc in scope.docs) {
    final typeId = doc.docTypeId;
    final docType = typeId == null ? null : scope.set.lookup(typeId);
    final newPath = movedPath(doc.docPath, moves);
    if (docType == null || newPath == doc.docPath || newPath == removedPath) {
      continue;
    }
    renamed[(docType.id, doc.name)] = docNameOf(
      newPath,
      docType,
      target: inTargetFolder ? doc.target : null,
    );
  }
  return renamed;
}

/// Returns the test that says whether a mention names a doc now and no doc
/// after [moves].
bool Function(NameMention mention) _stopsResolvingTest(
  MentionScope scope,
  List<PathMove> moves, {
  required bool namesChange,
}) {
  final renamed = renamedNamesIn(scope, moves);
  final docPathsBefore = {for (final doc in scope.docs) doc.docPath};
  final docPathsAfter = <String>{};
  final namesBefore = _NameSet();
  final namesAfter = _NameSet();
  for (final doc in scope.docs) {
    final newPath = movedPath(doc.docPath, moves);
    if (newPath != removedPath) docPathsAfter.add(newPath);
    final typeId = doc.docTypeId;
    if (typeId == null) continue;
    namesBefore.add(typeId, doc.name);
    if (newPath != removedPath) {
      namesAfter.add(typeId, renamed[(typeId, doc.name)] ?? doc.name);
    }
  }

  String? docPathNamedBy(String path) {
    for (final candidate in {path, scope.listedPathOf(path)}) {
      if (docPathsBefore.contains(candidate)) return candidate;
    }
    return null;
  }

  return (mention) {
    final address = mention.address;
    if (address.isName) {
      return namesChange &&
          namesBefore.holds(address) &&
          !namesAfter.holds(address);
    }
    final docPath = docPathNamedBy(mention.text);
    return docPath != null && !docPathsAfter.contains(docPath);
  };
}

/// The Names of docs, by doc type id and bare.
final class _NameSet {
  final _typed = <(String, String)>{};
  final _bare = <String>{};

  void add(String typeId, String name) {
    _typed.add((typeId, name));
    _bare.add(name);
  }

  /// Whether a doc carries the Name [address] names, of its doc type when the
  /// address gives one.
  bool holds(DocAddress address) => switch (address.typeId) {
    final typeId? => _typed.contains((typeId, address.body)),
    null => _bare.contains(address.body),
  };
}

/// Returns the files to read, by their path from the project root: the code
/// files outside the docs root, then the agent files of the walk.
Map<String, File> _filesToRead(MentionScope scope) {
  final files = <String, File>{};
  final paths = ProjectPathReader(
    projectRoot: scope.projectRoot,
    docsRoot: scope.docsRoot,
  );
  for (final (root: codeRoot, path: codePath) in codeFilesOf(
    scope.projectRoot,
    scope.set,
    targets: scope.targets,
    moves: scope.docMoves,
  )) {
    if (!readsNameMentions(_extensionOf(codePath))) continue;
    final projectPath = paths.projectPathOf(codePath, codeRoot);
    if (projectPath == null) continue;
    files[projectPath] = _fileIn(codeRoot, codePath);
  }
  for (final path in agentFilesOf(
    scope.projectRoot,
    scope.agentFileRoots,
    scope.runGit,
  )) {
    if (!readsNameMentions(_extensionOf(path))) continue;
    if (scope.listedPathOf(path) != path) continue;
    files.putIfAbsent(path, () => _fileIn(scope.projectRoot, path));
  }
  return files;
}

File _fileIn(Directory folder, String path) => File(
  '${folder.path}${Platform.pathSeparator}'
  '${path.split(_separator).join(Platform.pathSeparator)}',
);

/// Returns the text of [file] with LF line ends and no byte-order mark, or
/// null when it cannot be read or is not UTF-8.
String? _lfTextOf(File file) {
  try {
    final text = utf8.decode(readPlanInput(file));
    return toLf(text.startsWith(byteOrderMark) ? text.substring(1) : text);
  } on FormatException {
    return null;
  } on FileSystemException {
    return null;
  }
}

/// Returns the extension of [path], a `.` and the letters after its last
/// one, or an empty string for a name with none.
String _extensionOf(String path) {
  final name = path.substring(path.lastIndexOf(_separator) + 1);
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot);
}
