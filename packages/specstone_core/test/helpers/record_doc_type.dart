import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// The `statuses` field that makes a doc type a record doc type.
const MergedField statusesField = MergedField(
  id: 'statuses',
  type: FieldType.recordStatus,
  list: true,
);

/// The Verification matrix section a record doc type may carry.
const MergedSection matrixSection = MergedSection(
  id: verificationMatrixKey,
  header: 'Verification matrix',
  isOutputRef: true,
);

/// A record doc type `implementation`, at the record path.
///
/// It holds the Verification matrix section only; pass [sections] to change
/// them, and [fields] and [isPerTarget] for a record that differs.
MergedDocType recordDocType({
  List<MergedSection> sections = const [matrixSection],
  List<MergedField> fields = const [statusesField],
  bool isPerTarget = false,
}) => MergedDocType(
  id: 'implementation',
  path: 'specs/f{nn}_{slug}/IMPLEMENTATION.md',
  isPerTarget: isPerTarget,
  fields: fields,
  sections: sections,
  lint: const MergedLint(),
  files: const [],
);
