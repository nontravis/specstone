import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart'
    show withSectionAdded;
import 'package:specstone_core/src/rendering/formatter.dart' show headerKey;
import 'package:specstone_core/src/templates/merged_doc_type.dart';

const _openPrefix = '<!-- specstone:generated ';
const _openSuffix = ' (do not edit) -->';

/// Returns the line that opens a generated block of [kind].
String generatedOpenMarker(String kind) => '$_openPrefix$kind$_openSuffix';

/// The line that closes every generated block.
const String generatedEndMarker = '<!-- specstone:generated end -->';

/// Where a generated block sits inside its section.
sealed class BlockPlace {
  const new();
}

/// The top of a section body, directly under the `##` line.
final class SectionTop extends BlockPlace {
  const new();
}

/// Directly under body line [index] of a section, counted from 0.
final class BelowBodyLine extends BlockPlace {
  const new(this.index);

  /// The 0-based index among the lines of the section's body.
  final int index;
}

/// The text one generator returns for one place in one section.
final class GeneratedBlock {
  const new({
    required this.kind,
    required this.sectionId,
    required this.place,
    required this.text,
  });

  /// The generator kind that produced the block.
  final String kind;

  /// The id of the doc type section that holds the block.
  final String sectionId;

  /// Where in the section the block sits.
  final BlockPlace place;

  /// The block text without its marker lines.
  final String text;
}

/// A function that returns the generated blocks of [doc], the doc at
/// [docPath].
///
/// [R] is whatever the composition root hands every generator. When a
/// generator returns several blocks of one kind for one place, only the first
/// is written.
typedef Generator<R> = List<GeneratedBlock> Function(
  Doc doc,
  String docPath,
  MergedDocType docType,
  R resolver,
);

/// One doc that a format run keeps beside the doc whose generator lists it.
final class CompanionDoc {
  const new({required this.docPath, required this.seedText});

  /// The doc's path from the docs root.
  final String docPath;

  /// The LF text a missing doc starts from: a title line and empty `##`
  /// sections, before its blocks are filled.
  final String seedText;
}

/// The docs that one generator kind keeps beside the doc listing it.
final class CompanionDocs {
  const new({required this.docTypeId, required this.docs});

  /// The doc type of every companion; every existing doc of this type that
  /// [docs] leaves out is deleted. Empty when the layout has no companions.
  final String docTypeId;

  /// The companions the doc has now, in the order a run reports them.
  final List<CompanionDoc> docs;
}

/// Returns the companions of the doc at [docPath], whose type is [docType].
typedef CompanionsOf<R> = CompanionDocs Function(
  String docPath,
  MergedDocType docType,
  R resolver,
);

/// The generators of a run, keyed by kind, and the companions some of them
/// keep.
final class GeneratorRegistry<R> {
  new(
    Map<String, Generator<R>> generators, {
    Map<String, CompanionsOf<R>> companions = const {},
  }) : _generators = Map.unmodifiable(generators),
       _companions = Map.unmodifiable(companions);

  final Map<String, Generator<R>> _generators;
  final Map<String, CompanionsOf<R>> _companions;

  /// The registered kinds.
  Set<String> get kinds => _generators.keys.toSet();

  /// Returns the generator of [kind], or null when none is registered.
  Generator<R>? operator [](String kind) => _generators[kind];

  /// Returns the companions function of [kind], or null when it keeps none.
  CompanionsOf<R>? companionsOf(String kind) => _companions[kind];

  /// Returns the registry of the [kinds] alone, each with its companions.
  GeneratorRegistry<R> only(Set<String> kinds) => GeneratorRegistry(
    {
      for (final MapEntry(:key, :value) in _generators.entries)
        if (kinds.contains(key)) key: value,
    },
    companions: {
      for (final MapEntry(:key, :value) in _companions.entries)
        if (kinds.contains(key)) key: value,
    },
  );
}

/// The first generated block of a doc whose text a format run would change.
final class StaleBlock {
  const new({required this.kind, required this.line});

  /// The generator kind of the block.
  final String kind;

  /// The 1-based line of the block's opening marker, or null when the doc
  /// lacks the block.
  final int? line;
}

/// The result of writing generated blocks into a doc.
sealed class BlockWrite {
  const new();
}

/// The doc text with every block written.
final class BlocksWritten extends BlockWrite {
  const new(this.lfText);

  /// The text, LF line endings.
  final String lfText;
}

/// A doc with an opening marker that has no end marker.
final class OpenBlock extends BlockWrite {
  const new({required this.kind, required this.marker});

  /// The kind named by the opening marker.
  final String kind;

  /// The opening marker line as written.
  final String marker;
}

/// Returns the index in [Doc.sections] of the section with id [sectionId].
///
/// Headers match by [headerKey]. Null when [docType] has no such section or
/// the doc lacks its header.
int? sectionIndexOf(Doc doc, MergedDocType docType, String sectionId) {
  final template = docType.sections
      .where((section) => section.id == sectionId)
      .firstOrNull;
  if (template == null) return null;
  final key = headerKey(template.header);
  final index = doc.sections.indexWhere(
    (section) => headerKey(section.headerText) == key,
  );
  return index < 0 ? null : index;
}

/// Returns [lfText], a doc of [docType], with the template section [sectionId]
/// added holding [body]: before the first section the doc holds that follows it
/// in [docType], else at the end.
///
/// Throws a [StateError] when [docType] has no section [sectionId].
String withTemplateSection(
  String lfText,
  MergedDocType docType,
  String sectionId,
  String body,
) {
  final template = docType.sections.firstWhere((s) => s.id == sectionId);
  final doc = Doc.parse(lfText);
  int? before;
  for (final later
      in docType.sections.skipWhile((s) => s.id != sectionId).skip(1)) {
    before = sectionIndexOf(doc, docType, later.id);
    if (before != null) break;
  }
  return withSectionAdded(
    lfText,
    headerLine: '## ${template.header}',
    body: body,
    before: before,
  );
}

/// Returns, per line of [lines], whether it is a marker line or inner line of
/// a closed generated block of one of [kinds].
List<bool> generatedBlockLines(List<String> lines, Set<String> kinds) {
  final marked = List.filled(lines.length, false);
  final scan = _scan(_Lines(lines, endsWithNewline: true), kinds, bodyStart: 0);
  for (final pair in scan.pairs) {
    for (var i = pair.open; i <= pair.end; i++) {
      marked[i] = true;
    }
  }
  return marked;
}

/// Returns the first opening marker of one of [kinds] in [doc] that has no
/// end marker, or null when every such block closes.
OpenBlock? openBlockOf(Doc doc, Set<String> kinds) {
  if (kinds.isEmpty) return null;
  final lines = _Lines.split(doc.afterFrontmatter);
  return _scan(lines, kinds, bodyStart: 0).openBlock;
}

/// Runs the generators [docType] lists on [doc], the doc at [docPath], in
/// list order, and returns their blocks.
List<GeneratedBlock> runGenerators<R>(
  Doc doc,
  MergedDocType docType,
  GeneratorRegistry<R> registry,
  R resolver, {
  required String docPath,
}) => [
  for (final kind in docType.listedGenerators)
    ...?registry[kind]?.call(doc, docPath, docType, resolver),
];

/// Returns [lfText], the doc at [docPath], with the blocks of [docType]'s
/// listed generators written.
///
/// A block rewrites the pair of its kind at its place, or inserts one that
/// writes its own layout whitespace. Every other byte stays as written, a pair
/// outside every block's place and a pair of an unlisted kind included.
/// [lfText] comes back unchanged when [docType] lists no generator and when
/// it holds an opening marker with no end marker.
String fillGeneratedBlocks<R>(
  String lfText,
  MergedDocType docType,
  GeneratorRegistry<R> registry,
  R resolver, {
  required String docPath,
}) {
  if (docType.listedGenerators.isEmpty) return lfText;
  final doc = Doc.parse(lfText);
  final blocks = runGenerators(
    doc,
    docType,
    registry,
    resolver,
    docPath: docPath,
  );
  return switch (_writeBlocks(lfText, doc, docType, blocks)) {
    BlocksWritten(lfText: final written) => written,
    OpenBlock() => lfText,
  };
}

/// Returns the first block of [docType]'s listed generators on [doc], the doc
/// at [docPath], that a format run would rewrite or insert, or null.
///
/// It reads the edits [fillGeneratedBlocks] applies, so a doc is stale here
/// exactly when that function changes it. A block whose generator returns none,
/// a doc holding an opening marker with no end marker, and a type that lists no
/// generator give null.
StaleBlock? staleBlockOf<R>(
  Doc doc,
  MergedDocType docType,
  GeneratorRegistry<R> registry,
  R resolver, {
  required String docPath,
}) {
  if (docType.listedGenerators.isEmpty) return null;
  final lfText = doc.text;
  final kinds = docType.listedGenerators.toSet();
  final lines = _Lines.split(lfText);
  final scan = _scan(lines, kinds, bodyStart: _bodyStart(lfText, doc));
  if (scan.openBlock != null) return null;
  final blocks = runGenerators(
    doc,
    docType,
    registry,
    resolver,
    docPath: docPath,
  );
  final seen = <String>{};
  for (final block in blocks) {
    if (!kinds.contains(block.kind)) continue;
    if (!seen.add(_slotKey(block))) continue;
    final placed = _editFor(block, doc, docType, lines, scan);
    if (lines.apply(placed.edits) == null) continue;
    final open = placed.pair?.open;
    return StaleBlock(kind: block.kind, line: open == null ? null : open + 1);
  }
  return null;
}

/// Writes [blocks] into [lfText] parsed as [doc], sharing that one parse.
BlockWrite _writeBlocks(
  String lfText,
  Doc doc,
  MergedDocType docType,
  List<GeneratedBlock> blocks,
) {
  final kinds = docType.listedGenerators.toSet();
  final lines = _Lines.split(lfText);
  final scan = _scan(lines, kinds, bodyStart: _bodyStart(lfText, doc));
  final open = scan.openBlock;
  if (open != null) return open;

  final edits = <_Edit>[];
  final seen = <String>{};
  for (final block in blocks) {
    if (!kinds.contains(block.kind)) continue;
    if (!seen.add(_slotKey(block))) continue;
    edits.addAll(_editFor(block, doc, docType, lines, scan).edits);
  }
  return BlocksWritten(lines.apply(edits) ?? lfText);
}

String _slotKey(GeneratedBlock block) => switch (block.place) {
  SectionTop() => '${block.kind}\u0000${block.sectionId}\u0000top',
  BelowBodyLine(:final index) =>
    '${block.kind}\u0000${block.sectionId}\u0000$index',
};

/// The edits that bring one block current, and the pair of its kind they
/// rewrite, null when they insert one.
final class _BlockEdits {
  const new(this.edits, [this.pair]);

  final List<_Edit> edits;
  final _Pair? pair;
}

_BlockEdits _editFor(
  GeneratedBlock block,
  Doc doc,
  MergedDocType docType,
  _Lines lines,
  _Scan scan,
) {
  final sectionIndex = sectionIndexOf(doc, docType, block.sectionId);
  if (sectionIndex == null) return const _BlockEdits([]);
  final header = scan.bodyStart + doc.sectionLineIndexes[sectionIndex];
  final sectionEnd = sectionIndex + 1 < doc.sections.length
      ? scan.bodyStart + doc.sectionLineIndexes[sectionIndex + 1]
      : lines.length;
  final anchor = switch (block.place) {
    SectionTop() => header,
    BelowBodyLine(:final index) => header + 1 + index,
  };
  if (anchor < header || anchor >= sectionEnd) return const _BlockEdits([]);

  final inner = _innerLines(block.text);
  final pair = _pairAt(lines, scan, anchor + 1, block.kind);
  if (pair == null) {
    // The inserted pair carries the layout whitespace around itself,
    // so no later layout pass over the doc is needed: exactly one
    // blank under a heading anchor, and a hard break the insert severs
    // trimmed. A fenced or in-pair anchor keeps its bytes as written.
    final anchorLine = lines[anchor];
    final isProtected =
        scan.fenced[anchor - scan.bodyStart] || _inPair(scan, anchor);
    final trimmedAnchor = _trimEnd(anchorLine);
    return _BlockEdits([
      if (!isProtected && trimmedAnchor != anchorLine)
        _Edit(from: anchor, to: anchor + 1, replacement: [trimmedAnchor]),
      _Edit(
        from: anchor + 1,
        to: anchor + 1,
        replacement: [
          if (!isProtected && _isHeadingLine(anchorLine)) '',
          generatedOpenMarker(block.kind),
          ...inner,
          generatedEndMarker,
        ],
      ),
    ]);
  }
  return _BlockEdits([
    _Edit(from: pair.open + 1, to: pair.end, replacement: inner),
  ], pair);
}

bool _inPair(_Scan scan, int line) =>
    scan.pairs.any((pair) => line >= pair.open && line <= pair.end);

const _space = 0x20;
const _tab = 0x09;
const _hash = 0x23;

/// The most spaces before a heading's `#` run.
const _maxHeadingIndent = 3;
const _maxHeadingLevel = 6;

/// Whether [line], its trailing spaces and tabs aside, is up to 3 spaces,
/// 1 to 6 `#`, then the end or a space.
bool _isHeadingLine(String line) {
  final end = _contentEnd(line);
  var i = 0;
  while (i < end && i < _maxHeadingIndent && line.codeUnitAt(i) == _space) {
    i++;
  }
  final hashes = i;
  while (i < end && line.codeUnitAt(i) == _hash) {
    i++;
  }
  final level = i - hashes;
  if (level < 1 || level > _maxHeadingLevel) return false;
  return i == end || line.codeUnitAt(i) == _space;
}

/// Returns the first pair of [kind] in the run of pairs that starts at the
/// first non-blank line from [from], or null.
///
/// The run is the consecutive pairs with only blank lines between them.
_Pair? _pairAt(_Lines lines, _Scan scan, int from, String kind) {
  int skipBlanks(int start) {
    var index = start;
    while (index < lines.length && lines[index].trim().isEmpty) {
      index++;
    }
    return index;
  }

  var index = skipBlanks(from);
  for (;;) {
    final pair = scan.pairs.where((pair) => pair.open == index).firstOrNull;
    if (pair == null) return null;
    if (pair.kind == kind) return pair;
    index = skipBlanks(pair.end + 1);
  }
}

List<String> _innerLines(String text) {
  if (text.isEmpty) return const [];
  final trimmed = text.endsWith('\n')
      ? text.substring(0, text.length - 1)
      : text;
  return trimmed.split('\n');
}

/// The index of the first line after the frontmatter of [doc], parsed from
/// [lfText].
int _bodyStart(String lfText, Doc doc) {
  final after = doc.afterFrontmatter;
  final prefix = lfText.substring(0, lfText.length - after.length);
  return '\n'.allMatches(prefix).length;
}

/// The index after the last character of [line] that is not a space or a tab.
int _contentEnd(String line) {
  var i = line.length;
  while (i > 0) {
    final unit = line.codeUnitAt(i - 1);
    if (unit != _space && unit != _tab) break;
    i--;
  }
  return i;
}

String _trimEnd(String line) {
  final end = _contentEnd(line);
  return end == line.length ? line : line.substring(0, end);
}

_Scan _scan(_Lines lines, Set<String> kinds, {required int bodyStart}) {
  final fenced = fencedLines([
    for (var i = bodyStart; i < lines.length; i++) lines[i],
  ]);
  final kindByMarker = {
    for (final kind in kinds) generatedOpenMarker(kind): kind,
  };
  bool isMarker(int i, bool Function(String) test) =>
      !fenced[i - bodyStart] && test(lines[i]);

  final pairs = <_Pair>[];
  OpenBlock? openBlock;
  var i = bodyStart;
  while (i < lines.length) {
    // Layout trims trailing spaces and tabs, so a marker line that only
    // differs from an exact one by them is an open block too.
    final kind = fenced[i - bodyStart]
        ? null
        : kindByMarker[_trimEnd(lines[i])];
    if (kind == null) {
      i++;
      continue;
    }
    var j = i + 1;
    while (j < lines.length &&
        !isMarker(j, (line) => line == generatedEndMarker) &&
        !isMarker(j, (line) => kindByMarker.containsKey(_trimEnd(line)))) {
      j++;
    }
    if (j >= lines.length || lines[j] != generatedEndMarker) {
      openBlock ??= OpenBlock(kind: kind, marker: lines[i]);
      i = j;
      continue;
    }
    pairs.add(_Pair(kind: kind, open: i, end: j));
    i = j + 1;
  }
  return _Scan(
    bodyStart: bodyStart,
    pairs: pairs,
    openBlock: openBlock,
    fenced: fenced,
  );
}

final class _Pair {
  const new({required this.kind, required this.open, required this.end});

  final String kind;
  final int open;
  final int end;
}

final class _Scan {
  const new({
    required this.bodyStart,
    required this.pairs,
    required this.fenced,
    this.openBlock,
  });

  final int bodyStart;
  final List<_Pair> pairs;
  final OpenBlock? openBlock;

  /// Per line from [bodyStart], whether it sits inside a code fence.
  final List<bool> fenced;
}

/// Replaces lines `[from, to)` with [replacement].
final class _Edit {
  const new({required this.from, required this.to, required this.replacement});

  final int from;
  final int to;
  final List<String> replacement;
}

/// A doc as lines without line endings, plus whether the last line ends in
/// `\n`.
final class _Lines {
  new(this._lines, {required this.endsWithNewline});

  factory split(String text) {
    final endsWithNewline = text.endsWith('\n');
    final lines = (endsWithNewline ? text.substring(0, text.length - 1) : text)
        .split('\n');
    return _Lines(text.isEmpty ? [] : lines, endsWithNewline: endsWithNewline);
  }

  final List<String> _lines;
  final bool endsWithNewline;

  int get length => _lines.length;

  String operator [](int index) => _lines[index];

  String join() =>
      _lines.isEmpty ? '' : _lines.join('\n') + (endsWithNewline ? '\n' : '');

  /// Returns the text with [edits] applied, or null when none changes a line.
  ///
  /// Edits at one position apply in the order given.
  String? apply(List<_Edit> edits) {
    final result = [..._lines];
    final ordered = [...edits.indexed]
      ..sort((a, b) {
        final byPosition = b.$2.from.compareTo(a.$2.from);
        return byPosition != 0 ? byPosition : b.$1.compareTo(a.$1);
      });
    var changed = false;
    for (final (_, edit) in ordered) {
      final current = result.sublist(edit.from, edit.to);
      if (current.length == edit.replacement.length &&
          _sameLines(current, edit.replacement)) {
        continue;
      }
      result.replaceRange(edit.from, edit.to, edit.replacement);
      changed = true;
    }
    if (!changed) return null;
    return _Lines(result, endsWithNewline: endsWithNewline).join();
  }
}

bool _sameLines(List<String> a, List<String> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
