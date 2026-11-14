import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/doc_type_merger.dart';
import 'package:specstone_core/src/templates/feature_pattern_layer.dart';
import 'package:specstone_core/src/templates/merged_set_checks.dart';
import 'package:specstone_core/src/templates/reference_entry.dart';
import 'package:specstone_core/src/templates/template_fault.dart';

/// One merged checklist item.
///
/// `origin` is the id of the feature pattern whose layers last wrote the
/// item's text, so two patterns that share an item agree on all three fields.
typedef ChecklistItem = ({String id, String text, String origin});

/// One layer of a feature pattern and the pack it comes from, if any.
typedef WrittenPatternLayer = ({String? pack, FeaturePatternLayer layer});

/// One feature pattern after its layers merge.
final class FeaturePattern {
  const new({
    required this.id,
    required this.pack,
    required this.extendsId,
    required this.description,
    required this.items,
    required this.reference,
  });

  /// The feature pattern id.
  final String id;

  /// The pack of the lowest layer that names one; null for a project pattern.
  final String? pack;

  /// The feature pattern this one builds on, when written.
  final String? extendsId;

  /// The description the topmost layer writing one gives.
  final String description;

  /// The merged items in order: the `extends` target's first.
  final List<ChecklistItem> items;

  /// The merged reference list.
  final List<ReferenceEntry> reference;

  /// Returns `id`, `pack`, `extends`, `description`, `items`, and `reference`.
  ///
  /// `pack` and `extends` appear only when set; an item prints `id` and
  /// `text`.
  Map<String, Object> toJson() => {
    'id': id,
    'pack': ?pack,
    'extends': ?extendsId,
    'description': description,
    'items': [
      for (final item in items) {'id': item.id, 'text': item.text},
    ],
    'reference': [for (final entry in reference) entry.toJson()],
  };

  /// Returns the description, one line per item, then the sources block.
  ///
  /// Prints [items], every merged item when null; the sources block is absent
  /// when [reference] is empty. Each line ends with a newline.
  String renderBody([List<ChecklistItem>? items]) {
    return [
      description,
      for (final item in items ?? this.items)
        '- **${item.id}** ${item.text.trimRight()}',
      if (reference.isNotEmpty) ...[
        'Pattern sources:',
        ...reference.map(referenceSourceLine),
      ],
    ].map((line) => '$line\n').join();
  }
}

/// Merges every feature pattern of [layersById], layers lowest first.
///
/// [loadIndex] ranks the layer files an `extends_cycle` fault names, as the
/// doc-type merge ranks its own.
///
/// The first layer of an id defines it and must write `description` and
/// `items`. An entry whose item id the base holds replaces its text, or drops
/// the item with `disabled: true`; a new id adds the item last. A pattern
/// that `extends` another starts from the target's merged items and
/// reference. Returns the patterns in code point order of id.
///
/// Throws `override_id_not_found` for a disabled item the base lacks,
/// `missing_key` for a defining layer with no `description` or `items`,
/// `extends_cycle`, `extends_target_unknown`, and the list faults of
/// `reference`.
List<FeaturePattern> mergeFeaturePatterns(
  Map<String, List<WrittenPatternLayer>> layersById, {
  required LoadIndex loadIndex,
}) {
  final merge = _PatternMerge(layersById, loadIndex);
  return [
    for (final id in layersById.keys.toList()..sort(compareCodePoints))
      merge.of(id, const []),
  ];
}

final class _PatternMerge {
  new(this._layersById, this._loadIndex);

  final Map<String, List<WrittenPatternLayer>> _layersById;
  final LoadIndex _loadIndex;
  final _merged = <String, FeaturePattern>{};

  /// The reference list each merged pattern's layers wrote, null when none
  /// did, so a plain list over an unwritten one stays legal as for doc types.
  final _written = <String, List<ReferenceEntry>?>{};

  /// The merged pattern [id]; [path] holds the ids being merged above it.
  FeaturePattern of(String id, List<String> path) {
    final done = _merged[id];
    if (done != null) return done;
    final layers = _layersById[id]!;
    _checkDefining(layers.first.layer);
    final base = _baseOf(id, path);
    var items = base?.items ?? const <ChecklistItem>[];
    var reference = base == null ? null : _written[base.id];
    for (final (:layer, pack: _) in layers) {
      items = _applyItems(items, layer);
      reference = mergeList<ReferenceEntry>(
        reference,
        layer.reference,
        file: layer.file,
        key: 'reference',
        nameOf: (entry) => entry.title,
        notFound: FaultCode.referenceTitleNotFound,
      );
    }
    _written[id] = reference;
    return _merged[id] = FeaturePattern(
      id: id,
      pack: layers.map((l) => l.pack).nonNulls.firstOrNull,
      extendsId: _extendsWriter(id)?.extendsId,
      description: layers
          .map((l) => l.layer.description)
          .nonNulls
          .last
          .trimRight(),
      items: List.unmodifiable(items),
      reference: List.unmodifiable(reference ?? const <ReferenceEntry>[]),
    );
  }

  void _checkDefining(FeaturePatternLayer defining) {
    if (defining.description == null) {
      throw _missing(defining, 'description');
    }
    if (defining.items.isEmpty) throw _missing(defining, 'items');
  }

  TemplateFault _missing(FeaturePatternLayer defining, String key) =>
      TemplateFault(
        FaultCode.missingKey,
        'the key $key is required in the layer that defines the pattern',
        file: defining.file,
        key: key,
      );

  /// The merged `extends` target of [id], or null when it extends none.
  FeaturePattern? _baseOf(String id, List<String> path) {
    final writer = _extendsWriter(id);
    final target = writer?.extendsId;
    if (writer == null || target == null) return null;
    final walked = [...path, id];
    if (walked.contains(target)) {
      _throwCycle(walked.sublist(walked.indexOf(target)));
    }
    if (!_layersById.containsKey(target)) {
      throw TemplateFault(
        FaultCode.extendsTargetUnknown,
        'the key extends names no loaded feature pattern: $target',
        file: writer.file,
        key: 'extends',
      );
    }
    return of(target, walked);
  }

  /// The topmost layer of [id] that writes `extends`.
  FeaturePatternLayer? _extendsWriter(String id) => _layersById[id]!
      .map((l) => l.layer)
      .where((l) => l.extendsId != null)
      .lastOrNull;

  /// Throws `extends_cycle` for [cycle], naming files as the doc-type fault
  /// does: `file` the later-loaded layer file, `relatedFiles` the rest.
  Never _throwCycle(List<String> cycle) {
    final (:file, :related) = rankFaultFiles([
      for (final id in cycle) _extendsWriter(id)!.file,
    ], _loadIndex);
    final walkedPath = [...cycle, cycle.first].join(', ');
    throw TemplateFault(
      FaultCode.extendsCycle,
      'extends chain returns to its start: $walkedPath',
      file: file,
      relatedFiles: related,
    );
  }

  List<ChecklistItem> _applyItems(
    List<ChecklistItem> base,
    FeaturePatternLayer layer,
  ) {
    final items = [...base];
    for (final entry in layer.items) {
      final index = items.indexWhere((i) => i.id == entry.id);
      final text = entry.text;
      if (index == -1) {
        if (entry.disabled || text == null) {
          throw TemplateFault(
            FaultCode.overrideIdNotFound,
            'no item "${entry.id}" in the merged feature pattern to disable',
            file: layer.file,
            key: 'items',
          );
        }
        items.add((id: entry.id, text: text, origin: layer.id));
      } else if (entry.disabled) {
        items.removeAt(index);
      } else if (text != null && text != items[index].text) {
        items[index] = (id: entry.id, text: text, origin: layer.id);
      }
    }
    return items;
  }
}
