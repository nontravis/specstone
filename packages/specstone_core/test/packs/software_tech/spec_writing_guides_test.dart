import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';
import '../../helpers/software_tech.dart';

/// The title word each per-feature spec doc type puts after the feature name.
const _featureTitles = <String, String>{
  'architecture': 'architecture',
  'domain': 'domain',
  'api': 'API',
  'integration': 'integrations',
  'error': 'errors',
  'auth': 'auth',
  'implementation': 'implementation',
};

/// The item shape each spec doc type's description states.
const _itemShapes = <String, String>{
  'tech_stack': 'one Stack row per slot',
  'architecture': 'one Components row per component',
  'domain': 'one bullet per invariant',
  'api': 'one `###` per operation',
  'integration': 'one `###` per system',
  'error': 'one catalog row per code',
  'auth': 'one matrix row per resource and operation',
  'topic': 'one bullet per rule',
  'implementation': 'one entry per story and FR',
  'project_api': 'one bullet per convention',
  'project_architecture': 'one Components row per component',
  'project_domain': 'one bullet per invariant',
  'project_integration': 'one `###` per system',
  'project_error': 'one catalog row per code',
  'project_auth': 'one matrix row per resource and operation',
};

/// The doc types whose item-shape line still says each rule is one sentence.
const _sentenceRuleIds = {
  'api',
  'integration',
  'auth',
  'implementation',
  'project_integration',
  'project_auth',
};

void main() {
  late MergedSet set;
  setUpAll(() async {
    set = await resolveSoftwareTech();
  });

  String descriptionOf(String id) => prdCoreDocType(set, id).description ?? '';

  List<String> sharedIdsOf(String id) => [
    for (final line in prdCoreDocType(set, id).sharedLines) line.id,
  ];

  test('the seven per-feature descriptions title the doc with the feature '
      'name and no number', () {
    for (final MapEntry(key: id, value: word) in _featureTitles.entries) {
      expect(
        descriptionOf(id),
        contains(
          'Title it `# <Feature name> $word`, such as `# Rendering $word`, '
          'with no number.',
        ),
        reason: id,
      );
    }
  });

  test('topic, tech stack, and project descriptions carry their stated title '
      'forms', () {
    expect(
      descriptionOf('topic'),
      contains(
        'Title it `# <Topic name>`, such as `# Doc model`, with no number.',
      ),
    );
    expect(
      descriptionOf('tech_stack'),
      contains('Title it `# Tech stack`, with no number.'),
    );
    for (final id in projectSpecDocBases.keys) {
      final word = _featureTitles[projectSpecDocBases[id]]!;
      expect(
        descriptionOf(id),
        contains(
          'Title it `# <Project name> $word`, such as `# Specstone $word`, '
          'with no number.',
        ),
        reason: id,
      );
    }
  });

  test('every spec doc type guide prints the shared no-status line', () {
    for (final id in softwareTechIds) {
      final type = prdCoreDocType(set, id);
      expect(sharedIdsOf(id), contains('no_status'), reason: id);
      expect(
        type.renderGuide(),
        contains(
          "Never write `status:`; only a target's record, its `implementation` "
          'docs, says whether code exists in that target.',
        ),
        reason: id,
      );
    }
  });

  test('the integration and auth descriptions and their project twins state '
      'when the doc is written', () {
    for (final (id, sentence) in [
      (
        'integration',
        'Write this doc only when the feature calls an outside system.',
      ),
      ('auth', 'Write this doc only when the feature has access rules.'),
      (
        'project_integration',
        'Write this doc only when every feature follows one rule for outside '
            'calls.',
      ),
      (
        'project_auth',
        'Write this doc only when every feature follows one access rule.',
      ),
    ]) {
      expect(descriptionOf(id), contains(sentence), reason: id);
    }
  });

  test('descriptions hold the rules that have no section: no code sample, no '
      'stack trace, no secret', () {
    for (final id in ['architecture', 'project_architecture']) {
      expect(descriptionOf(id), contains('Write no code samples;'), reason: id);
    }
    for (final id in ['error', 'project_error']) {
      expect(
        descriptionOf(id),
        contains('Put no stack trace or internals in any error body.'),
        reason: id,
      );
    }
    expect(
      descriptionOf('tech_stack'),
      allOf(
        contains('Hold no secret in any row.'),
        contains(
          'Leave performance and scale to the project-wide and per-story '
          'non-functional requirements.',
        ),
      ),
    );
  });

  test(
    'each doc type description states its item shape as one rule per ID',
    () {
      for (final MapEntry(key: id, value: shape) in _itemShapes.entries) {
        expect(
          descriptionOf(id),
          contains(
            'Write one rule per ID: $shape'
            '${_sentenceRuleIds.contains(id) ? ', each rule one sentence' : ''}'
            '.',
          ),
          reason: id,
        );
      }
    },
  );

  test('the domain and architecture descriptions and their project twins say '
      'a DOMAIN cites its ARCHITECTURE by a section link', () {
    for (final id in ['domain', 'architecture']) {
      expect(
        descriptionOf(id),
        contains(
          'A DOMAIN cites its own ARCHITECTURE by a section link, such as '
          '`[architecture:rendering](ARCHITECTURE.md#components)`.',
        ),
        reason: id,
      );
    }
    for (final id in ['project_domain', 'project_architecture']) {
      expect(
        descriptionOf(id),
        contains(
          "The project's DOMAIN cites the project's ARCHITECTURE by a "
          'section link, such as `[architecture](ARCHITECTURE.md#components)`.',
        ),
        reason: id,
      );
    }
  });

  test('the architecture and tech stack descriptions say the record holds '
      'status and covers or code name the target own code', () {
    expect(
      descriptionOf('architecture'),
      contains(
        "The target's record holds each story's and FR's status and code "
        "paths; `covers` names the target's own code only.",
      ),
    );
    expect(
      descriptionOf('tech_stack'),
      contains(
        "The target's record holds each story's and FR's status and code "
        "paths; `code` names the target's own code only.",
      ),
    );
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
      expect(
        prdCoreDocType(set, id).renderGuide(),
        contains(
          'Cite a rule another doc owns by a link to its item, never restate '
          "it.\nCite a rule of a project spec doc or an ancestor feature's "
          'spec doc by a link to its item, never restate it.',
        ),
        reason: id,
      );
    }
  });

  test('project spec doc types print the every-feature and spec-folder lines, '
      'and the six per-feature types print the feature-folder line', () {
    for (final id in softwareTechIds) {
      final ids = sharedIdsOf(id);
      final isProject = projectSpecDocBases.containsKey(id);
      final isPerFeature = projectSpecDocBases.containsValue(id);
      expect(ids.contains('project_rules_only'), isProject, reason: id);
      expect(ids.contains('one_file_per_spec_folder'), isProject, reason: id);
      expect(
        ids.contains('one_file_per_feature_folder'),
        isPerFeature,
        reason: id,
      );
    }
    expect(
      prdCoreDocType(set, 'project_domain').renderGuide(),
      allOf(
        contains(
          'Hold only rules every feature uses; write any other rule in a '
          'per-feature spec doc, or in a `topic` when two or more features '
          'share it.',
        ),
        contains('Keep one file per spec folder.'),
      ),
    );
    expect(
      prdCoreDocType(set, 'domain').renderGuide(),
      contains('Keep one file per feature spec folder.'),
    );
  });

  test('the six per-feature types print an Overrides line, and topic keeps its '
      'own', () {
    for (final (id, line) in [
      ('api', 'overrides_line'),
      ('domain', 'overrides_line'),
      ('integration', 'overrides_line'),
      ('architecture', 'overrides_line_table'),
      ('auth', 'overrides_line_table'),
      ('error', 'overrides_line_table'),
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
    expect(
      prdCoreDocType(set, 'auth').renderGuide(),
      contains(
        'or right under its table when the item is a table row, write '
        '`Overrides: [<ID>](<doc>#<section>) — <how it differs>, because '
        '<why>`, its how-clause naming the row, and record its `overrides` '
        'entry.',
      ),
    );
    expect(sharedIdsOf('topic'), isNot(contains('overrides_line')));
    expect(
      descriptionOf('topic'),
      allOf(
        contains('write `Overrides: [<ID>]'),
        contains('record its `overrides` entry'),
      ),
    );
  });

  test('every spec doc type guide prints the readability lines after its '
      'description', () {
    for (final id in softwareTechIds) {
      final type = prdCoreDocType(set, id);
      expect(sharedIdsOf(id).take(4), [
        'one_rule_per_item',
        'cite_at_item_end',
        'one_example',
        'condition_first',
      ], reason: id);
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
}
