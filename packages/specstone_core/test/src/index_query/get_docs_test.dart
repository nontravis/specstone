// The expected values are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/get_docs.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';

void main() {
  late DocIndex index;
  setUpAll(() async => index = await indexWith());
  String file(String docPath) => loginProject['docs/$docPath']!;

  test('f01/us04/s1, f01/us04/fr02: a bare name prints each doc carrying it as written, stories left out', () async {
    final text = answerGet(index, 'login').text;
    expect(
      text,
      startsWith(
        '==> login (feature) · prds/features/f01_login/FEATURE.md <==\n'
        '${file('prds/features/f01_login/FEATURE.md')}\n==> login (api) · specs/f01_login/API.md <==\n',
      ),
    );
    expect('==> '.allMatches(text), hasLength(5));
    expect(text, isNot(contains('login/email_login')));
  });
  test('f01/us04/s2, f01/us04/fr02/e01: one section from each doc that holds it, nothing else', () async {
    expect(
      answerGet(index, 'login#components').text,
      '==> login (architecture) · specs/f01_login/ARCHITECTURE.md · base 047e817f9707 <==\n'
      '## Components\n| Component | Responsibility |\n|-----------|----------------|\n'
      '| Login form | Collects the email and the password |\n',
    );
  });
  test(
    'f01/us04/s3, f01/us04/fr01: a doc type prefix narrows to one doc',
    () async {
      expect(
        '==> '.allMatches(answerGet(index, 'architecture:login').text),
        hasLength(1),
      );
    },
  );
  test('f01/us04/s4, f01/us04/fr02/e04, f01/us01/s7: an untyped doc reads by its DocPath, a section by its heading slug', () async {
    expect(
      answerGet(index, 'prds/d01_context.md#project-vision').text,
      '==> prds/d01_context.md · prds/d01_context.md · base 49851a1d1229 <==\n## Project vision\nOne SDD system; ค้นหา เอกสาร\n',
    );
  });
  test('f01/us04/s5: a name no doc carries is doc_not_found', () async {
    expect(() => answerGet(index, 'logn'), throwsA(isA<IndexFault>()));
  });
  test('f01/us04/s6, f01/us04/fr02/e02: a key no resolved doc holds is section_not_found naming name and key', () async {
    expect(
      () => answerGet(index, 'login#acceptance'),
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
      () => answerGet(index, 'login/email_login#agent-signs-in-with-email'),
      throwsA(isA<IndexFault>()),
    );
  });
  test(
    'f01/us04/fr02/e05: nothing is trimmed: comments and N/A sections print',
    () async {
      expect(
        answerGet(index, 'login/email_login/validate_credentials').text,
        contains('<!-- fill in later -->'),
      );
      expect(
        answerGet(index, 'login/email_login/lock_after_failures').text,
        contains('## Rationale\nN/A\n'),
      );
    },
  );
  test("review focus 1, f02 review focus 4: two sections with one header both print, in file order, under the first one's base", () async {
    final notes = await indexWith({
      'docs/notes.md': '# Notes\n\n## Notes\nfirst\n\n## Notes\nsecond\n',
    });
    expect(
      answerGet(notes, 'notes.md#notes').text,
      '==> notes.md · notes.md · base b640e840b19d <==\n## Notes\nfirst\n## Notes\nsecond\n',
    );
  });
  test('f01/us04/fr02: --json gives name, path, section, and text; no docType on an untyped doc', () async {
    expect(answerGet(index, 'prds/d01_context.md#project-name').json['docs'], [
      {
        'name': 'prds/d01_context.md',
        'path': 'prds/d01_context.md',
        'section': 'project-name',
        'base': '908c3a4a7ade',
        'text': '## Project name\n- **Human:** Specstone\n- **Code:** `specstone`\n',
      },
    ]);
  });
  test('review focus 5, preflight F15: a whole doc keeps its CRLF line endings as written', () async {
    final crlf = await indexWith({
      'docs/crlf.md': '# Crlf\r\n\r\n## A\r\nx\r\n',
    });
    expect(
      answerGet(crlf, 'crlf.md').text,
      '==> crlf.md · crlf.md <==\n# Crlf\r\n\r\n## A\r\nx\r\n',
    );
  });
  test('s02_api_get: a doc with no final newline prints as one that ends in a newline, JSON text verbatim', () async {
    const feature = '# Login\n\n## Problem\nNo final newline';
    final bare = await indexWith({featureKey: feature});
    final ended = await indexWith({featureKey: '$feature\n'});
    final answer = answerGet(bare, 'login');
    expect(answer.text, answerGet(ended, 'login').text);
    expect(answer.text, contains('$feature\n\n==> login (api) · '));
    expect(answerGet(bare, 'feature:login').text, endsWith('$feature\n'));
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
  test('f01/us04/s8, f01/us04/fr02/e08: a section read names its base; a whole-doc read prints none', () async {
    expect(
      answerGet(index, 'user_story:login/email_login#acceptance_criteria').text,
      startsWith(
        '==> login/email_login (user_story) · prds/features/f01_login/us01_email_login/USER_STORY.md · base f704efb17833 <==\n## Acceptance Criteria\n',
      ),
    );
    expect(
      answerGet(index, 'user_story:login/email_login').text,
      isNot(contains('· base')),
    );
  });
  test('f01/us04/s9, f01/us04/fr02/e09: a template section the doc lacks prints empty with the base of empty text', () async {
    expect(
      answerGet(index, 'login/email_login#rules').text,
      '==> login/email_login (user_story) · prds/features/f01_login/us01_email_login/USER_STORY.md · base e3b0c44298fc <==\n## Rules\n',
    );
    final doc =
        (answerGet(index, 'login/email_login#rules').json['docs']! as List)
                .single
            as Map;
    expect(doc['text'], '## Rules\n');
    expect(doc['base'], emptyBaseHash);
  });
  test('f01/us04/fr02/e10: --json bases list the title, every section, and every field, absent ones empty', () async {
    final story =
        (answerGet(index, 'user_story:login/email_login').json['docs']! as List)
                .single
            as Map;
    final bases = story['bases']! as Map;
    expect(bases['title'], 'ff5b5994d060');
    expect((bases['sections']! as Map)['acceptance_criteria'], 'f704efb17833');
    expect((bases['sections']! as Map)['rules'], emptyBaseHash);
    expect((bases['fields']! as Map)['status'], 'e721f319d794');
    expect((bases['fields']! as Map)['approved'], emptyBaseHash);
    expect(story.containsKey('base'), isFalse);
    final untyped =
        (answerGet(index, 'prds/d01_context.md').json['docs']! as List).single
            as Map;
    expect(((untyped['bases']! as Map)['sections']! as Map).keys, [
      'project-name',
      'project-vision',
    ]);
    expect((untyped['bases']! as Map)['fields'], isEmpty);
    expect(
      (untyped['bases']! as Map)['title'],
      baseHashOf('D-01 — Project context'),
    );
  });

  test('f02/us01/s3, PD4, HD4: bases hash the first of two key blocks of one field, a quoted spelling included', () async {
    final dup = await indexWith({
      'docs/prds/features/f01_login/us01_email_login/USER_STORY.md':
          '---\nstatus: planned\nvision:\n  - PV-01\nstatus: implemented\n---\n\n'
          '# Agent signs in with email\n\n## Use Case\nSign in.\n',
      'docs/prds/features/f01_login/FEATURE.md': '---\nvision:\n  - PV-01\n"status": planned\n---\n\n# Login\n\n## Problem\nUsers sign in.\n',
    });
    final story =
        (answerGet(dup, 'user_story:login/email_login').json['docs']! as List)
                .single
            as Map;
    expect(
      ((story['bases']! as Map)['fields']! as Map)['status'],
      baseHashOf('status: planned\n'),
    );
    final feature =
        (answerGet(dup, 'feature:login').json['docs']! as List).single as Map;
    final fields = (feature['bases']! as Map)['fields']! as Map;
    expect(fields['status'], baseHashOf('"status": planned\n'));
    expect(fields.containsKey('"status"'), isFalse);
  });
}
