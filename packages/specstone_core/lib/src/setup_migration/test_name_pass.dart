import 'dart:io';

import 'package:specstone_core/src/canonical_path.dart'
    show pathInside, withNativeSeparators;
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart' show withKeyBlock;
import 'package:specstone_core/src/doc_model/number_label.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show readDocAddress;
import 'package:specstone_core/src/document_writing/rewrite_records.dart'
    as rewrite_records;
import 'package:specstone_core/src/git_process.dart' show RunGit, runRealGit;
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/parents.dart'
    show resolveParents;
import 'package:specstone_core/src/index_query/record_entries.dart'
    show recordTestFieldOf, recordTestLineOf;
import 'package:specstone_core/src/plan_hash.dart' show readPlanInput;
import 'package:specstone_core/src/rendering/formatter.dart' show layOutDoc;
import 'package:specstone_core/src/setup_migration/legacy_rewrites.dart'
    show DocText, readDocText, writtenText;
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/setup_migration/record_placement.dart'
    show NewRecord;
import 'package:specstone_core/src/setup_migration/run_plan.dart'
    show PlannedCreate, PlannedRewrite, draftNote;
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/code_target.dart'
    show
        CodeTarget,
        codeRootFolderOf,
        nestedRootsOf,
        targetNamesOf,
        twinNamesOf;
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:yaml/yaml.dart';

// MARK: - Constants

const _docsFolder = 'docs/';
const _specstoneFolder = '.specstone/';
const _projectTop = '.';
const _separator = '/';
const _listSeparator = '\x00';
const _change = 'move test-name ids';

/// The text after a test name's ID that is the separator, longest first; the
/// text after the separator is the name.
const _nameSeparators = [': ', ' — ', ' - ', ' '];

/// A call that declares a test or group, matched through the quote that opens
/// its name: a callee whose last identifier is `test`, `testWidgets`, `group`,
/// `it`, `describe`, or `context`, or ends in `Test` or, after a word, `_test`
/// (a wrapper such as `pathTest`), with an optional receiver and member
/// (`Deno.test.skip`). A longer word that only contains `test` (`contest`,
/// `latest`), a bare `_test` helper, and a lower-case wrapper (`pathtest`) are
/// no call.
final _declaringCall = RegExp(
  r'(?<![\w$])(?:test|testWidgets|group|it|describe|context|\w*Test|\w+_test)'
  '(?:\\.\\w+)?\\s*\\(\\s*(?=[\'"])',
);

final _nameRun = RegExp('^[a-z0-9_]+(?:/[a-z0-9_]+)*');
final _caseSuffix = RegExp(r'/([es]\d+)(?![A-Za-z0-9_])');
final _caseItemId = RegExp(r'^[ES]\d+$');

// MARK: - Types

/// A typed doc as the pass reads it: its DocPath after the moves, its doc type
/// and code target, and its LF text after the passes before this one.
typedef TestNameDoc = ({
  String plannedPath,
  MergedDocType? type,
  String? target,
  String lf,
});

/// The test-name pass of the upgrade that moves `software-tech` to the release
/// whose records name tests: each test name that opens with the ID of one
/// story or FR moves that ID into the item's record as a `tests` line, and the
/// ID leaves the name in every file the project's repository tracks.
///
/// A test name is any one-line string literal that opens with a doc ID, so no
/// language is parsed; a string that is no test call but opens with an ID is
/// read too, and its count and its `--json` entry show it.
final class TestNamePass {
  new _({
    required this.recordEdits,
    required this.recordCreates,
    required this.fileRewrites,
    required this.recordLines,
    required this.rewrittenFiles,
    required this.left,
    required this.planLine,
    required this.json,
  });

  /// Plans the pass over the test files of [root], the canonical project root.
  ///
  /// The files are the ones git tracks under each code root of [targets], in
  /// the project's repository and in each repository whose top [agentFileRoots]
  /// lists, never the docs root or `.specstone/`. [docs]
  /// are the typed docs of the run; [resolveLabel] gives the DocPath one label
  /// names, or null. [isTaken] says whether a DocPath holds an entry once the
  /// run's moves ran, and [pendingCreates] are the records the run already
  /// creates. Each file holding a test name is a plan input.
  ///
  /// Throws `MigrateFault` `git_failed` when `git ls-files` fails in a
  /// repository.
  factory plan({
    required Directory root,
    required MergedSet set,
    required List<CodeTarget> targets,
    required List<String> agentFileRoots,
    required List<TestNameDoc> docs,
    required String? Function(NumberLabel label) resolveLabel,
    required bool Function(String docPath) isTaken,
    List<PlannedCreate> pendingCreates = const [],
    RunGit runGit = runRealGit,
  }) {
    final recordType = set.recordDocType;
    if (recordType == null) return _empty();
    final testsKey = recordTestFieldOf(recordType)?.id;
    if (testsKey == null) return _empty();
    final tree = _ItemTree(set, recordType, docs, [
      for (final create in pendingCreates)
        (docPath: create.path.substring(_docsFolder.length), text: create.text),
    ], isTaken);
    final names = _scan(
      root: root,
      targets: targets,
      agentFileRoots: agentFileRoots,
      tree: tree,
      resolveLabel: resolveLabel,
      runGit: runGit,
    );
    if (names.isEmpty) return _empty();
    final records = _RecordWriter(
      recordType,
      testsKey,
      tree,
      twinNamesOf(targetNamesOf(targets)).isNotEmpty,
    )..write(names);
    return _result(names, records);
  }

  static TestNamePass _empty() => TestNamePass._(
    recordEdits: const {},
    recordCreates: const [],
    fileRewrites: const [],
    recordLines: const [],
    rewrittenFiles: const [],
    left: 0,
    planLine: null,
    json: const {'written': [], 'rewritten': [], 'left': []},
  );

  /// The new text of each record the run holds, by DocPath; a record the run
  /// creates is in it too.
  final Map<String, String> recordEdits;

  /// The records the pass creates, as drafts, in DocPath order.
  final List<NewRecord> recordCreates;

  /// Returns [held], the records the run creates, with the lines the pass
  /// adds to each, then the records the pass creates, as drafts; all in path
  /// order.
  List<PlannedCreate> recordsOver(List<PlannedCreate> held) => [
    for (final create in held)
      PlannedCreate(
        path: create.path,
        text:
            recordEdits[create.path.substring(_docsFolder.length)] ??
            create.text,
        note: create.note,
      ),
    for (final record in recordCreates)
      PlannedCreate(
        path: '$_docsFolder${record.docPath}',
        text: record.text,
        note: draftNote,
      ),
  ]..sort((a, b) => compareCodePoints(a.path, b.path));

  /// The test files whose names lose their ID, the project's repository's
  /// alone, in path order.
  final List<PlannedRewrite> fileRewrites;

  /// Each line the pass writes, `<record DocPath> <item>:<path>`, in order.
  final List<String> recordLines;

  /// The ProjectPath of each file in [fileRewrites].
  final List<String> rewrittenFiles;

  /// The test names kept as written: one whose ID resolves to no story or FR,
  /// and one the run cannot strip.
  final int left;

  /// The plan line, or null when the run finds no test name.
  final String? planLine;

  /// The `tests` object of the JSON plan: `written`, `rewritten`, and `left`.
  ///
  /// `rewritten` and `left` list each name whose ID resolves; a name that
  /// resolves to no story or FR counts in [left] and is not listed.
  final Map<String, Object?> json;
}

TestNamePass _result(List<_Name> names, _RecordWriter records) {
  final stripped = [
    for (final name in names)
      if (name.strips && !records.isBlocked(name)) name,
  ];
  final kept = [
    for (final name in names)
      if (!stripped.contains(name)) name,
  ];
  final files = _fileRewritesOf(stripped);
  final lines = records.lines;
  final listedLeft = [
    for (final name in kept)
      if (name.item != null) name,
  ];
  return TestNamePass._(
    recordEdits: records.edits,
    recordCreates: records.creates,
    fileRewrites: files,
    recordLines: lines,
    rewrittenFiles: [for (final file in files) file.path],
    left: kept.length,
    planLine:
        'tests: ${lines.length} lines in ${records.touched} records; '
        'names: ${stripped.length} rewritten in ${files.length} files; '
        'left: ${kept.length}',
    json: {
      'written': lines,
      'rewritten': [for (final name in stripped) name.json],
      'left': [for (final name in listedLeft) name.json],
    },
  );
}

// MARK: - Scanning

/// One test name: where it sits, what it names, and how to strip its ID.
final class _Name {
  new({
    required this.file,
    required this.absolute,
    required this.line,
    required this.start,
    required this.end,
    required this.written,
    required this.item,
    required this.suffix,
    required this.target,
    required this.codePath,
    required this.replacement,
    required this.isOwnRepository,
  });

  /// The ProjectPath of the test file, or its absolute path outside the
  /// project root.
  final String file;

  /// The path the file is read at.
  final String absolute;

  /// The 0-based line of the file.
  final int line;

  /// The offsets of the literal's text in its line.
  final int start;
  final int end;

  /// The literal's text as written.
  final String written;

  /// The story or FR the ID names; null when it names none.
  final _Item? item;

  /// The edge case or scenario ID the suffix names, or null.
  final String? suffix;

  /// The code target whose root holds the file.
  final CodeTarget target;

  /// The file's path from the code root of [target].
  final String codePath;

  /// The literal's text without the ID, or null when the run cannot write one.
  final String? replacement;

  /// Whether the project's repository tracks the file, so the run can commit
  /// its rewrite.
  final bool isOwnRepository;

  bool get strips => item != null && replacement != null && isOwnRepository;

  Map<String, Object?> get json => {
    'file': file,
    'name': written,
    'item': item?.name,
    'edgeCase': suffix != null && suffix!.startsWith('E') ? suffix : null,
    'scenario': suffix != null && suffix!.startsWith('S') ? suffix : null,
  };
}

/// A story or FR: its name, its feature, and its name relative to the feature.
typedef _Item = ({
  String name,
  String docPath,
  String title,
  IndexedDoc feature,
  String relative,
});

List<_Name> _scan({
  required Directory root,
  required List<CodeTarget> targets,
  required List<String> agentFileRoots,
  required _ItemTree tree,
  required String? Function(NumberLabel label) resolveLabel,
  required RunGit runGit,
}) {
  final names = <_Name>[];
  for (final file in _trackedFilesOf(root, agentFileRoots, runGit)) {
    final owner = _ownerOf(root, targets, file.path);
    if (owner == null) continue;
    final DocText text;
    try {
      text = readDocText(File(file.path).readAsBytesSync());
    } on FormatException {
      continue;
    } on FileSystemException {
      continue;
    }
    final projectPath = pathInside(root.path, file.path);
    final shown = projectPath ?? file.path;
    final lines = text.lf.split('\n');
    final before = names.length;
    final nameQuotes = _nameQuoteOffsets(text.lf);
    var lineStart = 0;
    for (final (index, line) in lines.indexed) {
      final lineOffset = lineStart;
      lineStart += line.length + 1;
      for (final literal in _literalsOf(line)) {
        if (!nameQuotes.contains(lineOffset + literal.start - 1)) continue;
        final read = _readOpening(literal.text, tree, resolveLabel);
        if (read == null) continue;
        names.add(
          _Name(
            file: shown,
            absolute: file.path,
            line: index,
            start: literal.start,
            end: literal.end,
            written: literal.text,
            item: read.item,
            suffix: read.suffix,
            target: owner.target,
            codePath: owner.path,
            replacement: read.replacement(literal.quote),
            isOwnRepository: file.isOwnRepository && projectPath != null,
          ),
        );
      }
    }
    if (names.length > before) readPlanInput(File(file.path));
  }
  return names;
}

/// The files git tracks under each repository the run reads, never one twice.
List<({String path, bool isOwnRepository})> _trackedFilesOf(
  Directory root,
  List<String> agentFileRoots,
  RunGit runGit,
) {
  final seen = <String>{};
  final files = <({String path, bool isOwnRepository})>[];
  for (final top in [_projectTop, ...agentFileRoots]) {
    final folder = Directory(repositoryFolderOf(root.path, top));
    for (final relative in _trackedIn(folder, runGit)) {
      final path = _nativePath(folder.path, relative);
      if (seen.add(path)) {
        files.add((path: path, isOwnRepository: top == _projectTop));
      }
    }
  }
  return files;
}

/// Returns the folder of the repository whose top is [top], `.` for the
/// project's own or a `/`-separated path from [root], in the platform's
/// separators as [root] is; [isWindows] picks the style.
String repositoryFolderOf(String root, String top, {bool? isWindows}) =>
    top == _projectTop
    ? root
    : withNativeSeparators('$root/$top', isWindows: isWindows);

String _nativePath(String folder, String relative) =>
    '$folder${Platform.pathSeparator}'
    '${relative.split(_separator).join(Platform.pathSeparator)}';

/// Returns the files [folder]'s repository tracks under it, by their path from
/// [folder]; none when [folder] is no work tree with a first commit.
List<String> _trackedIn(Directory folder, RunGit runGit) {
  try {
    final head = runGit([
      'rev-parse',
      '--verify',
      '-q',
      'HEAD',
    ], workingDirectory: folder.path);
    if (head.exitCode != 0) return const [];
    final listing = runGit(['ls-files', '-z'], workingDirectory: folder.path);
    if (listing.exitCode != 0) {
      throw MigrateFault(
        MigrateFaultCode.gitFailed,
        'git ls-files failed: ${'${listing.stderr}'.trim()}; fix the cause, '
        'then run the command again',
      );
    }
    return [
      for (final path in (listing.stdout as String).split(_listSeparator))
        if (path.isNotEmpty) path,
    ];
  } on ProcessException {
    return const [];
  } on FileSystemException {
    return const [];
  } on MigrateFault catch (fault) {
    if (fault.code != MigrateFaultCode.gitWorkTreeRequired) rethrow;
    return const [];
  }
}

/// Returns the target whose code root holds the file at [absolute] and the
/// file's path from that root, or null for a file no target reads: one under
/// the docs root, `.specstone/`, or the root of another target nested in its
/// own.
({CodeTarget target, String path})? _ownerOf(
  Directory root,
  List<CodeTarget> targets,
  String absolute,
) {
  final fromProject = pathInside(root.path, absolute);
  if (fromProject != null &&
      (fromProject.startsWith(_docsFolder) ||
          fromProject.startsWith(_specstoneFolder))) {
    return null;
  }
  for (final target in targets) {
    final path = pathInside(codeRootFolderOf(root, target).path, absolute);
    if (path == null) continue;
    final nested = nestedRootsOf(root, target, targets);
    if (nested.any((own) => path == own || path.startsWith('$own/'))) {
      continue;
    }
    return (target: target, path: path);
  }
  return null;
}

/// Returns the offsets in [lf] of the quote that opens the name argument of a
/// call that declares a test or group, the call's first argument on the same
/// line or a later one.
Set<int> _nameQuoteOffsets(String lf) => {
  for (final call in _declaringCall.allMatches(lf)) call.end,
};

/// A string literal of one line: the offsets of its text, the text, and the
/// quote that opens it.
typedef _Literal = ({int start, int end, String text, String quote});

/// Returns the string literals of [line], the text between a matching pair of
/// `'` or `"`; a backslash keeps the character after it inside the literal.
List<_Literal> _literalsOf(String line) {
  final literals = <_Literal>[];
  var at = 0;
  while (at < line.length) {
    final quote = line[at];
    if (quote != "'" && quote != '"') {
      at++;
      continue;
    }
    final close = _closingQuote(line, at + 1, quote);
    if (close < 0) {
      at++;
      continue;
    }
    literals.add((
      start: at + 1,
      end: close,
      text: line.substring(at + 1, close),
      quote: quote,
    ));
    at = close + 1;
  }
  return literals;
}

int _closingQuote(String line, int from, String quote) {
  for (var i = from; i < line.length; i++) {
    if (line[i] == r'\') {
      i++;
    } else if (line[i] == quote) {
      return i;
    }
  }
  return -1;
}

/// The ID a string opens with and what follows it.
final class _Opening {
  const new({required this.item, required this.suffix, required this.rest});

  /// The story or FR the ID names; null for a label that names none.
  final _Item? item;

  /// The edge case or scenario ID the ID's suffix names.
  final String? suffix;

  /// The name that stays once the ID and its separator leave.
  final String rest;

  /// The literal's text without its ID: [rest], or the doc's title for a name
  /// that was the ID alone; null when the title cannot sit in a literal.
  String? replacement(String quote) {
    final item = this.item;
    if (item == null) return null;
    if (rest.isNotEmpty) return rest;
    final title = item.title;
    final isSafe =
        title.isNotEmpty &&
        !title.contains(quote) &&
        !title.contains(r'\') &&
        !title.contains(r'$');
    return isSafe ? title : null;
  }
}

/// Reads the ID [text] opens with, as a label or as a Name, or null when it
/// opens with none or the ID is not followed by a separator.
_Opening? _readOpening(
  String text,
  _ItemTree tree,
  String? Function(NumberLabel label) resolveLabel,
) {
  final labels = numberLabelsIn(text);
  if (labels.isNotEmpty && labels.first.start == 0) {
    return _labelOpening(text, labels.first, tree, resolveLabel);
  }
  return _nameOpening(text, tree);
}

_Opening? _labelOpening(
  String text,
  NumberLabel label,
  _ItemTree tree,
  String? Function(NumberLabel label) resolveLabel,
) {
  var end = label.end;
  String? suffix;
  final itemId = label.itemId;
  if (itemId != null && _caseItemId.hasMatch(itemId)) {
    suffix = itemId;
    end += 1 + itemId.length;
  } else if (_caseSuffix.matchAsPrefix(text, end) case final match?) {
    suffix = match.group(1)!.toUpperCase();
    end = match.end;
  }
  final rest = _afterSeparator(text, end);
  if (rest == null) return null;
  final docPath = resolveLabel(_withoutItemId(label));
  return _Opening(item: tree.itemAt(docPath), suffix: suffix, rest: rest);
}

_Opening? _nameOpening(String text, _ItemTree tree) {
  final run = _nameRun.firstMatch(text)?.group(0);
  if (run == null) return null;
  final segments = run.split(_separator);
  for (var count = segments.length; count >= 2; count--) {
    final candidate = segments.take(count).join(_separator);
    if (!readDocAddress(candidate).isName) continue;
    final item = tree.itemNamed(candidate);
    if (item == null) continue;
    var end = candidate.length;
    String? suffix;
    if (_caseSuffix.matchAsPrefix(text, end) case final match?) {
      suffix = match.group(1)!.toUpperCase();
      end = match.end;
    }
    final rest = _afterSeparator(text, end);
    return rest == null
        ? null
        : _Opening(item: item, suffix: suffix, rest: rest);
  }
  return null;
}

/// Returns [text] after the ID that ends at [end] and its separator, `''` for
/// an ID alone, or null when anything else follows the ID.
String? _afterSeparator(String text, int end) {
  if (end == text.length) return '';
  for (final separator in _nameSeparators) {
    if (text.startsWith(separator, end)) {
      return text.substring(end + separator.length);
    }
  }
  return null;
}

NumberLabel _withoutItemId(NumberLabel label) => NumberLabel(
  start: label.start,
  end: label.end,
  written: label.written,
  shape: label.shape,
  feature: label.feature,
  story: label.story,
  fr: label.fr,
  slug: label.slug,
  prefix: label.prefix,
  isPartOfPath: label.isPartOfPath,
);

// MARK: - Files

/// Returns the rewrite of each file whose names [stripped] leave without
/// their ID, in path order.
List<PlannedRewrite> _fileRewritesOf(List<_Name> stripped) {
  final byFile = <String, List<_Name>>{};
  for (final name in stripped) {
    (byFile[name.file] ??= []).add(name);
  }
  return [
    for (final path in byFile.keys.toList()..sort(compareCodePoints))
      _rewriteOf(path, byFile[path]!),
  ];
}

PlannedRewrite _rewriteOf(String path, List<_Name> names) {
  final original = readDocText(readPlanInput(File(names.first.absolute)));
  final lines = original.lf.split('\n');
  final ordered = [...names]
    ..sort((a, b) {
      final byLine = a.line.compareTo(b.line);
      return byLine != 0 ? byLine : b.start.compareTo(a.start);
    });
  for (final name in ordered) {
    final line = lines[name.line];
    lines[name.line] =
        '${line.substring(0, name.start)}${name.replacement}'
        '${line.substring(name.end)}';
  }
  return PlannedRewrite(
    path: path,
    text: writtenText(original, lines.join('\n')),
    before: original.hash,
    changes: const [_change],
  );
}

// MARK: - Items

/// The stories and FRs of the run, the features above them, and the records
/// the run holds.
final class _ItemTree {
  new(
    this._set,
    this._recordType,
    List<TestNameDoc> docs,
    List<NewRecord> pending,
    this.isTaken,
  ) {
    final indexed = <String, IndexedDoc>{};
    for (final doc in docs) {
      final type = doc.type;
      if (type == null) continue;
      final item = IndexedDoc(
        docPath: doc.plannedPath,
        docTypeId: type.id,
        name: docNameOf(doc.plannedPath, type, target: doc.target),
        frontmatter: const {},
        tokens: 0,
      );
      indexed[doc.plannedPath] = item;
      _docs[doc.plannedPath] = doc;
      if (type.id == _recordType.id) {
        _records[(item.name, doc.target)] = doc.plannedPath;
        _texts[doc.plannedPath] = doc.lf;
      }
    }
    for (final record in pending) {
      _texts[record.docPath] = record.text;
    }
    final parents = resolveParents(indexed.values, _set).parents;
    for (final doc in indexed.values) {
      if (doc.docTypeId != storyType && doc.docTypeId != frType) continue;
      final feature = _featureOf(doc, indexed, parents);
      if (feature == null) continue;
      final item = (
        name: doc.name,
        docPath: doc.docPath,
        title: Doc.parse(_docs[doc.docPath]!.lf).title ?? '',
        feature: feature,
        relative: doc.name.substring(feature.name.length + 1),
      );
      _byPath[doc.docPath] = item;
      _byName[doc.name] = item;
    }
    _pending = {for (final record in pending) record.docPath};
  }

  final MergedSet _set;
  final MergedDocType _recordType;

  /// Whether a DocPath holds an entry once the run's moves ran.
  final bool Function(String docPath) isTaken;
  final _docs = <String, TestNameDoc>{};
  final _byPath = <String, _Item>{};
  final _byName = <String, _Item>{};
  final _records = <(String, String?), String>{};
  final _texts = <String, String>{};
  late final Set<String> _pending;

  _Item? itemAt(String? docPath) => docPath == null ? null : _byPath[docPath];

  _Item? itemNamed(String name) => _byName[name];

  /// Returns the DocPath of the record of [featureName] in [target], or null.
  String? recordPathOf(String featureName, String? target) =>
      _records[(featureName, target)];

  /// Returns the text of the record at [docPath] the run holds.
  String? textOf(String docPath) => _texts[docPath];

  /// Whether the run creates the record at [docPath] already.
  bool isPending(String docPath) => _pending.contains(docPath);

  /// Returns the new record of [feature] in [target]; null when the record
  /// doc type has no path for it.
  ({String docPath, String text})? newRecordOf(
    IndexedDoc feature,
    String? target,
  ) {
    final featureType = _set.lookup(feature.docTypeId!);
    if (featureType == null) return null;
    return rewrite_records.newRecordOf(
      _set,
      _recordType,
      featureType: featureType,
      featureDocPath: feature.docPath,
      featureName: feature.name,
      lines: (statuses: const [], code: const [], tests: const []),
      target: target,
    );
  }

  static IndexedDoc? _featureOf(
    IndexedDoc doc,
    Map<String, IndexedDoc> indexed,
    Map<String, String> parents,
  ) {
    var at = doc;
    while (at.docTypeId != featureType) {
      final parent = indexed[parents[at.docPath]];
      if (parent == null) return null;
      at = parent;
    }
    return at;
  }
}

// MARK: - Records

/// Writes the `tests` lines of the names into their records.
final class _RecordWriter {
  new(this._recordType, this._testsKey, this._tree, this._hasTwins);

  final MergedDocType _recordType;
  final String _testsKey;
  final _ItemTree _tree;
  final bool _hasTwins;

  /// The new text of each record the pass writes, by DocPath.
  final edits = <String, String>{};
  final _created = <String>{};
  final _blocked = <_Name>{};

  /// Each line written, `<record DocPath> <item>:<path>`.
  final lines = <String>[];

  /// How many records gain a line.
  int get touched => edits.length;

  /// The new records, in DocPath order.
  List<NewRecord> get creates => [
    for (final path in _created.toList()..sort(compareCodePoints))
      (docPath: path, text: edits[path]!),
  ];

  bool isBlocked(_Name name) => _blocked.contains(name);

  void write(List<_Name> names) {
    final byRecord = <(String, String?), List<_Name>>{};
    for (final name in names) {
      final item = name.item;
      if (item == null) continue;
      final target = _hasTwins ? name.target.name : null;
      (byRecord[(item.feature.name, target)] ??= []).add(name);
    }
    final keys = byRecord.keys.toList()
      ..sort((a, b) => compareCodePoints('${a.$1} ${a.$2}', '${b.$1} ${b.$2}'));
    for (final key in keys) {
      _writeRecord(key.$1, key.$2, byRecord[key]!);
    }
  }

  void _writeRecord(String featureName, String? target, List<_Name> names) {
    final feature = names.first.item!.feature;
    final wanted = {
      for (final name in names) '${name.item!.relative}:${name.codePath}',
    }.toList()..sort(compareCodePoints);
    var docPath = _tree.recordPathOf(featureName, target);
    String? text;
    var isNew = false;
    if (docPath != null) {
      text = _tree.textOf(docPath);
    } else {
      final created = _tree.newRecordOf(feature, target);
      if (created == null) return _block(names);
      docPath = created.docPath;
      if (_tree.isPending(docPath)) {
        text = _tree.textOf(docPath);
      } else if (_tree.isTaken(docPath)) {
        return _block(names);
      } else {
        text = created.text;
        isNew = true;
      }
    }
    final added = _withTests(text!, wanted, _testsKey);
    if (added == null) return _block(names);
    if (added.lines.isEmpty) return;
    final path = docPath;
    edits[path] = isNew || _tree.isPending(path)
        ? layOutDoc(added.text, _recordType)
        : added.text;
    if (isNew) _created.add(path);
    lines.addAll([for (final line in added.lines) '$path $line']);
  }

  void _block(List<_Name> names) => _blocked.addAll(names);
}

/// Returns [lf] with [wanted] added to its `tests` lines and the lines added;
/// null when its frontmatter holds no valid YAML.
({String text, List<String> lines})? _withTests(
  String lf,
  List<String> wanted,
  String testsKey,
) {
  final blocks = Doc.parse(lf).frontmatter ?? const <KeyBlock>[];
  final block = blocks.where((b) => b.name == testsKey).firstOrNull;
  final held = <Object?>[];
  if (block != null) {
    final Object? parsed;
    try {
      parsed = loadYaml(block.text);
    } on YamlException {
      return null;
    }
    final value = parsed is YamlMap ? parsed[testsKey] : null;
    switch (value) {
      case null:
        break;
      case final YamlList list:
        held.addAll(list);
      case final other:
        held.add(other);
    }
  } else if (blocks.isNotEmpty && !_hasValidFrontmatter(blocks)) {
    return null;
  }
  final present = {
    for (final line in held)
      if (line is String)
        if (recordTestLineOf(line) case final parsed?)
          '${parsed.item}:${parsed.path}',
  };
  final added = [
    for (final line in wanted)
      if (!present.contains(line)) line,
  ];
  if (added.isEmpty) return (text: lf, lines: const []);
  final appended = block == null ? null : _withItemsAppended(block.text, added);
  final listed = [
    for (final line in [...held, ...added]) '  - ${_yamlOf(line)}\n',
  ].join();
  return (
    text: withKeyBlock(
      lf,
      testsKey,
      appended ?? '${block?.key ?? testsKey}:\n$listed',
    ),
    lines: added,
  );
}

/// Returns [blockText], a `key:` line then block-list items, with [added]
/// after its last item in the first item's indent; null when the block is
/// not in that shape, so the caller writes the list anew.
String? _withItemsAppended(String blockText, List<String> added) {
  final [keyLine, ...rest] = blockText.split('\n')..removeLast();
  if (!keyLine.trimRight().endsWith(':')) return null;
  final items = [
    for (final line in rest)
      if (line.trim().isNotEmpty && !line.trimLeft().startsWith('#')) line,
  ];
  if (items.isEmpty || items.any((line) => !line.trimLeft().startsWith('- '))) {
    return null;
  }
  final first = items.first;
  final indent = first.substring(0, first.length - first.trimLeft().length);
  final lines = [for (final line in added) '$indent- ${_yamlOf(line)}\n'];
  return '$blockText${lines.join()}';
}

bool _hasValidFrontmatter(List<KeyBlock> blocks) {
  try {
    loadYaml(blocks.map((block) => block.text).join());
    return true;
  } on YamlException {
    return false;
  }
}

/// Returns [value] as a single-quoted YAML scalar.
String _yamlOf(Object? value) => "'${'$value'.replaceAll("'", "''")}'";
