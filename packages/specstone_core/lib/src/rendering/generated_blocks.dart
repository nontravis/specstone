import 'package:specstone_core/src/doc_model/doc.dart';
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

/// A function that returns the generated blocks of [doc].
///
/// [R] is whatever the composition root hands every generator. When a
/// generator returns several blocks of one kind for one place, only the first
/// is written.
typedef Generator<R> = List<GeneratedBlock> Function(
  Doc doc,
  MergedDocType docType,
  R resolver,
);

/// The generators of a run, keyed by kind.
final class GeneratorRegistry<R> {
  new(Map<String, Generator<R>> generators)
    : _generators = Map.unmodifiable(generators);

  final Map<String, Generator<R>> _generators;

  /// The registered kinds.
  Set<String> get kinds => _generators.keys.toSet();

  /// Returns the generator of [kind], or null when none is registered.
  Generator<R>? operator [](String kind) => _generators[kind];
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

/// Returns, per line of [lines], whether it is a marker line or inner line of
/// a closed generated block of one of [kinds].
List<bool> generatedBlockLines(List<String> lines, Set<String> kinds) {
  final marked = List.filled(lines.length, false);
  final scan = _scan(_Lines(lines, endsWithNewline: true), kinds);
  for (final pair in scan.pairs) {
    for (var i = pair.open; i <= pair.end; i++) {
      marked[i] = true;
    }
  }
  return marked;
}

/// Runs the generators [docType] lists, in list order, and returns their
/// blocks.
List<GeneratedBlock> runGenerators<R>(
  Doc doc,
  MergedDocType docType,
  GeneratorRegistry<R> registry,
  R resolver,
) => [
  for (final kind in docType.listedGenerators)
    ...?registry[kind]?.call(doc, docType, resolver),
];

/// Writes [blocks] into [lfText].
///
/// A block rewrites the pair of its kind at its place, or inserts one when
/// none is there. Every other byte, a pair outside every block's place and a
/// pair of a kind [docType] does not list included, stays as written.
/// Returns [OpenBlock] when an opening marker of a listed kind has no end
/// marker.
BlockWrite writeGeneratedBlocks(
  String lfText,
  MergedDocType docType,
  List<GeneratedBlock> blocks,
) {
  final kinds = docType.listedGenerators.toSet();
  final lines = _Lines.split(lfText);
  final scan = _scan(lines, kinds, bodyStart: _bodyStart(lfText));
  final open = scan.openBlock;
  if (open != null) return open;

  final doc = Doc.parse(lfText);
  final edits = <_Edit>[];
  final seen = <String>{};
  for (final block in blocks) {
    if (!kinds.contains(block.kind)) continue;
    if (!seen.add(_slotKey(block))) continue;
    final edit = _editFor(block, doc, docType, lines, scan);
    if (edit != null) edits.add(edit);
  }
  return BlocksWritten(lines.apply(edits) ?? lfText);
}

String _slotKey(GeneratedBlock block) => switch (block.place) {
  SectionTop() => '${block.kind}\u0000${block.sectionId}\u0000top',
  BelowBodyLine(:final index) =>
    '${block.kind}\u0000${block.sectionId}\u0000$index',
};

_Edit? _editFor(
  GeneratedBlock block,
  Doc doc,
  MergedDocType docType,
  _Lines lines,
  _Scan scan,
) {
  final sectionIndex = sectionIndexOf(doc, docType, block.sectionId);
  if (sectionIndex == null) return null;
  final header = scan.bodyStart + doc.sectionLineIndexes[sectionIndex];
  final sectionEnd = sectionIndex + 1 < doc.sections.length
      ? scan.bodyStart + doc.sectionLineIndexes[sectionIndex + 1]
      : lines.length;
  final anchor = switch (block.place) {
    SectionTop() => header,
    BelowBodyLine(:final index) => header + 1 + index,
  };
  if (anchor < header || anchor >= sectionEnd) return null;

  final inner = _innerLines(block.text);
  final pair = _pairAt(lines, scan, anchor + 1, block.kind);
  if (pair == null) {
    return _Edit(
      from: anchor + 1,
      to: anchor + 1,
      replacement: [
        generatedOpenMarker(block.kind),
        ...inner,
        generatedEndMarker,
      ],
    );
  }
  return _Edit(from: pair.open + 1, to: pair.end, replacement: inner);
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

/// The index of the first line after the frontmatter.
int _bodyStart(String lfText) {
  final after = Doc.parse(lfText).afterFrontmatter;
  final prefix = lfText.substring(0, lfText.length - after.length);
  return '\n'.allMatches(prefix).length;
}

_Scan _scan(_Lines lines, Set<String> kinds, {int? bodyStart}) {
  final start = bodyStart ?? _bodyStart(lines.join());
  final fenced = fencedLines([
    for (var i = start; i < lines.length; i++) lines[i],
  ]);
  final kindByMarker = {
    for (final kind in kinds) generatedOpenMarker(kind): kind,
  };
  bool isMarker(int i, bool Function(String) test) =>
      !fenced[i - start] && test(lines[i]);

  final pairs = <_Pair>[];
  OpenBlock? openBlock;
  var i = start;
  while (i < lines.length) {
    final kind = isMarker(i, kindByMarker.containsKey)
        ? kindByMarker[lines[i]]
        : null;
    if (kind == null) {
      i++;
      continue;
    }
    var j = i + 1;
    while (j < lines.length &&
        !isMarker(j, (line) => line == generatedEndMarker) &&
        !isMarker(j, kindByMarker.containsKey)) {
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
  return _Scan(bodyStart: start, pairs: pairs, openBlock: openBlock);
}

final class _Pair {
  const new({required this.kind, required this.open, required this.end});

  final String kind;
  final int open;
  final int end;
}

final class _Scan {
  const new({required this.bodyStart, required this.pairs, this.openBlock});

  final int bodyStart;
  final List<_Pair> pairs;
  final OpenBlock? openBlock;
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
