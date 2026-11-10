import 'package:specstone_core/src/doc_model/doc_items.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/held_sections.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/index_query/section_counts.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

const _indent = '  ';
const _headingMarker = '### ';

typedef _ItemSize = ({String? id, int line, int chars});
typedef _SectionSize = ({String key, int chars, List<_ItemSize> items});

/// Returns the docs tree, or the subtree of every doc [target] addresses.
///
/// Without [target] it holds each typed doc that has no parent, with its
/// subtree, then each folder of untyped docs. With one, [target] is resolved
/// as [DocIndex.resolve] does and each resolved doc that another resolved
/// doc's subtree already holds is left out. An untyped target prints its one
/// line with no folder line.
///
/// When [target] resolves to one typed doc, that doc's line is followed by one
/// line per section and, under it, one per item, each with its characters as
/// `check` counts them in the doc as `format` lays it out; the doc's JSON
/// object gains `sections`.
ReadAnswer answerStructure(DocIndex index, {String? target}) {
  final resolved = target == null ? null : index.resolve(target);
  final shown = resolved == null ? index.docs : _withoutNested(index, resolved);
  final sized = switch (resolved) {
    [final doc] when doc.isTyped => doc,
    _ => null,
  };
  final sizes = sized == null ? null : _sectionSizesOf(index, sized);
  final roots = [
    for (final doc in shown)
      if (doc.isTyped && (target != null || index.parentOf(doc) == null)) doc,
  ];
  final folders = _untypedByFolder([
    for (final doc in shown)
      if (!doc.isTyped) doc,
  ]);

  final text = StringBuffer();
  for (final root in roots) {
    _writeTree(text, index, root, 0, root == sized ? sizes : null);
  }
  for (final MapEntry(key: folder, value: docs) in folders.entries) {
    if (target == null) text.writeln(folder);
    for (final doc in docs) {
      text.writeln('${target == null ? _indent : ''}${docLine(index, doc)}');
    }
  }

  return ReadAnswer(
    text: text.toString(),
    json: {
      'docs': [
        for (final root in roots)
          _treeJson(index, root, root == sized ? sizes : null),
      ],
      'untyped': [
        for (final MapEntry(key: folder, value: docs) in folders.entries)
          {
            'folder': folder,
            'docs': [for (final doc in docs) docJson(index, doc)],
          },
      ],
    },
  );
}

List<IndexedDoc> _withoutNested(DocIndex index, List<IndexedDoc> resolved) {
  final nested = {
    for (final doc in resolved)
      for (final member in index.subtreeOf(doc).skip(1)) member.docPath,
  };
  return [
    for (final doc in resolved)
      if (!nested.contains(doc.docPath)) doc,
  ];
}

Map<String, List<IndexedDoc>> _untypedByFolder(List<IndexedDoc> docs) {
  final folders = <String, List<IndexedDoc>>{};
  for (final doc in docs) {
    final slash = doc.docPath.lastIndexOf('/');
    final folder = slash < 0 ? './' : doc.docPath.substring(0, slash + 1);
    (folders[folder] ??= []).add(doc);
  }
  return folders;
}

void _writeTree(
  StringBuffer text,
  DocIndex index,
  IndexedDoc doc,
  int depth,
  List<_SectionSize>? sizes,
) {
  text.writeln('${_indent * depth}${docLine(index, doc)}');
  for (final section in sizes ?? const <_SectionSize>[]) {
    text.writeln(
      '${_indent * (depth + 1)}${section.key} · ${section.chars} chars',
    );
    for (final item in section.items) {
      final label = item.id ?? 'line ${item.line}';
      text.writeln('${_indent * (depth + 2)}$label · ${item.chars} chars');
    }
  }
  for (final child in index.childrenOf(doc)) {
    _writeTree(text, index, child, depth + 1, null);
  }
}

Map<String, Object> _treeJson(
  DocIndex index,
  IndexedDoc doc,
  List<_SectionSize>? sizes,
) => {
  ...docJson(index, doc),
  if (sizes != null)
    'sections': [
      for (final section in sizes)
        {
          'key': section.key,
          'chars': section.chars,
          'items': [
            for (final item in section.items)
              {'id': ?item.id, 'line': item.line, 'chars': item.chars},
          ],
        },
    ],
  'children': [
    for (final child in index.childrenOf(doc)) _treeJson(index, child, null),
  ],
};

/// Returns the sections of [doc] as its counts cover them, each with its
/// items: the text `format` lays out, or the text as decoded for a doc with
/// no layout.
List<_SectionSize> _sectionSizesOf(DocIndex index, IndexedDoc doc) {
  final type = index.typeOf(doc);
  final counted = doc.countedTextOf(toLf(index.contentOf(doc).text), type);
  final content = docStructureOf(counted, type);
  final templates = heldTemplatesOf(content.sections, type);
  return [
    for (final (i, section) in content.sections.indexed)
      (
        key: section.key,
        chars: sectionCountsOf(section).chars,
        items: _itemSizesOf(content, i, templates[i]),
      ),
  ];
}

List<_ItemSize> _itemSizesOf(
  DocContent content,
  int sectionIndex,
  MergedSection? template,
) => [
  for (final item in itemsOf(
    sectionBodyLines(content.sections, content.lineFacts, sectionIndex),
  ))
    (id: _itemIdOf(item, template), line: item.line, chars: item.chars),
];

/// Returns the key `check` holds [item] by, or null when it reads none.
String? _itemIdOf(DocItem item, MergedSection? template) {
  if (item.heading && template?.id == acceptanceSectionId) {
    final scenario = readScenarioHeading('$_headingMarker${item.text}');
    if (scenario != null) return itemKeyOf(scenario, isScenario: true);
  }
  final prefix = template?.prefixId;
  final id = prefix == null ? null : readItemId(item.text, prefix);
  return id == null ? null : itemKeyOf(id, isScenario: false);
}
