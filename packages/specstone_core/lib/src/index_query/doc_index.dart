import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/record_entries.dart';
import 'package:specstone_core/src/index_query/status_tree.dart';
import 'package:specstone_core/src/templates/code_target.dart' show twinNamesOf;
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/template_fault.dart';

export 'package:specstone_core/src/index_query/indexed_doc.dart'
    show featureType, frType, storyType;

/// A `@<hash>` suffix: 12 lowercase hex characters.
final _hashSuffix = RegExp(r'@[0-9a-f]{12}$');

/// The docs root as a path from the project root begins.
const _docsPrefix = 'docs/';

/// The docs of one read snapshot, with their names, parent tree, and links.
///
/// Every list it returns is in tree order.
final class DocIndex {
  new(
    this.set,
    this.docs,
    this._store,
    this._docPathOfFile, {
    List<String> targetNames = const [],
  }) : statusTree = StatusTree(set, docs, targetNames: targetNames),
       _byName = _groupBy(docs, (doc) => doc.name),
       _chainTypes = _chainTypeIds(set),
       targetNames = List.unmodifiable(targetNames);

  /// The merged doc types of the project.
  final MergedSet set;

  /// Every doc in tree order.
  final List<IndexedDoc> docs;

  /// The config's target names, in config order; empty with one unnamed
  /// target.
  final List<String> targetNames;

  /// The targets a per-target doc's folder is read in: [targetNames] when it
  /// holds two or more, else none ([twinNamesOf]).
  List<String> get twinNames => twinNamesOf(targetNames);

  /// Whether the project names two or more code targets, so per-target docs
  /// sit in target folders and a shared doc's code paths count for no target.
  bool get hasTwins => twinNames.isNotEmpty;

  final IndexStore _store;

  /// Returns the DocPath of the file a working-directory path names, or null.
  final String? Function(String path) _docPathOfFile;
  final Map<String, List<IndexedDoc>> _byName;
  final Set<String> _chainTypes;

  /// The store-free statuses and tree of [docs], which the check and the
  /// migrate stamp read too.
  final StatusTree statusTree;

  /// Returns the doc at [docPath], or null when none is indexed there.
  IndexedDoc? at(String docPath) => statusTree.at(docPath);

  /// Returns the docs of the doc type [typeId] named [name], in tree order.
  List<IndexedDoc> ofTypeNamed(String typeId, String name) =>
      statusTree.ofTypeNamed(typeId, name);

  /// Returns the doc [doc] nests under, or null for a root doc.
  IndexedDoc? parentOf(IndexedDoc doc) => statusTree.parentOf(doc);

  /// Returns the docs that nest directly under [doc].
  List<IndexedDoc> childrenOf(IndexedDoc doc) => statusTree.childrenOf(doc);

  /// Returns [doc] followed by every doc nested under it, parents first.
  List<IndexedDoc> subtreeOf(IndexedDoc doc) => statusTree.subtreeOf(doc);

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
  /// [codeTarget], when given, must be one of [targetNames] and keeps a name
  /// to that target's docs and the shared docs (INV-26); a path names its doc
  /// whatever target.
  ///
  /// Throws an [IndexFault] for a code target [targetNames] holds none of
  /// (`argument_invalid`) or an empty one (`argument_missing`), and
  /// `argument_invalid` for such a suffix; a [TemplateFault] for a doc type id
  /// the set lacks and an [IndexFault] `doc_not_found` when no doc carries
  /// the name.
  List<IndexedDoc> resolve(String address, {String? codeTarget}) {
    checkCodeTarget(codeTarget);
    if (_atPath(address) case final doc?) return [doc];
    final docPart = _beforeSuffix(address);
    if (docPart == null) return _named(address, codeTarget);
    // Throws the not-found fault when the text before the suffix names no doc.
    if (_atPath(docPart) == null) _named(docPart, codeTarget);
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      '$address: this command takes no #<section key> or @<hash>',
    );
  }

  /// Throws for [codeTarget], unless [targetNames] holds it or it is null.
  ///
  /// An empty [codeTarget], a `--target` given no value, is `argument_missing`;
  /// any other name [targetNames] lacks is `argument_invalid`. Both messages
  /// name the targets.
  void checkCodeTarget(String? codeTarget) {
    if (codeTarget == null || targetNames.contains(codeTarget)) return;
    final held = targetNames.join(', ');
    final known = held.isEmpty
        ? 'this project names no code target'
        : 'the code targets are $held';
    throw IndexFault(
      codeTarget.isEmpty
          ? IndexFaultCode.argumentMissing
          : IndexFaultCode.argumentInvalid,
      codeTarget.isEmpty
          ? '--target needs a code target name: $known'
          : '--target $codeTarget: $known',
    );
  }

  /// Returns the shortest address that picks only [doc]: `<doc type>:<name>`
  /// when that names one doc, else its DocPath.
  String addressOf(IndexedDoc doc) {
    final typed = '${doc.docTypeId}:${doc.name}';
    return doc.docTypeId != null &&
            statusTree.ofTypeNamed(doc.docTypeId!, doc.name).length == 1
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

  List<IndexedDoc> _named(String address, String? codeTarget) {
    final read = readDocAddress(address);
    final typeId = read.typeId;
    if (typeId == null) {
      return _namedOf(_byName[read.body], codeTarget) ??
          _notFound('no doc carries the name ${read.body}');
    }
    if (set.lookup(typeId) == null) {
      throw TemplateFault(
        FaultCode.docTypeUnknown,
        'Could not find a doc type named "$typeId".',
      );
    }
    final typed = statusTree.ofTypeNamed(typeId, read.body);
    return _namedOf(typed.isEmpty ? null : typed, codeTarget) ??
        _notFound('no $typeId doc carries the name ${read.body}');
  }

  /// Returns [docs] with a null [codeTarget]; null or empty [docs] under a
  /// code target, so a name never crosses targets.
  List<IndexedDoc>? _namedOf(List<IndexedDoc>? docs, String? codeTarget) {
    if (docs == null || codeTarget == null) return docs;
    if (docs.every((doc) => doc.target != null && doc.target != codeTarget)) {
      return null;
    }
    return [
      for (final doc in docs)
        if (doc.inTarget(codeTarget)) doc,
    ];
  }

  /// Returns the doc [address] names as a path, or null when none.
  ///
  /// The whole text is tried as a path too: `c:/docs/x.md` reads as the doc
  /// type id `c`.
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
    if (at(path) case final doc?) return doc;
    if (path.startsWith(_docsPrefix)) {
      if (at(path.substring(_docsPrefix.length)) case final doc?) {
        return doc;
      }
    }
    final docPath = _docPathOfFile(path);
    return docPath == null ? null : at(docPath);
  }

  /// Returns the subtrees of every doc [name] addresses, each doc once.
  ///
  /// [codeTarget], when given, keeps [name] to that target's docs and the
  /// shared docs, as [resolve] does; a subtree member of another target
  /// stays out, since a resolved shared doc's subtree holds one tree per
  /// target.
  List<IndexedDoc> under(String name, {String? codeTarget}) {
    final paths = {
      for (final doc in resolve(name, codeTarget: codeTarget))
        for (final member in subtreeOf(doc))
          if (member.inTarget(codeTarget)) member.docPath,
    };
    return [
      for (final doc in docs)
        if (paths.contains(doc.docPath)) doc,
    ];
  }

  /// Returns the status of [doc] in [codeTarget] ([StatusTree.statusOf]).
  String? statusOf(IndexedDoc doc, {String? codeTarget}) =>
      statusTree.statusOf(doc, codeTarget: codeTarget);

  /// Returns the status of the story or FR [item] in [codeTarget]
  /// ([StatusTree.itemStatus]).
  RecordStatus itemStatus(IndexedDoc item, {String? codeTarget}) =>
      statusTree.itemStatus(item, codeTarget: codeTarget);

  /// Returns the name of the skip that covers [item] in [codeTarget] apart
  /// from its own entry ([StatusTree.coveringSkipOf]).
  String? coveringSkipOf(IndexedDoc item, {String? codeTarget}) =>
      statusTree.coveringSkipOf(item, codeTarget: codeTarget);

  /// Returns the record entry of [item] in [codeTarget]
  /// ([StatusTree.recordEntryOf]).
  RecordEntry? recordEntryOf(IndexedDoc item, {String? codeTarget}) =>
      statusTree.recordEntryOf(item, codeTarget: codeTarget);

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
