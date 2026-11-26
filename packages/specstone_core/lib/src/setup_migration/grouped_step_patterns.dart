import 'package:specstone_core/src/setup_migration/models/pack_step.dart';
import 'package:specstone_core/src/templates/feature_group_paths.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/models/migration_step.dart';
import 'package:specstone_core/src/templates/template_fault.dart';

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
void refuseUnequalStepPlaceholders(List<PackStep> steps, MergedSet set) {
  for (final PackStep(:step, :file, :entryIndex, :stepIndex) in steps) {
    if (step is! MoveFile) continue;
    final type = set.lookup(step.docType);
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
