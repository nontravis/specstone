import 'package:specstone_core/src/templates/models/checklist_item.dart';
import 'package:specstone_core/src/templates/models/reference_entry.dart';

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
}
