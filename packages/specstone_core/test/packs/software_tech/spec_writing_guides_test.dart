// Test names stay one literal so `specstone check` finds them by exact text.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';
import '../../helpers/shared_lines.dart';
import '../../helpers/software_tech.dart';

/// The title word each per-feature spec doc type puts after the feature name.
const _featureTitles = <String, String>{
  'architecture': 'architecture',
  'api': 'API',
  'integration': 'integrations',
  'security': 'security',
  'implementation': 'implementation',
};

/// The four per-feature spec doc types the one-file line reaches.
const _perFeatureIds = {'api', 'architecture', 'integration', 'security'};

/// The item shape each spec doc type's description states.
const _itemShapes = <String, String>{
  'tech_stack': 'one Stack row per slot',
  'architecture': 'one Components row per component',
  'api': 'one `###` per operation',
  'integration': 'one `###` per system',
  'security': 'one Threats row per threat',
  'implementation': 'one entry per story and FR',
  'project_api': 'one bullet per convention',
  'project_architecture': 'one Components row per component',
  'project_security': 'one Threats row per threat',
};

const _eachRuleOneSentence = ', each rule one sentence';

/// The tail of the item-shape line of each doc type whose line says more than
/// the shape: each rule one sentence, or one `###` filled as a section gives.
const _itemShapeTails = <String, String>{
  'api': ', filled as Operations gives; state every other rule in one sentence',
  'integration':
      ', filled as Contract per system gives; state every other rule in one '
      'sentence',
  'implementation': _eachRuleOneSentence,
};

/// Each API style's block line in the operations description, with the
/// literals it holds.
const _styleBlocks = <(String, List<String>)>[
  (
    'REST',
    [
      '`<operationId>`',
      '**Call:** the method and path',
      '**Input:** a table of Name, In, Type, Required, Constraint',
      '**Output:** the status and a schema name or field table',
      '**Effect:** read-only, creates, updates, or deletes',
      '**Deprecated:** the date and the successor',
    ],
  ),
  (
    'JSON-RPC',
    [
      '`<method>`',
      '**Params:** by-name or by-position',
      'a table of Name, Type, Required, Constraint',
      '**Result:** a type, or none for a notification',
      '**Effect** and **Deprecated** as in REST',
    ],
  ),
  (
    'gRPC',
    [
      '`<Service>.<Rpc>`',
      '**Call:** the `rpc` line and its standard method, or custom',
      "**Input:** the request's fields",
      'a table of Name, Number, Type, Required, Constraint',
      '**Output:** the response or the resource',
    ],
  ),
  (
    'GraphQL',
    [
      '`Query.<field>`',
      '`Mutation.<field>`',
      '`Subscription.<field>`',
      '**Args:** a table of Name, Type, Default',
      '**Returns:** the type with its nullability',
      '**Deprecated** as in REST',
    ],
  ),
  (
    'Events',
    [
      '`<event type>`',
      '**Direction:** send or receive',
      '**Channel:** the address and its parameters',
      '**Message:** its name, its headers',
      'a payload table of Name, Type, Required',
      '**Reply:** a message and its channel, or none',
      '**Delivery:** at-least-once or at-most-once',
      'with a dedup key only when it departs from the project rule',
    ],
  ),
  (
    'CLI',
    [
      '`<command> <subcommand>`',
      '**Synopsis:** the call line',
      '**Options:** a table of Flag, Argument, Default, Effect',
      '**Operands / Stdin:** what each holds',
      '**Stdout:** the format, the `--json` shape included',
      '**Files written:** the paths, or none',
      '**Exit:** each status and its condition',
      '**Env:** the variables only this command reads',
    ],
  ),
  (
    'MCP tools',
    [
      '`<tool name>`',
      '**Input:** the `inputSchema` fields',
      'a table of Name, Type, Required, Constraint',
      '**Output:** the `outputSchema` fields or the content kind',
      '**Hints:** readOnly, destructive, idempotent, openWorld',
      '**Handle:** only for a stateful tool',
    ],
  ),
  (
    'Library',
    [
      '`<symbol>`',
      '**Signature:** the declaration',
      '**Params:** a table of Name, Type, and the meaning of null or a default',
      '**Returns:** the type and what it holds',
      '**Panics:** when it applies',
    ],
  ),
];

void main() {
  late MergedSet set;
  setUpAll(() async {
    set = await resolveSoftwareTech();
  });

  String descriptionOf(String id) => prdCoreDocType(set, id).description ?? '';

  String sectionText(String typeId, String sectionId) =>
      sectionOf(prdCoreDocType(set, typeId), sectionId).description ?? '';

  List<String> sharedIdsOf(String id) => [
    for (final line in prdCoreDocType(set, id).sharedLines) line.id,
  ];

  test('the five per-feature descriptions title the doc with the feature '
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

  test('tech stack and project descriptions carry their stated title '
      'forms', () {
    expect(descriptionOf('tech_stack'), isNot(contains('Title it')));
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
          "Never write `status:`; only a target's `implementation` record says "
          'if its code exists.',
        ),
        reason: id,
      );
    }
  });

  test('the integration description states when the doc is written', () {
    expect(
      descriptionOf('integration'),
      contains('Write this doc only when the feature calls an outside system.'),
    );
  });

  test('integration translation maps the outside model to the PRD glossary '
      'terms', () {
    expect(
      sectionText('integration', 'translation'),
      contains("where each outside model maps to the PRD glossary's terms"),
    );
  });

  test('descriptions hold the rules that have no section: no code sample, no '
      'stack trace, no secret', () {
    for (final id in ['architecture', 'project_architecture']) {
      expect(
        descriptionOf(id),
        contains(
          'Write no code samples or skill and agent steps; code holds the '
          'implementation.',
        ),
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
            'Write one rule per ID: $shape${_itemShapeTails[id] ?? ''}.',
          ),
          reason: id,
        );
      }
    },
  );

  test('the api and integration descriptions state one ### per operation or '
      'system, filled as its section gives', () {
    expect(
      descriptionOf('api'),
      contains(
        'Write one rule per ID: one `###` per operation, filled as Operations '
        'gives; state every other rule in one sentence.',
      ),
    );
    expect(
      descriptionOf('integration'),
      contains(
        'Write one rule per ID: one `###` per system, filled as Contract per '
        'system gives; state every other rule in one sentence.',
      ),
    );
  });

  test('the operations description holds one block line per API style, each '
      'with its heading and lines', () {
    final lines = sectionText('api', 'operations').split('\n');
    for (final (label, literals) in _styleBlocks) {
      final line = lines.singleWhere(
        (l) => l.startsWith('$label: '),
        orElse: () => '',
      );
      expect(line, isNotEmpty, reason: '$label has no line');
      for (final literal in literals) {
        expect(line, contains(literal), reason: label);
      }
    }
  });

  test('the operations description prints the Idempotent and Limits forms', () {
    expect(
      sectionText('api', 'operations'),
      allOf(contains('`**Idempotent:**`'), contains('`**Limits:**`')),
    );
  });

  test('the operations description points to the source of truth, keeps the '
      'common lines, and allows examples only without one', () {
    expect(
      sectionText('api', 'operations'),
      allOf(
        contains('With a source of truth, point to the operation in that file'),
        contains('the lines every operation takes and only what the file'),
        contains('each field with its type, required mark, and range'),
        contains('and optionally one request and one response example'),
        contains('`**Limits:**` only when the operation departs'),
        contains('departs from the default limits of the project API'),
      ),
    );
  });

  test('the errors and error_model descriptions hold their columns, group '
      'column, and stable codes', () {
    for (final text in [
      sectionText('api', 'errors'),
      sectionText('project_api', 'error_model'),
    ]) {
      expect(
        text,
        allOf(
          contains(
            'the columns Code, Status or exit, Condition, Client action, '
            'Retryable',
          ),
          contains('optional Group column'),
          contains('never reused'),
        ),
      );
    }
    expect(sectionText('api', 'errors'), contains('no check reads it'));
    expect(
      sectionText('project_api', 'error_model'),
      contains('no check reads it'),
    );
    expect(
      sectionText('api', 'errors'),
      allOf(
        contains("beyond the project's shared codes"),
        contains('the general condition that raises the code'),
        contains('list no raising site'),
        contains("Restate neither the project's error envelope nor its retry"),
      ),
    );
    expect(
      sectionText('project_api', 'error_model'),
      allOf(
        contains(
          'Write one item per surface, headed `### API-E<N> — <surface>`',
        ),
        contains('its retry rule by error class'),
        contains('Never retry a non-idempotent call'),
      ),
    );
  });

  test('project_api surfaces and conventions hold their columns and the '
      'default limits', () {
    expect(
      sectionText('project_api', 'surfaces'),
      contains('the columns Style, Entry point, Version scheme, Auth scheme'),
    );
    expect(
      sectionText('project_api', 'conventions'),
      contains('default rate limit and the default limits'),
    );
  });

  test('the api source of truth and compatibility lines follow their rows', () {
    expect(
      sectionText('api', 'source_of_truth'),
      allOf(
        contains('Write a table of Format, Path, Purpose'),
        contains('OpenAPI, OpenRPC, `.proto`, GraphQL SDL, or AsyncAPI file'),
        contains('absent for a CLI or a library without one'),
      ),
    );
    expect(
      sectionText('api', 'compatibility'),
      allOf(
        contains("only the feature's departures from the project's"),
        contains('deprecations with dates'),
        isNot(contains('Rollout')),
      ),
    );
    expect(
      sectionText('project_api', 'compatibility'),
      isNot(contains('Rollout')),
    );
  });

  test('integration events names the api events block for a project-set '
      'format', () {
    expect(
      sectionText('integration', 'events'),
      allOf(
        contains('only an event whose format an outside system sets'),
        contains(
          'one the project sets goes in `api` `operations` as an events block',
        ),
      ),
    );
  });

  test('the api and project_api descriptions ask for no stack trace or '
      'internals in an error body', () {
    for (final id in ['api', 'project_api']) {
      expect(
        descriptionOf(id),
        contains('Put no stack trace or internals in any error body.'),
        reason: id,
      );
    }
  });

  test('the api errors section prints the override form for a departure from '
      'an error model item', () {
    expect(
      prdCoreDocType(set, 'api').renderGuide(),
      contains('`Overrides: [API-E<N>](…) — <how it departs>`'),
    );
    expect(sectionText('api', 'errors'), contains('under this section'));
  });

  test('the architecture and tech stack descriptions say the record holds '
      'status and covers or code name the target own code', () {
    expect(
      descriptionOf('architecture'),
      contains(
        "The target's record holds each story's and FR's status and code "
        "paths, and each feature's `covers`.",
      ),
    );
    expect(
      descriptionOf('tech_stack'),
      contains(
        "The target's record holds each story's and FR's status and code "
        "paths, and each feature's `covers`; `code` names the target's own "
        'code only.',
      ),
    );
  });

  test('no description or shared line names a dropped doc type or section', () {
    const dropped = [
      'DOMAIN',
      'AUTH.md',
      'project_domain',
      'domain doc',
      '`topic`',
      'component_details',
      'Component details',
    ];
    for (final id in softwareTechIds) {
      final type = prdCoreDocType(set, id);
      final texts = [
        type.description,
        for (final field in type.fields) field.description,
        for (final section in type.sections) section.description,
        for (final line in type.sharedLines) line.text,
      ];
      for (final text in texts) {
        for (final word in dropped) {
          expect(text ?? '', isNot(contains(word)), reason: '$id: $word');
        }
      }
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
      expect(
        prdCoreDocType(set, id).renderGuide(),
        contains(
          'Link to the item of a rule another doc owns; never restate it.'
          '\nLink to the item of a project or ancestor-feature spec '
          "doc's rule; never restate it.",
        ),
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
    expect(
      prdCoreDocType(set, 'project_security').renderGuide(),
      allOf(
        contains(
          'Hold only rules every feature uses; write a rule two or more '
          'features share as a `project_architecture` concept naming them, '
          'and any other rule in a per-feature spec doc.',
        ),
        contains('Keep one file per doc type in each spec folder.'),
      ),
    );
    expect(
      prdCoreDocType(set, 'security').renderGuide(),
      contains('Keep one file per doc type per feature spec folder.'),
    );
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
    expect(
      prdCoreDocType(set, 'security').renderGuide(),
      contains(
        'or under its table for a table row, write '
        '`Overrides: [<ID>](<doc>#<section>) — <how it differs>, because '
        '<why>`, naming the row in the how-clause, and record its `overrides` '
        'entry.',
      ),
    );
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
    const lines = {
      'wire_fact_home':
          'A wire-contract fact lives in the `api` operation that traces the '
          'FR; the FR keeps its product words.',
      'mechanism_home':
          "A lock, retry, or parser mechanism lives in the feature's "
          '`architecture` doc, never in the FR.',
    };
    final withSoftwareTech = prdCoreDocType(set, 'fr');
    final alone = prdCoreDocType(await resolvePrdCore(), 'fr');

    for (final MapEntry(key: id, value: text) in lines.entries) {
      expect(sharedIdsOf('fr'), contains(id));
      expect(withSoftwareTech.renderGuide(), contains(text), reason: id);
      expect([for (final l in alone.sharedLines) l.id], isNot(contains(id)));
      expect(alone.renderGuide(), isNot(contains(text)), reason: id);
    }
  });
}
