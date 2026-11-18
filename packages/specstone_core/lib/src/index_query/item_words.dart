import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/doc_model/markdown_body.dart'
    show holdsLinkSyntax;
import 'package:specstone_core/src/doc_model/models/body_line.dart';
import 'package:specstone_core/src/doc_model/models/code_span.dart';
import 'package:specstone_core/src/doc_model/models/id_read.dart';
import 'package:specstone_core/src/doc_model/models/item_id_at.dart';
import 'package:specstone_core/src/doc_model/models/section_item.dart';
import 'package:specstone_core/src/doc_model/models/text_range.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show itemIdsInProse, readItemId;
import 'package:specstone_core/src/index_query/link_blocks.dart'
    show leafTextOf, linkLabel;
import 'package:specstone_core/src/index_query/link_scan.dart';
import 'package:specstone_core/src/index_query/models/rule_item_words.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// The section keys whose items `check --repeats` reads.
const ruleBearingSectionKeys = {
  'statement',
  'edge_cases',
  'invariants',
  'rules',
  'behavior',
  'business_rules',
};

/// Returns the words of [item], an item of a rule-bearing section whose item
/// IDs carry [prefix], or null when it is no item `check --repeats` reads: a
/// table row, a heading, a Given, When, Then, or And line, or an item that
/// holds no word.
RuleItemWords? wordsOfItem(
  SectionItem item,
  String? prefix, {
  required Set<String> idPrefixes,
  required String definitions,
}) {
  if (item.kind == SectionItemKind.tableRow ||
      item.kind == SectionItemKind.heading ||
      _gherkinLine.hasMatch(item.head)) {
    return null;
  }
  final continuation = item.text.split('\n').skip(1);
  final words = normalizedWordsOf(
    [item.head, ...continuation].join('\n'),
    idPrefixes: idPrefixes,
    definitions: definitions,
  );
  if (words.isEmpty) return null;
  final id = prefix == null ? null : readItemId(item.head, prefix);
  return RuleItemWords(
    line: item.line,
    itemId: id is ItemId ? id.written : null,
    words: words,
  );
}

final _gherkinLine = RegExp(r'^[*_\s]*(?:Given|When|Then|And)\b');

const _commentOpen = '<!--';
const _commentClose = '-->';

/// Returns [lines] with each HTML comment blanked to spaces, so it is no
/// item and its lines keep their numbers: from `<!--` to `-->`, across lines,
/// the text around it kept. Fenced lines are left as they are.
List<BodyLine> withCommentsBlanked(List<BodyLine> lines) {
  var open = false;
  final blanked = <BodyLine>[];
  for (final line in lines) {
    if (line.fenced) {
      blanked.add(line);
      continue;
    }
    final text = StringBuffer();
    final spans = line.text.contains('`')
        ? codeSpansOf(line.text)
        : const <CodeSpan>[];
    var at = 0;
    while (at < line.text.length) {
      final stop = open
          ? line.text.indexOf(_commentClose, at)
          : _commentOpenAt(line.text, at, spans);
      final markLength = open ? _commentClose.length : _commentOpen.length;
      final end = stop < 0 ? line.text.length : stop + markLength;
      final piece = line.text.substring(at, end);
      text.write(open ? ' ' * piece.length : piece);
      if (stop >= 0) open = !open;
      at = end;
    }
    blanked.add(
      BodyLine(text: text.toString(), line: line.line, fenced: false),
    );
  }
  return blanked;
}

/// Returns the offset of the first `<!--` of [line] at or after [from] that
/// is no part of a code span of [spans], or -1.
int _commentOpenAt(String line, int from, List<CodeSpan> spans) {
  var at = line.indexOf(_commentOpen, from);
  while (at >= 0) {
    final inSpan = spans.where((s) => s.start <= at && at < s.end);
    if (inSpan.isEmpty) return at;
    at = line.indexOf(_commentOpen, inSpan.first.end);
  }
  return -1;
}

final _notWordOrSpace = RegExp(r'[^\p{L}\p{M}\p{N}\s]', unicode: true);

final _whitespaceRun = RegExp(r'\s+');

/// Returns the words of [text], normalized: each link read as its text, each
/// item ID of [idPrefixes] dropped, then lowercased, every punctuation
/// character dropped (backticks and bold included), and the rest split at
/// whitespace.
///
/// [definitions] are the link reference definitions of the doc [text] is
/// from (see [definitionLinesOf]), so `[text][label]` reads as `text`. Two
/// items that word one rule alike give the same words, whatever the IDs,
/// bold, links, or punctuation around them. An HTML comment is no part of an
/// item; [withCommentsBlanked] takes it out first.
List<String> normalizedWordsOf(
  String text, {
  Set<String> idPrefixes = const {},
  String definitions = '',
}) => _withoutItemIds(_linksAsText(text, definitions), idPrefixes)
    .toLowerCase()
    .replaceAll(_notWordOrSpace, '')
    .split(_whitespaceRun)
    .where((word) => word.isNotEmpty)
    .toList();

/// Returns [body]'s link reference definitions as `[label]: <destination>`
/// lines, for [normalizedWordsOf] to read a reference link against.
String definitionLinesOf(String body) {
  if (!body.contains(']:')) return '';
  final leaf = leafTextOf(body);
  return [
    for (final TextRange(:start, :end) in leaf.definitionLabels)
      if (leaf.definitions[linkLabel(body.substring(start, end))]
          case final destination?)
        '[${body.substring(start, end)}]: <${destination.shown}>',
  ].join('\n');
}

/// Returns the item ID prefixes of [docTypes], the scenario ref prefix `S`
/// included: the prefixes whose tokens `normalizedWordsOf` drops.
Set<String> itemIdPrefixesOf(Iterable<MergedDocType> docTypes) => {
  for (final type in docTypes)
    for (final section in type.sections) ?section.prefixId,
  'S',
};

/// Returns [text] with each link replaced by its text, as the link scan reads
/// the links, [definitions] appended after it for the references.
String _linksAsText(String text, String definitions) {
  if (!text.contains('[')) return text;
  final scanned = definitions.isEmpty ? text : '$text\n\n$definitions';
  if (!holdsLinkSyntax(scanned)) return text;
  final out = StringBuffer();
  var at = 0;
  for (final source in linkSourcesOf(scanned, firstLine: 1)) {
    final textEnd = source.textEnd;
    if (source.offset >= text.length) break;
    if (textEnd == null || source.offset < at || source.end > text.length) {
      continue;
    }
    final from = source.offset + (text.startsWith('!', source.offset) ? 2 : 1);
    out
      ..write(text.substring(at, source.offset))
      ..write(text.substring(from, textEnd));
    at = source.end;
  }
  return (out..write(text.substring(at))).toString();
}

/// Returns [text] with each item ID of [prefixes] blanked to spaces.
String _withoutItemIds(String text, Set<String> prefixes) {
  var out = text;
  for (final ItemIdAt(:at, :id) in itemIdsInProse(text, prefixes: prefixes)) {
    out = out.replaceRange(at, at + id.written.length, ' ' * id.written.length);
  }
  return out;
}
