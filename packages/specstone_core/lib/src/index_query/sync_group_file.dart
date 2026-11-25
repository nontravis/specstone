import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/code_fingerprint.dart'
    show codeLinkFiles;
import 'package:specstone_core/src/consistency_check/code_link_rules.dart'
    show CodeLink;
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/records_root.dart'
    show docPathOfProjectPath;
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show edgeCasesSectionKey;
import 'package:specstone_core/src/index_query/code_root_files.dart'
    show normalCodeEntry;
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/models/matrix_line.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/index_query/sync_prefill.dart';
import 'package:specstone_core/src/index_query/sync_work.dart';

const _arrowOpen = '==>';
const _arrowClose = '<==';
const _partSeparator = ' · ';
const _commitLength = 12;

const _rationaleKey = 'rationale';

/// The sections of an FR a group file prints.
const Set<String> _frContractKeys = {
  'statement',
  'input_output',
  'behavior',
  edgeCasesSectionKey,
};

/// Returns the text of the file of [group]: its naming line, its code part,
/// then its verdict part.
String syncGroupText(ReadSession session, SyncGroup group) {
  final verdicts = syncVerdictsOf(session, group);
  return '${_naming(['sync', group.scope])}'
      '${syncCodePart(session, group, verdicts.judgedDocs)}${verdicts.text}';
}

// MARK: - Code part

/// Returns the code part of the file of [group]: each changed code file with
/// its diff, then the contract text of each of [judgedDocs] on it, then each
/// suspect matrix row.
///
/// A folder entry's part also prints the judged docs on paths under it; one
/// under no part prints after the last part. A code file two links name
/// prints once, and so does a doc judged twice. A file with no diff base
/// prints whole, and so does an untracked file under a folder entry.
String syncCodePart(
  ReadSession session,
  SyncGroup group,
  List<SyncJudgedDoc> judgedDocs,
) {
  final index = session.index;
  final out = StringBuffer();
  final seenFiles = <String>{};
  final seenDocs = <String>{};
  void writeDocs(Iterable<IndexedDoc> docs) {
    for (final doc in docs) {
      if (seenDocs.add(doc.docPath)) _writeDoc(out, index, doc);
    }
  }

  final covered = {
    for (final work in group.links)
      if (_isUnderFolderLink(work, group.links)) work,
  };
  // A file under a folder link follows the folder, whose diff holds it.
  final ordered = [
    ...group.links.where((work) => !covered.contains(work)),
    ...covered,
  ];
  for (final work in ordered) {
    if (!seenFiles.add(_codeKeyOf(work.link.root, work.link.path))) continue;
    if (!covered.contains(work)) _writeCode(out, work);
    writeDocs(_judgedOn(work.link, judgedDocs));
  }
  writeDocs(judgedDocs.map((judged) => judged.doc));
  for (final finding in group.findings) {
    if (finding.kind == FindingKind.suspect) {
      _writeSuspectRow(out, session, finding);
    }
  }
  return '$out';
}

/// Whether [work]'s code lies under a folder link of [links] of the same root,
/// whose own diff or listing already holds it.
bool _isUnderFolderLink(SyncLinkWork work, List<SyncLinkWork> links) =>
    links.any((other) => _isUnder(work.link.root, work.link.path, other.link));

/// Whether [path], from [root], lies under the folder [folder] names, of the
/// same root.
bool _isUnder(Directory root, String path, CodeLink folder) {
  if (folder.root.path != root.path) return false;
  final entry = normalCodeEntry(path);
  final folderEntry = normalCodeEntry(folder.path);
  return folderEntry != entry &&
      (folderEntry.isEmpty || entry.startsWith('$folderEntry/')) &&
      FileSystemEntity.isDirectorySync('${root.path}/${folder.path}');
}

String _codeKeyOf(Directory root, String path) =>
    '${root.path}/${normalCodeEntry(path)}';

/// Returns the docs of [judgedDocs] on [part]'s code, then, for a folder
/// entry, those on paths under it, in [judgedDocs] order.
List<IndexedDoc> _judgedOn(CodeLink part, List<SyncJudgedDoc> judgedDocs) {
  final key = _codeKeyOf(part.root, part.path);
  return [
    for (final judged in judgedDocs)
      if (_codeKeyOf(judged.root, judged.path) == key) judged.doc,
    for (final judged in judgedDocs)
      if (_isUnder(judged.root, judged.path, part)) judged.doc,
  ];
}

void _writeCode(StringBuffer out, SyncLinkWork work) {
  final diff = work.diff;
  final base = work.base;
  if (diff == null || base == null) {
    _writeWhole(out, work);
    return;
  }
  out
    ..write(
      _naming([
        'code',
        work.link.path,
        'diff since ${base.commit.substring(0, _commitLength)}',
      ]),
    )
    ..write(_lineEnded(diff));
  final untracked = work.untracked;
  if (untracked == null) {
    out.write(
      _naming(['code', work.link.path, 'untracked files could not be listed']),
    );
    return;
  }
  for (final path in untracked) {
    _writeFile(out, work.link.root, path, 'untracked, whole');
  }
}

void _writeWhole(StringBuffer out, SyncLinkWork work) {
  final link = work.link;
  final isFolder = FileSystemEntity.isDirectorySync(
    '${link.root.path}/${link.path}',
  );
  final files = isFolder
      ? codeLinkFiles(link.root, link.path, nestedRoots: work.nestedRoots)
      : [link.path];
  for (final path in files) {
    _writeFile(out, link.root, path, 'whole');
  }
}

void _writeFile(StringBuffer out, Directory root, String path, String state) {
  final file = File('${root.path}/$path');
  if (!file.existsSync()) {
    out.write(_naming(['code', path, 'missing']));
    return;
  }
  final text = _textOf(file);
  if (text == null) {
    out.write(_naming(['code', path, 'unreadable']));
    return;
  }
  out
    ..write(_naming(['code', path, state]))
    ..write(_lineEnded(text));
}

/// Returns the text of [file]; null when it cannot be read.
String? _textOf(File file) {
  try {
    return utf8.decode(file.readAsBytesSync(), allowMalformed: true);
  } on FileSystemException {
    return null;
  }
}

// MARK: - Docs

/// Writes the contract text of [doc]: an FR's Statement, Input / Output,
/// Behavior, and Edge cases; any other doc whole, less its Rationale.
void _writeDoc(StringBuffer out, DocIndex index, IndexedDoc doc) {
  final isFr = doc.docTypeId == frType;
  out.write(_naming(['doc', '${doc.name} (${doc.docTypeId})', doc.docPath]));
  final texts = [
    for (final section in index.contentOf(doc).sections)
      if (isFr
          ? _frContractKeys.contains(section.key)
          : section.key != _rationaleKey)
        section.text,
  ];
  if (texts.isNotEmpty) out.write(_lineEnded(texts.join('\n\n')));
}

/// Writes a suspect matrix row: the current text of the block its stamp
/// covers, its fingerprint, then each literal of the row with the test file
/// and line that holds it.
void _writeSuspectRow(StringBuffer out, ReadSession session, Finding finding) {
  if (finding.keys case {
    'link': final String label,
    'targetPath': final String targetPath,
    'text': final String text,
    'fingerprint': final String fingerprint,
  }) {
    out
      ..write(_naming(['matrix row', label, '${finding.path}:${finding.line}']))
      ..write(_lineEnded(text))
      ..write('fingerprint $fingerprint\n');
    final index = session.index;
    final record = index.at(finding.path);
    final frPath = docPathOfProjectPath(targetPath);
    final fr = frPath == null ? null : index.at(frPath);
    if (record == null || fr == null) return;
    final row = record.matrixLines
        .whereType<TestRow>()
        .where((row) => row.label == label)
        .firstOrNull;
    if (row == null) return;
    final tests = _testLinesOf(session, record, index, fr);
    for (final literal in row.literals) {
      out.write('- $literal${_placeOf(literal, tests)}\n');
    }
  }
}

/// Returns the lines of each test file the record lists for [fr], by path;
/// a file that cannot be read gives none.
Map<String, List<String>> _testLinesOf(
  ReadSession session,
  IndexedDoc record,
  DocIndex index,
  IndexedDoc fr,
) {
  final target = session.project.targets
      .where((target) => target.name == record.target)
      .firstOrNull;
  final paths = index.recordEntryOf(fr, codeTarget: record.target)?.testPaths;
  if (target == null || paths == null) return const {};
  final root = session.project.codeRootOf(target);
  return {
    for (final path in paths)
      if (_textOf(File('${root.path}/$path')) case final text?)
        path: const LineSplitter().convert(text),
  };
}

/// Returns ` · <test file>:<line>` for the first line of [tests] holding
/// [literal] as a quoted string, as a test file writes a name; empty when no
/// test file does.
String _placeOf(String literal, Map<String, List<String>> tests) {
  final quoted = ["'$literal'", '"$literal"'];
  for (final MapEntry(key: path, value: lines) in tests.entries) {
    final at = lines.indexWhere((line) => quoted.any(line.contains));
    if (at >= 0) return '$_partSeparator$path:${at + 1}';
  }
  return '';
}

// MARK: - Text

String _naming(List<String> parts) =>
    '$_arrowOpen ${parts.join(_partSeparator)} $_arrowClose\n';

String _lineEnded(String text) =>
    text.isEmpty || text.endsWith('\n') ? text : '$text\n';
