import 'package:specstone_core/src/doc_model/models/id_read.dart';
import 'package:specstone_core/src/doc_model/path_pattern.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/setup_migration/renumber_doc.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

// MARK: - Constants

const _apiType = 'api';
// MARK: - Types

/// The block a `confirmed` label tracks: its doc and block key.
final class BlockRef {
  const new({required this.docPath, required this.key});

  final String docPath;
  final String key;
}

// MARK: - RenumberIndex

/// What a `confirmed` label of a doc resolves to among the docs of the run.
final class RenumberIndex {
  new(List<RenumberDoc> docs) : _docs = docs {
    for (final doc in docs) {
      _docsByPath[doc.docPath] = doc;
      _typeIds[doc.docPath] = doc.type.id;
      (_byTypedName['${doc.type.id}:${doc.name}'] ??= []).add(doc.docPath);
      if (doc.holdsScenarios) {
        _storyPaths.putIfAbsent(doc.name, () => doc.docPath);
      }
      for (final lettered in doc.lettered) {
        (_letteredByDoc[lettered.docPath] ??= {}).putIfAbsent(
          _keyOf(lettered.from),
          () => lettered,
        );
      }
    }
    _indexParents(docs);
  }

  final List<RenumberDoc> _docs;
  final _docsByPath = <String, RenumberDoc>{};
  final _typeIds = <String, String>{};
  final _byTypedName = <String, List<String>>{};
  final _storyPaths = <String, String>{};

  /// Each doc's lettered items, keyed as [_keyOf] keys an ID.
  final _letteredByDoc = <String, Map<String, LetteredItem>>{};

  /// The Name of each doc's parent, by DocPath.
  final _parentNames = <String, String>{};

  /// The gnfr doc holding each NFR ID.
  late final Map<String, String> _nfrPaths = _idPathsOfType(gnfrTypeId);

  /// Per story DocPath, the one lettered scenario of each number value that
  /// the story holds no plain scenario of, which 1.1.0 read `S<N>` as.
  late final Map<String, Map<BigInt, LetteredItem>> _soleLettered =
      _soleLetteredOf();

  /// Maps each item ID of the docs of [typeId] to its doc; the first doc in
  /// tree order wins.
  Map<String, String> _idPathsOfType(String typeId) {
    final paths = <String, String>{};
    for (final doc in _docs) {
      if (doc.type.id != typeId) continue;
      final ids = [
        for (final item in doc.items)
          if (item.id case final id? when id is! UnreadableId) id.written,
        ...doc.unprefixedNfrStatements.keys,
      ];
      for (final id in ids) {
        paths.putIfAbsent(id, () => doc.docPath);
      }
    }
    return paths;
  }

  Map<String, Map<BigInt, LetteredItem>> _soleLetteredOf() {
    final sole = <String, Map<BigInt, LetteredItem>>{};
    for (final MapEntry(key: docPath, value: byKey) in _letteredByDoc.entries) {
      final byValue = <BigInt, List<LetteredItem>>{};
      for (final lettered in byKey.values) {
        if (lettered.item.prefix != scenarioIdPrefix) continue;
        final value = BigInt.parse(lettered.item.id!.digits);
        (byValue[value] ??= []).add(lettered);
      }
      final plain = {
        for (final item in _docsByPath[docPath]!.items)
          if (item.prefix == scenarioIdPrefix)
            if (item.id case ItemId(:final number)) number,
      };
      for (final MapEntry(key: value, value: items) in byValue.entries) {
        if (items.length != 1 || plain.contains(value)) continue;
        (sole[docPath] ??= {})[value] = items.single;
      }
    }
    return sole;
  }

  /// Names each doc's parent as `check`'s parent resolution does: its Name
  /// less the `{slug}`s its type adds to the parent type's, when exactly one
  /// doc of the parent type carries that Name.
  void _indexParents(List<RenumberDoc> docs) {
    final types = {for (final doc in docs) doc.type.id: doc.type};
    for (final doc in docs) {
      final parentType = types[doc.type.parent];
      if (parentType == null || parentType.id == doc.type.id) continue;
      final parentSlugs = _slugCountOf(parentType);
      final segments = doc.name.split('/');
      final length = segments.length - _slugCountOf(doc.type) + parentSlugs;
      if (parentSlugs == 0 || length < parentSlugs) continue;
      final name = segments.take(length).join('/');
      final parents = _byTypedName['${parentType.id}:$name'];
      if (parents?.length == 1) _parentNames[doc.docPath] = name;
    }
  }

  static int _slugCountOf(MergedDocType type) =>
      PathSegment.slugCount(type.path ?? '');

  /// The key of the ID [id] among a doc's lettered items: a scenario ID by
  /// the value of its number, any other ID as written.
  static String _keyOf(String id) =>
      id.startsWith(scenarioIdPrefix) ? scenarioBlockKeyOfId(id) : id;

  // MARK: - Scenarios

  /// The lettered scenario of the story at [storyPath] the number [number]
  /// names: the one written as [number], else, for a plain number, the
  /// story's one lettered scenario of that value that no plain scenario
  /// shares, which 1.1.0 read `S<N>` as; null for none.
  LetteredItem? _scenarioAt(String storyPath, IdRead number) =>
      _scenarioMovedAt(storyPath, number) ??
      switch (number) {
        ItemId(:final number) => _soleLettered[storyPath]?[number],
        _ => null,
      };

  /// The lettered scenario of the story at [storyPath] the number [number]
  /// names as written, by its value; null for none.
  LetteredItem? _scenarioMovedAt(String storyPath, IdRead number) =>
      switch (number) {
        UnreadableId() => null,
        _ => _letteredByDoc[storyPath]?[scenarioBlockKeyOf(number)],
      };

  /// The DocPath of the story [ref] names from the doc at [docPath], or
  /// null.
  String? _storyOfRef(ScenarioRef ref, String docPath) {
    final named = ref.storyName ?? _parentNames[docPath];
    return named == null ? null : _storyPaths[named];
  }

  // MARK: - Targets

  /// The block a `confirmed` [label] of the doc at [docPath] tracks, as
  /// `check` resolves it: a scenario ref, an NFR ID, or an api's FR ref.
  BlockRef? confirmedTarget(String label, String docPath) =>
      _scenarioTarget(label, docPath) ??
      _nfrTarget(label) ??
      _frTarget(label, docPath);

  /// The scenario block the ref [label] in the doc at [docPath] names, an
  /// `S<N>` ref one of the doc's parent story.
  BlockRef? _scenarioTarget(String label, String docPath) {
    final ref = readScenarioRef(label);
    if (ref == null) return null;
    final storyPath = _storyOfRef(ref, docPath);
    if (storyPath == null) return null;
    final lettered = _scenarioAt(storyPath, ref.number);
    return BlockRef(
      docPath: storyPath,
      key: scenarioBlockKeyOf(lettered?.item.id ?? ref.number),
    );
  }

  BlockRef? _nfrTarget(String label) {
    final docPath = _nfrPaths[label];
    return docPath == null ? null : BlockRef(docPath: docPath, key: label);
  }

  /// The FR an api's FR ref [label] names: `<feature Name>/<label>`.
  BlockRef? _frTarget(String label, String docPath) {
    final feature = _parentNames[docPath];
    if (_typeIds[docPath] != _apiType || feature == null) return null;
    final frPath = _byTypedName['$frTypeId:$feature/$label']?.firstOrNull;
    if (frPath == null) return null;
    return BlockRef(docPath: frPath, key: statementSectionId);
  }
}
