import 'package:specstone_core/src/consistency_check/fingerprint.dart';
import 'package:specstone_core/src/doc_model/confirmed_list.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/journeys/journey_steps.dart';
import 'package:specstone_core/src/journeys/step_scenarios.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

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
  final list = readConfirmedList(doc);
  if (list == null) return lfText;
  final named = {...list.labels};
  final added = <String>[];
  for (final step in stepsOfDoc(doc, docType).steps) {
    final target = step.target;
    if (target == null || named.contains(target.label)) continue;
    final block = scenarioBlockOf(index, target);
    if (block == null) continue;
    named.add(target.label);
    added.add('${target.label} ${fingerprintOf(block)}');
  }
  if (added.isEmpty) return lfText;
  return withConfirmedEntries(
    lfText,
    list,
    added,
    fieldOrder: [for (final field in docType.fields) field.id],
  );
}
