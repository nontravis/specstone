import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_facts.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';

const _indent = '  ';

typedef _SectionSize = ({String key, int chars, List<ItemFact> items});

/// Returns the docs tree, or the subtree of every doc [target] addresses.
///
/// Without [target] it holds each typed doc that has no parent, with its
/// subtree, then each folder of untyped docs. With one, [target] is resolved
/// as [DocIndex.resolve] does and each resolved doc that another resolved
/// doc's subtree already holds is left out. An untyped target prints its one
/// line with no folder line. [codeTarget], when given, keeps a name to that
/// code target's docs and the shared docs, and the tree holds no other
/// target's doc.
///
/// Each feature, story, and FR line holds its status in each code target, in
/// [DocIndex.targetNames] order, `<target>: <status>` joined by `, `, or its
/// one status alone with one target or with [codeTarget]; any other doc holds
/// the status it writes, or none.
///
/// When [target] resolves to one typed doc, that doc's line is followed by one
/// line per section, its lead first when it holds text, and, under each, one
/// per item, each with the characters the index stores for it, as `check`
/// counts them in the doc as `format` lays it out; the doc's JSON object gains
/// `sections`. No doc is laid out or counted again.
ReadAnswer answerStructure(
  DocIndex index, {
  String? target,
  String? codeTarget,
}) {
  index.checkCodeTarget(codeTarget);
  final resolved = target == null
      ? null
      : index.resolve(target, codeTarget: codeTarget);
  final shown = resolved == null ? index.docs : _withoutNested(index, resolved);
  final sized = switch (resolved) {
    [final doc] when doc.isTyped => doc,
    _ => null,
  };
  final sizes = sized == null ? null : _sectionSizesOf(index, sized);
  final roots = [
    for (final doc in shown)
      if (doc.isTyped &&
          (target != null ||
              (index.parentOf(doc) == null && _shownIn(doc, codeTarget))))
        doc,
  ];
  final folders = _untypedByFolder([
    for (final doc in shown)
      if (!doc.isTyped) doc,
  ]);

  final text = StringBuffer();
  for (final root in roots) {
    _writeTree(text, index, root, 0, codeTarget, root == sized ? sizes : null);
  }
  for (final MapEntry(key: folder, value: docs) in folders.entries) {
    if (target == null) text.writeln(folder);
    for (final doc in docs) {
      text.writeln(
        '${target == null ? _indent : ''}${_docLine(index, doc, codeTarget)}',
      );
    }
  }

  return ReadAnswer(
    text: text.toString(),
    json: {
      'docs': [
        for (final root in roots)
          _treeJson(index, root, codeTarget, root == sized ? sizes : null),
      ],
      'untyped': [
        for (final MapEntry(key: folder, value: docs) in folders.entries)
          {
            'folder': folder,
            'docs': [
              for (final doc in docs)
                docJsonWithStatuses(index, doc, codeTarget),
            ],
          },
      ],
    },
  );
}

/// Whether [doc] shows under [codeTarget]: shared, or that target's alone.
bool _shownIn(IndexedDoc doc, String? codeTarget) =>
    codeTarget == null || doc.target == null || doc.target == codeTarget;

/// Returns [doc]'s line with each code target's status [index] computes.
String _docLine(DocIndex index, IndexedDoc doc, String? codeTarget) =>
    docLineWithStatus(doc, statusPartOf(index, doc, codeTarget));

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

/// Returns the children of [doc] the tree holds: every child, or, with
/// [codeTarget], the shared ones and that target's alone.
List<IndexedDoc> _childrenShown(
  DocIndex index,
  IndexedDoc doc,
  String? codeTarget,
) => [
  for (final child in index.childrenOf(doc))
    if (_shownIn(child, codeTarget)) child,
];

void _writeTree(
  StringBuffer text,
  DocIndex index,
  IndexedDoc doc,
  int depth,
  String? codeTarget,
  List<_SectionSize>? sizes,
) {
  text.writeln('${_indent * depth}${_docLine(index, doc, codeTarget)}');
  for (final section in sizes ?? const <_SectionSize>[]) {
    text.writeln(
      '${_indent * (depth + 1)}${section.key} · ${section.chars} chars',
    );
    for (final item in section.items) {
      final label = item.id ?? 'line ${item.line}';
      text.writeln('${_indent * (depth + 2)}$label · ${item.chars} chars');
    }
  }
  for (final child in _childrenShown(index, doc, codeTarget)) {
    _writeTree(text, index, child, depth + 1, codeTarget, null);
  }
}

Map<String, Object> _treeJson(
  DocIndex index,
  IndexedDoc doc,
  String? codeTarget,
  List<_SectionSize>? sizes,
) => {
  ...docJsonWithStatuses(index, doc, codeTarget),
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
    for (final child in _childrenShown(index, doc, codeTarget))
      _treeJson(index, child, codeTarget, null),
  ],
};

/// Returns the sections of [doc] as the index stores them: the lead first when
/// it holds text, then each section in file order, each with its items.
List<_SectionSize> _sectionSizesOf(DocIndex index, IndexedDoc doc) {
  final content = index.contentOf(doc);
  final facts = content.itemFacts;
  return [
    if (facts.lead case final lead?)
      (key: leadKey, chars: lead.chars, items: facts.leadItems),
    for (final (i, section) in content.sections.indexed)
      (
        key: section.key,
        chars: content.lineFacts.sectionCounts[i].chars,
        items: facts.sectionItems[i],
      ),
  ];
}
