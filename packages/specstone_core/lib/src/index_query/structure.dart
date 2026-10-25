import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';

const _indent = '  ';

/// Returns the docs tree, or the subtree of every doc [target] addresses.
///
/// Without [target] it holds each typed doc that has no parent, with its
/// subtree, then each folder of untyped docs. With one, [target] is resolved
/// as [DocIndex.resolve] does and each resolved doc that another resolved
/// doc's subtree already holds is left out. An untyped target prints its one
/// line with no folder line.
ReadAnswer answerStructure(DocIndex index, {String? target}) {
  final shown = target == null ? index.docs : _withoutNested(index, target);
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
    _writeTree(text, index, root, 0);
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
      'docs': [for (final root in roots) _treeJson(index, root)],
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

List<IndexedDoc> _withoutNested(DocIndex index, String target) {
  final resolved = index.resolve(target);
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

void _writeTree(StringBuffer text, DocIndex index, IndexedDoc doc, int depth) {
  text.writeln('${_indent * depth}${docLine(index, doc)}');
  for (final child in index.childrenOf(doc)) {
    _writeTree(text, index, child, depth + 1);
  }
}

Map<String, Object> _treeJson(DocIndex index, IndexedDoc doc) => {
  ...docJson(index, doc),
  'children': [
    for (final child in index.childrenOf(doc)) _treeJson(index, child),
  ],
};
