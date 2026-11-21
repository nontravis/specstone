import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/canonical_path.dart';
import 'package:specstone_core/src/doc_model/doc.dart' show fencedLines;
import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/bundle_render.dart';
import 'package:specstone_core/src/index_query/feature_pattern_parts.dart'
    show featurePatternDocAddress, featurePatternListName;
import 'package:specstone_core/src/index_query/folder_prune.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart'
    show tokenSizeOf;
import 'package:specstone_core/src/index_query/models/bundle_entry.dart';
import 'package:specstone_core/src/index_query/models/bundle_text.dart';
import 'package:specstone_core/src/index_query/models/read_plan.dart';
import 'package:specstone_core/src/index_query/out_file.dart';
import 'package:specstone_core/src/index_query/read_answer.dart'
    show ReadAnswer, nameWithType;
import 'package:specstone_core/src/rendering/build_output.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';

/// The most lines an index keeps its sections within, its header included.
const _indexLineCap = 200;

/// The most UTF-8 bytes an index keeps its sections within, its header
/// included.
const _indexByteCap = 8192;

/// The characters a file name writes as `-`: path separators and `:`.
const _nameSeparators = ['/', r'\', ':'];

/// What joins the written target arguments in a name; legal in file names on
/// Windows, macOS, and Linux.
const _targetJoint = '+';

/// What a refs file's name carries before its extension.
const _refsMark = '.refs';

/// The most UTF-8 bytes a cut name holds, which leaves room for [_refsMark].
const _cutNameByteCap = 250;

const _refsIsReadFirst = 'the refs file is the read-first file';

/// The most est. tokens one read of a read-first file holds.
///
/// Est. tokens are characters / 4. One Read counted a file of about 64,100 est.
/// tokens at 63,968 tokens, so 24,000 stays about 4% under the 25,000-token cap
/// of a Read.
const readRangeTokenLimit = 24000;

/// The code points an est. token counts, the divisor of [tokenSizeOf].
const _runesPerToken = 4;

const _headingMark = '## ';

// MARK: - Name

/// Returns the name a bare `--out` gives the bundle file.
///
/// A name, or its refs file's name, past 255 bytes is cut to at most 250 bytes
/// as [cutFileName] gives.
///
/// - [targets]: the call's target arguments, as given, each written on its own
///   and joined by `+`; else [codePath], the `--code` value as given, which
///   takes `code-` before it.
/// - [codeTarget]: the `--target` value the call passes, or null.
String bundleFileName({
  List<String> targets = const [],
  String? codePath,
  required BundleMode mode,
  required bool summary,
  required bool noProject,
  String? codeTarget,
}) {
  assert(
    targets.isNotEmpty != (codePath != null),
    'a bundle has targets or a code path',
  );
  final named = codePath == null
      ? targets.map(_slugOf).join(_targetJoint)
      : _slugOf('code-$codePath');
  final modePart = [
    mode.wire,
    if (summary) 'summary',
    if (noProject) 'no-project',
  ].join('-');
  final targetPart = codeTarget == null ? '' : '.$codeTarget';
  final tail = '.$modePart$targetPart.txt';
  final full = '$named$tail';
  final refsBytes = mode == BundleMode.query ? 0 : _refsMark.length;
  if (byteCountOf(full) + refsBytes <= fileNameByteCap) return full;
  return cutFileName(named, tail, byteCap: _cutNameByteCap);
}

/// Returns [text] with each path separator and `:` written `-`.
String _slugOf(String text) {
  var slug = text;
  for (final separator in _nameSeparators) {
    slug = slug.replaceAll(separator, '-');
  }
  return slug;
}

/// Returns the folder under [projectRoot] that holds the files a bare `--out`
/// writes.
Directory bundlesFolderOf(Directory projectRoot) {
  final separator = Platform.pathSeparator;
  return Directory(
    '${projectRoot.path}$separator.specstone${separator}bundles',
  );
}

/// Returns the file a bare `--out` writes: [name] under the project root's
/// `.specstone/bundles/`.
File bareBundleFile(Directory projectRoot, String name) =>
    File('${bundlesFolderOf(projectRoot).path}${Platform.pathSeparator}$name');

/// Returns the refs file of the read-first file at [path]: `.refs` before the
/// extension of its name, or at its end when the name has none.
///
/// A dot that opens the name or lies in a folder name is no extension.
String refsPathOf(String path) {
  final dot = path.lastIndexOf('.');
  if (dot <= _nameStartOf(path)) return '$path$_refsMark';
  return '${path.substring(0, dot)}$_refsMark${path.substring(dot)}';
}

int _nameStartOf(String path) {
  final slash = path.lastIndexOf('/');
  final backslash = Platform.isWindows ? path.lastIndexOf(r'\') : -1;
  return (slash > backslash ? slash : backslash) + 1;
}

// MARK: - Write

/// Writes [bundle]'s text to [file], and its refs text to the refs file beside
/// it when the answer is split, then prunes old bundle and report files.
///
/// An `implement` refs file opens with the index lines of its docs and parts,
/// each range counting those lines; the reply's refs header and `--json` count
/// the file as written.
/// The reply names each file by its canonical path. Throws
/// `output_not_writable` for a path [requireOutPath] refuses, judged for both
/// files before either is written, or for a write that fails; a call that
/// throws prunes nothing.
ReadAnswer answerBundleFile(
  ContextAnswer bundle,
  File file, {
  required DocsProject project,
  required bool isBare,
}) {
  assert(bundle.exitStatus == 0, 'a bundle over budget is never written');
  final answer = _withRefsHeadOf(bundle);
  final shownPath = canonicalPath(file.absolute.path);
  final refs = answer.refs;
  final refsPath = refs == null ? null : canonicalPath(refsPathOf(shownPath));
  if (refsPath == shownPath) {
    throw RenderFault(
      RenderFaultCode.outputNotWritable,
      _refsIsReadFirst,
      file: shownPath,
    );
  }
  final writes = {shownPath: answer.text, ?refsPath: ?refs?.text};
  for (final path in writes.keys) {
    requireOutPath(
      path,
      projectRoot: project.projectRoot,
      docsRoot: project.docsRoot,
      isBare: isBare,
    );
  }
  for (final MapEntry(key: path, value: text) in writes.entries) {
    writeBuildOutput(File(path), utf8.encode(text), displayPath: path);
  }
  pruneSpecstoneFolder(
    project.projectRoot,
    keep: writes.keys.toSet(),
    bounds: project.cleanup,
    now: DateTime.now(),
  );
  return ReadAnswer(
    text: bundleIndex(answer, shownPath, refsPath: refsPath),
    json: bundleIndexJson(answer, shownPath, refsPath: refsPath),
    warnings: [...answer.warnings, ..._overLimitWarnings(answer, shownPath)],
  );
}

/// Returns [answer] with an `implement` refs file opening with its index; any
/// other answer comes back as it is.
ContextAnswer _withRefsHeadOf(ContextAnswer answer) {
  final refs = answer.refs;
  if (refs == null || answer.json['for'] != BundleMode.implement.wire) {
    return answer;
  }
  return ContextAnswer(
    text: answer.text,
    json: answer.json,
    warnings: answer.warnings,
    exitStatus: answer.exitStatus,
    entries: answer.entries,
    tokens: answer.tokens,
    codeTarget: answer.codeTarget,
    refs: _withRefsHead(refs),
  );
}

/// Returns [refs] opened by the index lines of its entries, then a blank line.
///
/// Every entry, section, and token moves by the head: each range counts the
/// head's lines, which one line per entry fixes before any range is written,
/// and the size counts the head and the blocks, never the closing line and
/// list. The blocks end on the last entry's last line, and the closing line
/// that follows is written again for the new size. A refs file with no entry
/// has no head.
BundleText _withRefsHead(BundleText refs) {
  if (refs.entries.isEmpty) return refs;
  final lines = refs.text.split('\n');
  final blocksEnd = refs.entries.last.last;
  final shift = refs.entries.length + 1;
  final entries = [for (final entry in refs.entries) _shifted(entry, shift)];
  final head = [
    for (final entry in entries) _indexLine(entry, withSections: true),
  ].join().trimRight();
  final shown = '$head\n\n${lines.take(blocksEnd).join('\n')}';
  final tokens = tokenSizeOf(shown);
  final closing = closingLineOf(docCountOf(entries), tokens);
  return BundleText(
    text: '$shown\n$closing${lines.skip(blocksEnd + 1).join('\n')}',
    entries: entries,
    tokens: tokens,
  );
}

BundleEntry _shifted(BundleEntry entry, int lines) => BundleEntry(
  doc: entry.doc,
  kind: entry.kind,
  summary: entry.summary,
  sectionKey: entry.sectionKey,
  itemId: entry.itemId,
  featurePattern: entry.featurePattern,
  first: entry.first + lines,
  last: entry.last + lines,
  sections: [
    for (final section in entry.sections)
      EntrySection(key: section.key, first: section.first + lines),
  ],
);

// MARK: - Read plan

/// Returns the reads that take [readFirst] whole, each within
/// [readRangeTokenLimit] est. tokens, contiguous from line 1 to its last line.
///
/// A range ends on the line before an entry's first line, the last one that
/// keeps it within the limit. A part too large from the range's start ends it
/// before the part's last `## ` heading that fits and lies outside fenced code,
/// else on its last fitting line. A line over the limit is a range alone and
/// joins [ReadPlan.overLimitLines].
ReadPlan readPlanOf(BundleText readFirst) => _RangeCutter(readFirst).plan();

/// Cuts one file's lines into reads; sizes come from prefix sums, so a plan
/// costs one pass over the lines.
final class _RangeCutter {
  new(BundleText file)
    : _lines = const LineSplitter().convert(file.text),
      _starts = ({for (final entry in file.entries) entry.first}.toList()
        ..sort()) {
    var runes = 0;
    for (final line in _lines) {
      runes += line.runes.length;
      _runesThrough.add(runes);
    }
  }

  final List<String> _lines;
  final List<int> _starts;
  final List<int> _runesThrough = [0];

  int get _total => _lines.length;

  /// Est. tokens of lines [first] to [last] joined by line feeds, as
  /// [tokenSizeOf] counts the joined text.
  int _tokens(int first, int last) {
    final runes = _runesThrough[last] - _runesThrough[first - 1];
    return (runes + last - first) ~/ _runesPerToken;
  }

  bool _fits(int first, int last) =>
      _tokens(first, last) <= readRangeTokenLimit;

  ReadPlan plan() {
    final ranges = <ReadRange>[];
    final overLimitLines = <int>[];
    var start = 1;
    while (start <= _total) {
      final end = _endFrom(start);
      if (end == start && !_fits(start, start)) overLimitLines.add(start);
      ranges.add(ReadRange(first: start, last: end));
      start = end + 1;
    }
    return ReadPlan(ranges: ranges, overLimitLines: overLimitLines);
  }

  int _endFrom(int start) {
    if (_fits(start, _total)) return _total;
    return _lastEntryEnd(start) ?? _cutInsidePart(start);
  }

  /// The line before the last entry start that keeps the range from [start]
  /// within the limit; null when none does.
  int? _lastEntryEnd(int start) {
    int? end;
    for (final entryStart in _starts) {
      if (entryStart <= start) continue;
      if (!_fits(start, entryStart - 1)) break;
      end = entryStart - 1;
    }
    return end;
  }

  /// The end of a range from [start] cut inside its part: before the last
  /// fitting `## ` heading outside fenced code, else on the last fitting line,
  /// else [start] alone.
  int _cutInsidePart(int start) {
    final isFenced = _fencedInPartOf(start);
    var lastFit = start;
    int? beforeHeading;
    for (var line = start + 1; line <= _total; line++) {
      if (!_fits(start, line - 1)) break;
      lastFit = line - 1;
      if (_lines[line - 1].startsWith(_headingMark) && !isFenced(line)) {
        beforeHeading = line - 1;
      }
    }
    return beforeHeading ?? lastFit;
  }

  /// Returns whether a line of the part that holds [line] is fenced code, the
  /// fences read from the part's own first line.
  bool Function(int line) _fencedInPartOf(int line) {
    final first = _starts.lastWhere((s) => s <= line, orElse: () => 1);
    final next = _starts.firstWhere((s) => s > line, orElse: () => _total + 1);
    final fenced = fencedLines(_lines.sublist(first - 1, next - 1));
    return (number) => fenced[number - first];
  }
}

/// Returns the plan line: `read whole, in <n> read(s): lines <a>-<b>, …`.
String _readPlanLine(ReadPlan plan) {
  final count = plan.ranges.length;
  final ranges = [
    for (final range in plan.ranges) 'lines ${range.first}-${range.last}',
  ].join(', ');
  return 'read whole, in $count ${count == 1 ? 'read' : 'reads'}: $ranges';
}

/// Whether [answer] gives its read-first file a read plan: `implement` and
/// `design` do; `query` and an answer with no mode do not.
bool _hasReadPlan(ContextAnswer answer) => switch (answer.json['for']) {
  final String mode =>
    mode == BundleMode.implement.wire || mode == BundleMode.design.wire,
  _ => false,
};

/// Returns one warning per line of the read-first file over one read.
List<String> _overLimitWarnings(ContextAnswer answer, String path) {
  if (!_hasReadPlan(answer)) return const [];
  final lines = const LineSplitter().convert(answer.text);
  String warningOf(int number) {
    final tokens = tokenSizeOf(lines[number - 1]);
    return '⚠️ WARNING: line $number of $path holds $tokens est. tokens, '
        'more than one read holds';
  }

  return [
    for (final number in readPlanOf(answer.readFirst).overLimitLines)
      warningOf(number),
  ];
}

// MARK: - Index

/// Returns the stdout index of [answer]'s bundle saved at [shownPath] and, for
/// a split answer, of its refs file saved at [refsPath].
///
/// It prints the code target line when the answer has one, then per file, the
/// read-first file's first, a header line and one line per doc, appended
/// part, cited-by part, names block, and feature pattern part with its line
/// range in that file. The read-first header is followed by the read plan line
/// of an `implement` or `design` answer. An `implement` answer prints the refs
/// file's header line alone, its index heading the refs file. Each line lists
/// its sections' first lines while the counted index stays within 200 lines and
/// 8 KiB, header lines, the read plan line, and the code target line counted
/// with it, both files' for `design` and the read-first file's for
/// `implement`; past either bound no line lists a section, and every doc still
/// prints.
String bundleIndex(ContextAnswer answer, String shownPath, {String? refsPath}) {
  final files = _filesOf(answer, shownPath, refsPath);
  final isImplement = answer.json['for'] == BundleMode.implement.wire;
  final planLine = _hasReadPlan(answer)
      ? '${_readPlanLine(readPlanOf(answer.readFirst))}\n'
      : '';
  String index({required bool withSections, bool forCap = false}) => [
    codeTargetLine(answer.codeTarget),
    for (final (i, saved) in files.indexed)
      if (i == 0 || !isImplement)
        _fileIndex(
          saved.file,
          saved.path,
          withSections: withSections,
          plan: i == 0 ? planLine : '',
        )
      else if (!forCap)
        _fileHeader(saved.file, saved.path),
  ].join();
  final full = index(withSections: true, forCap: true);
  final fits =
      _lineCountOf(full) <= _indexLineCap &&
      utf8.encode(full).length <= _indexByteCap;
  return index(withSections: fits);
}

/// Returns `--out`'s `--json` object for [answer]'s bundle saved at
/// [shownPath], with its `codeTarget` when it has one; each doc lists its
/// sections whatever the index's size.
///
/// The object describes the read-first file; an `implement` or `design` answer
/// adds its `reads`, one `[first, last]` pair per read range. A split answer
/// adds a `refs` object of the same shape, `{out, tokens, lines, docs}`, for
/// the file saved at [refsPath]. A design answer also lists its feature pattern
/// parts under `featurePatterns`, as `{id, doc, lines}`; `docs` lists no part
/// but an appended one or an ancestor spec piece, whose entry has
/// `cited: false` and `cites: true` when inbound.
Map<String, Object> bundleIndexJson(
  ContextAnswer answer,
  String shownPath, {
  String? refsPath,
}) {
  final [readFirst, ...refs] = _filesOf(answer, shownPath, refsPath);
  return {
    ..._fileJson(readFirst.file, readFirst.path, codeTarget: answer.codeTarget),
    if (_hasReadPlan(answer))
      'reads': [
        for (final range in readPlanOf(readFirst.file).ranges)
          [range.first, range.last],
      ],
    if (answer.json['for'] == BundleMode.design.wire)
      'featurePatterns': [
        for (final entry in answer.entries)
          if (entry.featurePattern case final id?)
            {
              'id': id,
              'doc': featurePatternDocAddress(entry.doc),
              'lines': [entry.first, entry.last],
            },
      ],
    for (final file in refs) 'refs': _fileJson(file.file, file.path),
  };
}

/// Returns each file [answer] saves, the read-first file first, with its
/// path; the refs file's is [refsPath], which a split answer needs.
List<_SavedFile> _filesOf(
  ContextAnswer answer,
  String shownPath,
  String? refsPath,
) {
  assert(
    (answer.refs == null) == (refsPath == null),
    'a split answer names its refs path, an unsplit one none',
  );
  return [
    _SavedFile(file: answer.readFirst, path: shownPath),
    if ((answer.refs, refsPath) case (final refs?, final path?))
      _SavedFile(file: refs, path: path),
  ];
}

/// One file a bundle answer saves: its text and the path it is saved at.
final class _SavedFile {
  const new({required this.file, required this.path});

  final BundleText file;
  final String path;
}

/// Returns the header line of [file] saved at [path], then [plan], then one
/// index line per entry.
String _fileIndex(
  BundleText file,
  String path, {
  required bool withSections,
  String plan = '',
}) =>
    _fileHeader(file, path) +
    plan +
    [
      for (final entry in file.entries)
        _indexLine(entry, withSections: withSections),
    ].join();

/// Returns the header line of [file] saved at [path].
String _fileHeader(BundleText file, String path) =>
    '==> bundle: ${docCountOf(file.entries)} docs, ${file.tokens} tokens, '
    '${_lineCountOf(file.text)} lines · $path <==\n';

/// Returns `{out, tokens, lines, docs}` for [file] saved at [path], with
/// `codeTarget` after `out` when [codeTarget] is given.
Map<String, Object> _fileJson(
  BundleText file,
  String path, {
  String? codeTarget,
}) => {
  'out': path,
  'codeTarget': ?codeTarget,
  'tokens': file.tokens,
  'lines': _lineCountOf(file.text),
  'docs': [
    for (final entry in file.entries)
      if (entry.kind
          case BundleEntryKind.doc ||
              BundleEntryKind.cited ||
              BundleEntryKind.cites)
        {
          'name': entry.doc.name,
          'docType': ?entry.doc.docTypeId,
          'docPath': entry.doc.docPath,
          'lines': [entry.first, entry.last],
          'summary': entry.summary,
          'cited': entry.kind == BundleEntryKind.cited,
          if (entry.kind == BundleEntryKind.cites) 'cites': true,
          'sections': [
            for (final section in entry.sections)
              {'key': section.key, 'first': section.first},
          ],
        },
  ],
};

/// Returns `- <name> (<doc type>) · <first>-<last>`, then ` · summary`, the
/// kind's mark, and ` · <key> <first>, …` for [entry]'s sections when
/// [withSections].
///
/// The kind's mark is `cited <section key> [<ID>]` for an appended part or an
/// outbound ancestor spec piece, `cites <section key> [<ID>]` for an inbound
/// one, `cited by [<ID>]`, `cited by [#<section key>]`, or `cited by` for a
/// cited-by part, and `names` for a names block. A feature pattern part's line
/// is its list name, then ` · <first>-<last>`.
String _indexLine(BundleEntry entry, {required bool withSections}) {
  if (entry.featurePattern case final id?) {
    return '- ${featurePatternListName(id)} · ${entry.first}-${entry.last}\n';
  }
  final fields = [
    nameWithType(entry.doc),
    '${entry.first}-${entry.last}',
    if (entry.summary) 'summary',
    ?_kindMark(entry),
    if (withSections && entry.sections.isNotEmpty)
      [for (final section in entry.sections) '${section.key} ${section.first}']
          .join(', '),
  ];
  return '- ${fields.join(' · ')}\n';
}

String? _kindMark(BundleEntry entry) => switch (entry.kind) {
  BundleEntryKind.cited => _citedField(entry, 'cited'),
  BundleEntryKind.cites => _citedField(entry, 'cites'),
  BundleEntryKind.citedBy => _citedByField(entry),
  BundleEntryKind.names => 'names',
  BundleEntryKind.doc || BundleEntryKind.pattern => null,
};

/// Returns [word], with the section key and `[<ID>]` [entry] names.
String _citedField(BundleEntry entry, String word) => [
  word,
  ?entry.sectionKey,
  if (entry.itemId != null) '[${entry.itemId}]',
].join(' ');

/// Returns `cited by`, with the `[<ID>]` of the item or block [entry] follows,
/// or the `[#<section key>]` of the section; none for a whole doc.
String _citedByField(BundleEntry entry) => [
  'cited by',
  if (entry.itemId case final id?)
    '[$id]'
  else if (entry.sectionKey case final key?)
    '[#$key]',
].join(' ');

int _lineCountOf(String text) => const LineSplitter().convert(text).length;
