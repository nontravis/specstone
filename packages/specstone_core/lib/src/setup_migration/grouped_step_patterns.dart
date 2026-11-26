import 'package:specstone_core/src/setup_migration/models/pack_step.dart';
import 'package:specstone_core/src/templates/feature_group_paths.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/models/migration_step.dart';
import 'package:specstone_core/src/templates/template_fault.dart';

/// The doc types a run's steps read their group levels from.
///
/// A type of the merged set at the new pins reads from that set. A type it
/// lacks, such as one a `merge_doc` step folds, reads from its frozen copy
/// with the project layer `path:` over it, grouped as the merge at the
/// project's current pins groups it.
final class StepDocTypes {
  /// [layerPathOf] returns the project layer `path:` of a doc type id, or
  /// null when the project writes none.
  new(
    this._set, {
    required Map<String, MergedDocType> frozen,
    required String? Function(String id) layerPathOf,
  }) : _beforeRun = _groupedBeforeRun(_set, frozen, layerPathOf);

  final MergedSet _set;

  /// The frozen types [_set] lacks, as the project's current pins hold them.
  final Map<String, MergedDocType> _beforeRun;

  /// Returns the doc type of [id], or null when neither source holds it.
  MergedDocType? lookup(String id) => _set.lookup(id) ?? _beforeRun[id];
}

Map<String, MergedDocType> _groupedBeforeRun(
  MergedSet set,
  Map<String, MergedDocType> frozen,
  String? Function(String id) layerPathOf,
) {
  final absent = [
    for (final MapEntry(key: id, value: type) in frozen.entries)
      if (set.lookup(id) == null)
        switch (layerPathOf(id)) {
          final path? => type.copyWith(path: path),
          null => type,
        },
  ];
  if (absent.isEmpty) return const {};
  final absentIds = {for (final type in absent) type.id};
  return {
    for (final type in withGroupLevels([...set.docTypes, ...absent]))
      if (absentIds.contains(type.id)) type.id: type,
  };
}

/// Returns [pattern] with the group levels the template merge inserted into
/// the path of [type], so a step reads the paths its docs sit at.
///
/// A [type] that is null or holds no inserted group level leaves [pattern] as
/// written.
String groupedStepPattern(String pattern, MergedDocType? type) =>
    insertGroupLevels(pattern, type?.insertedGroupLevels ?? 0);

final _stepPlaceholder = RegExp(r'\{nn\}|\{slug\}');

int _placeholderCount(String pattern) =>
    _stepPlaceholder.allMatches(pattern).length;

/// Throws `unknown_value` at the first `move_file` of [steps] whose grouped
/// `from` and `to` hold different placeholder counts, since the move fills `to`
/// with the values `from` read.
void refuseUnequalStepPlaceholders(List<PackStep> steps, StepDocTypes types) {
  for (final PackStep(:step, :file, :entryIndex, :stepIndex) in steps) {
    if (step is! MoveFile) continue;
    final type = types.lookup(step.docType);
    final fromCount = _placeholderCount(groupedStepPattern(step.from, type));
    final toCount = _placeholderCount(groupedStepPattern(step.to, type));
    if (fromCount == toCount) continue;
    throw TemplateFault(
      FaultCode.unknownValue,
      'move_file of ${step.docType} holds $fromCount placeholders in from '
      "and $toCount in to once the feature path's group levels are read in",
      file: file,
      key: 'migrations[$entryIndex].steps[$stepIndex].move_file.to',
    );
  }
}
