import 'package:specstone_core/src/index_query/models/banned_match.dart';
import 'package:specstone_core/src/index_query/models/indexed_section.dart';
import 'package:specstone_core/src/index_query/models/item_facts.dart';
import 'package:specstone_core/src/index_query/models/line_facts.dart';
import 'package:specstone_core/src/index_query/models/rule_item_words.dart';

/// The text and structure of one doc, as `get` and `context` print it.
final class DocContent {
  /// Takes [text], [bannedMatches], and [itemFacts] through [readText],
  /// [readBannedMatches], and [readItemFacts], each called on the first read
  /// of its field.
  new({
    required String Function() readText,
    this.frontmatterText,
    required this.head,
    required this.sections,
    required this.links,
    required this.lineFacts,
    required List<BannedMatch> Function() readBannedMatches,
    required ItemFacts Function() readItemFacts,
    this.itemWords = const [],
  }) : _readText = readText,
       _readBannedMatches = readBannedMatches,
       _readItemFacts = readItemFacts;

  /// The whole file as decoded, in its own line endings.
  late final String text = _readText();

  final String Function() _readText;

  /// The frontmatter lines, delimiters included, in LF; null without any.
  final String? frontmatterText;

  /// The text between the frontmatter and the first section, in LF.
  final String head;

  /// The sections in file order.
  final List<IndexedSection> sections;

  /// The docPaths of the other docs this one links to, each once in order.
  final List<String> links;

  /// The line facts of the file, stored by the refresh that parsed it.
  final LineFacts lineFacts;

  /// The banned-pattern matches of the file under its doc type, stored by the
  /// refresh that parsed it.
  late final List<BannedMatch> bannedMatches = _readBannedMatches();

  final List<BannedMatch> Function() _readBannedMatches;

  /// The items of the doc and its lead's counts, stored by the refresh that
  /// parsed it; a read command that never reads them never decodes them.
  late final ItemFacts itemFacts = _readItemFacts();

  final ItemFacts Function() _readItemFacts;

  /// The words of each item of a rule-bearing section, which the refresh that
  /// parsed the doc writes to the `item_words` table; empty for an untyped
  /// doc and for content read back from the index.
  final List<RuleItemWords> itemWords;
}
