import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/template_fault.dart';

const _featureType = 'feature';
const _storyType = 'user_story';
const _planned = 'planned';
const _implemented = 'implemented';
const _deprecated = 'deprecated';

/// A `@<hash>` suffix: 12 lowercase hex characters.
final _hashSuffix = RegExp(r'@[0-9a-f]{12}$');

/// The docs root as a path from the project root begins.
const _docsPrefix = 'docs/';

/// The docs of one read snapshot, with their names, parent tree, and links.
///
/// Every list it returns is in tree order.
final class DocIndex {
  new(this.set, this.docs, this._store, this._docPathOfFile)
    : _byPath = {for (final doc in docs) doc.docPath: doc},
      _children = _childrenByParent(docs),
      _byName = _groupBy(docs, (doc) => doc.name),
      _byTypeAndName = _groupBy(docs, (doc) => '${doc.docTypeId}:${doc.name}'),
      _chainTypes = _chainTypeIds(set);

  /// The merged doc types of the project.
  final MergedSet set;

  /// Every doc in tree order.
  final List<IndexedDoc> docs;

  final IndexStore _store;

  /// Returns the DocPath of the file a working-directory path names, or null.
  final String? Function(String path) _docPathOfFile;
  final Map<String, IndexedDoc> _byPath;
  final Map<String, List<IndexedDoc>> _children;
  final Map<String, List<IndexedDoc>> _byName;
  final Map<String, List<IndexedDoc>> _byTypeAndName;
  final Set<String> _chainTypes;

  /// Returns the doc at [docPath], or null when none is indexed there.
  IndexedDoc? at(String docPath) => _byPath[docPath];

  /// Returns the docs of the doc type [typeId] named [name], in tree order.
  List<IndexedDoc> ofTypeNamed(String typeId, String name) =>
      _byTypeAndName['$typeId:$name'] ?? const [];

  /// Returns the doc [doc] nests under, or null for a root doc.
  IndexedDoc? parentOf(IndexedDoc doc) {
    final parentPath = doc.parentPath;
    return parentPath == null ? null : _byPath[parentPath];
  }

  /// Returns the docs that nest directly under [doc].
  List<IndexedDoc> childrenOf(IndexedDoc doc) =>
      _children[doc.docPath] ?? const [];

  /// Returns [doc] followed by every doc nested under it, parents first.
  List<IndexedDoc> subtreeOf(IndexedDoc doc) => [
    doc,
    for (final child in childrenOf(doc)) ...subtreeOf(child),
  ];

  /// Returns [doc], then each parent up to the top doc.
  List<IndexedDoc> chainOf(IndexedDoc doc) {
    final chain = <IndexedDoc>[];
    for (var next = doc as IndexedDoc?; next != null; next = parentOf(next)) {
      chain.add(next);
    }
    return chain;
  }

  /// Returns every doc [address] names, read as a path first, then as a name.
  ///
  /// - A name: bare, `<doc type>:<name>`, or an untyped doc's DocPath.
  /// - A path, tried in order: a DocPath, `docs/` and a DocPath, a file path
  ///   from the working directory inside the docs root. `<doc type>:<path>`
  ///   keeps the doc only when it has that doc type.
  ///
  /// The path is read first: the whole text naming a doc wins, so a path may
  /// hold `#` or `@`. A command that reads a `#<section key>` or an `@<hash>`
  /// splits it off before it calls; one left on text before it that names a
  /// doc is refused, so a whole-doc command never acts on a doc the caller
  /// meant to narrow.
  ///
  /// Throws an [IndexFault] `argument_invalid` for such a suffix, a
  /// [TemplateFault] for a doc type id the set lacks and an [IndexFault]
  /// `doc_not_found` when no doc carries the name.
  List<IndexedDoc> resolve(String address) {
    if (_atPath(address) case final doc?) return [doc];
    final docPart = _beforeSuffix(address);
    if (docPart == null) return _named(address);
    // Throws the not-found fault when the text before the suffix names no doc.
    if (_atPath(docPart) == null) _named(docPart);
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      '$address: this command takes no #<section key> or @<hash>',
    );
  }

  /// Returns the shortest address that picks only [doc]: `<doc type>:<name>`
  /// when that names one doc, else its DocPath.
  String addressOf(IndexedDoc doc) {
    final typed = '${doc.docTypeId}:${doc.name}';
    return doc.docTypeId != null && _byTypeAndName[typed]!.length == 1
        ? typed
        : doc.docPath;
  }

  /// Splits [address] into the text that names docs and its `#<section key>`
  /// (RULE-11).
  ///
  /// The whole text is read as a path first, as [resolve] reads it: one that
  /// names a doc has no section key, even when it holds `#`.
  ({String docPart, String? sectionKey}) splitAddress(String address) {
    if (_atPath(address) != null) return (docPart: address, sectionKey: null);
    final read = readDocAddress(address);
    return (docPart: read.docPart, sectionKey: read.sectionKey);
  }

  /// The text of [address] before its `#<section key>` or `@<hash>`; null
  /// when it carries neither.
  String? _beforeSuffix(String address) {
    final read = readDocAddress(address);
    if (read.sectionKey != null) return read.docPart;
    final hash = _hashSuffix.firstMatch(address);
    return hash == null ? null : address.substring(0, hash.start);
  }

  List<IndexedDoc> _named(String address) {
    final read = readDocAddress(address);
    final typeId = read.typeId;
    if (typeId == null) {
      return _byName[read.body] ??
          _notFound('no doc carries the name ${read.body}');
    }
    if (set.lookup(typeId) == null) {
      throw TemplateFault(
        FaultCode.docTypeUnknown,
        'Could not find a doc type named "$typeId".',
      );
    }
    return _byTypeAndName['$typeId:${read.body}'] ??
        _notFound('no $typeId doc carries the name ${read.body}');
  }

  /// Returns the doc [address] names as a path, or null when none.
  ///
  /// The whole text is tried as a path too: `C:/docs/x.md` reads as the doc
  /// type id `C`.
  IndexedDoc? _atPath(String address) {
    final read = readDocAddress(address);
    final typeId = read.typeId;
    if (typeId != null) {
      final typed = _docAtPath(read.body);
      if (typed != null && typed.docTypeId == typeId) return typed;
    }
    return _docAtPath(address);
  }

  IndexedDoc? _docAtPath(String path) {
    if (_byPath[path] case final doc?) return doc;
    if (path.startsWith(_docsPrefix)) {
      if (_byPath[path.substring(_docsPrefix.length)] case final doc?) {
        return doc;
      }
    }
    final docPath = _docPathOfFile(path);
    return docPath == null ? null : _byPath[docPath];
  }

  /// Returns the subtrees of every doc [name] addresses, each doc once.
  List<IndexedDoc> under(String name) {
    final paths = {
      for (final doc in resolve(name))
        for (final member in subtreeOf(doc)) member.docPath,
    };
    return [
      for (final doc in docs)
        if (paths.contains(doc.docPath)) doc,
    ];
  }

  /// Returns the status of [doc].
  ///
  /// A feature takes it from the stories of its whole subtree: `planned` with
  /// no story, `deprecated` when every story is, `implemented` when every story
  /// that is not deprecated is, else `planned`. Any other doc returns the
  /// status it writes, or null.
  String? statusOf(IndexedDoc doc) {
    if (doc.docTypeId != _featureType) return doc.writtenStatus;
    final stories = [
      for (final member in subtreeOf(doc).skip(1))
        if (member.docTypeId == _storyType) member.writtenStatus,
    ];
    if (stories.isEmpty) return _planned;
    if (stories.every((status) => status == _deprecated)) return _deprecated;
    final live = stories.where((status) => status != _deprecated);
    return live.every((status) => status == _implemented)
        ? _implemented
        : _planned;
  }

  /// Whether the doc type [docTypeId] sits on the parent chain of a query.
  bool isChainType(String docTypeId) => _chainTypes.contains(docTypeId);

  /// Whether [doc] is typed with a ChainType.
  bool isChainDoc(IndexedDoc doc) {
    final typeId = doc.docTypeId;
    return typeId != null && isChainType(typeId);
  }

  /// Returns the doc type of [doc], or null when it is untyped.
  MergedDocType? typeOf(IndexedDoc doc) {
    final typeId = doc.docTypeId;
    return typeId == null ? null : set.lookup(typeId);
  }

  /// Returns the text and structure of [doc].
  DocContent contentOf(IndexedDoc doc) => _store.loadContent(doc.docPath);

  /// Returns the rows of the full-text index that match [matchExpression].
  List<SearchRow> search(String matchExpression) =>
      _store.search(matchExpression);

  /// Returns the docs whose text holds [needle], case-sensitive.
  List<IndexedDoc> holding(String needle) {
    final paths = _store.docPathsHolding(needle).toSet();
    return [
      for (final doc in docs)
        if (paths.contains(doc.docPath)) doc,
    ];
  }

  /// Returns the docs [doc] links to.
  List<IndexedDoc> linkedFrom(IndexedDoc doc) =>
      _linked((link) => link.source == doc.docPath, (link) => link.target);

  /// Returns the docs that link to [doc].
  List<IndexedDoc> linkingTo(IndexedDoc doc) =>
      _linked((link) => link.target == doc.docPath, (link) => link.source);

  List<IndexedDoc> _linked(
    bool Function(({String source, String target}) link) keep,
    String Function(({String source, String target}) link) end,
  ) {
    final paths = {
      for (final link in _store.loadLinks())
        if (keep(link)) end(link),
    };
    return [
      for (final doc in docs)
        if (paths.contains(doc.docPath)) doc,
    ];
  }
}

Never _notFound(String message) =>
    throw IndexFault(IndexFaultCode.docNotFound, message);

Map<String, List<IndexedDoc>> _groupBy(
  List<IndexedDoc> docs,
  String Function(IndexedDoc doc) key,
) {
  final groups = <String, List<IndexedDoc>>{};
  for (final doc in docs) {
    (groups[key(doc)] ??= []).add(doc);
  }
  return _unmodifiable(groups);
}

Map<String, List<IndexedDoc>> _childrenByParent(List<IndexedDoc> docs) {
  final children = <String, List<IndexedDoc>>{};
  for (final doc in docs) {
    if (doc.parentPath case final parentPath?) {
      (children[parentPath] ??= []).add(doc);
    }
  }
  return _unmodifiable(children);
}

/// Returns [groups] with each list unmodifiable, so no caller can sort the
/// index's own lists in place.
Map<String, List<IndexedDoc>> _unmodifiable(
  Map<String, List<IndexedDoc>> groups,
) => {
  for (final MapEntry(:key, :value) in groups.entries)
    key: List.unmodifiable(value),
};

/// Returns the ids INV-10 calls chain types: a doc type with a child doc type,
/// or one whose parent has no child doc type with children of its own.
Set<String> _chainTypeIds(MergedSet set) {
  final parents = {for (final type in set.docTypes) ?type.parent};
  bool hasChildren(String id) => parents.contains(id);
  return {
    for (final type in set.docTypes)
      if (hasChildren(type.id) ||
          switch (type.parent) {
            final parent? => !set.docTypes.any(
              (sibling) => sibling.parent == parent && hasChildren(sibling.id),
            ),
            null => false,
          })
        type.id,
  };
}
