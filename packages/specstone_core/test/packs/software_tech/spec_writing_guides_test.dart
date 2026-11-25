// Test names stay one literal so `specstone check` finds them by exact text.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';
import '../../helpers/shared_lines.dart';
import '../../helpers/software_tech.dart';

/// The four per-feature spec doc types the one-file line reaches.
const _perFeatureIds = {'api', 'architecture', 'integration', 'security'};

void main() {
  late MergedSet set;
  setUpAll(() async {
    set = await resolveSoftwareTech();
  });

  List<String> sharedIdsOf(String id) => [
    for (final line in prdCoreDocType(set, id).sharedLines) line.id,
  ];

  test('every spec doc type guide prints the shared no-status line', () {
    for (final id in softwareTechIds) {
      expect(sharedIdsOf(id), contains('no_status'), reason: id);
    }
  });

  test('every spec doc type guide prints the spec cite line right after the '
      'cite rule', () {
    for (final id in softwareTechIds) {
      final ids = sharedIdsOf(id);
      expect(
        ids.indexOf('cite_spec_docs'),
        ids.indexOf('cite_by_link') + 1,
        reason: id,
      );
    }
  });

  test('project spec doc types print the every-feature and spec-folder lines, '
      'and the four per-feature types print the feature-folder line', () {
    for (final id in softwareTechIds) {
      final ids = sharedIdsOf(id);
      final isProject = projectSpecDocBases.containsKey(id);
      final isPerFeature = _perFeatureIds.contains(id);
      expect(ids.contains('project_rules_only'), isProject, reason: id);
      expect(ids.contains('one_file_per_spec_folder'), isProject, reason: id);
      expect(
        ids.contains('one_file_per_feature_folder'),
        isPerFeature,
        reason: id,
      );
    }
  });

  test('the four per-feature types print an Overrides line, and no project '
      'type does', () {
    for (final (id, line) in [
      ('api', 'overrides_line'),
      ('integration', 'overrides_line'),
      ('architecture', 'overrides_line_table'),
      ('security', 'overrides_line_table'),
    ]) {
      final ids = sharedIdsOf(id);
      expect(ids, contains(line), reason: id);
      expect(
        ids.where((i) => i.startsWith('overrides_line')),
        hasLength(1),
        reason: id,
      );
    }
    for (final id in projectSpecDocBases.keys) {
      expect(
        sharedIdsOf(id).where((i) => i.startsWith('overrides_line')),
        isEmpty,
        reason: id,
      );
    }
  });

  test('every spec doc type guide prints the readability lines after its '
      'description', () {
    for (final id in softwareTechIds) {
      final type = prdCoreDocType(set, id);
      expect(
        sharedIdsOf(id).take(4),
        everyTypeSharedLineIds.take(4),
        reason: id,
      );
      final guide = type.renderGuide();
      expect(
        guide.indexOf(type.sharedLines.first.text),
        greaterThan(guide.indexOf(type.description!.split('\n').last)),
        reason: id,
      );
    }
  });

  test('no description of a spec doc type holds a shared line', () {
    final texts = {
      for (final type in set.docTypes)
        for (final line in type.sharedLines) line.text,
    };
    for (final id in softwareTechIds) {
      final type = prdCoreDocType(set, id);
      for (final description in [
        type.description,
        for (final field in type.fields) field.description,
        for (final section in type.sections) section.description,
      ]) {
        for (final text in texts) {
          expect(description ?? '', isNot(contains(text)), reason: id);
        }
      }
    }
  });

  test('the fr guide with software-tech prints the two home lines and with prd-core alone prints neither', () async {
    const ids = ['wire_fact_home', 'mechanism_home'];
    final alone = prdCoreDocType(await resolvePrdCore(), 'fr');

    for (final id in ids) {
      expect(sharedIdsOf('fr'), contains(id));
      expect([for (final l in alone.sharedLines) l.id], isNot(contains(id)));
    }
  });
}
