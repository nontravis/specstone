import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// The `prd-core` shared line ids that reach every doc type, in print order.
const everyTypeSharedLineIds = <String>[
  'one_rule_per_item',
  'cite_at_item_end',
  'one_example',
  'condition_first',
  'cite_by_link',
];

/// The description of [type], its declared fields, and its sections.
List<String?> descriptionsOf(MergedDocType type) => [
  type.description,
  for (final field in type.fields)
    if (!field.isBuiltIn) field.description,
  for (final section in type.sections) section.description,
];
