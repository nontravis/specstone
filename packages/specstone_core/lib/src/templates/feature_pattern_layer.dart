import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/layer.dart';
import 'package:specstone_core/src/templates/models/checklist_item_entry.dart';
import 'package:specstone_core/src/templates/models/reference_entry.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/yaml_reader.dart';
import 'package:yaml/yaml.dart';

const _topKeys = {'id', 'description', 'items', 'extends', 'reference'};
const _itemKeys = {'id', 'text', 'disabled'};

final _patternFileName = RegExp(r'^patterns/[a-z][a-z0-9_]*\.yaml$');

/// Whether [layerRelativePath] is a feature pattern file: `patterns/<slug>.yaml`.
bool isFeaturePatternFileName(String layerRelativePath) =>
    _patternFileName.hasMatch(layerRelativePath);

/// One layer of one feature pattern, as its file writes it.
final class FeaturePatternLayer {
  new _({
    required this.id,
    required this.file,
    required this.kind,
    required this.description,
    required this.extendsId,
    required this.items,
    required this.reference,
  });

  /// Parses one feature pattern file; [patternId] is the file name without
  /// `.yaml`.
  ///
  /// [files] answers whether the layer holds a file, for `reference` checks.
  /// `description` and `items` are not required here: only the defining layer
  /// needs them, and only the merge knows which layer defines the pattern.
  /// Throws a [TemplateFault] for any format fault.
  static FeaturePatternLayer parse(
    String yaml, {
    required String file,
    required String patternId,
    required LayerKind kind,
    required LayerFiles files,
  }) {
    final map = readYamlMap(yaml, file: file);
    checkKeys(map, _topKeys, file: file, format: 'feature-pattern');
    final id = requireValue<String>(map, 'id', file: file);
    if (!isDocTypeIdShaped(id)) {
      throw TemplateFault(
        FaultCode.unknownValue,
        'the key id must be a slug: [a-z][a-z0-9_]*',
        file: file,
        key: 'id',
      );
    }
    if (id != patternId) {
      throw TemplateFault(
        FaultCode.featurePatternIdMismatch,
        'the key id must equal the file name without .yaml',
        file: file,
        key: 'id',
      );
    }
    return FeaturePatternLayer._(
      id: id,
      file: file,
      kind: kind,
      description: optionalValue<String>(map, 'description', file: file),
      extendsId: optionalValue<String>(map, 'extends', file: file),
      items: _parseItems(map, file: file),
      reference: parseReferenceList(
        map,
        file: file,
        kind: kind,
        files: files,
        templateFolder: 'patterns',
      ),
    );
  }

  /// The feature pattern id, equal to the file name without `.yaml`.
  final String id;

  /// The file this layer was parsed from, with `/` separators.
  final String file;

  /// The layer this file sits in.
  final LayerKind kind;

  /// The description, when this layer writes it.
  final String? description;

  /// The feature pattern this one builds on, when written.
  final String? extendsId;

  /// The checklist items this layer writes, in file order.
  final List<ChecklistItemEntry> items;

  /// The reference list this layer writes, when written.
  final ListWrite<ReferenceEntry>? reference;
}

List<ChecklistItemEntry> _parseItems(YamlMap map, {required String file}) {
  final list = optionalValue<YamlList>(map, 'items', file: file);
  if (list == null) return const [];
  final seen = <String>{};
  return [
    for (var i = 0; i < list.length; i++)
      _parseItem(list[i], i, seen: seen, file: file),
  ];
}

ChecklistItemEntry _parseItem(
  Object? entry,
  int index, {
  required Set<String> seen,
  required String file,
}) {
  final keyPath = 'items[$index]';
  if (entry is! YamlMap) {
    throw TemplateFault(
      FaultCode.unknownValue,
      'the entry must be a mapping',
      file: file,
      key: keyPath,
    );
  }
  final prefix = '$keyPath.';
  checkKeys(
    entry,
    _itemKeys,
    file: file,
    format: 'feature-pattern',
    prefix: prefix,
  );
  final id = requireValue<String>(entry, 'id', file: file, prefix: prefix);
  if (!isDocTypeIdShaped(id)) {
    throw TemplateFault(
      FaultCode.unknownValue,
      'the key id must be a slug: [a-z][a-z0-9_]*',
      file: file,
      key: '${prefix}id',
    );
  }
  if (!seen.add(id)) {
    throw TemplateFault(
      FaultCode.checklistItemDuplicate,
      'the file holds the item id $id more than once',
      file: file,
      key: 'items',
    );
  }
  final text = optionalValue<String>(entry, 'text', file: file, prefix: prefix);
  final disabled =
      optionalValue<bool>(entry, 'disabled', file: file, prefix: prefix) ??
      false;
  if (text == null && !disabled) {
    throw TemplateFault(
      FaultCode.missingKey,
      'the item needs text, or disabled: true',
      file: file,
      key: '${prefix}text',
    );
  }
  return ChecklistItemEntry(id: id, text: text, disabled: disabled);
}
