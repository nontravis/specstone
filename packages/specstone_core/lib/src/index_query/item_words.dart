import 'package:specstone_core/src/doc_model/body_line.dart';
import 'package:specstone_core/src/doc_model/doc_items.dart'
    show SectionItem, SectionItemKind;
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show ItemId, readItemId;

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
  final (:id, :head) = _withoutOwnId(item.head, prefix);
  final continuation = item.text.split('\n').skip(1);
  final words = normalizedWordsOf([head, ...continuation].join('\n'));
  return words.isEmpty ? null : (line: item.line, itemId: id, words: words);
}

/// Returns [head], an item's first line after any list marker, without the
/// item ID of [prefix] it opens with, and that ID.
({String? id, String head}) _withoutOwnId(String head, String? prefix) {
  if (prefix == null || readItemId(head, prefix) is! ItemId) {
    return (id: null, head: head);
  }
  final at = head.startsWith('**') ? 2 : 0;
  final id = readItemId(head, prefix)!.written;
  return (id: id, head: head.replaceRange(at, at + id.length, ''));
}

final _gherkinLine = RegExp(r'^[*_\s]*(?:Given|When|Then|And)\b');

/// Returns [lines] with each line of an HTML comment marked fenced, so it is
/// no item: a line that opens a comment and every line up to the one that
/// closes it.
List<BodyLine> withCommentsFenced(List<BodyLine> lines) {
  final marked = <BodyLine>[];
  var inComment = false;
  for (final line in lines) {
    var hidden = false;
    if (!line.fenced) {
      final opens = !inComment && line.text.trimLeft().startsWith(_commentOpen);
      if (inComment || opens) {
        hidden = true;
        final from = opens
            ? line.text.indexOf(_commentOpen) + _commentOpen.length
            : 0;
        inComment = !line.text.contains(_commentClose, from);
      }
    }
    marked.add((
      text: line.text,
      line: line.line,
      fenced: line.fenced || hidden,
    ));
  }
  return marked;
}

const _commentOpen = '<!--';
const _commentClose = '-->';

final _inlineComment = RegExp('<!--.*?-->');

/// A link, `[text](destination)` or `[text][label]`, whose text stays.
final _inlineLink = RegExp(
  r'\[([^\[\]]*)\](?:\((?:[^()]|\([^()]*\))*\)|\[[^\[\]]*\])',
);

final _notWordOrSpace = RegExp(r'[^\p{L}\p{M}\p{N}\s]', unicode: true);

final _whitespaceRun = RegExp(r'\s+');

/// Returns the words of [text], normalized: lowercased, a link read as its
/// text, an inline HTML comment, backticks, bold, and every punctuation
/// character dropped, then split at whitespace.
///
/// Two items that word one rule alike give the same words, whatever the ID,
/// bold, link, or punctuation around them (`consistency_check/list_repeated_text/list_repeat_groups`
/// E01).
List<String> normalizedWordsOf(String text) => text
    .toLowerCase()
    .replaceAll(_inlineComment, ' ')
    .replaceAllMapped(_inlineLink, (match) => match[1]!)
    .replaceAll(_notWordOrSpace, '')
    .split(_whitespaceRun)
    .where((word) => word.isNotEmpty)
    .toList();
