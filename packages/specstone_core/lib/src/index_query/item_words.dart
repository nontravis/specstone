import 'package:specstone_core/src/doc_model/body_line.dart';
import 'package:specstone_core/src/doc_model/doc_items.dart'
    show SectionItem, SectionItemKind;
import 'package:specstone_core/src/doc_model/markdown_body.dart'
    show holdsLinkSyntax;
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show ItemId, itemIdsInProse, readItemId;
import 'package:specstone_core/src/index_query/link_scan.dart';

/// The section keys whose items `check --repeats` reads.
const ruleBearingSectionKeys = {
  'statement',
  'edge_cases',
  'invariants',
  'rules',
  'behavior',
  'business_rules',
};

/// One item of a rule-bearing section: its first file line, its item ID when
/// it holds one, and its normalized words (see [normalizedWordsOf]).
typedef RuleItemWords = ({int line, String? itemId, List<String> words});

/// Returns the words of [item], an item of a rule-bearing section whose item
/// IDs carry [prefix], or null when it is no item `check --repeats` reads: a
/// table row, a heading, a Given, When, Then, or And line, or an item that
/// holds no word.
RuleItemWords? wordsOfItem(SectionItem item, String? prefix) {
  if (item.kind == SectionItemKind.tableRow ||
      item.kind == SectionItemKind.heading ||
      _gherkinLine.hasMatch(item.head)) {
    return null;
  }
  final continuation = item.text.split('\n').skip(1);
  final words = normalizedWordsOf([item.head, ...continuation].join('\n'));
  if (words.isEmpty) return null;
  final id = prefix == null ? null : readItemId(item.head, prefix);
  return (
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
    var at = 0;
    while (at < line.text.length) {
      final stop = line.text.indexOf(open ? _commentClose : _commentOpen, at);
      final markLength = open ? _commentClose.length : _commentOpen.length;
      final end = stop < 0 ? line.text.length : stop + markLength;
      final piece = line.text.substring(at, end);
      text.write(open ? ' ' * piece.length : piece);
      if (stop >= 0) open = !open;
      at = end;
    }
    blanked.add((text: text.toString(), line: line.line, fenced: false));
  }
  return blanked;
}

final _notWordOrSpace = RegExp(r'[^\p{L}\p{M}\p{N}\s]', unicode: true);

final _whitespaceRun = RegExp(r'\s+');

/// Returns the words of [text], normalized: each link read as its text, each
/// item ID dropped, then lowercased, every punctuation character dropped
/// (backticks and bold included), and the rest split at whitespace.
///
/// Two items that word one rule alike give the same words, whatever the IDs,
/// bold, links, or punctuation around them
/// (`consistency_check/list_repeated_text/list_repeat_groups` E01). An HTML
/// comment is no part of an item; [withCommentsBlanked] takes it out first.
List<String> normalizedWordsOf(String text) =>
    _withoutItemIds(_linksAsText(text))
        .toLowerCase()
        .replaceAll(_notWordOrSpace, '')
        .split(_whitespaceRun)
        .where((word) => word.isNotEmpty)
        .toList();

/// Returns [text] with each link replaced by its text, as the link scan reads
/// the links.
String _linksAsText(String text) {
  if (!holdsLinkSyntax(text)) return text;
  final out = StringBuffer();
  var at = 0;
  for (final source in linkSourcesOf(text, firstLine: 1)) {
    final textEnd = source.textEnd;
    if (textEnd == null || source.offset < at) continue;
    final from = source.offset + (text.startsWith('!', source.offset) ? 2 : 1);
    out
      ..write(text.substring(at, source.offset))
      ..write(text.substring(from, textEnd));
    at = source.end;
  }
  return (out..write(text.substring(at))).toString();
}

/// Returns [text] with each item ID blanked to spaces.
String _withoutItemIds(String text) {
  var out = text;
  for (final (:at, :id) in itemIdsInProse(text)) {
    out = out.replaceRange(at, at + id.written.length, ' ' * id.written.length);
  }
  return out;
}
