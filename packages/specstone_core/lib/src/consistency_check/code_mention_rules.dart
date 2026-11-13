import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/canonical_path.dart' show canonicalPath;
import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/code_rules.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/name_mentions.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/document_writing/agent_file_walk.dart';
import 'package:specstone_core/src/index_query/code_root_files.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/rendering/line_ending.dart' show toLf;
import 'package:specstone_core/src/templates/code_target.dart';

const _codeField = 'code';
const _separator = '/';
const _wholeCodeRoot = '.';
const _byteOrderMark = '﻿';

/// Returns a `doc_cited_in_code` finding for each mention of a doc in the
/// code files of the targets of [work].
///
/// A code file is each file under the `code:` roots of a target's docs; a
/// target with no `code:` entry lists its whole code root but the docs root,
/// hidden folders, and nested checkouts. An agent file is never read, and a
/// file with no comment mark or markdown extension is not read at all. A
/// mention counts only when it resolves to a doc in the index, so a layout
/// template, an item ID, or a number label never does. A file that is not
/// UTF-8 or cannot be read is a warning, not a finding.
Iterable<Finding> docNamesInCode(
  CheckContext context,
  ImplementedWork work,
) sync* {
  final reader = _DocMentionReader(context);
  for (final target in work.targets) {
    for (final file in _codeFilesOf(context, work, target)) {
      yield* reader.mentionsIn(target, file);
    }
  }
}

/// Returns the code files of [target], as paths from its code root, sorted by
/// code point, each once.
List<String> _codeFilesOf(
  CheckContext context,
  ImplementedWork work,
  CodeTarget target,
) {
  final codeRoot = context.codeRootOf(target);
  final entries = _codeEntriesOf(context, work, target);
  final nested = nestedRootsOf(context.projectRoot, target, context.targets);
  if (entries.isEmpty) {
    return filesUnderCodeRoot(
      codeRoot,
      _wholeCodeRoot,
      skipFolders: [...nested, ..._docsRootIn(context, codeRoot)],
      skipRepositories: true,
      onUnlistable: (folder) => context.warn(
        '$folder: cannot list the folder; files under it are not checked for '
        'doc names',
      ),
    );
  }
  // The coverage rule lists these roots and warns about a folder it cannot
  // list, so this walk adds no second warning.
  return {
    for (final entry in entries)
      ...filesUnderCodeRoot(codeRoot, entry, skipFolders: nested),
  }.toList();
}

/// Returns the `code:` entries of the docs of [target].
Set<String> _codeEntriesOf(
  CheckContext context,
  ImplementedWork work,
  CodeTarget target,
) => {
  for (final doc in context.index.docs)
    if (work.targetOf(doc) == target &&
        context.typeHoldsField(context.typeOf(doc), _codeField))
      for (final (:value, line: _, text: _)
          in context.linesOf(doc).entriesOf(_codeField))
        if (value is String) value,
};

/// Returns the docs root as a folder of [codeRoot], when it lies inside.
List<String> _docsRootIn(CheckContext context, Directory codeRoot) =>
    nestedPathsOf(canonicalPath(codeRoot.path), [
      canonicalPath(context.docsRoot.path),
    ]);

/// Reads the mentions of docs in code files, against one index.
final class _DocMentionReader {
  new(this._context)
    : _index = _context.index,
      _docsFolder = _context.docsRoot.uri.pathSegments.lastWhere(
        (segment) => segment.isNotEmpty,
      ),
      _names = {for (final doc in _context.index.docs) doc.name};

  final CheckContext _context;
  final DocIndex _index;
  final String _docsFolder;
  final Set<String> _names;

  Iterable<Finding> mentionsIn(CodeTarget target, String codePath) sync* {
    final extension = _extensionOf(codePath);
    if (!readsNameMentions(extension)) return;
    final projectPath = _projectPathOf(target, codePath);
    if (projectPath == null || isAgentFile(projectPath)) return;
    final text = _readText(target, codePath, projectPath);
    if (text == null) return;
    final lf = toLf(text);
    for (final mention in nameMentionsInFile(lf, extension)) {
      if (_isCited(mention, bare: false)) yield _finding(projectPath, mention);
    }
    for (final mention in bareNameMentionsInFile(lf, extension)) {
      if (_isCited(mention, bare: true)) yield _finding(projectPath, mention);
    }
  }

  String? _projectPathOf(CodeTarget target, String codePath) {
    try {
      return projectPathOfCodeFile(
        codePath,
        projectRoot: _context.projectRoot,
        docsRoot: _context.docsRoot,
        codeRoot: _context.codeRootOf(target),
      );
    } on FileSystemException {
      return null;
    }
  }

  String? _readText(CodeTarget target, String codePath, String projectPath) {
    try {
      final bytes = File(
        '${_context.codeRootOf(target).path}$_separator$codePath',
      ).readAsBytesSync();
      final text = utf8.decode(bytes);
      return text.startsWith(_byteOrderMark) ? text.substring(1) : text;
    } on FormatException {
      _context.warn('$projectPath: not UTF-8; doc names in it are not checked');
    } on FileSystemException {
      _context.warn(
        '$projectPath: cannot read the file; doc names in it are not checked',
      );
    }
    return null;
  }

  /// Whether [mention] names a doc: a path read from the docs root or the
  /// project root, or a Name some doc carries.
  bool _isCited(NameMention mention, {required bool bare}) {
    final address = mention.address;
    if (bare || address.isReferenceWithoutLookup) return _namesDoc(address);
    return _docAtPath(mention.text) != null;
  }

  bool _namesDoc(DocAddress address) => switch (address.typeId) {
    final typeId? => _index.ofTypeNamed(typeId, address.body).isNotEmpty,
    null => _names.contains(address.body),
  };

  IndexedDoc? _docAtPath(String path) {
    if (_index.at(path) case final doc?) return doc;
    final prefix = '$_docsFolder$_separator';
    return path.startsWith(prefix)
        ? _index.at(path.substring(prefix.length))
        : null;
  }

  Finding _finding(String projectPath, NameMention mention) => Finding(
    kind: FindingKind.docCitedInCode,
    path: projectPath,
    line: mention.line,
    message:
        '${mention.text} names a doc; the doc names the code, never the '
        'reverse',
    keys: {'mention': mention.text},
  );
}

String _extensionOf(String path) {
  final name = path.substring(path.lastIndexOf(_separator) + 1);
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? '' : name.substring(dot);
}
