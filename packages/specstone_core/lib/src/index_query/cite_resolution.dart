import 'package:specstone_core/src/doc_model/doc_anchors.dart'
    show headingSlugOf;
import 'package:specstone_core/src/doc_model/markdown_lines.dart'
    show atxHeadingOf;
import 'package:specstone_core/src/doc_model/models/id_read.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show
        ScenarioRef,
        acceptanceSectionId,
        itemKeyOf,
        readDocAddress,
        readScenarioRef;
import 'package:specstone_core/src/document_writing/moved_paths.dart'
    show relativeHref;
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/doc_mentions.dart'
    show docNamedBy, namesakesIn;
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/models/cite_candidate.dart';
import 'package:specstone_core/src/index_query/models/cite_doc.dart';
import 'package:specstone_core/src/index_query/models/cite_item.dart';
import 'package:specstone_core/src/index_query/models/cite_section.dart';
import 'package:specstone_core/src/index_query/models/line_facts.dart';

// MARK: - Results

/// What a cite candidate names (consistency_check `report_old_cite_forms`).
sealed class CiteResolution {
  const new();
}

/// One doc, section, or set of items: the cite's links.
final class CiteLink extends CiteResolution {
  const new({
    required this.docPath,
    this.sectionKey,
    this.anchor,
    this.items = const [],
    required this.linkText,
  });

  final String docPath;

  /// The key of the `##` section the cite's `#key` names; null without one.
  final String? sectionKey;

  /// The anchor of that section's heading, which a section link's fragment
  /// carries.
  final String? anchor;

  /// The items the cite names, in its order, each with its own section; one
  /// item link each, and empty for a doc or section link.
  final List<CiteItem> items;

  /// The text of a doc or section link.
  final String linkText;
}

/// A name several docs share, whose `#key` or item IDs pick none or several.
final class CiteAmbiguous extends CiteResolution {
  const new({required this.docPaths});

  final List<String> docPaths;
}

/// The one doc named holds no section of the `#key`, or not every item ID.
final class CiteMissingPart extends CiteResolution {
  const new({required this.docPath});

  final String docPath;
}

/// A cite that names no doc: plain text.
final class CiteNoDoc extends CiteResolution {
  const new();
}

// MARK: - Resolution

/// Returns what [candidate], written in the doc at [citingDocPath], names in
/// [tree].
///
/// A Name names every doc that carries it, bare or `<doc type>:<Name>`; a
/// path names the doc [docNamedBy] picks. Of several docs, the `#key` or the
/// item IDs must pick exactly one.
CiteResolution resolveCite(
  CiteTree tree,
  String citingDocPath,
  CiteCandidate candidate,
) {
  final address = readDocAddress(candidate.written);
  final docs = address.isName
      ? tree.named(
          address.body,
          typeId: address.typeId,
          fromDocPath: citingDocPath,
        )
      : [?_docAtPath(tree, citingDocPath, candidate.written)];
  if (docs.isEmpty) return const CiteNoDoc();
  final links = [
    for (final doc in docs)
      ?_linkTo(
        tree,
        doc,
        candidate,
        linkText: address.isName ? candidate.written : _typedNameOf(doc),
      ),
  ];
  if (docs.length == 1) {
    return links.singleOrNull ?? CiteMissingPart(docPath: docs.single.docPath);
  }
  return links.length == 1
      ? links.single
      : CiteAmbiguous(docPaths: [for (final doc in docs) doc.docPath]);
}

/// Returns [link] as markdown links, each path relative to the doc at
/// [citingDocPath]: one item link per item, in the cite's order, else one doc
/// or section link.
///
/// The caller joins item links with the cite's own words, such as ` and `
/// or the ` to ` of a range. A link into the citing doc itself is
/// a bare `#anchor`.
List<String> citeLinkMarkdown(String citingDocPath, CiteLink link) {
  final isSelf = link.docPath == citingDocPath;
  final path = isSelf
      ? ''
      : relativeHref(
          citingDocPath,
          link.docPath,
        ).split('/').map(Uri.encodeComponent).join('/');
  String destination(String? anchor) => switch (anchor) {
    final anchor? => '$path#$anchor',
    null => isSelf ? '#' : path,
  };
  if (link.items.isEmpty) {
    return ['[${link.linkText}](${destination(link.anchor)})'];
  }
  return [
    for (final CiteItem(:itemId, :anchor) in link.items)
      '[$itemId](${destination(anchor)})',
  ];
}

CiteDoc? _docAtPath(CiteTree tree, String citingDocPath, String written) {
  final fileName = written.substring(written.lastIndexOf('/') + 1);
  final docPath = docNamedBy(written, citingDocPath, tree.namesakes(fileName));
  return docPath == null ? null : tree.at(docPath);
}

/// The text a path cite's link takes: `<doc type>:<Name>`, or the Name of
/// an untyped doc.
String _typedNameOf(CiteDoc doc) => switch (doc.docTypeId) {
  final typeId? => '$typeId:${doc.name}',
  null => doc.name,
};

/// Returns the link [candidate] makes to [doc], or null when [doc] holds no
/// section of its `#key` or not every item ID.
///
/// Each item takes the section that holds it, inside the `#key`'s section
/// when the cite writes one.
CiteLink? _linkTo(
  CiteTree tree,
  CiteDoc doc,
  CiteCandidate candidate, {
  required String linkText,
}) {
  final key = candidate.sectionKey;
  if (key == null && candidate.itemIds.isEmpty) {
    return CiteLink(docPath: doc.docPath, linkText: linkText);
  }
  final sections = tree.sectionsOf(doc.docPath);
  final keyed = key == null
      ? null
      : sections.where((section) => section.key == key).firstOrNull;
  if (key != null && keyed == null) return null;
  final items = <CiteItem>[];
  for (final id in candidate.itemIds) {
    final holder = (keyed == null ? sections : [keyed])
        .where((section) => section.itemKeys.contains(_itemKeyOf(id, section)))
        .firstOrNull;
    if (holder == null) return null;
    items.add(
      CiteItem(itemId: id, sectionKey: holder.key, anchor: holder.anchor),
    );
  }
  return CiteLink(
    docPath: doc.docPath,
    sectionKey: keyed?.key,
    anchor: keyed?.anchor,
    items: items,
    linkText: linkText,
  );
}

/// Returns the key [section] holds the item ID [written] by: `Scenario <n>`
/// for an `S<N>` of an `acceptance_criteria` section, else [written].
String _itemKeyOf(String written, CiteSection section) {
  if (section.key != acceptanceSectionId) return written;
  return switch (readScenarioRef(written)) {
    ScenarioRef(storyName: null, :final ItemId number) => itemKeyOf(
      number,
      isScenario: true,
    ),
    _ => written,
  };
}

// MARK: - CiteTree

/// The docs a cite resolves against: an index for `check`, or the tree a
/// migrate run plans.
abstract interface class CiteTree {
  /// Returns the docs [name] names, of the doc type [typeId] when not null,
  /// that the doc at [fromDocPath] reaches, in tree order.
  List<CiteDoc> named(
    String name, {
    required String? typeId,
    required String fromDocPath,
  });

  /// Returns the doc at [docPath], or null when the tree holds none there.
  CiteDoc? at(String docPath);

  /// Returns the DocPaths whose file name is [fileName], each with its
  /// segments, as `namesakesByFileName` groups them.
  Map<String, List<String>> namesakes(String fileName);

  /// Returns the sections of the doc at [docPath], in file order.
  List<CiteSection> sectionsOf(String docPath);
}

/// A [CiteTree] over the stored facts of an index; it reads no doc file.
final class IndexCiteTree implements CiteTree {
  /// Reads each doc's content through [contentOf], [DocIndex.contentOf] when
  /// null.
  new(this._index, {DocContent Function(IndexedDoc doc)? contentOf})
    : _contentOf = contentOf ?? _index.contentOf;

  final DocIndex _index;
  final DocContent Function(IndexedDoc doc) _contentOf;
  final _sections = <String, List<CiteSection>>{};

  late final Map<String, List<IndexedDoc>> _byName = () {
    final byName = <String, List<IndexedDoc>>{};
    for (final doc in _index.docs) {
      (byName[doc.name] ??= []).add(doc);
    }
    return byName;
  }();

  @override
  List<CiteDoc> named(
    String name, {
    required String? typeId,
    required String fromDocPath,
  }) {
    final docs = typeId == null
        ? _byName[name] ?? const <IndexedDoc>[]
        : _index.ofTypeNamed(typeId, name);
    final own = _index.hasTwins ? _index.at(fromDocPath)?.target : null;
    return [
      for (final doc in docs)
        if (doc.inTarget(own)) _citeDocOf(doc),
    ];
  }

  @override
  CiteDoc? at(String docPath) => switch (_index.at(docPath)) {
    final doc? => _citeDocOf(doc),
    null => null,
  };

  @override
  Map<String, List<String>> namesakes(String fileName) =>
      namesakesIn(_index)[fileName] ?? const {};

  @override
  List<CiteSection> sectionsOf(String docPath) =>
      _sections[docPath] ??= switch (_index.at(docPath)) {
        final doc? => citeSectionsOf(_contentOf(doc)),
        null => const [],
      };
}

CiteDoc _citeDocOf(IndexedDoc doc) =>
    CiteDoc(docPath: doc.docPath, docTypeId: doc.docTypeId, name: doc.name);

/// Returns the sections of [content] as a cite names them.
///
/// A section's anchor is its heading's slug in the stored anchor set, else
/// the slug of its header text when that set or the heading lines are
/// unknown.
List<CiteSection> citeSectionsOf(DocContent content) {
  final items = content.itemFacts.sectionItems;
  return [
    for (final (i, section) in content.sections.indexed)
      CiteSection(
        key: section.key,
        anchor: _anchorOf(content.lineFacts, i, section),
        itemKeys: {
          if (i < items.length)
            for (final item in items[i]) ?item.id,
        },
      ),
  ];
}

String _anchorOf(LineFacts facts, int index, IndexedSection section) {
  final anchors = facts.anchors;
  final lines = facts.headingLines;
  if (anchors != null && lines != null && index < facts.sectionLines.length) {
    final at = lines.indexOf(facts.sectionLines[index]);
    if (at >= 0) return anchors.headingSlugs[at];
  }
  return headingSlugOf(atxHeadingOf(section.headerLine)?.text ?? '');
}
