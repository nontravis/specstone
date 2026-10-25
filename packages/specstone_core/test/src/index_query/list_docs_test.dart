import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/list_docs.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';

void main() {
  late DocIndex index;
  setUpAll(() async => index = await indexWith());
  List<String> names(ReadAnswer a) => [
    for (final d in a.json['docs']! as List) (d as Map)['name']! as String,
  ];

  test('f01/us03/s1, f01/us03/fr01/e01: list feature gives every feature, one line each, in tree order', () async {
    final answer = answerList(index, 'feature', const ListFilters());
    expect(names(answer), ['login', 'signup']);
    expect(
      answer.text.split('\n').first,
      docLine(index, index.at('prds/features/f01_login/FEATURE.md')!),
    );
  });
  test('f01/us03/s2, f01/us03/fr02/e01: --under a story keeps only its FRs; --under a feature its stories', () async {
    expect(
      names(
        answerList(index, 'fr', const ListFilters(under: 'login/email_login')),
      ),
      [
        'login/email_login/validate_credentials',
        'login/email_login/lock_after_failures',
      ],
    );
    expect(
      names(answerList(index, 'user_story', const ListFilters(under: 'login'))),
      ['login/email_login', 'login/reset_password'],
    );
  });
  test(
    'f01/us03/s3, f01/us03/fr02/e02, s03/inv20: --cites reads frontmatter only',
    () async {
      const reset =
          'docs/prds/features/f01_login/us02_reset_password/USER_STORY.md';
      final cited = await indexWith({
        reset: '${loginProject[reset]}\nIt serves PG-01.\n',
      });
      expect(
        names(
          answerList(cited, 'user_story', const ListFilters(cites: 'PG-01')),
        ),
        ['login/email_login'],
      );
    },
  );
  test('f01/us03/fr02/e03: --cites a persona name', () async {
    expect(
      names(answerList(index, 'user_story', const ListFilters(cites: 'buyer'))),
      ['login/email_login'],
    );
  });
  test(
    "f01/us03/s6, f01/us03/fr02/e04: --status uses a feature's computed status",
    () async {
      expect(
        names(
          answerList(
            index,
            'feature',
            const ListFilters(status: 'implemented'),
          ),
        ),
        ['signup'],
      );
    },
  );
  test(
    'f01/us03/s4, f01/us03/fr02/e05: --status and --draft together',
    () async {
      expect(
        names(
          answerList(
            index,
            'user_story',
            const ListFilters(status: 'planned', draft: true),
          ),
        ),
        ['login/email_login'],
      );
    },
  );
  test('f01/us03/s5, f01/us03/fr02/e06: --no-implements keeps FRs with no implements entry', () async {
    expect(
      names(answerList(index, 'fr', const ListFilters(noImplements: true))),
      [
        'login/email_login/lock_after_failures',
        'login/reset_password/send_reset_link',
      ],
    );
  });
  test('f01/us03/fr02: --slug keeps docs whose aliases hold it', () async {
    expect(
      names(answerList(index, 'feature', const ListFilters(slug: 'sign-in'))),
      ['login'],
    );
  });
  test('f01/us03/s9, f01/us03/fr02/e07: --under a name no doc carries is doc_not_found', () async {
    expect(
      () => answerList(index, 'fr', const ListFilters(under: 'logn')),
      throwsA(isA<IndexFault>()),
    );
  });
  test(
    'f01/us03/s7, f01/us03/fr01/e02: no match is an empty list and success',
    () async {
      final answer = answerList(
        index,
        'feature',
        const ListFilters(status: 'deprecated'),
      );
      expect(answer.text, isEmpty);
      expect(answer.json['docs'], isEmpty);
      expect(answer.exitStatus, 0);
    },
  );
  test('f01/us03/s8, f01/us03/fr01/e03: an unknown doc type is doc_type_unknown naming it', () async {
    expect(
      () => answerList(index, 'featur', const ListFilters()),
      throwsA(
        isA<TemplateFault>().having(
          (f) => f.message,
          'message',
          'Could not find a doc type named "featur".',
        ),
      ),
    );
  });
  test('f01/us03/fr01/e05, s03/inv8: untyped docs are never listed', () async {
    expect([
      for (final t in index.set.docTypes)
        ...names(answerList(index, t.id, const ListFilters())),
    ], isNot(contains('prds/d01_context.md')));
  });
}
