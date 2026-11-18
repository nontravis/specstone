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

  test('every spec doc type description says to never write status and where '
      'code existence lives', () {
    for (final id in softwareTechIds) {
      expect(
        descriptionOf(id),
        contains(
          'Never write `status:`; whether code exists in a target lives in '
          "that target's record, its `implementation` docs, only.",
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

  test('every spec doc type description says to cite another doc rule by a '
      'link and never restate it', () {
    for (final id in softwareTechIds) {
      expect(
        descriptionOf(id),
        contains(
          'Cite a rule another doc owns by a link to the item that holds it, '
          'never restate it.\n'
          'This includes a rule of a project spec doc or of an ancestor '
          "feature's spec doc.",
        ),
        reason: id,
      );
    }
  });

  test('the six per-feature types and topic ask for an Overrides line and its '
      'entry', () {
    for (final id in [
      'architecture',
      'domain',
      'api',
      'integration',
      'error',
      'auth',
      'topic',
    ]) {
      final description = descriptionOf(id);
      expect(description, contains('`Overrides:` line'), reason: id);
      expect(
        description,
        contains('record its `overrides` entry.'),
        reason: id,
      );
    }
  });

  test('every spec doc type description adds the four readability lines', () {
    for (final id in softwareTechIds) {
      expect(
        descriptionOf(id),
        contains(
          'Keep one rule in each item, and put several conditions in a nested '
          'list. A one-sentence paragraph with no ID moves its detail to the '
          'section of the same doc that owns it, never into a sub-list.\n'
          "Put a cite or an ownership note at the item's end.\n"
          'Give a non-obvious rule one example inside its item, as a `such '
          'as` clause or one "For example," sentence, within the sentence\'s '
          'cap.\n'
          'State the condition first, then the rule, one clause chain per '
          'sentence; split a sentence whose clauses nest.',
        ),
        reason: id,
      );
    }
  });
}
