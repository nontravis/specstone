// The test titles and literals are plan values kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/bundle_follow.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';
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

String _frWith(String statement) =>
    '---\nverify_method: test\n---\n\n# Validate credentials\n\n## Statement\n$statement\n';

/// Names [part] by its DocPath, `#<section key>`, `###` anchor, item ID, and
/// summary mark.
String _id(AppendedPart part) =>
    '${part.doc.docPath}'
    '${part.sectionKey == null ? '' : '#${part.sectionKey}'}'
    '${part.heading == null ? '' : ' #${part.heading}'}'
    '${part.itemId == null ? '' : ' ${part.itemId}'}'
    '${part.summary ? ' summary' : ''}';

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

  const inv14 = '[INV-14]($_specs/f02_signup/DOMAIN.md#invariants)';

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
  test(
    'an item that links to a rule appends the rule after it, each once',
    () async {
      final parts = await followed('The system shall lock, by $inv14.');
      expect(parts.map(_id), [
        'specs/f02_signup/DOMAIN.md#invariants INV-14',
        'specs/topics/doc_model.md#rules RULE-3',
      ]);
    },
  );
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
  test(
    'a part printed whole or already appended is not appended again',
    () async {
      final parts = await followed(
        'See the [story](USER_STORY.md), $inv14, and $inv14 again.',
      );
      expect(parts.map(_id), [
        'specs/f02_signup/DOMAIN.md#invariants INV-14',
        'specs/topics/doc_model.md#rules RULE-3',
      ]);
    },
  );
  test('two parts that link to each other are each appended once', () async {
    final parts = await followed(
      'See [doc model]($_specs/topics/doc_model.md#purpose).',
    );
    expect(parts.map(_id), [
      'specs/topics/doc_model.md#purpose',
      'specs/topics/ranges.md#purpose',
    ]);
  });
  test('a chain into a summary doc appends no part twice and none the summary prints', () async {
    final parts = await followed(
      'See [guide]($_specs/topics/guide.md#purpose), [reset]($_resetStory), and [reset]($_resetStory#use-case).',
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
      'See [doc model]($_specs/topics/doc_model.md#purpose).',
      extra: {
        'docs/specs/topics/doc_model.md':
            '# Doc model\n\n## Purpose\nSee [examples](#examples), '
            '[RULE-2](ranges.md#rules), and [ranges](ranges.md#purpose).\n\n'
            '## Examples\nOne link.\n',
      },
    );
    expect(parts.map(_id), [
      'specs/topics/doc_model.md#purpose',
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
        'specs/topics/doc_model.md#rules RULE-3',
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
}
