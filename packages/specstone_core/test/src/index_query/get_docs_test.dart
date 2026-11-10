import 'dart:convert';

// The expected values are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/fault.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/get_docs.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart' show withApprovalHashes;
import '../../helpers/index_fixture.dart';
import '../../helpers/nested_fixture.dart';

void main() {
  late DocIndex index;
  setUpAll(() async => index = await indexWith());
  String file(String docPath) => loginProject['docs/$docPath']!;

  test('f01/us04/s1, f01/us04/fr02: a bare name prints each doc carrying it as written, stories left out', () async {
    final text = answerGet(index, ['login']).text;
    expect(
      text,
      startsWith(
        '==> login (feature) · prds/features/f01_login/FEATURE.md · base ${baseHashOf(file('prds/features/f01_login/FEATURE.md'))} <==\n'
        '${file('prds/features/f01_login/FEATURE.md')}\n==> login (api) · specs/f01_login/API.md · base ${baseHashOf(file('specs/f01_login/API.md'))} <==\n',
      ),
    );
    expect('==> '.allMatches(text), hasLength(5));
    expect(text, isNot(contains('login/email_login')));
  });
  test('f01/us04/s2, f01/us04/fr02/e01: one section from each doc that holds it, nothing else', () async {
    expect(
      answerGet(index, ['login#components']).text,
      '==> login (architecture) · specs/f01_login/ARCHITECTURE.md#components · base cf930e1810b0 <==\n'
      '## Components\n| Component | Responsibility |\n|-----------|----------------|\n'
      '| Login form | Collects the email and the password |\n',
    );
  });
  test(
    'f01/us04/s3, f01/us04/fr01: a doc type prefix narrows to one doc',
    () async {
      expect(
        '==> '.allMatches(answerGet(index, ['architecture:login']).text),
        hasLength(1),
      );
    },
  );
  test('f01/us04/s4, f01/us04/fr02/e04, f01/us01/s7: an untyped doc reads by its DocPath, a section by its snake_case key', () async {
    expect(
      answerGet(index, ['prds/d01_context.md#project_vision']).text,
      '==> prds/d01_context.md · prds/d01_context.md#project_vision · base 6f3e9bae7bdc <==\n## Project vision\nOne SDD system; ค้นหา เอกสาร\n',
    );
  });
  test('f01/us04/fr01/e09, f01/us04/fr02/e01: a path takes a section key as the name does', () async {
    expect(
      answerGet(index, [
        'docs/specs/f01_login/ARCHITECTURE.md#components',
      ]).text,
      answerGet(index, ['architecture:login#components']).text,
    );
  });
  test('f01/us04/s5: a name no doc carries is doc_not_found', () async {
    expect(() => answerGet(index, ['logn']), throwsA(isA<IndexFault>()));
  });
  test('f01/us04/s6, f01/us04/fr02/e02: a key no resolved doc holds is section_not_found naming name and key', () async {
    expect(
      () => answerGet(index, ['login#acceptance']),
      throwsA(
        isA<IndexFault>()
            .having((f) => f.code, 'code', IndexFaultCode.sectionNotFound)
            .having(
              (f) => f.message,
              'message',
              'no doc named login holds a section with the key acceptance',
            ),
      ),
    );
  });
  test('f01/us04/fr02/e03, s03/inv4: the head is no section', () async {
    expect(
      () => answerGet(index, ['login/email_login#agent_signs_in_with_email']),
      throwsA(isA<IndexFault>()),
    );
  });
  test(
    'f01/us04/fr02/e05: nothing is trimmed: comments and N/A sections print',
    () async {
      expect(
        answerGet(index, ['login/email_login/validate_credentials']).text,
        contains('<!-- fill in later -->'),
      );
      expect(
        answerGet(index, ['login/email_login/lock_after_failures']).text,
        contains('## Rationale\nN/A\n'),
      );
    },
  );
  test("review focus 1, f02 review focus 4: two sections with one header both print, in file order, under the first one's base", () async {
    final notes = await indexWith({
      'docs/notes.md': '# Notes\n\n## Notes\nfirst\n\n## Notes\nsecond\n',
    });
    expect(
      answerGet(notes, ['notes.md#notes']).text,
      '==> notes.md · notes.md#notes · base 47471c97c516 <==\n## Notes\nfirst\n## Notes\nsecond\n',
    );
  });
  test('f01/us01/fr03/e13, f01/us04/fr02: headers Root schema and Root-schema key alike and both print', () async {
    final doc = await indexWith({
      'docs/roots.md':
          '# Roots\n\n## Root schema\nfirst\n\n## Root-schema\nsecond\n',
    });
    final text = answerGet(doc, ['roots.md#root_schema']).text;
    expect(text, contains('## Root schema\nfirst\n'));
    expect(text, contains('## Root-schema\nsecond\n'));
    expect(text, startsWith('==> roots.md · roots.md#root_schema · base '));
    final content = parseIndexedDoc(
      docPath: 'roots.md',
      bytes: utf8.encode(
        '# Roots\n\n## Root schema\nfirst\n\n## Root-schema\nsecond\n',
      ),
      match: const NoDocType(),
    ).content;
    expect(content.sections.map((s) => s.key), ['root_schema', 'root_schema']);
    expect(basesOf(content, null)['sections'], {
      'root_schema': sectionBaseOf(content.sections.first.body, null),
    });
  });
  test('f01/us04/fr02: --json gives name, path, section, and text; no docType on an untyped doc', () async {
    expect(
      answerGet(index, ['prds/d01_context.md#project_name']).json['docs'],
      [
        {
          'name': 'prds/d01_context.md',
          'path': 'prds/d01_context.md',
          'section': 'project_name',
          'base': '26018c0105bb',
          'text': '## Project name\n- **Human:** Specstone\n- **Code:** `specstone`\n',
        },
      ],
    );
  });
  test('review focus 5, preflight F15: a whole doc keeps its CRLF line endings as written', () async {
    final crlf = await indexWith({
      'docs/crlf.md': '# Crlf\r\n\r\n## A\r\nx\r\n',
    });
    expect(
      answerGet(crlf, ['crlf.md']).text,
      '==> crlf.md · crlf.md · base ${baseHashOf('# Crlf\n\n## A\nx\n')} <==\n# Crlf\r\n\r\n## A\r\nx\r\n',
    );
  });
  test('s02_api_get: a doc with no final newline prints as one that ends in a newline, JSON text verbatim', () async {
    const feature = '# Login\n\n## Problem\nNo final newline';
    final bare = await indexWith({featureKey: feature});
    final ended = await indexWith({featureKey: '$feature\n'});
    final answer = answerGet(bare, ['login']);
    String afterNamingLine(String text) => text.split('\n').skip(1).join('\n');
    expect(
      afterNamingLine(answer.text),
      afterNamingLine(answerGet(ended, ['login']).text),
    );
    expect(answer.text, contains('$feature\n\n==> login (api) · '));
    expect(answerGet(bare, ['feature:login']).text, endsWith('$feature\n'));
    final docs = answer.json['docs']! as List;
    expect((docs.first as Map)['text'], feature);
  });
  test('namingLine: the name with its doc type, then the DocPath; an untyped doc has no type', () async {
    expect(
      namingLine(index.resolve('login').first),
      '==> login (feature) · prds/features/f01_login/FEATURE.md <==',
    );
    expect(
      namingLine(index.resolve('prds/d01_context.md').single),
      '==> prds/d01_context.md · prds/d01_context.md <==',
    );
    expect(
      namingLine(
        index.at('prds/features/f01_login/FEATURE.md')!,
        base: 'abc123abc123',
      ),
      '==> login (feature) · prds/features/f01_login/FEATURE.md · base abc123abc123 <==',
    );
  });
  test('index_query/read_doc_section/print_doc_or_section E08, E13: a section read names <DocPath>#<key> with its base; a whole-doc read names its path with bases.doc', () async {
    const storyPath = 'prds/features/f01_login/us01_email_login/USER_STORY.md';
    expect(
      answerGet(index, [
        'user_story:login/email_login#acceptance_criteria',
      ]).text,
      startsWith(
        '==> login/email_login (user_story) · $storyPath#acceptance_criteria · base 6d6a67fa9a00 <==\n## Acceptance Criteria\n',
      ),
    );
    final whole = answerGet(index, ['user_story:login/email_login']);
    expect(
      whole.text,
      startsWith(
        '==> login/email_login (user_story) · $storyPath · base ${baseHashOf(file(storyPath))} <==\n',
      ),
    );
    final doc = (whole.json['docs']! as List).single as Map;
    expect((doc['bases']! as Map)['doc'], baseHashOf(file(storyPath)));
  });
  group('index_query/read_doc_section/print_doc_or_section E08, layout-blind bases', () {
    const storyPath =
        'docs/prds/features/f01_login/us01_email_login/USER_STORY.md';
    const bareBody =
        '\n### Scenario 1 — [happy] Sign in\n- **Given** a registered email\n';
    Future<DocIndex> withStory(String sections) =>
        indexWith({storyPath: '# Agent signs in with email\n\n$sections'});
    Map<String, Object?> story(DocIndex i) =>
        (answerGet(i, ['user_story:login/email_login']).json['docs']! as List)
                .single
            as Map<String, Object?>;

    test('the section prints as on disk and names the laid-out base', () async {
      final tight = await withStory(
        '## Acceptance Criteria\n### Scenario 1 — [happy] Sign in\n'
        '- **Given** a registered email\n',
      );
      final text = answerGet(tight, [
        'user_story:login/email_login#acceptance_criteria',
      ]).text;
      expect(text, contains('base 19db7e6aacbd <=='));
      expect(
        text,
        endsWith(
          '## Acceptance Criteria\n### Scenario 1 — [happy] Sign in\n'
          '- **Given** a registered email\n',
        ),
      );
      expect(sectionBaseOf(bareBody, null), '19db7e6aacbd');
    });
    test('a padded table and its compact twin share one base', () {
      expect(
        sectionBaseOf('| A | B |\n|---|---|\n| 1 | 2 |\n', null),
        sectionBaseOf('| A   | B   |\n|-----|-----|\n| 1   | 2   |\n', null),
      );
    });
    test(
      'a lead with and without a blank line under the title share a base',
      () async {
        final tight = await indexWith({
          'docs/notes.md': '# Notes\nlead text\n\n## One\nx\n',
        });
        final spaced = await indexWith({
          'docs/notes.md': '# Notes\n\nlead text\n\n## One\nx\n',
        });
        Object? leadBase(DocIndex i) =>
            (((answerGet(i, ['notes.md']).json['docs']! as List).single
                    as Map)['bases']!
                as Map)['sections'];
        expect(
          (leadBase(tight)! as Map)[leadKey],
          (leadBase(spaced)! as Map)[leadKey],
        );
      },
    );
    test(
      'a title with trailing spaces gets the base of the title without them',
      () {
        expect(titleBaseOf('Notes  \t'), titleBaseOf('Notes'));
        expect(titleBaseOf('Notes'), baseHashOf('Notes'));
        expect(titleBaseOf(null), emptyBaseHash);
      },
    );
    test(
      'a last section with no final newline shares the base of its twin',
      () {
        expect(sectionBaseOf('x', null), sectionBaseOf('x\n', null));
        expect(sectionBaseOf('', null), emptyBaseHash);
      },
    );
    test('a lead with no final newline shares the base of its twin', () {
      expect(
        leadBaseOf(Doc.parse('# T\nlead'), null),
        leadBaseOf(Doc.parse('# T\nlead\n'), null),
      );
    });
    test('bases.title ignores trailing spaces of the title line', () async {
      final i = await indexWith({'docs/notes.md': '# Notes  \n\n## One\nx\n'});
      final doc =
          (answerGet(i, ['notes.md']).json['docs']! as List).single as Map;
      expect((doc['bases']! as Map)['title'], baseHashOf('Notes'));
    });
    test('#_lead names the laid-out lead base', () async {
      final tight = await indexWith({
        'docs/notes.md': '# Notes\nlead text\n\n## One\nx\n',
      });
      final spaced = await indexWith({
        'docs/notes.md': '# Notes\n\nlead text\n\n## One\nx\n',
      });
      String lead(DocIndex i) =>
          ((answerGet(i, ['notes.md#_lead']).json['docs']! as List).single
                  as Map)['base']!
              as String;
      expect(lead(tight), lead(spaced));
      expect(lead(tight), baseHashOf('\nlead text\n'));
    });
    test(
      'field bases and bases.doc stay the hash of the text as written',
      () async {
        final i = await withStory('## Acceptance Criteria\n- one\n');
        final bases = story(i)['bases']! as Map;
        expect(
          bases['doc'],
          baseHashOf(
            '# Agent signs in with email\n\n## Acceptance Criteria\n- one\n',
          ),
        );
      },
    );
  });
  test('index_query/read_doc_section/print_doc_or_section E09: a template section the doc lacks prints its naming line alone with the base of empty text', () async {
    expect(
      answerGet(index, ['login/email_login#rules']).text,
      '==> login/email_login (user_story) · prds/features/f01_login/us01_email_login/USER_STORY.md#rules · base e3b0c44298fc <==\n',
    );
    final doc =
        (answerGet(index, ['login/email_login#rules']).json['docs']! as List)
                .single
            as Map;
    expect(doc['text'], '');
    expect(doc['base'], emptyBaseHash);
  });
  test('f01/us04/fr02/e10: --json bases list the title, every section, and every field, absent ones empty', () async {
    final story =
        (answerGet(index, ['user_story:login/email_login']).json['docs']!
                    as List)
                .single
            as Map;
    final bases = story['bases']! as Map;
    expect(bases['title'], 'ff5b5994d060');
    expect((bases['sections']! as Map)['acceptance_criteria'], '6d6a67fa9a00');
    expect((bases['sections']! as Map)['rules'], emptyBaseHash);
    expect((bases['fields']! as Map)['status'], 'e721f319d794');
    expect((bases['fields']! as Map)['approved'], emptyBaseHash);
    expect((bases['sections']! as Map).keys, [
      'use_case',
      'rules',
      'acceptance_criteria',
      'open_questions',
    ]);
    expect((bases['fields']! as Map).keys, [
      'slug',
      'status',
      'draft',
      'approved',
      'reference',
      'vision',
      'goals',
      'persona',
      'implements',
    ]);
    expect(story.containsKey('base'), isFalse);
    final untyped =
        (answerGet(index, ['prds/d01_context.md']).json['docs']! as List).single
            as Map;
    expect(((untyped['bases']! as Map)['sections']! as Map).keys, [
      'project_name',
      'project_vision',
    ]);
    expect((untyped['bases']! as Map)['fields'], isEmpty);
    expect(
      (untyped['bases']! as Map)['title'],
      baseHashOf('D-01 — Project context'),
    );
  });

  test('ms-r10: --json bases.doc hashes the whole text, LF-normalized, the same with CRLF and a BOM', () async {
    const text = '---\ndraft: true\n---\n\n# Notes\n\n## A\nx\n';
    final lf = await indexWith({'docs/notes.md': text});
    final crlf = await indexWith({
      'docs/notes.md': '﻿${text.replaceAll('\n', '\r\n')}',
    });
    Map<Object?, Object?> docBase(DocIndex index) =>
        ((answerGet(index, ['notes.md']).json['docs']! as List).single
                as Map)['bases']!
            as Map;
    expect(docBase(lf)['doc'], baseHashOf(text));
    expect(docBase(crlf)['doc'], baseHashOf(text));
  });

  test('f01/us04/fr02/e10, PD16, H27: a doc with no title has the base of empty text', () async {
    final untitled = await indexWith({'docs/untitled.md': '## A\nx\n'});
    final doc =
        (answerGet(untitled, ['untitled.md']).json['docs']! as List).single
            as Map;
    expect((doc['bases']! as Map)['title'], emptyBaseHash);
  });

  test('f02/us01/s3, PD4, HD4: bases hash the first of two key blocks of one field, a quoted spelling included', () async {
    final dup = await indexWith({
      'docs/prds/features/f01_login/us01_email_login/USER_STORY.md':
          '---\nstatus: planned\nvision:\n  - PV-01\nstatus: implemented\n---\n\n'
          '# Agent signs in with email\n\n## Use Case\nSign in.\n',
      'docs/prds/features/f01_login/FEATURE.md': '---\nvision:\n  - PV-01\n"status": planned\n---\n\n# Login\n\n## Problem\nUsers sign in.\n',
    });
    final story =
        (answerGet(dup, ['user_story:login/email_login']).json['docs']! as List)
                .single
            as Map;
    expect(
      ((story['bases']! as Map)['fields']! as Map)['status'],
      baseHashOf('status: planned\n'),
    );
    final feature =
        (answerGet(dup, ['feature:login']).json['docs']! as List).single as Map;
    final fields = (feature['bases']! as Map)['fields']! as Map;
    expect(fields['status'], baseHashOf('"status": planned\n'));
    expect(fields.containsKey('"status"'), isFalse);
  });

  const gnfrWithLead = '# GNFR\n\nLead [x](a.md).\n\n## Performance\nN/A\n';

  test('f01/us04/fr02/e11: #_lead prints the lead under its base', () async {
    final withLead = await indexWith({'docs/prds/GNFR.md': gnfrWithLead});
    final answer = answerGet(withLead, ['gnfr#_lead']);
    const lead = '\nLead [x](a.md).\n';
    expect(
      answer.text,
      '==> gnfr (gnfr) · prds/GNFR.md#_lead · base ${baseHashOf(lead)} <==\n$lead',
    );
    final doc = (answer.json['docs']! as List).single as Map;
    expect(doc['section'], '_lead');
    expect(doc['base'], baseHashOf(lead));
    expect(doc['text'], lead);
  });

  test('f01/us04/fr02/e12: #_lead of a doc with no lead prints the naming line with the empty-text base', () async {
    final answer = answerGet(index, ['gnfr#_lead']);
    expect(
      answer.text,
      '==> gnfr (gnfr) · prds/GNFR.md#_lead · base $emptyBaseHash <==\n',
    );
    final doc = (answer.json['docs']! as List).single as Map;
    expect(doc['base'], emptyBaseHash);
    expect(doc['text'], '');
  });

  test('f01/us04/fr02/e10: bases.sections lists _lead first only when the lead holds non-blank text', () async {
    final withLead = await indexWith({'docs/prds/GNFR.md': gnfrWithLead});
    final held =
        ((answerGet(withLead, ['gnfr']).json['docs']! as List).single
                as Map)['bases']!
            as Map;
    expect((held['sections']! as Map).keys.first, '_lead');
    expect(
      (held['sections']! as Map)['_lead'],
      baseHashOf('\nLead [x](a.md).\n'),
    );

    final bare =
        ((answerGet(index, ['gnfr']).json['docs']! as List).single
                as Map)['bases']!
            as Map;
    expect((bare['sections']! as Map).containsKey('_lead'), isFalse);
  });

  test('f01/us04/fr02: a whole-doc get of an empty file prints the naming line and one blank line, as at 404b9a7', () async {
    final withEmpty = await indexWith({'docs/prds/empty.md': ''});
    expect(
      answerGet(withEmpty, ['prds/empty.md']).text,
      '==> prds/empty.md · prds/empty.md · base $emptyBaseHash <==\n\n',
    );
  });
  test('index_query/read_doc_section/resolve_doc_name E13 (W8): a path holding # is read whole, as resolve reads it, so get splits no section key off it', () async {
    final noted = await indexWith({'docs/prds/notes#draft.md': '# Draft\n'});
    expect(
      answerGet(noted, ['prds/notes#draft.md']).text,
      '==> prds/notes#draft.md · prds/notes#draft.md · base ${baseHashOf('# Draft\n')} <==\n# Draft\n',
    );
    expect(
      () => answerGet(noted, ['prds/notes#draft']),
      throwsA(isA<IndexFault>()),
    );
  });
  group('index_query/read_doc_section/print_doc_or_section, several names', () {
    const featurePath = 'prds/features/f01_login/FEATURE.md';
    const storyPath = 'prds/features/f01_login/us01_email_login/USER_STORY.md';
    List<String> headings(String text) => [
      for (final line in text.split('\n'))
        if (line.startsWith('==> ')) line.split(' · ')[1].split(' ').first,
    ];
    List<Object?> docNames(ReadAnswer answer) => [
      for (final doc in answer.json['docs']! as List) (doc as Map)['name'],
    ];
    Matcher faultOf(IndexFaultCode code, String message) => isA<IndexFault>()
        .having((f) => f.code, 'code', code)
        .having((f) => f.message, 'message', message);

    test('E13: each name prints in argument order, a whole doc under its '
        'whole-text base, a section under its own', () {
      final answer = answerGet(index, [
        'feature:login',
        'user_story:login/email_login',
        'gnfr#performance',
      ]);
      expect(headings(answer.text), [
        featurePath,
        storyPath,
        'prds/GNFR.md#performance',
      ]);
      expect(
        answer.text,
        startsWith(
          '==> login (feature) · $featurePath · base ${baseHashOf(file(featurePath))} <==\n',
        ),
      );
      expect(
        answer.text,
        contains(
          '==> login/email_login (user_story) · $storyPath · base ${baseHashOf(file(storyPath))} <==\n',
        ),
      );
      expect(
        answer.text,
        endsWith(answerGet(index, ['gnfr#performance']).text),
      );
      expect(docNames(answer), ['login', 'login/email_login', 'gnfr']);
    });

    test('E13: --json holds one object per doc or section, in argument order, '
        'a section read with base and no bases', () {
      final docs =
          answerGet(index, [
                'gnfr#security',
                'feature:login',
                'gnfr#performance',
              ]).json['docs']!
              as List;
      expect(
        [for (final doc in docs) (doc as Map)['section']],
        ['security', null, 'performance'],
      );
      final sections = [docs.first as Map, docs.last as Map];
      for (final doc in sections) {
        expect(doc.containsKey('base'), isTrue);
        expect(doc.containsKey('bases'), isFalse);
      }
      expect(sections.first['base'], isNot(sections.last['base']));
      expect((docs[1] as Map).containsKey('bases'), isTrue);
    });

    test('E14: a doc read whole prints once at the first name that names it '
        'or a part of it, and drops its sections', () {
      final whole = answerGet(index, ['login']).text;
      for (final names in [
        ['login', 'feature:login#problem'],
        ['feature:login#problem', 'login'],
        ['login', 'feature:login#problem', 'feature:login#_lead'],
      ]) {
        final answer = answerGet(index, names);
        expect(answer.text, whole, reason: '$names');
        expect(answer.json['docs'], hasLength(5), reason: '$names');
      }
      final partFirst = answerGet(index, [
        'architecture:login#components',
        'feature:login',
        'architecture:login',
      ]);
      expect(headings(partFirst.text), [
        'specs/f01_login/ARCHITECTURE.md',
        featurePath,
      ]);
    });

    test('E14: two different sections of one doc both print; one section '
        'named twice, or a doc two names resolve to, prints once', () {
      expect(
        headings(
          answerGet(index, [
            'feature:login#problem',
            'feature:login#out_of_scope',
          ]).text,
        ),
        ['$featurePath#problem', '$featurePath#out_of_scope'],
      );
      expect(
        answerGet(index, [
          'feature:login#problem',
          'feature:login#problem',
        ]).text,
        answerGet(index, ['feature:login#problem']).text,
      );
      expect(
        answerGet(index, ['login', 'architecture:login']).text,
        answerGet(index, ['login']).text,
      );
      expect(
        answerGet(index, ['gnfr#_lead', 'gnfr', 'gnfr#_lead']).text,
        answerGet(index, ['gnfr']).text,
      );
    });

    test('E15: every name that resolves to no doc is named, the whole call '
        'refused with one doc_not_found', () {
      expect(
        () => answerGet(index, ['login', 'logn', 'architecture:nope', 'nope']),
        throwsA(
          faultOf(
            IndexFaultCode.docNotFound,
            'no doc carries the name logn; '
            'no architecture doc carries the name nope; '
            'no doc carries the name nope',
          ),
        ),
      );
    });

    test('E02: a key no resolved doc holds refuses the whole call, naming '
        'the name and the key of each', () {
      expect(
        () => answerGet(index, ['login', 'login#acceptance', 'gnfr#nope']),
        throwsA(
          faultOf(
            IndexFaultCode.sectionNotFound,
            'no doc named login holds a section with the key acceptance; '
            'no doc named gnfr holds a section with the key nope',
          ),
        ),
      );
    });

    test('E17: faults of two codes throw IndexFaults, one per code, in the '
        "order of each code's first name", () {
      final docFirst = _thrownFaults(index, [
        'logn',
        'login#acceptance',
        'nope',
        'gnfr#nope',
      ]);
      expect(
        [for (final f in docFirst.faults) f.toJson()['error']],
        [
          {
            'code': 'doc_not_found',
            'message':
                'no doc carries the name logn; no doc carries the name nope',
          },
          {
            'code': 'section_not_found',
            'message':
                'no doc named login holds a section with the key acceptance; '
                'no doc named gnfr holds a section with the key nope',
          },
        ],
      );
      final sectionFirst = _thrownFaults(index, ['login#acceptance', 'logn']);
      expect(
        [for (final f in sectionFirst.faults) _codeOf(f)],
        ['section_not_found', 'doc_not_found'],
      );
      expect(sectionFirst.exitStatus, 64);
      expect(sectionFirst.toJson(), sectionFirst.faults.first.toJson());
    });

    test('E17: an unknown doc type is one more fault of its name, in the '
        "order of each code's first name", () {
      final mixed = _thrownFaults(index, [
        'nosuch1',
        'login#zzz',
        'nosuchtype:x',
      ]);
      expect(
        [for (final f in mixed.faults) _codeOf(f)],
        ['doc_not_found', 'section_not_found', 'doc_type_unknown'],
      );
      expect(_codeOf(mixed), 'doc_not_found');
      final typeFirst = _thrownFaults(index, ['nosuchtype:x', 'nosuch2']);
      expect(
        [for (final f in typeFirst.faults) _codeOf(f)],
        ['doc_type_unknown', 'doc_not_found'],
      );
      expect(_codeOf(typeFirst), 'doc_type_unknown');
      expect(typeFirst.exitStatus, 64);
    });

    test('E17: names with two unknown doc types give one doc_type_unknown '
        'fault naming both', () {
      expect(
        () => answerGet(index, ['a:x', 'b:y']),
        throwsA(
          isA<TemplateFault>().having(
            (f) => f.message,
            'message',
            'Could not find a doc type named "a".; '
                'Could not find a doc type named "b".',
          ),
        ),
      );
    });

    test('E15, E02: a name given twice is named once in its fault', () {
      expect(
        () => answerGet(index, ['logn', 'logn']),
        throwsA(
          isA<IndexFault>().having(
            (f) => f.message,
            'message',
            'no doc carries the name logn',
          ),
        ),
      );
      expect(
        () => answerGet(index, ['login#x', 'login#x']),
        throwsA(
          isA<IndexFault>().having(
            (f) => f.message,
            'message',
            'no doc named login holds a section with the key x',
          ),
        ),
      );
    });

    test('E17: a fault of one code stays one IndexFault', () {
      expect(
        () => answerGet(index, ['logn', 'login']),
        throwsA(isA<IndexFault>()),
      );
    });
  });
  test('f01/us04/fr02: get feature:shop/cart prints the text of the nested feature', () async {
    final nested = await nestedIndexWith();
    final text = withApprovalHashes(nestedFiles())['docs/$cartFeature']!;
    expect(
      answerGet(nested, ['feature:shop/cart']).text,
      '==> shop/cart (feature) · $cartFeature · base ${baseHashOf(text)} <==\n$text',
    );
  });
}

String _codeOf(SpecstoneFault fault) =>
    (fault.toJson()['error']! as Map)['code']! as String;

IndexFaults _thrownFaults(DocIndex index, List<String> names) {
  try {
    answerGet(index, names);
  } on IndexFaults catch (faults) {
    return faults;
  }
  fail('$names did not throw IndexFaults');
}
