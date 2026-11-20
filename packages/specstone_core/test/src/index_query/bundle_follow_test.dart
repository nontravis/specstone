// The test titles and literals are plan values kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/bundle_follow.dart';
import 'package:specstone_core/src/index_query/cited_by.dart';
import 'package:specstone_core/src/index_query/code_bundle.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/models/cited_place.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';
import '../../helpers/record_fixture.dart' show recordsRootTemplates;
import '../../helpers/shipped_pins.dart';
import '../../helpers/temp_tree.dart';

const _story = 'docs/prds/features/f01_login/us01_email_login/USER_STORY.md';
const _fr =
    'docs/prds/features/f01_login/us01_email_login/fr01_validate_credentials.md';
const _specs = '../../../../specs';
const _resetStory = '../us02_reset_password/USER_STORY.md';

/// The docs the links of these tests cite, and a story with no link.
const _cited = <String, String>{
  _story:
      '# Agent signs in with email\n\n## Use Case\nSign in with an email.\n\n'
      '## Acceptance Criteria\n- Given a sign-in\n',
  'docs/prds/features/f01_login/us02_reset_password/USER_STORY.md':
      '---\nslug:\n  - reset\n---\n\n# Agent resets a password\n\n## Use Case\nReset it.\n\n'
      '## Acceptance Criteria\n- Given a reset\n',
  'docs/specs/f02_signup/DOMAIN.md':
      '# Sign-up domain\n\n## Entities\n- Account\n\n## Invariants\n'
      '- **INV-13** An account has one email.\n'
      '- **INV-14** An account locks after five failures, by [RULE-3](../topics/doc_model.md#rules).\n'
      '  - **Enforcer:** the lock service\n'
      '  - **Consistency:** strong\n'
      '- **INV-15** A locked account mails its owner.\n',
  'docs/specs/topics/doc_model.md':
      '# Doc model\n\n## Purpose\nModel the docs; see [ranges](ranges.md#purpose).\n\n'
      '## Rules\n### RULE-3 — One cite form\nA doc cites by a link.\n\n'
      '- Each link names its target.\n\n'
      '### RULE-4 — Item ranges\nTwo links joined by to.\n\n'
      '## Examples\n### A worked example\nOne link.\n\n### Another example\nTwo links.\n',
  'docs/specs/topics/ranges.md':
      '# Ranges\n\n## Purpose\nRead ranges; see [doc model](doc_model.md#purpose).\n\n'
      '## Rules\n- **RULE-1** One.\n- **RULE-2** Two.\n- **RULE-3** Three.\n'
      '- **RULE-4** Four.\n- **RULE-5** Five.\n',
  'docs/specs/topics/guide.md':
      '# Guide\n\n## Purpose\nSee [reset](../../prds/features/f01_login/us02_reset_password/USER_STORY.md#use-case), '
      '[reset criteria](../../prds/features/f01_login/us02_reset_password/USER_STORY.md#acceptance-criteria), '
      'and [reset](../../prds/features/f01_login/us02_reset_password/USER_STORY.md).\n',
};

const _project = 'docs/prds/PROJECT.md';
const _measurementFile = 'docs/measurements/fewer_resets/MEASUREMENT.md';
const _measurementDoc = 'measurements/fewer_resets/MEASUREMENT.md';
const _measurementFromProject = '../measurements/fewer_resets/MEASUREMENT.md';
const _measurementFromStory =
    '../../../../measurements/fewer_resets/MEASUREMENT.md';

/// A project doc whose Project name section holds [links].
String _projectLinking(String links) =>
    '---\nowner: Owner\n---\n\n# Project context\n\n## Project name\n'
    'Login demo; $links\n';

/// A measurement with a link in its Scope, one in its Method block, and a
/// Baseline section.
const _measurement =
    '# Fewer resets\n\n## Scope\n- Resets per week; see [ranges](../../specs/topics/ranges.md#purpose).\n\n'
    '## Method\n### Take a run\nCount them.\n\n'
    '## Baseline\n| Metric | Run | Value | Date | Source |\n|---|---|---|---|---|\n| resets | 1 | 4 | 2026-11-01 | log |\n\n'
    '## Results\nNewest first. Met: halved.\n\n| Date | Run | Met |\n|---|---|---|\n| 2026-11-14 | 2 | no |\n';

String _frWith(String statement) =>
    '---\nverify_method: test\n---\n\n# Validate credentials\n\n## Statement\n$statement\n';

/// Names the parts of [parts] that cite the measurement.
List<String> _measurementParts(List<AppendedPart> parts) => [
  for (final part in parts)
    if (part.doc.docPath == _measurementDoc) _id(part),
];

/// Names [part] by its DocPath, `#<section key>`, `###` anchor, item ID, and
/// summary mark.
String _id(AppendedPart part) =>
    '${part.doc.docPath}'
    '${part.sectionKey == null ? '' : '#${part.sectionKey}'}'
    '${part.heading == null ? '' : ' #${part.heading}'}'
    '${part.itemId == null ? '' : ' ${part.itemId}'}'
    '${part.summary ? ' summary' : ''}'
    '${part.nameOnly ? ' name' : ''}';

void main() {
  Future<DocIndex> indexFor(
    String statement, [
    Map<String, String> extra = const {},
  ]) => indexWith({..._cited, _fr: _frWith(statement), ...extra});

  Future<List<AppendedPart>> followed(
    String statement, {
    BundleMode mode = BundleMode.implement,
    bool noProject = false,
    Map<String, String> extra = const {},
  }) async {
    final index = await indexFor(statement, extra);
    return followLinks(
      index,
      pickBundle(
        index,
        'login/email_login/validate_credentials',
        mode,
        noProject: noProject,
      ),
    );
  }

  Future<List<AppendedPart>> followedFrom(
    String target,
    Map<String, String> extra, {
    BundleMode mode = BundleMode.implement,
  }) async {
    final index = await indexWith({
      ..._cited,
      _fr: _frWith('The system shall check the password.'),
      ...extra,
    });
    return followLinks(
      index,
      pickBundle(index, target, mode, noProject: false),
    );
  }

  const inv14 = '[INV-14]($_specs/f02_signup/DOMAIN.md#invariants)';

  test('an item a record cites by a link through the project root is appended', () async {
    final parts = await followedFrom('login/email_login/validate_credentials', {
      ...recordsRootTemplates,
      '.specstone/records/f01_login/IMPLEMENTATION.md':
          "---\nstatuses:\n  - 'email_login:planned'\n---\n\n# Login implementation\n\n"
          'Locks by [RULE-3](../../../docs/specs/topics/doc_model.md#rules).\n',
    });
    expect(parts.map(_id), contains('specs/topics/doc_model.md#rules RULE-3'));
  });
  test('one file a record and a doc both cite appends its path once', () async {
    final parts = await followedFrom('login/email_login/validate_credentials', {
      ...recordsRootTemplates,
      '.specstone/records/f01_login/IMPLEMENTATION.md':
          "---\nstatuses:\n  - 'email_login:planned'\n---\n\n# Login implementation\n\n"
          'Schema in [schema](../../../docs/specs/schema.dbml).\n',
      _fr: _frWith('See [schema]($_specs/schema.dbml).'),
    });
    expect(parts.map(_id), ['specs/schema.dbml']);
  });
  test('one file under the records root a record and a doc both cite appends its path once', () async {
    final parts = await followedFrom('login/email_login/validate_credentials', {
      ...recordsRootTemplates,
      '.specstone/records/f01_login/IMPLEMENTATION.md':
          "---\nstatuses:\n  - 'email_login:planned'\n---\n\n# Login implementation\n\n"
          'Flow in [diagram](diagram.png).\n',
      '.specstone/records/f01_login/diagram.png': 'png',
      _fr: _frWith(
        'See [diagram](../../../../../.specstone/records/f01_login/diagram.png).',
      ),
    });
    expect(parts.map(_id), ['../.specstone/records/f01_login/diagram.png']);
  });
  test('a bundle whose docs link nowhere outside appends nothing', () async {
    expect(await followed('The system shall check the password.'), isEmpty);
  });
  test(
    'an item link appends the item with its nested items and no other',
    () async {
      final parts = await followed('The system shall lock, by $inv14.');
      expect(parts.first.doc.docPath, 'specs/f02_signup/DOMAIN.md');
      expect(parts.first.sectionKey, 'invariants');
      expect(parts.first.itemId, 'INV-14');
      expect(parts.first.summary, isFalse);
      expect(
        parts.first.text,
        '- **INV-14** An account locks after five failures, by [RULE-3](../topics/doc_model.md#rules).\n'
        '  - **Enforcer:** the lock service\n'
        '  - **Consistency:** strong',
      );
      for (final part in parts) {
        expect(part.text, isNot(contains('INV-13')));
        expect(part.text, isNot(contains('INV-15')));
      }
    },
  );
  test("an appended invariant's topic-rule link appends nothing", () async {
    final parts = await followed('The system shall lock, by $inv14.');
    expect(parts.map(_id), ['specs/f02_signup/DOMAIN.md#invariants INV-14']);
  });
  test('a rule an appended part links is appended when a picked part links it too', () async {
    final parts = await followed(
      'The system shall lock, by $inv14, and by [RULE-3]($_specs/topics/doc_model.md#rules).',
    );
    expect(parts.map(_id), [
      'specs/f02_signup/DOMAIN.md#invariants INV-14',
      'specs/topics/doc_model.md#rules RULE-3',
    ]);
  });
  test("a picked part and an appended part that link one item append it once, and the appended part's other links stay unfollowed", () async {
    final parts = await followed(
      'See [hub]($_specs/topics/hub.md#purpose) and [RULE-2]($_specs/topics/ranges.md#rules).',
      extra: {
        'docs/specs/topics/hub.md': '# Hub\n\n## Purpose\nSee [RULE-2](ranges.md#rules) and [model](doc_model.md#purpose).\n',
      },
    );
    expect(parts.map(_id), [
      'specs/topics/hub.md#purpose',
      'specs/topics/ranges.md#rules RULE-2',
    ]);
  });
  test(
    'an item link to an ID-headed ### heading appends its whole block',
    () async {
      final parts = await followed(
        'See [RULE-3]($_specs/topics/doc_model.md#rules).',
      );
      expect(parts.map(_id), ['specs/topics/doc_model.md#rules RULE-3']);
      expect(
        parts.single.text,
        '### RULE-3 — One cite form\nA doc cites by a link.\n\n- Each link names its target.',
      );
    },
  );
  test('a fragment that names a ### heading appends that block', () async {
    final parts = await followed(
      'See [the cite rule]($_specs/topics/doc_model.md#rule-3--one-cite-form) and '
      '[an example]($_specs/topics/doc_model.md#a-worked-example).',
    );
    expect(parts.map(_id), [
      'specs/topics/doc_model.md#rules RULE-3',
      'specs/topics/doc_model.md#examples #a-worked-example',
    ]);
    expect(parts.last.text, '### A worked example\nOne link.');
  });
  for (final mode in [BundleMode.implement, BundleMode.design]) {
    test(
      'an item range appends each item from the first to the last, each a part (${mode.wire})',
      () async {
        final parts = await followed(
          'See [RULE-2]($_specs/topics/ranges.md#rules) to [RULE-4]($_specs/topics/ranges.md#rules).',
          mode: mode,
        );
        expect(parts.map(_id), [
          'specs/topics/ranges.md#rules RULE-2',
          'specs/topics/ranges.md#rules RULE-3',
          'specs/topics/ranges.md#rules RULE-4',
        ]);
        expect(parts[1].text, '- **RULE-3** Three.');
      },
    );
  }
  test('a section link appends the section whole', () async {
    final parts = await followed(
      'See [signup architecture]($_specs/f02_signup/ARCHITECTURE.md#components).',
    );
    expect(parts.map(_id), ['specs/f02_signup/ARCHITECTURE.md#components']);
    expect(
      parts.single.text,
      '## Components\n| Component | Responsibility |\n|---|---|\n| Form | Takes the email |',
    );
  });
  test('a section link appends nothing when the section is N/A or still its template', () async {
    const pay = '../../f03_pay/FEATURE.md';
    final parts = await followed(
      'See [hypothesis]($pay#benefit-hypothesis), [measures]($pay#success-measures), '
      'and [problem]($pay#problem).',
      extra: {
        'docs/prds/features/f03_pay/FEATURE.md':
            '# Pay\n\n## Problem\nSlow pay.\n\n## Benefit hypothesis\n'
            'We believe <outcome> will be achieved if <persona> attains <benefit> with <feature>.\n\n'
            '## Success measures\nN/A — one local user\n',
      },
    );
    expect(parts.map(_id), ['prds/features/f03_pay/FEATURE.md#problem']);
  });
  test('a doc link with no fragment or an empty one appends the doc in summary, once', () async {
    final parts = await followed(
      'See [ranges]($_specs/topics/ranges.md) and [again]($_specs/topics/ranges.md#).',
    );
    expect(parts.map(_id), ['specs/topics/ranges.md summary']);
    expect(parts.single.text, '# Ranges');
  });
  test(
    'a link below the cut of a summary_rows section is not followed',
    () async {
      final parts = await followedFrom('project', {
        _project: _projectLinking(
          '[resets](../measurements/fewer_resets/MEASUREMENT.md)',
        ),
        _measurementFile:
            '# Fewer resets\n\n## Scope\n- Resets per week.\n\n## Results\n'
            'Newest first.\n\n| Date | Note |\n|---|---|\n'
            '| 2026-11-14 | [ranges](../../specs/topics/ranges.md#purpose) |\n'
            '| 2026-11-01 | [guide](../../specs/topics/guide.md#purpose) |\n',
      });
      expect(parts.map(_id), ['$_measurementDoc summary']);
    },
  );
  group('in a design bundle', () {
    const frName = 'login/email_login/validate_credentials';

    Future<List<AppendedPart>> followedWithLines(String statement) async {
      final index = await indexFor(statement);
      return followLinks(
        index,
        pickBundle(index, frName, BundleMode.design, noProject: false),
        citedBy: citedByIndex(index),
      );
    }

    test('a section part a link appends carries the line right after its header', () async {
      const line = 'See [the examples]($_specs/topics/doc_model.md#examples).';
      final part = (await followedWithLines(line)).single;

      expect(
        part.text,
        startsWith(
          '## Examples\n  · cited by $frName (fr) —: $line\n### A worked example',
        ),
      );
      expect(part.cited.map((c) => (c.kind, c.sectionKey)), [
        (CitedKind.section, 'examples'),
      ]);
    });

    test('an item part carries the lines of the cited items inside its lines, a nested one included, and the nested item has no part of its own', () async {
      const nest = '$_specs/topics/nest.md#rules';
      final index = await indexFor(
        'See [RULE-1]($nest), [RULE-2]($nest), and [RULE-3]($nest).',
        {
          'docs/specs/topics/nest.md':
              '# Nest\n\n## Rules\n'
              '- **RULE-1** Outer.\n'
              '  - **RULE-2** Inner.\n'
              '- **RULE-3** Third.\n',
        },
      );
      final parts = followLinks(
        index,
        pickBundle(index, frName, BundleMode.design, noProject: false),
        citedBy: citedByIndex(index),
      );

      expect(
        {
          for (final part in parts)
            part.itemId: [for (final c in part.cited) '${c.item}@${c.after}'],
        },
        {
          'RULE-1': ['RULE-2@5', 'RULE-1@5'],
          'RULE-3': ['RULE-3@6'],
        },
      );
    });

    test('a block part a link appends carries the line right after its heading', () async {
      const line =
          'See [a worked example]($_specs/topics/doc_model.md#a-worked-example).';
      final part = (await followedWithLines(line)).single;

      expect(
        part.text,
        '### A worked example\n  · cited by $frName (fr) —: $line\nOne link.',
      );
      expect(part.cited.map((c) => (c.kind, c.item)), [
        (CitedKind.item, 'a-worked-example'),
      ]);
    });
  });
  test('a section of a summary doc is appended unless the summary prints it', () async {
    final parts = await followed(
      'See [reset]($_resetStory#use-case) and [reset criteria]($_resetStory#acceptance-criteria).',
      mode: BundleMode.design,
    );
    expect(parts.map(_id), [
      'prds/features/f01_login/us02_reset_password/USER_STORY.md#acceptance_criteria',
    ]);
    expect(parts.single.text, '## Acceptance Criteria\n- Given a reset');
  });
  test('a summary section linked before its doc link prints in the later summary', () async {
    final parts = await followed(
      'See [reset use case]($_resetStory#use-case), then [reset]($_resetStory).',
    );

    expect(parts.map(_id), [
      'prds/features/f01_login/us02_reset_password/USER_STORY.md#use_case',
      'prds/features/f01_login/us02_reset_password/USER_STORY.md summary',
    ]);
    expect(parts.first.text, '## Use Case\nReset it.');
    expect(
      parts.last.text,
      '# Agent resets a password\n\n## Use Case\nReset it.',
    );
  });
  test(
    'a part printed whole or already appended is not appended again',
    () async {
      final parts = await followed(
        'See the [story](USER_STORY.md), $inv14, and $inv14 again.',
      );
      expect(parts.map(_id), ['specs/f02_signup/DOMAIN.md#invariants INV-14']);
    },
  );
  test('two parts that link to each other are each appended once', () async {
    final parts = await followed(
      'See [doc model]($_specs/topics/doc_model.md#purpose) and [ranges]($_specs/topics/ranges.md#purpose).',
    );
    expect(parts.map(_id), [
      'specs/topics/doc_model.md#purpose',
      'specs/topics/ranges.md#purpose',
    ]);
  });
  test('a section a picked link and an appended part both cite appends no part twice and none the summary prints', () async {
    final parts = await followed(
      'See [guide]($_specs/topics/guide.md#purpose), [reset]($_resetStory), [reset]($_resetStory#use-case), and [criteria]($_resetStory#acceptance-criteria).',
      mode: BundleMode.design,
    );
    expect(parts.map(_id), [
      'specs/topics/guide.md#purpose',
      'prds/features/f01_login/us02_reset_password/USER_STORY.md#acceptance_criteria',
    ]);
  });
  test('a link to a file that is no .md doc appends its path only, once, in source order; a missing file appends nothing', () async {
    final parts = await followed(
      'See [schema]($_specs/schema.dbml), [ranges]($_specs/topics/ranges.md), '
      '[schema again]($_specs/schema.dbml), and [gone]($_specs/gone.dbml).',
    );
    expect(parts.map(_id), [
      'specs/schema.dbml',
      'specs/topics/ranges.md summary',
    ]);
    expect(parts.first.pathOnly, isTrue);
    expect(parts.first.text, isEmpty);
  });
  test('links written <dest> or with spaces around the destination keep source order on their line', () async {
    final parts = await followed(
      'See [g](<$_specs/topics/guide.md>), [d]( $_specs/topics/doc_model.md ), '
      'then [r]($_specs/topics/ranges.md).',
    );
    expect(parts.map(_id).take(3), [
      'specs/topics/guide.md summary',
      'specs/topics/doc_model.md summary',
      'specs/topics/ranges.md summary',
    ]);
  });
  test(
    'a link to a file no doc type describes appends its path only, once',
    () async {
      final parts = await followed(
        'See [the old context](../../../d01_context.md) and '
        '[again](../../../d01_context.md#project-name).',
      );
      expect(parts.map(_id), ['prds/d01_context.md']);
      expect(parts.single.pathOnly, isTrue);
      expect(parts.single.text, isEmpty);
    },
  );
  test('--no-project follows no link into, or out of, a dropped doc', () async {
    const projectWithLink = {
      'docs/prds/PROJECT.md':
          '---\nowner: Owner\n---\n\n# Project context\n\n## Project name\n'
          'Login demo; see [ranges](../specs/topics/ranges.md).\n',
    };
    const statement = 'See [the project](../../../PROJECT.md#project-name).';
    expect((await followed(statement, extra: projectWithLink)).map(_id), [
      'specs/topics/ranges.md summary',
    ]);
    expect(
      await followed(statement, noProject: true, extra: projectWithLink),
      isEmpty,
    );
  });
  test(
    'a link to no doc, a missing anchor, or a missing item appends nothing',
    () async {
      expect(
        await followed(
          'See [gone](missing.md), [nope]($_specs/topics/ranges.md#nope), and '
          '[RULE-9]($_specs/topics/ranges.md#rules).',
        ),
        isEmpty,
      );
    },
  );
  test(
    'a link to an anchor that names no section or block appends nothing',
    () async {
      expect(
        await followed(
          'See [the ranges title]($_specs/topics/ranges.md#ranges).',
        ),
        isEmpty,
      );
    },
  );
  test('the links of one line append their parts in source order', () async {
    final parts = await followed(
      'See [examples]($_specs/topics/doc_model.md#examples), '
      '[RULE-2]($_specs/topics/ranges.md#rules), and [ranges]($_specs/topics/ranges.md#purpose).',
    );
    expect(parts.map(_id), [
      'specs/topics/doc_model.md#examples',
      'specs/topics/ranges.md#rules RULE-2',
      'specs/topics/ranges.md#purpose',
    ]);
  });
  test('--for query follows no link', () async {
    final index = await indexFor('The system shall lock, by $inv14.');
    expect(
      followLinks(
        index,
        pickBundle(
          index,
          'login/email_login/validate_credentials',
          BundleMode.query,
          noProject: false,
        ),
      ),
      isEmpty,
    );
  });
  test(
    'a part is cut from the stored text; the follow reads no file',
    () async {
      final project = await writeLoginProject(
        extra: {..._cited, _fr: _frWith('The system shall lock, by $inv14.')},
      );
      final session = openSession(project);
      addTearDown(session.close);
      final bundle = pickBundle(
        session.index,
        'login/email_login/validate_credentials',
        BundleMode.implement,
        noProject: false,
      );
      File('${project.path}/docs/specs/f02_signup/DOMAIN.md').deleteSync();
      File('${project.path}/docs/specs/topics/doc_model.md').deleteSync();
      expect(followLinks(session.index, bundle).map(_id), [
        'specs/f02_signup/DOMAIN.md#invariants INV-14',
      ]);
    },
  );
  test(
    "a link into another code target's doc is appended, with --target",
    () async {
      const show =
          'docs/prds/features/f02_feedback/f03_toast/us01_show/USER_STORY.md';
      final session = openSession(
        await writeTree({
          '.specstone/templates/architecture.yaml':
              'id: architecture\nper_target: true\n',
          '.specstone/templates/tech_stack.yaml':
              'id: tech_stack\nper_target: true\n',
          '.specstone/config.yaml':
              '${shippedPinsConfig()}targets:\n'
              '  flutter:\n    code_root: flutter_lib\n'
              '  jaspr:\n    code_root: jaspr_lib\n',
          'flutter_lib/.keep': '',
          'jaspr_lib/.keep': '',
          'docs/prds/features/f02_feedback/FEATURE.md': '# Feedback\n',
          'docs/prds/features/f02_feedback/f03_toast/FEATURE.md': '# Toast\n',
          show:
              '# Agent sees a toast\n\n## Use Case\nSee the '
              '[flutter toast](../../../../../specs/flutter/f02_feedback/f03_toast/ARCHITECTURE.md#components).\n',
          'docs/specs/flutter/f02_feedback/f03_toast/ARCHITECTURE.md': '# Toast architecture\n\n## Components\n| Component | Responsibility |\n|---|---|\n| Toast | Shows it |\n',
          'docs/specs/jaspr/f02_feedback/f03_toast/ARCHITECTURE.md':
              '# Toast architecture\n',
          'docs/specs/flutter/TECH_STACK.md': '# Flutter stack\n',
          'docs/specs/jaspr/TECH_STACK.md': '# Jaspr stack\n',
        }),
      );
      addTearDown(session.close);
      final parts = followLinks(
        session.index,
        pickBundle(
          session.index,
          'feedback/toast/show',
          BundleMode.implement,
          noProject: false,
          codeTarget: 'jaspr',
        ),
      );
      expect(parts.map(_id), [
        'specs/flutter/f02_feedback/f03_toast/ARCHITECTURE.md#components',
      ]);
    },
  );

  test(
    "a link into another code target's doc is appended with no --target given",
    () async {
      const show =
          'docs/prds/features/f02_feedback/f03_toast/us01_show/USER_STORY.md';
      final session = openSession(
        await writeTree({
          '.specstone/templates/architecture.yaml':
              'id: architecture\nper_target: true\n',
          '.specstone/templates/tech_stack.yaml':
              'id: tech_stack\nper_target: true\n',
          '.specstone/config.yaml':
              '${shippedPinsConfig()}targets:\n'
              '  flutter:\n    code_root: flutter_lib\n'
              '  jaspr:\n    code_root: jaspr_lib\n',
          'flutter_lib/.keep': '',
          'jaspr_lib/.keep': '',
          'docs/prds/features/f02_feedback/FEATURE.md': '# Feedback\n',
          'docs/prds/features/f02_feedback/f03_toast/FEATURE.md': '# Toast\n',
          'docs/prds/features/f02_feedback/f04_alert/FEATURE.md': '# Alert\n',
          show:
              '# Agent sees a toast\n\n## Use Case\nSee the '
              '[flutter toast](../../../../../specs/flutter/f02_feedback/f04_alert/ARCHITECTURE.md#components).\n',
          'docs/specs/flutter/f02_feedback/f03_toast/ARCHITECTURE.md':
              '# Toast architecture\n',
          'docs/specs/flutter/f02_feedback/f04_alert/ARCHITECTURE.md': '# Alert architecture\n\n## Components\n| Component | Responsibility |\n|---|---|\n| Toast | Shows it |\n',
          'docs/specs/jaspr/f02_feedback/f03_toast/ARCHITECTURE.md':
              '# Toast architecture\n',
          'docs/specs/flutter/TECH_STACK.md': '# Flutter stack\n',
          'docs/specs/jaspr/TECH_STACK.md': '# Jaspr stack\n',
        }),
      );
      addTearDown(session.close);
      final parts = followLinks(
        session.index,
        pickBundle(
          session.index,
          'feedback/toast/show',
          BundleMode.design,
          noProject: false,
        ),
      );
      expect(parts.map(_id), [
        'specs/flutter/f02_feedback/f04_alert/ARCHITECTURE.md#components',
      ]);
    },
  );

  test('an appended matrix section keeps the rows in scope', () async {
    const matrixLink =
        '../../../../../.specstone/records/jaspr/f01_login/IMPLEMENTATION.md#verification-matrix';
    final session = openSession(
      await writeTree({
        '.specstone/config.yaml':
            '${shippedPinsConfig()}targets:\n'
            '  flutter:\n    code_root: flutter_lib\n'
            '  jaspr:\n    code_root: jaspr_lib\n',
        'flutter_lib/.keep': '',
        'jaspr_lib/.keep': '',
        'docs/prds/features/f01_login/FEATURE.md': '# Login\n',
        _story: '# Agent signs in with email\n\n## Use Case\nSign in.\n',
        _fr: _frWith(
          'The system shall check it, as the [rows]($matrixLink) say.',
        ),
        'docs/prds/features/f01_login/us02_reset_password/USER_STORY.md':
            '# Agent resets a password\n\n## Use Case\nReset it.\n',
        'docs/prds/features/f01_login/us02_reset_password/fr01_send_reset_link.md':
            _frWith('The system shall mail a link.'),
        '.specstone/records/jaspr/f01_login/IMPLEMENTATION.md':
            "---\nstatuses:\n  - 'email_login:planned'\n---\n\n"
            '# Login implementation\n\n## Verification matrix\n\n'
            '- email_login/validate_credentials E01: `a wrong password`\n'
            '- reset_password/send_reset_link E01: `a link is mailed`\n',
      }),
    );
    addTearDown(session.close);
    final parts = followLinks(
      session.index,
      pickBundle(
        session.index,
        'login/email_login',
        BundleMode.implement,
        noProject: false,
        codeTarget: 'flutter',
      ),
    );

    expect(parts.map(_id), [
      '.specstone/records/jaspr/f01_login/IMPLEMENTATION.md#verification_matrix',
    ]);
    expect(
      parts.single.text,
      '## Verification matrix\n\n'
      '- email_login/validate_credentials E01: `a wrong password`',
    );
  });

  group('a doc whose type lists summary_for', () {
    final linkedFromProject = {
      _project: _projectLinking('[resets]($_measurementFromProject)'),
      _measurementFile: _measurement,
    };

    test("a story's bundle gets the naming line alone, and no link inside it is followed", () async {
      final parts = await followedFrom('login/email_login', linkedFromProject);

      expect(parts.map(_id), ['$_measurementDoc name']);
      expect(parts.single.text, isEmpty);
      expect(parts.single.summary, isFalse);
    });
    test("the project bundle gets the measurement in summary, and the summary's links are not followed", () async {
      final parts = await followedFrom('project', linkedFromProject);

      expect(parts.map(_id), ['$_measurementDoc summary']);
    });
    test("the measurement's own bundle prints it whole, so a link to it appends nothing", () async {
      final parts = await followedFrom(
        'measurement:fewer_resets',
        linkedFromProject,
      );

      expect(
        parts.where((part) => part.doc.docPath == _measurementDoc),
        isEmpty,
      );
    });
    test("an FR's and a spec doc's bundle get the naming line alone", () async {
      for (final target in [
        'login/email_login/validate_credentials',
        'architecture:signup',
      ]) {
        final parts = await followedFrom(target, linkedFromProject);

        expect(_measurementParts(parts), [
          '$_measurementDoc name',
        ], reason: target);
      }
    });
    test("a code path's bundle gets the naming line alone", () async {
      final project = await writeLoginProject(
        extra: {...loginRecords, ...linkedFromProject},
      );
      final session = openSession(project);
      addTearDown(session.close);
      final bundle = pickCodeBundle(
        session.index,
        resolveCodePath(
          'app/lib/src/login/sign_in_page.dart',
          workingDirectory: project,
          targets: session.project.targets,
          codeRootOf: session.project.codeRootOf,
          projectRoot: session.project.projectRoot,
          reachedFromProjectRoot: (_) => false,
        ),
        BundleMode.implement,
        noProject: false,
      );

      expect(_measurementParts(followLinks(session.index, bundle)), [
        '$_measurementDoc name',
      ]);
    });
    test(
      'a bundle lists the doc type ids of the docs its target picks',
      () async {
        final index = await indexWith(linkedFromProject);
        Set<String> typesOf(String target) => pickBundle(
          index,
          target,
          BundleMode.implement,
          noProject: false,
        ).targetTypeIds;

        expect(typesOf('login/email_login'), {'user_story'});
        expect(typesOf('project'), {'project'});
      },
    );
    test('a broken anchor into the doc prints nothing', () async {
      final parts = await followedFrom('login/email_login', {
        _measurementFile: _measurement,
        _story:
            '# Agent signs in with email\n\n## Use Case\nSee '
            '[nope]($_measurementFromStory#nope) and [title]($_measurementFromStory#fewer-resets).\n',
      });

      expect(_measurementParts(parts), isEmpty);
    });
    test(
      'a type with no summary_for prints the doc in summary in a story bundle',
      () async {
        final parts = await followedFrom('login/email_login', {
          _story:
              '# Agent signs in with email\n\n## Use Case\nSee '
              '[ranges]($_specs/topics/ranges.md).\n',
        });

        expect(parts.map(_id), ['specs/topics/ranges.md summary']);
      },
    );
    test('one naming line however many links', () async {
      final parts = await followedFrom('login/email_login', {
        ...linkedFromProject,
        _story:
            '# Agent signs in with email\n\n## Use Case\nSign in; see '
            '[resets]($_measurementFromStory), [baseline]($_measurementFromStory#baseline), '
            '[run]($_measurementFromStory#take-a-run), and [resets again]($_measurementFromStory).\n',
      });

      expect(parts.map(_id), ['$_measurementDoc name']);
    });
    test('a section, an item, a block, and an item range name only the doc, in a story and a feature bundle', () async {
      const topicOnly = {
        '.specstone/templates/topic.yaml': 'summary_for: [project]\n',
      };
      for (final (target, mode) in [
        ('login/email_login', BundleMode.implement),
        ('login', BundleMode.design),
      ]) {
        final parts = await followedFrom(target, mode: mode, {
          ...topicOnly,
          _story:
              '# Agent signs in with email\n\n## Use Case\nSee [rules]($_specs/topics/ranges.md#rules), '
              '[RULE-3]($_specs/topics/doc_model.md#rules), [an example]($_specs/topics/doc_model.md#a-worked-example), '
              'and [RULE-2]($_specs/topics/ranges.md#rules) to [RULE-4]($_specs/topics/ranges.md#rules).\n',
        });

        expect(parts.map(_id), [
          'specs/topics/ranges.md name',
          'specs/topics/doc_model.md name',
        ], reason: target);
      }
    });
  });

  group('a goal Metric link into a measurement', () {
    const goalLayers = {
      '.specstone/templates/measurement.yaml': 'summary_for: [project, goal]\n',
      'docs/prds/GOAL.md':
          '# Goals\n\n## Long-term goals\n'
          '- **PG-01** Fewer resets.\n'
          '  - **Metric:** [resets]($_measurementFromProject)\n',
      _measurementFile: _measurement,
    };

    test(
      'a goal Metric link prints the naming line in a story bundle',
      () async {
        final parts = await followedFrom('login/email_login', goalLayers);

        expect(_measurementParts(parts), ['$_measurementDoc name']);
        expect(
          parts
              .singleWhere(
                (p) => p.nameOnly && p.doc.docPath == _measurementDoc,
              )
              .text,
          isEmpty,
        );
      },
    );
    test('a goal Metric link prints the naming line in an FR bundle', () async {
      final parts = await followedFrom(
        'login/email_login/validate_credentials',
        goalLayers,
      );

      expect(_measurementParts(parts), ['$_measurementDoc name']);
      expect(
        parts
            .singleWhere((p) => p.nameOnly && p.doc.docPath == _measurementDoc)
            .text,
        isEmpty,
      );
    });
    test('context goal prints the measurement in summary', () async {
      final parts = await followedFrom('goal', goalLayers);

      expect(_measurementParts(parts), ['$_measurementDoc summary']);
      expect(parts.map(_id), isNot(contains('specs/topics/ranges.md#purpose')));
    });
  });

  group('a link into a summary_rows section', () {
    const results = '$_measurementFromProject#results';
    const resultsFromStory = '$_measurementFromStory#results';
    const cut =
        '## Results\nNewest first. Met: halved.\n\n| Date | Run | Met |\n|---|---|---|\n'
        '| 2026-11-14 | 2 | no |';
    const plain =
        '# Fewer resets\n\n## Scope\n- Resets per week.\n\n'
        '## Baseline\n| Metric | Run | Value | Date | Source |\n|---|---|---|---|---|\n| resets | 1 | 4 | 2026-11-01 | log |\n\n'
        '## Results\nNewest first. Met: halved.\n\n| Date | Run | Met |\n|---|---|---|\n'
        '| 2026-11-14 | 2 | no |\n| 2026-11-01 | 1 | no |\n';
    const itemLayer = {
      '.specstone/templates/measurement.yaml':
          'sections:\n  - id: results\n    prefix_id: RUN-\n',
    };

    Future<List<AppendedPart>> fromProject(
      String links, {
      String measurement = plain,
      Map<String, String> extra = const {},
    }) => followedFrom('project', {
      _project: _projectLinking(links),
      _measurementFile: measurement,
      ...extra,
    });

    test(
      'a section link appends the cut once, under a summary mark, with no item',
      () async {
        final parts = await fromProject('[results]($results)');

        expect(parts.map(_id), ['$_measurementDoc#results summary']);
        expect(parts.single.text, cut);
        expect(parts.single.itemId, isNull);
        expect(parts.single.nameOnly, isFalse);
      },
    );
    test('an item link appends the cut and no item part', () async {
      final parts = await fromProject(
        '[RUN-1]($results)',
        measurement: plain.replaceFirst(
          '## Results\n',
          '## Results\n- **RUN-1** First run.\n\n',
        ),
        extra: itemLayer,
      );

      expect(parts.map(_id), ['$_measurementDoc#results summary']);
      expect(parts.single.itemId, isNull);
      expect(
        parts.single.text,
        startsWith('## Results\n- **RUN-1** First run.'),
      );
      expect(parts.single.text, isNot(contains('2026-11-01')));
    });
    test('a second link into the section appends nothing again', () async {
      final parts = await fromProject(
        '[results]($results), [again]($results), and [RUN-2]($results)',
        measurement: plain.replaceFirst(
          '## Results\n',
          '## Results\n- **RUN-2** Second run.\n\n',
        ),
        extra: itemLayer,
      );

      expect(parts.map(_id), ['$_measurementDoc#results summary']);
    });
    test('an item range link appends the cut once', () async {
      final parts = await fromProject(
        '[RUN-1]($results) to [RUN-3]($results)',
        measurement: plain.replaceFirst(
          '## Results\n',
          '## Results\n- **RUN-1** First run.\n- **RUN-2** Second run.\n- **RUN-3** Third run.\n\n',
        ),
        extra: itemLayer,
      );

      expect(parts.map(_id), ['$_measurementDoc#results summary']);
      expect(parts.single.itemId, isNull);
    });
    test(
      'a section link after the doc link appends nothing the summary holds',
      () async {
        final parts = await fromProject(
          '[resets]($_measurementFromProject) and [results]($results)',
        );

        expect(parts.map(_id), ['$_measurementDoc summary']);
      },
    );
    test('a doc link after the cut still appends the summary with Scope and the cut', () async {
      final parts = await fromProject(
        '[results]($results) and [resets]($_measurementFromProject)',
      );

      expect(parts.map(_id), [
        '$_measurementDoc#results summary',
        '$_measurementDoc summary',
      ]);
      expect(parts.last.text, contains('## Scope\n- Resets per week.'));
      expect(parts.last.text, contains(cut));
      expect(parts.last.text, isNot(contains('2026-11-01 | 1')));
    });
    test('a link into a section that is no summary_rows section appends it whole', () async {
      final parts = await fromProject(
        '[resets]($_measurementFromProject) and [baseline]($_measurementFromProject#baseline)',
      );

      expect(parts.map(_id), [
        '$_measurementDoc summary',
        '$_measurementDoc#baseline',
      ]);
      expect(parts.last.summary, isFalse);
    });
    test(
      'a link to a ### heading inside the section appends the cut',
      () async {
        final parts = await fromProject(
          '[runs]($_measurementFromProject#runs)',
          measurement:
              '# Fewer resets\n\n## Scope\n- Resets per week.\n\n'
              '## Results\nNewest first. Met: halved.\n\n### Runs\n'
              '| Date | Run | Met |\n|---|---|---|\n'
              '| 2026-11-14 | 2 | no |\n| 2026-11-01 | 1 | no |\n',
        );

        expect(parts.map(_id), ['$_measurementDoc#results summary']);
        expect(parts.single.text, contains('2026-11-14 | 2'));
        expect(parts.single.text, isNot(contains('2026-11-01 | 1')));
      },
    );
    test('a section written as prose appends its text whole', () async {
      final parts = await fromProject(
        '[results]($results)',
        measurement: '# Fewer resets\n\n## Scope\n- Resets per week.\n\n## Results\nRun one met the goal.\nRun two did not.\n',
      );

      expect(parts.map(_id), ['$_measurementDoc#results summary']);
      expect(
        parts.single.text,
        '## Results\nRun one met the goal.\nRun two did not.',
      );
    });
    test(
      'a layer that turns summary_rows off appends the section whole',
      () async {
        final parts = await fromProject(
          '[resets]($_measurementFromProject) and [results]($results)',
          extra: {
            '.specstone/templates/measurement.yaml':
                'sections:\n  - id: results\n    summary_rows: false\n',
          },
        );

        expect(parts.map(_id), [
          '$_measurementDoc summary',
          '$_measurementDoc#results',
        ]);
        expect(parts.last.summary, isFalse);
        expect(parts.last.text, contains('2026-11-01 | 1'));
        expect(parts.first.text, isNot(contains('## Results')));
      },
    );
    test('the naming line wins over the cut in a story bundle', () async {
      final parts = await followedFrom('login/email_login', {
        _measurementFile: plain,
        _story:
            '# Agent signs in with email\n\n## Use Case\nSee [results]($resultsFromStory).\n',
      });

      expect(parts.map(_id), ['$_measurementDoc name']);
    });
  });
}
