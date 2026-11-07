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

/// The block a `confirmed` label tracks, as a stamp key, and the label after
/// the renumber pass.
typedef LinkTarget = ({String label, (String, String) block});

// MARK: - RenumberIndex

/// What the renumber pass's renumberings and doc names resolve to.
final class RenumberIndex {
  new(List<RenumberDoc> docs)
    : _lettered = [for (final doc in docs) ...doc.lettered] {
    for (final doc in docs) {
      _docPaths.add(doc.docPath);
      _typeIds[doc.docPath] = doc.type.id;
      (_byName[doc.name] ??= []).add(doc.docPath);
      (_byTypedName['${doc.type.id}:${doc.name}'] ??= []).add(doc.docPath);
      if (doc.holdsScenarios) {
        _storyPaths.putIfAbsent(doc.name, () => doc.docPath);
      }
    }
    for (final (:docPath, :item, :from, :to) in _lettered) {
      (_toByDoc[docPath] ??= {}).putIfAbsent(from, () => to);
      prefixes.add(item.prefix);
    }
    _indexIdsOfType(docs, gnfrTypeId, _nfrPaths, letteredOnly: false);
    _indexIdsOfType(docs, _projectType, _projectPaths, letteredOnly: true);
    _indexParents(docs);
  }

  final List<LetteredItem> _lettered;
  final _docPaths = <String>{};
  final _typeIds = <String, String>{};
  final _byName = <String, List<String>>{};
  final _byTypedName = <String, List<String>>{};
  final _storyPaths = <String, String>{};
  final _toByDoc = <String, Map<String, String>>{};

  /// The `gnfr` doc holding each NFR ID.
  final _nfrPaths = <String, String>{};

  /// The `project` doc holding each lettered project ID.
  final _projectPaths = <String, String>{};

  /// The Name of each doc's parent, by DocPath.
  final _parentNames = <String, String>{};

  /// The prefixes of the renumbered IDs.
  final prefixes = <String>{};

  List<({String docPath, String from, String to})> get renumberings => [
    for (final (:docPath, item: _, :from, :to) in _lettered)
      (docPath: docPath, from: from, to: to),
  ];

  /// Maps each item ID of the docs of [typeId], or each lettered one, to its
  /// doc; the first doc in tree order wins.
  static void _indexIdsOfType(
    List<RenumberDoc> docs,
    String typeId,
    Map<String, String> paths, {
    required bool letteredOnly,
  }) {
    for (final doc in docs) {
      if (doc.type.id != typeId) continue;
      final ids = letteredOnly
          ? [for (final lettered in doc.lettered) lettered.from]
          : [for (final item in doc.items) ?item.id?.written];
      for (final id in ids) {
        paths.putIfAbsent(id, () => doc.docPath);
      }
    }
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

  // MARK: - Renumberings

  /// Whether [lf] holds the text of any renumbered ID or scenario ref.
  bool mayName(String lf) => _lettered.any(
    (lettered) =>
        lf.contains(lettered.from) || lf.contains(scenarioRefOf(lettered.from)),
  );

  /// The new ID of [from] in the doc at [docPath], or null.
  String? toOf(String docPath, String from) => _toByDoc[docPath]?[from];

  /// The renumbering of scenario [number] of the story named [storyName].
  Renumbering? scenarioOf(String? storyName, IdRead number) {
    final docPath = storyName == null ? null : _storyPaths[storyName];
    if (docPath == null) return null;
    final digits = number.written.substring(number.prefix.length);
    final from = '$scenarioIdPrefix$digits';
    final to = toOf(docPath, from);
    return to == null ? null : (docPath: docPath, from: from, to: to);
  }

  // MARK: - Entry values

  /// The new `traced_from` value of [value] in the doc at [docPath]: a
  /// renumbered scenario ref or project ID; null to keep it.
  String? tracedFromLabel(String value, String docPath) {
    final scenario = scenarioTarget(value, docPath)?.label;
    if (scenario != null) return scenario == value ? null : scenario;
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
    final storyName = ref.storyName;
    final named = storyName ?? _parentNames[docPath];
    final storyPath = named == null ? null : _storyPaths[named];
    if (storyPath == null) return null;
    final written = ref.number.written;
    final to = scenarioOf(named, ref.number)?.to;
    final number = to == null ? written : scenarioRefOf(to);
    return (
      label: storyName == null ? number : '$storyName#$number',
      block: (storyPath, written),
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
        when _docPaths.contains(docPath)) {
      return docPath;
    }
    if (_docPaths.contains(path)) return path;
    if (!path.startsWith(_docsPrefix)) return null;
    final docPath = path.substring(_docsPrefix.length);
    return _docPaths.contains(docPath) ? docPath : null;
  }
}
