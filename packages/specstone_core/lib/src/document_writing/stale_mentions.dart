import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/doc_model/name_mentions.dart'
    show NameMention, nameMentionsInFile, readsNameMentions;
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show DocAddress;
import 'package:specstone_core/src/document_writing/agent_file_walk.dart';
import 'package:specstone_core/src/document_writing/moved_paths.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/git_process.dart' show runRealGit;
import 'package:specstone_core/src/index_query/code_root_files.dart'
    show projectPathOfCodeFile;
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/rendering/line_ending.dart' show toLf;
import 'package:specstone_core/src/setup_migration/agent_targets.dart'
    show codeFilesOf;
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/project_config.dart';

const _separator = '/';
const _byteOrderMark = '﻿';

/// The `to` of a [PathMove] that removes the doc at its `from`.
const removedPath = '';

/// A mention in a code file or an agent file that a change stops resolving:
/// the file's path from the project root, the 1-based line, and the mention
/// as written.
typedef StaleMention = ({String path, int line, String mention});

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
}) {
  if (moves.isEmpty) return const [];
  final stopsResolving = _stopsResolvingTest(
    session,
    moves,
    namesChange: namesChange,
  );
  final files = _filesToRead(session);
  final stale = <StaleMention>[];
  for (final projectPath in files.keys.toList()..sort(compareCodePoints)) {
    final lf = _lfTextOf(files[projectPath]!);
    if (lf == null) continue;
    for (final mention in nameMentionsInFile(lf, _extensionOf(projectPath))) {
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
) {
  final inTargetFolder = session.index.hasTwins;
  final renamed = <(String, String), String>{};
  for (final doc in session.index.docs) {
    final typeId = doc.docTypeId;
    final docType = typeId == null ? null : session.index.set.lookup(typeId);
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
  WriteSession session,
  List<PathMove> moves, {
  required bool namesChange,
}) {
  final renamed = renamedNamesOf(session, moves);
  final docPathsAfter = <String>{};
  final namesBefore = _NameSet();
  final namesAfter = _NameSet();
  for (final doc in session.index.docs) {
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
    for (final candidate in {path, session.listedPathOf(path)}) {
      if (session.index.at(candidate) != null) return candidate;
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
Map<String, File> _filesToRead(WriteSession session) {
  final project = session.project;
  final files = <String, File>{};
  for (final (root: codeRoot, path: codePath) in codeFilesOf(
    project.projectRoot,
    project.set,
    targets: project.targets,
  )) {
    if (!readsNameMentions(_extensionOf(codePath))) continue;
    final projectPath = projectPathOfCodeFile(
      codePath,
      projectRoot: project.projectRoot,
      docsRoot: project.docsRoot,
      codeRoot: codeRoot,
    );
    if (projectPath == null) continue;
    files[projectPath] = _fileIn(codeRoot, codePath);
  }
  final config = ProjectConfig.read(project.projectRoot);
  for (final path in agentFilesOf(project.projectRoot, config, runRealGit)) {
    if (!readsNameMentions(_extensionOf(path))) continue;
    if (session.listedPathOf(path) != path) continue;
    files.putIfAbsent(path, () => _fileIn(project.projectRoot, path));
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
    final text = utf8.decode(file.readAsBytesSync());
    return toLf(text.startsWith(_byteOrderMark) ? text.substring(1) : text);
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
