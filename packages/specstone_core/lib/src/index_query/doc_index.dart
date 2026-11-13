import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/record_entries.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/template_fault.dart';

/// The id of the `feature` doc type.
const featureType = 'feature';

/// The id of the `user_story` doc type.
const storyType = 'user_story';

/// The id of the `fr` doc type.
const frType = 'fr';

/// A `@<hash>` suffix: 12 lowercase hex characters.
final _hashSuffix = RegExp(r'@[0-9a-f]{12}$');

/// The docs root as a path from the project root begins.
const _docsPrefix = 'docs/';

/// The entry item that names the record's own feature (a skip).
const _featureItem = '';

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
  }) : _byPath = {for (final doc in docs) doc.docPath: doc},
       _children = _childrenByParent(docs),
       _byName = _groupBy(docs, (doc) => doc.name),
       _byTypeAndName = _groupBy(docs, (doc) => '${doc.docTypeId}:${doc.name}'),
       _chainTypes = _chainTypeIds(set),
       targetNames = List.unmodifiable(targetNames);

  /// The merged doc types of the project.
  final MergedSet set;

  /// Every doc in tree order.
  final List<IndexedDoc> docs;

  /// The config's target names, in config order; empty with one unnamed
  /// target.
  final List<String> targetNames;

  final IndexStore _store;

  /// Returns the DocPath of the file a working-directory path names, or null.
  final String? Function(String path) _docPathOfFile;
  final Map<String, IndexedDoc> _byPath;
  final Map<String, List<IndexedDoc>> _children;
  final Map<String, List<IndexedDoc>> _byName;
  final Map<String, List<IndexedDoc>> _byTypeAndName;
  final Set<String> _chainTypes;

  /// The record entries of each record doc, keyed by its docPath; built on
  /// first read.
  late final Map<String, List<RecordEntry>> _recordEntries = {
    if (set.recordDocType case final type?)
      for (final record in docs)
        if (record.docTypeId == type.id)
          record.docPath: recordEntriesOf(record, type),
  };

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
  /// [codeTarget], when given, must be one of [targetNames] and keeps a name
  /// to that target's docs and the shared docs (INV-26); a path names its doc
  /// whatever target.
  ///
  /// Throws an [IndexFault] `argument_invalid` for a code target [targetNames]
  /// holds none of, or for such a suffix, a [TemplateFault] for a doc type id
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
    return _namedOf(_byTypeAndName['$typeId:${read.body}'], codeTarget) ??
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
        if (doc.target == null || doc.target == codeTarget) doc,
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
  ///
  /// [codeTarget], when given, keeps [name] to that target's docs and the
  /// shared docs, as [resolve] does; a subtree member of another target
  /// stays out, since a resolved shared doc's subtree holds one tree per
  /// target.
  List<IndexedDoc> under(String name, {String? codeTarget}) {
    final paths = {
      for (final doc in resolve(name, codeTarget: codeTarget))
        for (final member in subtreeOf(doc))
          if (codeTarget == null ||
              member.target == null ||
              member.target == codeTarget)
            member.docPath,
    };
    return [
      for (final doc in docs)
        if (paths.contains(doc.docPath)) doc,
    ];
  }

  /// Returns the status of [doc] in [codeTarget], or in its one target when
  /// null: the one `targets:` names when it names one, else the unnamed
  /// target.
  ///
  /// A feature computes it from its subtree's stories (INV-17); a story or FR
  /// takes its record entry's status, or `planned` without one, outside every
  /// skip that covers it (INV-29); any other doc returns the status it writes,
  /// or null. With no record doc type every story and FR reads its `status:`
  /// with no target, and a feature computes from those (INV-29).
  String? statusOf(IndexedDoc doc, {String? codeTarget}) {
    final typeId = doc.docTypeId;
    if (typeId == featureType) return _featureStatusOf(doc, codeTarget).wire;
    if (typeId != storyType && typeId != frType) return doc.writtenStatus;
    if (set.recordDocType == null) return doc.writtenStatus;
    return itemStatus(doc, codeTarget: codeTarget).wire;
  }

  /// Returns the status of the story or FR [item] in [codeTarget] (INV-29):
  /// `skipped` under a skip of its feature, of a feature above, or, for an FR,
  /// of its story; else its record entry's `statuses` status, `planned`
  /// without an entry or a status.
  RecordStatus itemStatus(IndexedDoc item, {String? codeTarget}) {
    final records = _recordsOf(item, _namedOrGiven(codeTarget));
    for (final record in records) {
      final relative = _relativeItemOf(item, record);
      for (final entry in record.entries) {
        if (entry.status == RecordStatus.skipped &&
            _skipCovers(entry.item, relative)) {
          return RecordStatus.skipped;
        }
      }
    }
    for (final record in records) {
      final relative = _relativeItemOf(item, record);
      for (final entry in record.entries) {
        if (entry.item == relative) return entry.status ?? RecordStatus.planned;
      }
    }
    return RecordStatus.planned;
  }

  /// Returns the record entry of the story or FR [item] in [codeTarget], or
  /// in its one target when null (as [statusOf] reads it); null with no
  /// entry, and with no record doc type.
  RecordEntry? recordEntryOf(IndexedDoc item, {String? codeTarget}) {
    final record = set.recordDocType;
    if (record == null) return null;
    for (final doc in _recordsOf(item, _namedOrGiven(codeTarget))) {
      final relative = _relativeItemOf(item, doc);
      for (final entry in doc.entries) {
        if (entry.item == relative) return entry;
      }
    }
    return null;
  }

  /// Returns the feature [doc]'s status in [codeTarget] from the stories of
  /// its whole subtree (INV-17): `skipped` under its own skip or one above;
  /// `planned` with no story; `skipped` when every story is; `deprecated`
  /// when every story not skipped is; `implemented` when every story neither
  /// skipped nor deprecated is; `planned` otherwise.
  RecordStatus _featureStatusOf(IndexedDoc doc, String? codeTarget) {
    final records = _recordsOf(doc, _namedOrGiven(codeTarget));
    final skippedAbove = records.any(
      (record) => record.entries.any(
        (entry) =>
            entry.item == _featureItem && entry.status == RecordStatus.skipped,
      ),
    );
    if (skippedAbove) return RecordStatus.skipped;
    RecordStatus storyStatusOf(IndexedDoc story) => set.recordDocType == null
        ? RecordStatus.byWire(story.writtenStatus ?? '') ?? RecordStatus.planned
        : itemStatus(story, codeTarget: _namedOrGiven(codeTarget));
    final stories = [
      for (final member in subtreeOf(doc).skip(1))
        if (member.docTypeId == storyType) storyStatusOf(member),
    ];
    if (stories.isEmpty) return RecordStatus.planned;
    if (stories.every((s) => s == RecordStatus.skipped)) {
      return RecordStatus.skipped;
    }
    final left = stories.where((s) => s != RecordStatus.skipped);
    if (left.every((s) => s == RecordStatus.deprecated)) {
      return RecordStatus.deprecated;
    }
    final live = left.where((s) => s != RecordStatus.deprecated);
    return live.every((s) => s == RecordStatus.implemented)
        ? RecordStatus.implemented
        : RecordStatus.planned;
  }

  /// Returns [codeTarget], or the one name `targets:` holds when the project
  /// names exactly one code target and none was given.
  String? _namedOrGiven(String? codeTarget) =>
      codeTarget ?? (targetNames.length == 1 ? targetNames.single : null);

  /// The records of [doc]'s feature and of each feature above it in
  /// [codeTarget], nearest feature first.
  List<_RecordDoc> _recordsOf(IndexedDoc doc, String? codeTarget) {
    final type = set.recordDocType;
    if (type == null) return const [];
    final records = <_RecordDoc>[];
    for (IndexedDoc? member = doc; member != null; member = parentOf(member)) {
      if (member.docTypeId != featureType) continue;
      for (final record in ofTypeNamed(type.id, member.name)) {
        if (record.target != codeTarget) continue;
        records.add((
          feature: member.name,
          entries: _recordEntries[record.docPath] ?? const [],
        ));
      }
    }
    return records;
  }

  /// Returns [item]'s name relative to [record]'s feature: its own name with
  /// the feature's prefix dropped.
  String _relativeItemOf(IndexedDoc item, _RecordDoc record) {
    final prefix = '${record.feature}/';
    return item.name.startsWith(prefix)
        ? item.name.substring(prefix.length)
        : item.name;
  }

  /// Whether the skipped [entryItem] covers [relative]: the record's own
  /// feature, the item itself, or a story or feature above it.
  bool _skipCovers(String entryItem, String relative) =>
      entryItem.isEmpty ||
      entryItem == relative ||
      relative.startsWith('$entryItem/');

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

/// The record doc of one feature in one target: the feature's name, the one
/// the record's entry items are relative to, and its parsed entries.
typedef _RecordDoc = ({String feature, List<RecordEntry> entries});

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
