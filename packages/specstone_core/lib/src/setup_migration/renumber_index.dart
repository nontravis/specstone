import 'package:specstone_core/src/doc_model/doc_link.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/setup_migration/renumber_doc.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

// MARK: - Constants

const _apiType = 'api';
const _projectType = 'project';
const _docsPrefix = 'docs/';
final _slugPlaceholder = RegExp(r'\{slug\}');

// MARK: - Types

/// The block a `confirmed` label tracks, as its DocPath and block key, and the
/// label after the renumber pass.
typedef LinkTarget = ({String label, (String, String) block});

// MARK: - RenumberIndex

/// What the renumber pass's renumberings and doc names resolve to.
final class RenumberIndex {
  new(List<RenumberDoc> docs)
    : _docs = docs,
      _lettered = [for (final doc in docs) ...doc.lettered] {
    for (final doc in docs) {
      _docsByPath[doc.docPath] = doc;
      _typeIds[doc.docPath] = doc.type.id;
      (_byName[doc.name] ??= []).add(doc.docPath);
      (_byTypedName['${doc.type.id}:${doc.name}'] ??= []).add(doc.docPath);
      if (doc.holdsScenarios) {
        _storyPaths.putIfAbsent(doc.name, () => doc.docPath);
        _storyDocPaths.add(doc.docPath);
      }
    }
    for (final lettered in _lettered) {
      final key = _keyOf(lettered.from);
      (_letteredByDoc[lettered.docPath] ??= {}).putIfAbsent(
        key,
        () => lettered,
      );
      prefixes.add(lettered.item.prefix);
    }
    _indexParents(docs);
  }

  final List<RenumberDoc> _docs;
  final List<LetteredItem> _lettered;
  final _docsByPath = <String, RenumberDoc>{};
  final _typeIds = <String, String>{};
  final _byName = <String, List<String>>{};
  final _byTypedName = <String, List<String>>{};
  final _storyPaths = <String, String>{};
  final _storyDocPaths = <String>{};

  /// Each renumbered doc's lettered items, keyed as [_keyOf] keys an ID.
  final _letteredByDoc = <String, Map<String, LetteredItem>>{};

  /// The Name of each doc's parent, by DocPath.
  final _parentNames = <String, String>{};

  /// The prefixes of the renumbered IDs.
  final prefixes = <String>{};

  /// The `gnfr` doc holding each NFR ID.
  late final Map<String, String> _nfrPaths = _idPathsOfType(
    gnfrTypeId,
    letteredOnly: false,
  );

  /// The `project` doc holding each lettered project ID.
  late final Map<String, String> _projectPaths = _idPathsOfType(
    _projectType,
    letteredOnly: true,
  );

  /// Per story DocPath, the one lettered scenario of each number value that
  /// the story holds no plain scenario of, which 1.1.0 read `S<N>` as (W10).
  late final Map<String, Map<BigInt, LetteredItem>> _soleLettered =
      _soleLetteredOf();

  /// The texts one of which a doc must hold for the body rewrite to change
  /// it: each renumbered ID and its short scenario ref (W17).
  late final Set<String> _tokens = {
    for (final (:from, docPath: _, item: _, to: _) in _lettered) ...[
      from,
      if (from.startsWith(scenarioIdPrefix)) scenarioRefOf(from),
    ],
  };

  List<({String docPath, String from, String to})> get renumberings => [
    for (final (:docPath, item: _, :from, :to) in _lettered)
      (docPath: docPath, from: from, to: to),
  ];

  /// Whether a scenario is renumbered, so a ref by another digit count or a
  /// 1.1.0 `S<N>` may name it.
  late final bool renumbersScenarios = _lettered.any(
    (lettered) => lettered.item.prefix == scenarioIdPrefix,
  );

  /// Maps each item ID of the docs of [typeId], or each lettered one, to its
  /// doc; the first doc in tree order wins.
  Map<String, String> _idPathsOfType(
    String typeId, {
    required bool letteredOnly,
  }) {
    final paths = <String, String>{};
    for (final doc in _docs) {
      if (doc.type.id != typeId) continue;
      final ids = letteredOnly
          ? [for (final lettered in doc.lettered) lettered.from]
          : [
              for (final item in doc.items)
                if (item.id case final id? when id is! UnreadableId) id.written,
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
      _slugPlaceholder.allMatches(type.path ?? '').length;

  /// The key of the ID [id] among a doc's lettered items: a scenario ID by
  /// the value of its number (W9), any other ID as written.
  static String _keyOf(String id) =>
      id.startsWith(scenarioIdPrefix) ? scenarioBlockKeyOfId(id) : id;

  // MARK: - Renumberings

  /// Whether [text] holds the text of any renumbered ID or scenario ref.
  bool mayName(String text) => _tokens.any(text.contains);

  /// The new ID of [from] in the doc at [docPath], or null.
  String? toOf(String docPath, String from) =>
      _letteredByDoc[docPath]?[_keyOf(from)]?.to;

  /// The lettered scenario of the story at [storyPath] the number [number]
  /// names: a lettered number by its value, or a plain one 1.1.0 read as the
  /// story's one lettered scenario of that value (W10); null for none.
  LetteredItem? scenarioAt(String storyPath, IdRead number) => switch (number) {
    LetteredId() => _letteredByDoc[storyPath]?[scenarioBlockKeyOf(number)],
    ItemId(:final number) => _soleLettered[storyPath]?[number],
    UnreadableId() => null,
  };

  /// The renumbering of scenario [number] of the story named [storyName].
  LetteredItem? scenarioOf(String? storyName, IdRead number) {
    final storyPath = storyName == null ? null : _storyPaths[storyName];
    return storyPath == null ? null : scenarioAt(storyPath, number);
  }

  /// Whether the story at [storyPath] holds a renumbered lettered scenario.
  bool renumbersAScenarioOf(String storyPath) =>
      _letteredByDoc[storyPath]?.values.any(
        (lettered) => lettered.item.prefix == scenarioIdPrefix,
      ) ??
      false;

  /// The story the doc at [docPath] holds its own scenario refs of: itself
  /// when it holds scenarios, else its parent story; null for none.
  String? ownStoryOf(String docPath) {
    if (_storyDocPaths.contains(docPath)) return docPath;
    final parent = _parentNames[docPath];
    return parent == null ? null : _storyPaths[parent];
  }

  /// The DocPath of the story [ref] names from the doc at [docPath], or
  /// null.
  String? storyOfRef(ScenarioRef ref, String docPath) {
    final named = ref.storyName ?? _parentNames[docPath];
    return named == null ? null : _storyPaths[named];
  }

  // MARK: - Entry values

  /// The new `traced_from` value of [value] in the doc at [docPath]: a
  /// renumbered scenario ref or project ID; null to keep it.
  String? tracedFromLabel(String value, String docPath) {
    final scenario = scenarioTarget(value, docPath)?.label;
    if (scenario != null) return scenario == value ? null : scenario;
    return projectIdLabel(value);
  }

  /// The new `vision`, `goals`, or `traced_from` value of [value], a
  /// renumbered `project` ID; null to keep it.
  String? projectIdLabel(String value) {
    final projectPath = _projectPaths[value];
    return projectPath == null ? null : toOf(projectPath, value);
  }

  /// The new `overrides` value of [value], a renumbered NFR ID; null to keep
  /// it.
  String? overridesLabel(String value) {
    final docPath = _nfrPaths[value];
    return docPath == null ? null : toOf(docPath, value);
  }

  /// The block a `confirmed` [label] of the doc at [docPath] tracks, as
  /// `check` resolves it: a scenario ref, an NFR ID, or an api's FR ref.
  LinkTarget? confirmedTarget(String label, String docPath) =>
      scenarioTarget(label, docPath) ??
      _nfrTarget(label) ??
      _frTarget(label, docPath);

  /// The scenario block the ref [label] in the doc at [docPath] names, an
  /// `S<N>` ref one of the doc's parent story.
  LinkTarget? scenarioTarget(String label, String docPath) {
    final ref = readScenarioRef(label);
    if (ref == null) return null;
    final storyPath = storyOfRef(ref, docPath);
    if (storyPath == null) return null;
    final lettered = scenarioAt(storyPath, ref.number);
    final number = lettered == null
        ? ref.number.written
        : scenarioRefOf(lettered.to);
    final storyName = ref.storyName;
    return (
      label: storyName == null ? number : '$storyName#$number',
      block: (storyPath, scenarioBlockKeyOf(lettered?.item.id ?? ref.number)),
    );
  }

  LinkTarget? _nfrTarget(String label) {
    final docPath = _nfrPaths[label];
    if (docPath == null) return null;
    return (label: toOf(docPath, label) ?? label, block: (docPath, label));
  }

  /// The FR an api's FR ref [label] names: `<feature Name>/<label>`.
  LinkTarget? _frTarget(String label, String docPath) {
    final feature = _parentNames[docPath];
    if (_typeIds[docPath] != _apiType || feature == null) return null;
    final frPath = _byTypedName['$frTypeId:$feature/$label']?.firstOrNull;
    if (frPath == null) return null;
    return (label: label, block: (frPath, statementSectionId));
  }

  // MARK: - Citations

  /// The docs the code span text [text] in the doc at [fromPath] cites: a
  /// Name, `<doc type>:<Name>`, or a path that resolves (RULE-11); empty for
  /// a doc address naming no doc of the run; null when it cites no doc.
  List<String>? citedBySpan(String text, String fromPath) {
    final address = readDocAddress(text);
    if (address.isName) {
      final typeId = address.typeId;
      final named = typeId == null
          ? _byName[address.body]
          : _byTypedName['$typeId:${address.body}'];
      if (named != null) return named;
      return address.isReferenceWithoutLookup ? const [] : null;
    }
    if (address.typeId != null) return null;
    final docPath = docAtPath(address.body, fromPath);
    return docPath == null ? null : [docPath];
  }

  /// The doc of the run [path] reaches from the doc at [fromPath], as a link
  /// would, else read as a DocPath; null when none.
  String? docAtPath(String path, String fromPath) {
    if (resolveDocLink(path, fromPath) case DocTarget(:final docPath)
        when _docsByPath.containsKey(docPath)) {
      return docPath;
    }
    if (_docsByPath.containsKey(path)) return path;
    if (!path.startsWith(_docsPrefix)) return null;
    final docPath = path.substring(_docsPrefix.length);
    return _docsByPath.containsKey(docPath) ? docPath : null;
  }
}
