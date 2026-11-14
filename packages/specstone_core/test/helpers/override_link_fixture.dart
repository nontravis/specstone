import 'package:specstone_core/src/consistency_check/finding.dart';

import 'check_fixture.dart';
import 'project_domain_fixture.dart';

const _overridesField =
    'fields:\n  - id: overrides\n    type: string\n    list: true\n';

/// The doc types that carry `overrides`, plus the project-wide domain type.
const overrideTemplates = <String, String>{
  '.specstone/templates/domain.yaml': _overridesField,
  '.specstone/templates/topic.yaml': _overridesField,
  ...projectDomainTemplate,
};

/// The DocPath of the project-wide domain doc.
const rootDomain = 'specs/DOMAIN.md';

/// The DocPath of the login feature's domain doc.
const loginDomain = 'specs/f01_login/DOMAIN.md';

/// The DocPath of the topic doc.
const rulesTopic = 'specs/topics/rules.md';

/// The rule the project-wide domain doc holds.
const rootRule = '- **INV-3** A cart expires after 7 days.';

/// The address of [rootRule].
const rootAddress = 'project_domain:project_domain#INV-3';

/// A line that overrides [rootRule] from a doc one folder below the root.
const overrideOfRoot =
    '- Overrides: [INV-3](../DOMAIN.md#invariants) — carts expire after '
    '7 days, because a cart holds stock';

/// The fingerprint of [rootRule] as it stands.
final String rootFingerprint = fingerprintFor(rootRule);

/// Returns a `domain` doc holding [items] and the `overrides` [entries].
String domainDoc(
  List<String> items, {
  List<String> entries = const [],
  bool draft = false,
}) =>
    '${_frontmatter(entries: entries, draft: draft)}'
    '# Domain\n\n## Invariants\n\n${items.join('\n')}\n';

/// Returns a `topic` doc holding [items] and the `overrides` [entries].
String topicDoc(
  List<String> items, {
  List<String> entries = const [],
  bool draft = false,
}) =>
    '${_frontmatter(entries: entries, draft: draft, covers: true)}'
    '# Rules\n\n## Rules\n\n${items.join('\n')}\n';

String _frontmatter({
  required List<String> entries,
  required bool draft,
  bool covers = false,
}) {
  final fields = [
    if (draft) 'draft: true',
    if (covers) 'covers:\n  - app/lib/',
    if (entries.isNotEmpty)
      'overrides:\n${[for (final entry in entries) '  - $entry'].join('\n')}',
  ];
  return fields.isEmpty ? '' : '---\n${fields.join('\n')}\n---\n\n';
}

/// Returns the project files that hold the project-wide domain doc.
///
/// [extra] adds or replaces files; docs stay as written, so the lines a test
/// names hold.
Map<String, String> overrideFiles({
  String root = rootRule,
  Map<String, String> extra = const {},
}) => {
  ...overrideTemplates,
  'docs/$rootDomain': domainDoc([root]),
  ...extra,
};

/// Returns the one-based file line of the first line of [text] holding
/// [needle].
int lineOf(String text, String needle) =>
    text.split('\n').indexWhere((line) => line.contains(needle)) + 1;

/// The kinds a link check reports, override lines included.
const Set<FindingKind> linkKinds = {
  FindingKind.suspect,
  FindingKind.unconfirmed,
  FindingKind.confirmedEntryMalformed,
  FindingKind.confirmedEntryStale,
  FindingKind.overrideLineMalformed,
  FindingKind.overrideNotInChain,
};
