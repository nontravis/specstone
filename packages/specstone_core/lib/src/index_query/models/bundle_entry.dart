import 'package:specstone_core/src/index_query/indexed_doc.dart';

/// What one entry of a bundle text is.
///
/// - [doc]: a picked, joined, or summary doc.
/// - [cited]: a part a link appended, or a piece of an ancestor spec doc that
///   a doc of the target subtree links to.
/// - [cites]: a piece of an ancestor spec doc that links to a doc of the
///   target subtree.
/// - [pattern]: a feature pattern part.
/// - [names]: a `==> names:` block of a top doc's chain children.
/// - [citedBy]: the cited-by lines of one item, block, section, or doc, a part
///   of its own in a split bundle.
enum BundleEntryKind { doc, cited, cites, pattern, names, citedBy }

/// A `##` section an entry prints whole: its key and its header's line in the
/// bundle text, counted from 1.
final class EntrySection {
  const new({required this.key, required this.first});

  final String key;
  final int first;
}

/// One doc or part a bundle text prints, with the lines it spans there,
/// counted from 1: its naming line `first` to its `last` line, and the
/// header line of each `##` section it prints whole. A cited part names
/// the `##` section that holds it and its item ID, when it has them, and so
/// does a cited-by part, except that a section's has its `sectionKey` alone
/// and a doc's neither. A feature pattern part's `doc` is the doc that
/// lists it and its `featurePattern` the pattern id; null for any other
/// entry. A names block's `doc` is its top doc.
final class BundleEntry {
  const new({
    required this.doc,
    required this.kind,
    required this.summary,
    required this.sectionKey,
    required this.itemId,
    required this.featurePattern,
    required this.first,
    required this.last,
    required this.sections,
  });

  final IndexedDoc doc;
  final BundleEntryKind kind;
  final bool summary;
  final String? sectionKey;
  final String? itemId;
  final String? featurePattern;
  final int first;
  final int last;
  final List<EntrySection> sections;
}
