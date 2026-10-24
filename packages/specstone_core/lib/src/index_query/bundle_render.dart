import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

final _htmlComment = RegExp(r'<!--[\s\S]*?-->');

/// Renders [bundle]'s docs as one `context` answer (us05 FR-02).
///
/// [label] is the target as given, or the code path for `--code`; [byCode]
/// prints it under the JSON key `code` instead of `target`. [budget] is
/// accepted and ignored; M4-T17 gives it FR-03's meaning.
ReadAnswer answerContext(
  DocIndex index,
  Bundle bundle, {
  required String label,
  required bool byCode,
  int? budget,
}) {
  final ordered = _orderedDocs(index, bundle);
  final docBlocks = [
    for (final doc in ordered) _docBlock(index, doc, bundle.mode),
  ];
  final mapBlocks = [
    for (final top in _byTreeOrder(index, bundle.mapTops))
      _mapBlock(index, index.at(top)!),
  ];
  final namesBlocks = [
    for (final top in _byTreeOrder(index, bundle.nameListTops))
      _namesBlock(index, index.at(top)!),
  ];
  final shown = [...docBlocks, ...mapBlocks, ...namesBlocks].join('\n\n');
  final tokens = tokenSizeOf(shown);
  final text =
      '$shown\n'
      '==> bundle: ${ordered.length} docs, $tokens tokens <==\n'
      '${[for (final doc in ordered) '- ${nameWithType(doc)}\n'].join()}';
  final json = <String, Object>{
    byCode ? 'code' : 'target': label,
    'for': bundle.mode.wire,
    'tokens': tokens,
    'docs': [
      for (final (doc, block) in docBlocks.indexed)
        {
          'name': ordered[doc].name,
          'docType': ?ordered[doc].docTypeId,
          'path': ordered[doc].docPath,
          'tokens': ordered[doc].tokens,
          'text': _blockBody(block),
        },
    ],
    ..._mapJson(index, bundle.mapTops),
    ..._namesJson(index, bundle.nameListTops),
  };
  return ReadAnswer(text: text, json: json, warnings: [...bundle.warnings]);
}

/// Returns [bundle]'s docs in bundle order: the joined docs in tree order,
/// then a pre-order walk from each doc of `docPaths` whose parent is outside
/// it, children inside `docPaths` sorted by chain type first, then doc type
/// id, then DocPath, by code point (INV-15).
List<IndexedDoc> _orderedDocs(DocIndex index, Bundle bundle) {
  final inDocPaths = bundle.docPaths;
  final roots = [
    for (final doc in index.docs)
      if (inDocPaths.contains(doc.docPath) &&
          (doc.parentPath == null || !inDocPaths.contains(doc.parentPath)))
        doc,
  ];
  final walkOrder = <IndexedDoc>[];
  for (final root in roots) {
    _walk(index, root, inDocPaths, walkOrder);
  }
  return [
    for (final doc in index.docs)
      if (bundle.joinedPaths.contains(doc.docPath)) doc,
    ...walkOrder,
  ];
}

void _walk(
  DocIndex index,
  IndexedDoc doc,
  Set<String> inDocPaths,
  List<IndexedDoc> out,
) {
  out.add(doc);
  final children = [
    for (final child in index.childrenOf(doc))
      if (inDocPaths.contains(child.docPath)) child,
  ]..sort(_compareSiblings(index));
  for (final child in children) {
    _walk(index, child, inDocPaths, out);
  }
}

int Function(IndexedDoc, IndexedDoc) _compareSiblings(DocIndex index) =>
    (a, b) {
      final aChain = _isChainDoc(index, a) ? 0 : 1;
      final bChain = _isChainDoc(index, b) ? 0 : 1;
      if (aChain != bChain) return aChain - bChain;
      final byType = compareCodePoints(a.docTypeId ?? '', b.docTypeId ?? '');
      if (byType != 0) return byType;
      return compareCodePoints(a.docPath, b.docPath);
    };

bool _isChainDoc(DocIndex index, IndexedDoc doc) {
  final typeId = doc.docTypeId;
  return typeId != null && index.isChainType(typeId);
}

/// Returns the doc block of [doc] for [mode]: its naming line, then its
/// frontmatter text, head, and kept sections, each trimmed at its end and
/// joined by one blank line (Plan decision 21, INV-14).
String _docBlock(DocIndex index, IndexedDoc doc, BundleMode mode) {
  final content = index.contentOf(doc);
  final docType = index.typeOf(doc);
  final parts = <String>[];
  if (mode != BundleMode.query) {
    final frontmatter = content.frontmatterText;
    if (frontmatter != null) parts.add(frontmatter.trimRight());
    final head = _removeComments(content.head);
    if (head.trim().isNotEmpty) parts.add(head.trimRight());
  }
  for (final section in _keptSections(content, docType, mode)) {
    parts.add(
      '${section.headerLine}\n${_removeComments(section.body).trimRight()}',
    );
  }
  return '${namingLine(doc)}\n${parts.join('\n\n')}';
}

/// Returns the sections [content] keeps for [mode], in its doc type's section
/// order, a section the type does not define after them in file order
/// (INV-15). A section is kept unless, with HTML comments removed and both
/// ends trimmed, its body equals its merged section's `template` likewise
/// cleaned, or is `N/A`, or starts with `N/A —`; in `query` only the sections
/// whose merged section is a query section stay (INV-14).
List<IndexedSection> _keptSections(
  DocContent content,
  MergedDocType? docType,
  BundleMode mode,
) {
  final merged = {
    for (final section in docType?.sections ?? const <MergedSection>[])
      section.id: section,
  };
  final kept = <IndexedSection>[];
  final undefined = <IndexedSection>[];
  for (final section in content.sections) {
    if (_kept(section, merged[section.key], mode)) {
      (merged.containsKey(section.key) ? kept : undefined).add(section);
    }
  }
  final inTemplateOrder = [
    for (final section in docType?.sections ?? const <MergedSection>[])
      for (final candidate in kept)
        if (candidate.key == section.id) candidate,
  ];
  return [...inTemplateOrder, ...undefined];
}

bool _kept(IndexedSection section, MergedSection? merged, BundleMode mode) {
  if (mode == BundleMode.query && merged?.query != true) return false;
  if (merged == null) return _naChecked(section.body);
  final body = _cleaned(section.body);
  final template = merged.template;
  if (template != null && body == _cleaned(template)) return false;
  return _naChecked(section.body);
}

bool _naChecked(String body) {
  final cleaned = _cleaned(body);
  return cleaned != 'N/A' && !cleaned.startsWith('N/A —');
}

/// Returns [text] with every HTML comment removed.
String _removeComments(String text) => text.replaceAll(_htmlComment, '');

/// Returns [text] with HTML comments removed and both ends trimmed.
String _cleaned(String text) => _removeComments(text).trim();

/// Returns the map block of [top]: its subtree, one line per doc with its
/// name, doc type, and token size, indented two spaces per depth below [top]
/// (Plan decision 13).
String _mapBlock(DocIndex index, IndexedDoc top) {
  final lines = [
    for (final member in index.subtreeOf(top)) _mapLine(index, top, member),
  ];
  return '==> map: ${nameWithType(top)} <==\n${lines.join('\n')}';
}

String _mapLine(DocIndex index, IndexedDoc top, IndexedDoc member) =>
    '${' ' * (2 * _depthBelow(index, top, member))}'
    '- ${nameWithType(member)} · ${member.tokens} tokens';

/// Returns the names block of [top]: one `- <name> (<doc type>) · <n> tokens`
/// line per ChainType child of [top] (Plan decision 13).
String _namesBlock(DocIndex index, IndexedDoc top) {
  final lines = [
    for (final child in index.childrenOf(top))
      if (_isChainDoc(index, child))
        '- ${nameWithType(child)} · ${child.tokens} tokens',
  ];
  return '==> names: ${nameWithType(top)} <==\n${lines.join('\n')}';
}

int _depthBelow(DocIndex index, IndexedDoc top, IndexedDoc doc) {
  var depth = 0;
  for (
    var member = doc;
    member.docPath != top.docPath;
    member = index.parentOf(member)!
  ) {
    depth++;
  }
  return depth;
}

/// Returns each DocPath of [paths] in tree order.
List<String> _byTreeOrder(DocIndex index, Set<String> paths) => [
  for (final doc in index.docs)
    if (paths.contains(doc.docPath)) doc.docPath,
];

/// Returns the block after its naming line, trimmed at both ends: the doc's
/// JSON `text`.
String _blockBody(String block) =>
    block.substring(block.indexOf('\n') + 1).trim();

Map<String, Object> _mapJson(DocIndex index, Set<String> tops) => {
  if (tops.isNotEmpty)
    'map': [
      for (final top in _byTreeOrder(index, tops))
        _docJson(index, index.at(top)!),
    ],
};

Map<String, Object> _docJson(DocIndex index, IndexedDoc doc) => {
  'name': doc.name,
  'docType': ?doc.docTypeId,
  'path': doc.docPath,
  'tokens': doc.tokens,
  'children': [
    for (final child in index.childrenOf(doc)) _docJson(index, child),
  ],
};

Map<String, Object> _namesJson(DocIndex index, Set<String> tops) => {
  if (tops.isNotEmpty)
    'names': [
      for (final top in _byTreeOrder(index, tops))
        for (final child in index.childrenOf(index.at(top)!))
          if (_isChainDoc(index, child))
            {
              'name': child.name,
              'docType': ?child.docTypeId,
              'path': child.docPath,
              'tokens': child.tokens,
            },
    ],
};
