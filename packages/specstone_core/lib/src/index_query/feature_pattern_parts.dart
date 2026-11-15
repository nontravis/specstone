import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/feature_pattern.dart';

const _patternsField = 'patterns';

/// One feature pattern a design bundle prints right after its `lister`, the
/// doc that names it, with the `items` that part prints.
typedef FeaturePatternPart = ({
  IndexedDoc lister,
  FeaturePattern pattern,
  List<ChecklistItem> items,
});

/// Returns the feature pattern parts of [bundle], in print order.
///
/// Empty outside design. A part follows each doc of [printOrder] that the
/// bundle marks as a lister, whose doc type carries the `patterns` field, one
/// per merged feature pattern its `patterns:` names, each pattern once per
/// bundle. A part drops each item an earlier part printed with the same
/// `id`, `text`, and `origin`. A value that is no string or names no merged
/// pattern is skipped.
List<FeaturePatternPart> featurePatternParts(
  DocIndex index,
  Bundle bundle,
  List<IndexedDoc> printOrder,
) {
  if (bundle.mode != BundleMode.design) return const [];
  final seenPatterns = <String>{};
  final seenItems = <ChecklistItem>{};
  final parts = <FeaturePatternPart>[];
  for (final lister in printOrder) {
    if (!bundle.patternListerPaths.contains(lister.docPath) ||
        !_carriesPatterns(index, lister)) {
      continue;
    }
    for (final id in _patternIdsOf(lister)) {
      final pattern = index.set.featurePattern(id);
      if (pattern == null || !seenPatterns.add(id)) continue;
      final items = [
        for (final item in pattern.items)
          if (!seenItems.contains(item)) item,
      ];
      seenItems.addAll(pattern.items);
      parts.add((lister: lister, pattern: pattern, items: items));
    }
  }
  return parts;
}

/// Returns [part] as its text block: the naming line
/// `==> <id> (feature pattern) · <name> <==`, then its body.
String featurePatternBlock(FeaturePatternPart part) =>
    '==> ${featurePatternListName(part.pattern.id)} · ${part.lister.name} <==\n'
    '${part.pattern.renderBody(part.items).trimRight()}';

/// Returns the list name of the part for pattern [id]: the id, then
/// ` (feature pattern)`.
String featurePatternListName(String id) => '$id (feature pattern)';

/// Returns the typed address `<doc type>:<name>` of [lister], the doc that
/// lists a feature pattern part.
String featurePatternDocAddress(IndexedDoc lister) =>
    '${lister.docTypeId}:${lister.name}';

/// Returns [part] as its `--json` entry.
Map<String, Object> featurePatternJson(FeaturePatternPart part) => {
  'id': part.pattern.id,
  'doc': featurePatternDocAddress(part.lister),
  'description': part.pattern.description,
  'items': [
    for (final item in part.items) {'id': item.id, 'text': item.text},
  ],
  'reference': [for (final entry in part.pattern.reference) entry.toJson()],
};

bool _carriesPatterns(DocIndex index, IndexedDoc doc) =>
    index.typeOf(doc)?.fields.any((field) => field.id == _patternsField) ??
    false;

/// Returns the strings of [doc]'s `patterns:` value; no other value counts.
List<String> _patternIdsOf(IndexedDoc doc) =>
    switch (doc.frontmatter[_patternsField]) {
      final String id => [id],
      final List<Object?> values => [
        for (final value in values)
          if (value is String) value,
      ],
      _ => const [],
    };
