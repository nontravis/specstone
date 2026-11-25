import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// The `prd-core` shared line ids that make up the readability bar, in print
/// order.
const readabilityBarSharedLineIds = <String>[
  'one_rule_per_item',
  'cite_at_item_end',
  'one_example',
  'condition_first',
];

/// The `prd-core` shared line ids that reach every doc type, in print order.
const everyTypeSharedLineIds = <String>[
  ...readabilityBarSharedLineIds,
  'cite_by_link',
];

/// The two sentence clauses every doc `Limits:` line ends with.
const builtInSentenceLimitClauses =
    '≤ 25 words per sentence (ko 17); '
    '≤ 100 characters per sentence in a no-space script '
    '(th 100, ja 60, zh 45).';

/// The three built-in clauses a doc `Limits:` line holds when its layers set
/// no limit.
const builtInLimitClauses =
    '≤ 600 characters per item; $builtInSentenceLimitClauses';

/// The description of [type], its declared fields, and its sections.
List<String?> descriptionsOf(MergedDocType type) => [
  type.description,
  for (final field in type.fields)
    if (!field.isBuiltIn) field.description,
  for (final section in type.sections) section.description,
];
