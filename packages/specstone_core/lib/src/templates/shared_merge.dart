import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/layer_source.dart';
import 'package:specstone_core/src/templates/pack_chain.dart';
import 'package:specstone_core/src/templates/shared_entry.dart';
import 'package:specstone_core/src/templates/template_fault.dart';

const _linesKey = 'shared_lines';
const _fieldsKey = 'shared_fields';
const _forDocTypesKey = 'for_doc_types';

/// A shared guide line after every layer merged, as a guide prints it.
final class MergedSharedLine {
  const new({
    required this.id,
    required this.text,
    this.forDocTypes,
    required this.printRank,
  });

  /// The id the layers matched the line by.
  final String id;

  /// The one line of guide text.
  final String text;

  /// The doc type ids the line names; null reaches every doc type of the
  /// merged set.
  final List<String>? forDocTypes;

  /// The place of the line among the lines, set by its first defining layer.
  final int printRank;
}

/// A shared field after every layer merged.
final class MergedSharedField {
  const new({
    required this.entry,
    required this.forDocTypes,
    required this.declaringPack,
    required this.order,
  });

  /// The field with each property its layers wrote, never disabled.
  final FieldEntry entry;

  /// The doc type ids the field names.
  final List<String> forDocTypes;

  /// The pack whose layer first defined the field.
  final String declaringPack;

  /// The place of the field among the fields, set by its first defining layer.
  final int order;

  /// The id the layers matched the field by.
  String get id => entry.id;
}

/// The shared lines and fields of one resolve, disabled entries absent, in
/// print order.
final class SharedSet {
  const new({
    required this.lines,
    required this.fields,
    this.disabledLineIds = const {},
  });

  /// No shared entries.
  static const SharedSet empty = SharedSet(lines: [], fields: []);

  /// The merged lines.
  final List<MergedSharedLine> lines;

  /// The ids of lines a layer declared and a later layer disabled.
  final Set<String> disabledLineIds;

  /// The merged fields.
  final List<MergedSharedField> fields;

  /// Returns the lines that name [docTypeId] or name no doc type.
  List<MergedSharedLine> linesNaming(String docTypeId) => [
    for (final line in lines)
      if (line.forDocTypes?.contains(docTypeId) ?? true) line,
  ];

  /// Returns the fields that name [docTypeId].
  List<MergedSharedField> fieldsNaming(String docTypeId) => [
    for (final field in fields)
      if (field.forDocTypes.contains(docTypeId)) field,
  ];
}

/// Merges the shared entries of [ordered] and [projectLines] by `id`.
///
/// [ordered] holds the packs in layer order, [projectLines] the `shared.yaml`
/// lines on top. [docTypeIdsByPack] holds the doc type ids each pack defines,
/// keyed by pack name, and [mergedDocTypeIds] every doc type of the merged
/// set.
///
/// Throws `unknown_value` for a pack entry naming a doc type outside its pack
/// chain, a `shared.yaml` line naming a doc type outside [mergedDocTypeIds],
/// and an id two packs declare with neither extending the other;
/// `override_id_not_found` for an entry that can neither change nor add; and
/// `missing_key` for a new shared field with no `for_doc_types`.
SharedSet mergeSharedEntries({
  required List<LoadedPack> ordered,
  required List<SharedLine> projectLines,
  required Map<String, Set<String>> docTypeIdsByPack,
  required Set<String> mergedDocTypeIds,
}) {
  final extendsOf = extendsMapOf(ordered);
  for (final pack in ordered) {
    _checkPackReach(pack, ordered, docTypeIdsByPack, extendsOf);
  }
  _checkProjectReach(projectLines, mergedDocTypeIds);
  _checkNewFieldReach(ordered);
  final merge = _SharedMerge(extendsOf);
  ordered.forEach(merge.addPack);
  merge.addProjectLines(projectLines);
  return merge.build();
}

/// Throws `missing_key` for the first complete new shared field, one no lower
/// pack holds, that writes no `for_doc_types`.
///
/// Runs before the merge pass, so it precedes any merge fault. A field a
/// lower layer disabled counts as new when a later layer adds it again.
void _checkNewFieldReach(List<LoadedPack> ordered) {
  final held = <String>{};
  for (final pack in ordered) {
    for (final field in pack.manifest.shared.fields) {
      final entry = field.entry;
      if (entry.disabled) {
        held.remove(entry.id);
      } else if (!held.contains(entry.id) && entry.type != null) {
        if (field.forDocTypes == null) throw _missingFieldReach(field);
        held.add(entry.id);
      }
    }
  }
}

TemplateFault _missingFieldReach(SharedField field) => TemplateFault(
  FaultCode.missingKey,
  'a new shared field requires $_forDocTypesKey',
  file: field.file,
  key: '$_fieldsKey[${field.index}].$_forDocTypesKey',
);

List<String>? _frozen(List<String>? list) =>
    list == null ? null : List.unmodifiable(list);

/// Throws `unknown_value` for the first `for_doc_types` id of [pack]'s shared
/// entries outside the doc types of [pack] and the packs it reaches.
void _checkPackReach(
  LoadedPack pack,
  List<LoadedPack> ordered,
  Map<String, Set<String>> docTypeIdsByPack,
  Map<String, String?> extendsOf,
) {
  final chain = <String>{
    ...?docTypeIdsByPack[pack.manifest.name],
    for (final other in ordered)
      if (reaches(pack, other, extendsOf: extendsOf))
        ...?docTypeIdsByPack[other.manifest.name],
  };
  final shared = pack.manifest.shared;
  for (final (i, line) in shared.lines.indexed) {
    _requireKnown(
      line.forDocTypes,
      chain,
      file: line.file,
      key: '$_linesKey[$i].$_forDocTypesKey',
      scope: 'the pack chain',
    );
  }
  for (final (i, field) in shared.fields.indexed) {
    _requireKnown(
      field.forDocTypes,
      chain,
      file: field.file,
      key: '$_fieldsKey[$i].$_forDocTypesKey',
      scope: 'the pack chain',
    );
  }
}

/// Throws `unknown_value` for the first `shared.yaml` line naming a doc type
/// outside [mergedDocTypeIds].
void _checkProjectReach(
  List<SharedLine> projectLines,
  Set<String> mergedDocTypeIds,
) {
  for (final line in projectLines) {
    _requireKnown(
      line.forDocTypes,
      mergedDocTypeIds,
      file: line.file,
      key: '$_linesKey[${line.index}].$_forDocTypesKey',
      scope: 'the merged set',
    );
  }
}

void _requireKnown(
  List<String>? named,
  Set<String> known, {
  required String file,
  required String key,
  required String scope,
}) {
  for (final id in named ?? const <String>[]) {
    if (known.contains(id)) continue;
    throw TemplateFault(
      FaultCode.unknownValue,
      'for_doc_types names no doc type of $scope: $id',
      file: file,
      key: key,
    );
  }
}

/// The pack and list position of one shared entry's declaration.
final class _Declarer {
  const new(this.pack, this.index);

  final LoadedPack pack;
  final int index;
}

/// The running merge of shared lines and fields, layer by layer.
///
/// The maps keep first-insertion order, so their values are in print order;
/// an entry a layer disables leaves its map, and one added again takes a new
/// place, as sections do.
final class _SharedMerge {
  new(this._extendsOf);

  final Map<String, String?> _extendsOf;
  final _lines = <String, MergedSharedLine>{};
  final _fields = <String, MergedSharedField>{};
  final _disabledLineIds = <String>{};
  final _disabledFieldIds = <String>{};
  final _lineDeclarers = <String, List<_Declarer>>{};
  final _fieldDeclarers = <String, List<_Declarer>>{};
  var _nextPlace = 0;

  /// Merges the lines, then the fields, of [pack]'s `pack.yaml`.
  void addPack(LoadedPack pack) {
    final shared = pack.manifest.shared;
    for (final line in shared.lines) {
      _claim(_lineDeclarers, pack, line.id, line.index, listKey: _linesKey);
      _mergeLine(line);
    }
    for (final field in shared.fields) {
      _claim(_fieldDeclarers, pack, field.id, field.index, listKey: _fieldsKey);
      _mergeField(field, pack.manifest.name);
    }
  }

  /// Merges the `shared.yaml` lines on top of every pack.
  void addProjectLines(List<SharedLine> lines) => lines.forEach(_mergeLine);

  /// Returns the merged entries.
  SharedSet build() => SharedSet(
    lines: List.unmodifiable(_lines.values),
    fields: List.unmodifiable(_fields.values),
    disabledLineIds: Set.unmodifiable(_disabledLineIds),
  );

  /// Records [pack] as a declarer of [id], or throws `unknown_value` when a
  /// prior declarer and [pack] reach neither way.
  ///
  /// The fault names the entry of the pack whose name sorts later.
  void _claim(
    Map<String, List<_Declarer>> declarers,
    LoadedPack pack,
    String id,
    int index, {
    required String listKey,
  }) {
    final current = _Declarer(pack, index);
    final prior = declarers.putIfAbsent(id, () => []);
    for (final other in prior) {
      final related =
          reaches(pack, other.pack, extendsOf: _extendsOf) ||
          reaches(other.pack, pack, extendsOf: _extendsOf);
      if (related) continue;
      final later =
          compareCodePoints(pack.manifest.name, other.pack.manifest.name) > 0
          ? current
          : other;
      throw TemplateFault(
        FaultCode.unknownValue,
        'shared entry $id is declared by two packs, neither extending the '
        'other',
        file: later.pack.manifest.file,
        key: '$listKey[${later.index}].id',
      );
    }
    prior.add(current);
  }

  void _mergeLine(SharedLine line) {
    final held = _lines[line.id];
    if (held != null) {
      if (line.disabled) {
        _lines.remove(line.id);
        _disabledLineIds.add(line.id);
        return;
      }
      _lines[line.id] = MergedSharedLine(
        id: held.id,
        text: line.text ?? held.text,
        forDocTypes: _frozen(line.forDocTypes) ?? held.forDocTypes,
        printRank: held.printRank,
      );
      return;
    }
    if (line.disabled && _disabledLineIds.contains(line.id)) return;
    final text = line.text;
    if (line.disabled || text == null) {
      throw _notFound(
        kind: 'line',
        id: line.id,
        file: line.file,
        key: '$_linesKey[${line.index}].id',
        disabled: line.disabled,
        missing: 'text',
      );
    }
    _disabledLineIds.remove(line.id);
    _lines[line.id] = MergedSharedLine(
      id: line.id,
      text: text,
      forDocTypes: _frozen(line.forDocTypes),
      printRank: _nextPlace++,
    );
  }

  void _mergeField(SharedField field, String packName) {
    final entry = field.entry;
    final held = _fields[entry.id];
    if (held != null) {
      if (entry.disabled) {
        _fields.remove(entry.id);
        _disabledFieldIds.add(entry.id);
        return;
      }
      _fields[entry.id] = MergedSharedField(
        entry: _overlay(held.entry, entry),
        forDocTypes: _frozen(field.forDocTypes) ?? held.forDocTypes,
        declaringPack: held.declaringPack,
        order: held.order,
      );
      return;
    }
    if (entry.disabled && _disabledFieldIds.contains(entry.id)) return;
    if (entry.disabled || entry.type == null) {
      throw _notFound(
        kind: 'field',
        id: entry.id,
        file: field.file,
        key: '$_fieldsKey[${field.index}].id',
        disabled: entry.disabled,
        missing: 'type',
      );
    }
    final reach = field.forDocTypes;
    if (reach == null) throw _missingFieldReach(field);
    _disabledFieldIds.remove(entry.id);
    _fields[entry.id] = MergedSharedField(
      entry: entry,
      forDocTypes: List.unmodifiable(reach),
      declaringPack: packName,
      order: _nextPlace++,
    );
  }

  /// Returns [lower] with each property [upper] writes replacing the same one.
  FieldEntry _overlay(FieldEntry lower, FieldEntry upper) => FieldEntry(
    id: lower.id,
    type: upper.type ?? lower.type,
    list: upper.list ?? lower.list,
    required: upper.required ?? lower.required,
    enumValues: upper.enumValues ?? lower.enumValues,
    docTypes: upper.docTypes ?? lower.docTypes,
    pointer: upper.pointer ?? lower.pointer,
    root: upper.root ?? lower.root,
    description: upper.description ?? lower.description,
    lint: upper.lint == null
        ? lower.lint
        : (lower.lint?.mergedWith(upper.lint!) ?? upper.lint),
    disabled: false,
  );

  /// The fault for an entry that has nothing to disable, or lacks the
  /// [missing] key that would add it.
  TemplateFault _notFound({
    required String kind,
    required String id,
    required String file,
    required String key,
    required bool disabled,
    required String missing,
  }) => TemplateFault(
    FaultCode.overrideIdNotFound,
    disabled
        ? 'no shared $kind "$id" in the merged set to disable'
        : 'no shared $kind "$id" in the merged set and no $missing to add it',
    file: file,
    key: key,
  );
}
