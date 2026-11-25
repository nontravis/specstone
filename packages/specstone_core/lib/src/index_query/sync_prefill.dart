import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/code_fingerprint.dart';
import 'package:specstone_core/src/consistency_check/code_rules.dart'
    show ownerTargetOf;
import 'package:specstone_core/src/consistency_check/contract_block.dart';
import 'package:specstone_core/src/consistency_check/edge_case_blocks.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/fingerprint.dart';
import 'package:specstone_core/src/consistency_check/implements_entry.dart';
import 'package:specstone_core/src/consistency_check/models/doc_lines.dart';
import 'package:specstone_core/src/consistency_check/models/yaml_entry.dart';
import 'package:specstone_core/src/consistency_check/record_doc.dart';
import 'package:specstone_core/src/consistency_check/task_ref_rules.dart'
    show taskRefEntriesOf;
import 'package:specstone_core/src/doc_model/code_spans.dart' show codeSpanOf;
import 'package:specstone_core/src/doc_model/records_root.dart'
    show docPathOfProjectPath;
import 'package:specstone_core/src/git_process.dart';
import 'package:specstone_core/src/index_query/code_root_files.dart'
    show normalCodeEntry;
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/models/matrix_line.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/index_query/record_entries.dart';
import 'package:specstone_core/src/index_query/sync_diff_base.dart'
    show CodeRepos;
import 'package:specstone_core/src/index_query/sync_task_closes.dart';
import 'package:specstone_core/src/index_query/sync_work.dart';
import 'package:specstone_core/src/templates/code_link_entry.dart';

/// The marking line that opens the verdict part of a group file.
const syncVerdictMarker = '==> verdicts <==';

const _parentSegment = '..';
const _hunkMark = '@@';
const _diffFileMark = 'diff --git ';
const _literalPathspecs = '--literal-pathspecs';
const _testKey = 'test';
const _fingerprintKey = 'fingerprint';
const _renameStatus = 'R';
const _copyStatus = 'C';

final RegExp _quoted = RegExp(
  r"'((?:[^'\\]|\\.)*)'|"
  r'"((?:[^"\\]|\\.)*)"',
);

/// The verdict part of a group file and the docs its lines are judged against.
final class SyncVerdicts {
  const new({required this.text, required this.judgedDocs});

  /// The marking line, then one line per code link or matrix row to judge and
  /// each pre-filled write.
  final String text;

  /// The owner of each link of the group, then of each moved-path and row-fix
  /// `?` line; a doc may repeat.
  final List<SyncJudgedDoc> judgedDocs;
}

/// A doc a line of the verdict part is judged against, with the code path the
/// line's entry names.
final class SyncJudgedDoc {
  const new({required this.doc, required this.root, required this.path});

  final IndexedDoc doc;

  /// The folder [path] is read from.
  final Directory root;

  /// The path as the entry names it: the old path of a moved entry, or the
  /// test file of a row fix.
  final String path;
}

/// Returns the verdict part of the file of [group] and the docs its lines are
/// judged against.
///
/// Code-pointer lines come first, then `row` lines, then the matrix-row lines,
/// since a `match` that stamps a row a `row` line writes comes after it. The
/// `remove-task` lines come last.
SyncVerdicts syncVerdictsOf(ReadSession session, SyncGroup group) {
  final context = CheckContext(session);
  // One run places each code path once, whichever line asks.
  final repos = CodeRepos();
  final pointerLines = <String>[];
  final judgedDocs = [
    for (final work in group.links)
      if (work.owner case final owner?)
        SyncJudgedDoc(doc: owner, root: work.link.root, path: work.link.path),
  ];
  final rowFixes = <String, _RowFix>{};
  final matrixLines = <String>[];
  final unresolvedRows = {
    for (final finding in group.findings)
      if (finding.kind == FindingKind.matrixTestUnresolved)
        _rowKey(finding.path, finding.line),
  };
  for (final finding in group.findings) {
    switch (finding.kind) {
      case FindingKind.codeSuspect || FindingKind.codeUnconfirmed:
        pointerLines.add(_codeVerdictLine(context, finding));
      case FindingKind.implementsPathUnresolved ||
          FindingKind.coversPathMissing:
        final moved = _movedPathOf(context, repos, finding, judges: true);
        pointerLines.addAll(moved.lines);
        judgedDocs.addAll([?moved.judged]);
      case FindingKind.testsUnresolved when !finding.keys.containsKey(_testKey):
        pointerLines.addAll(
          _movedPathOf(context, repos, finding, judges: false).lines,
        );
      case FindingKind.matrixTestUnresolved:
        _collectRowFix(context, repos, finding, rowFixes);
      case FindingKind.suspect || FindingKind.unconfirmed:
        matrixLines.addAll(_matrixLines(context, finding, unresolvedRows));
      case _:
    }
  }
  pointerLines.addAll(_cleanLinkLines(context, group));
  final asked = _askedRows(rowFixes.values, matrixLines);
  judgedDocs.addAll([for (final fix in asked) ?fix.judged]);
  return SyncVerdicts(
    text: [
      '$syncVerdictMarker\n',
      for (final line in [
        ...pointerLines,
        for (final fix in rowFixes.values) fix.line,
        ...matrixLines,
        for (final fix in asked) ?fix.question,
        ..._removeTaskLines(context, repos, group),
      ])
        '$line\n',
    ].join(),
    judgedDocs: judgedDocs,
  );
}

String _rowKey(String path, int line) => '$path:$line';

/// Returns each row fix with a `?` line the matrix lines do not already hold,
/// so a `match` after the `row` line can copy it.
List<_RowFix> _askedRows(Iterable<_RowFix> fixes, List<String> held) => [
  for (final fix in fixes)
    if (fix.question case final question? when !held.contains(question)) fix,
];

// MARK: - Code links

/// Returns the `?` line of a `code_suspect` or `code_unconfirmed` finding.
String _codeVerdictLine(CheckContext context, Finding finding) {
  final doc = context.index.at(finding.path);
  final entry = doc == null ? null : _entryAt(context, doc, finding.line);
  return _question(
    finding.path,
    entry?.text ?? '${finding.keys['entry']}',
    '${finding.keys[_fingerprintKey]}',
  );
}

/// Returns the `?` line of each link of [group] no `code_suspect` or
/// `code_unconfirmed` finding names, with the fingerprint the link records.
///
/// A link with no recorded fingerprint, or whose entry no longer resolves,
/// gets none.
List<String> _cleanLinkLines(CheckContext context, SyncGroup group) {
  final judged = {
    for (final finding in group.findings)
      if (finding.kind == FindingKind.codeSuspect ||
          finding.kind == FindingKind.codeUnconfirmed)
        _rowKey(finding.path, finding.line),
  };
  final lines = <String>[];
  for (final work in group.links) {
    final recorded = work.link.recorded;
    if (recorded == null ||
        judged.contains(_rowKey(work.doc.docPath, work.link.line))) {
      continue;
    }
    final entry = _entryAt(context, work.doc, work.link.line);
    if (entry != null) {
      lines.add(_question(work.doc.docPath, entry.text, recorded));
    }
  }
  return lines;
}

String _question(String doc, String entry, String fingerprint) =>
    '? $doc $entry $fingerprint';

/// The lines of a path finding and the doc its `?` line is judged against.
final class _MovedPath {
  const new({this.lines = const [], this.judged});

  final List<String> lines;

  /// Null with no `?` line.
  final SyncJudgedDoc? judged;
}

/// Returns the `repoint` line of a path finding whose file git shows renamed,
/// and with [judges], a `?` line when the file at its new path no longer
/// fingerprints as the entry records.
_MovedPath _movedPathOf(
  CheckContext context,
  CodeRepos repos,
  Finding finding, {
  required bool judges,
}) {
  final doc = context.index.at(finding.path);
  final entry = doc == null ? null : _entryAt(context, doc, finding.line);
  if (doc == null || entry == null) return const _MovedPath();
  final moved = _renamedTo(repos, entry.base, entry.path);
  if (moved == null) return const _MovedPath();
  final repoint = 'repoint ${finding.path} ${entry.text} $moved';
  final recorded = entry.recorded;
  final current = judges && recorded != null
      ? _fingerprintOfFile(File('${entry.base.path}/$moved'), moved)
      : null;
  if (current == null || current == recorded) {
    return _MovedPath(lines: [repoint]);
  }
  final owner = syncOwnerOf(context, doc, entry.item);
  return _MovedPath(
    lines: [repoint, _question(finding.path, entry.text, current)],
    judged: owner == null
        ? null
        : SyncJudgedDoc(doc: owner, root: entry.base, path: entry.path),
  );
}

/// Returns the fingerprint of [file], read as the code file at [path]; null
/// when it is absent or cannot be read.
String? _fingerprintOfFile(File file, String path) {
  try {
    return fileCodeFingerprint(file.readAsBytesSync(), path: path);
  } on FileSystemException {
    return null;
  }
}

/// A code-link entry of a doc, as the doc holds it.
final class _Entry {
  const new({
    required this.text,
    required this.path,
    required this.base,
    this.item,
    this.recorded,
  });

  /// The entry before any fingerprint: `item:pointer` on a record, else the
  /// pointer.
  final String text;

  /// The story or FR a record entry names; null on any other doc.
  final String? item;

  /// The path the entry names, from [base].
  final String path;

  /// The folder [path] is read from.
  final Directory base;

  /// The fingerprint the entry ends in; null with none.
  final String? recorded;
}

/// Returns the code-link entry on file [line] of [doc]; null when none stands
/// there.
_Entry? _entryAt(CheckContext context, IndexedDoc doc, int line) {
  final type = context.typeOf(doc);
  if (type == null) return null;
  final lines = context.linesOf(doc);
  if (recordDocOf(context, doc) != null) {
    final root = context.targets
        .where((target) => target.name == doc.target)
        .map(context.codeRootOf)
        .firstOrNull;
    if (root == null) return null;
    final recordEntry =
        _recordEntryAt(
          lines,
          recordCodeFieldOf(type)?.id,
          line,
          root,
          hasFingerprint: true,
        ) ??
        _recordEntryAt(
          lines,
          recordTestFieldOf(type)?.id,
          line,
          root,
          hasFingerprint: false,
        );
    // A record's `covers` entries are plain pointers, read as any doc's.
    if (recordEntry != null) return recordEntry;
  }
  final target = ownerTargetOf(doc, context.targets);
  for (final field in coversFieldsOf(type)) {
    final base = readsFromProjectRoot(field)
        ? context.projectRoot
        : (target == null ? null : context.codeRootOf(target));
    if (base == null) continue;
    for (final YamlEntry(:value, line: entryLine) in lines.entriesOf(
      field.id,
    )) {
      if (entryLine != line || value is! String) continue;
      final entry = CodeLinkEntry(value);
      return _Entry(
        text: entry.pointer,
        path: entry.pointer,
        base: base,
        recorded: entry.fingerprint,
      );
    }
  }
  return null;
}

_Entry? _recordEntryAt(
  DocLines lines,
  String? fieldId,
  int line,
  Directory root, {
  required bool hasFingerprint,
}) {
  if (fieldId == null) return null;
  for (final YamlEntry(:value, line: entryLine) in lines.entriesOf(fieldId)) {
    if (entryLine != line || value is! String) continue;
    final parsed = recordCodeLineOf(value);
    if (parsed == null) return null;
    final code = CodeLinkEntry(parsed.code);
    final pointer = hasFingerprint ? code.pointer : parsed.code;
    return _Entry(
      text: '${parsed.item}:$pointer',
      path: ImplementsEntry(pointer).path,
      base: root,
      item: parsed.item,
      recorded: hasFingerprint ? code.fingerprint : null,
    );
  }
  return null;
}

// MARK: - Task refs

/// Returns one `remove-task` line per task a commit that changed a link's code
/// closes, for each link of [group] it came from.
///
/// The candidates are the tasks of the `task_ref` entries of the docs that
/// cover the link.
List<String> _removeTaskLines(
  CheckContext context,
  CodeRepos repos,
  SyncGroup group,
) {
  final lines = <String>[];
  for (final work in group.links) {
    final candidates = {
      for (final doc in work.coveringDocs)
        for (final entry in taskRefEntriesOf(context, doc)) entry.ref.task,
    };
    if (candidates.isEmpty) continue;
    final closed = {
      for (final message in _messagesSince(repos, work))
        ...closedTasks(message, candidates),
    }.toList()..sort();
    final entry = closed.isEmpty
        ? null
        : _entryAt(context, work.doc, work.link.line);
    if (entry == null) continue;
    lines.addAll([
      for (final task in closed)
        'remove-task $task ${work.doc.docPath} ${entry.text}',
    ]);
  }
  return lines;
}

/// Returns the message of each commit that changed [work]'s code since its
/// diff base, or in all its history with no base; none when git fails.
List<String> _messagesSince(CodeRepos repos, SyncLinkWork work) {
  try {
    final base = work.base;
    final String top;
    final String? path;
    if (base == null) {
      final entry = normalCodeEntry(work.link.path);
      final place = repos.placeOf(work.link.root, entry);
      if (place == null) return const [];
      top = place.top;
      path = place.repoPathOf(entry);
    } else {
      top = base.repo.path;
      path = base.repoPath;
    }
    if (path == null) return const [];
    return _nulFields(
      _git(top, [
        'log',
        '--format=%B%x00',
        if (base != null) '${base.commit}..HEAD',
        '--',
        if (path.isEmpty) '.' else path,
      ]),
    );
  } on ProcessException {
    return const [];
  }
}

// MARK: - Renames

/// Returns the path [path], from [base], became when the newest commit that
/// removed it shows a rename, followed through later renames to the path that
/// exists now; null when git shows none, [path] still stands at `HEAD`, no
/// path in the chain exists, or git fails.
String? _renamedTo(CodeRepos repos, Directory base, String path) {
  final entry = normalCodeEntry(path);
  if (entry.isEmpty || entry.startsWith(_parentSegment)) return null;
  try {
    final place = repos.placeOf(base, entry);
    final start = place?.repoPathOf(entry);
    if (place == null || start == null || _isAtHead(place.top, start)) {
      return null;
    }
    var from = start;
    final seen = {from};
    while (true) {
      final removed = _gitLines(place.top, [
        'log',
        '--no-renames',
        '--diff-filter=D',
        '--format=%H',
        '-n',
        '1',
        '--',
        from,
      ]).firstOrNull;
      final renamed = removed == null
          ? null
          : _renameIn(place.top, removed, from);
      final renamedPath = renamed == null ? null : place.rootPathOf(renamed);
      if (renamed == null || renamedPath == null || !seen.add(renamed)) {
        return null;
      }
      if (FileSystemEntity.typeSync('${place.top}/$renamed') !=
          FileSystemEntityType.notFound) {
        return renamedPath;
      }
      from = renamed;
    }
  } on ProcessException {
    return null;
  }
}

bool _isAtHead(String top, String repoPath) =>
    runRealGitBytes([
      'cat-file',
      '-e',
      'HEAD:$repoPath',
    ], workingDirectory: top).exitCode ==
    0;

/// Returns the path [from] became in [commit] when git reports it as a
/// rename there.
String? _renameIn(String top, String commit, String from) {
  final fields = _nulFields(
    _git(top, [
      'diff-tree',
      '-r',
      '-M',
      '--name-status',
      '-z',
      '--no-commit-id',
      commit,
    ]),
  );
  for (var i = 0; i < fields.length;) {
    final status = fields[i];
    final isPair =
        status.startsWith(_renameStatus) || status.startsWith(_copyStatus);
    if (status.startsWith(_renameStatus) &&
        i + 2 < fields.length &&
        fields[i + 1] == from) {
      return fields[i + 2];
    }
    i += isPair ? 3 : 2;
  }
  return null;
}

String _git(String top, List<String> arguments) {
  final result = runRealGitBytes([
    _literalPathspecs,
    ...arguments,
  ], workingDirectory: top);
  if (result.exitCode != 0) {
    throw ProcessException(
      'git',
      arguments,
      '${result.stderr}'.trim(),
      result.exitCode,
    );
  }
  return gitStdoutText(result.stdout);
}

List<String> _gitLines(String top, List<String> arguments) =>
    const LineSplitter().convert(_git(top, arguments));

List<String> _nulFields(String text) => [
  for (final field in text.split('\u0000'))
    if (field.isNotEmpty) field,
];

// MARK: - Matrix rows

/// One `row` line in the making: a matrix row and the literals it swaps.
final class _RowFix {
  new({
    required this.record,
    required this.entry,
    this.fingerprint,
    this.judged,
  });

  final String record;
  final String entry;

  /// The fingerprint of the FR or edge-case block the row is stamped against,
  /// as `check` computes it; null when the block cannot be read.
  final String? fingerprint;

  /// The FR the row's `?` line is judged against; null when it is not found.
  final SyncJudgedDoc? judged;
  final List<String> changes = [];

  String get line => 'row $record $entry: ${changes.join(' ')}';

  /// The `?` line with the block fingerprint; null without one.
  String? get question => switch (fingerprint) {
    final fingerprint? => _question(record, entry, fingerprint),
    null => null,
  };
}

/// Adds to [fixes] the swap the test file's diff gives for the literal a
/// `matrix_test_unresolved` [finding] names; adds nothing when it gives none.
void _collectRowFix(
  CheckContext context,
  CodeRepos repos,
  Finding finding,
  Map<String, _RowFix> fixes,
) {
  final old = finding.keys[_testKey];
  final record = context.index.at(finding.path);
  final type = record == null ? null : context.typeOf(record);
  final testField = type == null ? null : recordTestFieldOf(type);
  if (old is! String || record == null || testField == null) return;
  final row = record.matrixLines
      .whereType<TestRow>()
      .where((row) => row.line == finding.line)
      .firstOrNull;
  final root = context.targets
      .where((target) => target.name == record.target)
      .map(context.codeRootOf)
      .firstOrNull;
  if (row == null || root == null) return;
  final paths = {
    for (final test in recordTestLinesOf(record, testField))
      if (test.item == row.item) test.path,
  };
  for (final path in paths) {
    final replacement = _replacementOf(repos, root, path, old);
    if (replacement == null) continue;
    final fr = syncOwnerOf(context, record, row.item);
    fixes
        .putIfAbsent(
          _rowKey(finding.path, finding.line),
          () => _RowFix(
            record: finding.path,
            entry: row.edgeCase == null
                ? row.item
                : '${row.item} ${row.edgeCase}',
            fingerprint: _blockFingerprintOf(context, fr, row),
            judged: fr == null
                ? null
                : SyncJudgedDoc(doc: fr, root: root, path: path),
          ),
        )
        .changes
        .addAll(['+${codeSpanOf(replacement)}', '-${codeSpanOf(old)}']);
    return;
  }
}

/// Returns the fingerprint of the block [row] of [fr] is stamped against: the
/// contract block of [fr], or its edge case; null when it has none.
String? _blockFingerprintOf(CheckContext context, IndexedDoc? fr, TestRow row) {
  if (fr == null) return null;
  final edgeCase = row.edgeCase;
  final block = edgeCase == null
      ? contractBlockOf(context, fr)?.text
      : edgeCaseBlocksOf(context, fr)[edgeCase];
  return block == null ? null : fingerprintOf(block);
}

/// Returns the literal that replaced [old] in the newest commit of the test
/// file at [path] that changed how often [old] occurs: the string at the same
/// place on the line added in place of the removed line that held [old].
String? _replacementOf(
  CodeRepos repos,
  Directory root,
  String path,
  String old,
) {
  final entry = normalCodeEntry(path);
  try {
    final place = repos.placeOf(root, entry);
    final repoPath = place?.repoPathOf(entry);
    if (place == null || repoPath == null) return null;
    final patch = _git(place.top, [
      'log',
      '--no-renames',
      '--no-color',
      '--no-ext-diff',
      '--no-textconv',
      '-U0',
      '-n',
      '1',
      '-S$old',
      '-p',
      '--format=',
      '--',
      repoPath,
    ]);
    return _swapIn(patch, old);
  } on ProcessException {
    return null;
  }
}

/// Returns the string that stands for [old] in the first hunk of [patch] that
/// swaps a removed line holding it for an added line; null when none does.
String? _swapIn(String patch, String old) {
  var removed = <String>[];
  var added = <String>[];
  var isInHunk = false;
  String? closeHunk() {
    final swap = _swapInHunk(removed, added, old);
    removed = [];
    added = [];
    return swap;
  }

  for (final line in const LineSplitter().convert(patch)) {
    if (line.startsWith(_diffFileMark) || line.startsWith(_hunkMark)) {
      if (closeHunk() case final swap?) return swap;
      isInHunk = line.startsWith(_hunkMark);
    } else if (isInHunk && line.startsWith('-')) {
      removed.add(line.substring(1));
    } else if (isInHunk && line.startsWith('+')) {
      added.add(line.substring(1));
    }
  }
  return closeHunk();
}

String? _swapInHunk(List<String> removed, List<String> added, String old) {
  for (final (i, line) in removed.indexed) {
    if (i >= added.length) return null;
    final before = _quotedIn(line);
    final after = _quotedIn(added[i]);
    final at = before.indexOf(old);
    if (at < 0 || at >= after.length) continue;
    final swap = after[at];
    if (swap.isNotEmpty && swap != old) {
      return swap;
    }
  }
  return null;
}

List<String> _quotedIn(String line) => [
  for (final match in _quoted.allMatches(line)) match[1] ?? match[2]!,
];

/// Returns the line of an `unconfirmed` or `suspect` matrix-row [finding]: a
/// `match` for an `unconfirmed` row with `waitsFor` `agent` whose literals all
/// resolve and whose FR is no draft; else a `?` line.
List<String> _matrixLines(
  CheckContext context,
  Finding finding,
  Set<String> unresolvedRows,
) {
  final label = finding.keys['link'];
  final fingerprint = finding.keys[_fingerprintKey];
  if (label is! String || fingerprint is! String) return const [];
  final entry = label.replaceFirst('#', ' ');
  final frPath = docPathOfProjectPath('${finding.keys['targetPath']}');
  final isDeclared =
      finding.kind == FindingKind.unconfirmed &&
      finding.isForAgent &&
      !unresolvedRows.contains(_rowKey(finding.path, finding.line)) &&
      frPath != null &&
      context.index.at(frPath)?.isDraft == false;
  return [
    if (isDeclared)
      'match ${finding.path} $entry $fingerprint'
    else
      _question(finding.path, entry, fingerprint),
  ];
}
