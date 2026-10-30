import 'package:specstone_core/src/consistency_check/fingerprint.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/journeys/journey_steps.dart';
import 'package:specstone_core/src/journeys/step_scenarios.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:yaml/yaml.dart';

const _confirmedKey = 'confirmed';

/// Returns [lfText] with a first `confirmed` entry for each resolving step.
///
/// An entry reads `<story identity>#S<N> <fingerprint>`, the fingerprint of
/// the scenario block the step names now, so `check` finds it clean once the
/// Owner approves. A step naming a missing story or scenario gets none, and
/// neither does a step whose link the `confirmed` list already names, however
/// that entry reads. Two steps naming one scenario share one entry. A
/// `confirmed` list the doc holds keeps its entries as written and gains the
/// new ones at its end; an absent one lands at its field slot. A `confirmed`
/// value that is not a block list is left as written.
///
/// Returns [lfText] unchanged unless [docType] is the `journey` doc type.
String withFirstConfirmations(
  String lfText,
  MergedDocType docType,
  DocIndex index,
) {
  if (docType.id != journeyTypeId) return lfText;
  final doc = Doc.parse(lfText);
  final held = _confirmedBlock(doc);
  if (held != null && !_isBlockList(held)) return lfText;
  final named = {for (final label in _heldLabels(held)) label};
  final added = <String>[];
  for (final step in stepsOfDoc(doc, docType).steps) {
    final target = step.target;
    if (target == null || named.contains(target.label)) continue;
    final block = scenarioBlockOf(index, target);
    if (block == null) continue;
    named.add(target.label);
    added.add('  - ${target.label} ${fingerprintOf(block)}\n');
  }
  if (added.isEmpty) return lfText;
  return withKeyBlock(
    lfText,
    _confirmedKey,
    '${held?.text ?? '$_confirmedKey:\n'}${added.join()}',
    fieldOrder: [for (final field in docType.fields) field.id],
  );
}

KeyBlock? _confirmedBlock(Doc doc) =>
    doc.frontmatter?.where((b) => b.name == _confirmedKey).firstOrNull;

// An empty value or a `- ` list takes more lines; a flow list or a scalar does
// not.
bool _isBlockList(KeyBlock block) {
  final value = block.valueText;
  return value.isEmpty || value.startsWith('-');
}

// The link label each held entry starts with.
Iterable<String> _heldLabels(KeyBlock? block) sync* {
  if (block == null) return;
  final value = loadYaml(block.valueText);
  if (value is! YamlList) return;
  for (final item in value) {
    if (item is String) yield item.split(' ').first;
  }
}
