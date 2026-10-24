import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/index_query/search_docs.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';

void main() {
  late DocIndex index;
  setUpAll(() async => index = await indexWith());
  List<String> heads(ReadAnswer a) => [
    for (final l in a.text.split('\n'))
      if (l.isNotEmpty && !l.startsWith('  ')) l,
  ];

  test('f01/us06/s1, f01/us06/fr01: hits name doc and section, with type, title, and an indented snippet', () async {
    final answer = answerSearch(
      index,
      'lock the account',
      const SearchOptions(),
    );
    expect(
      heads(answer),
      containsAll([
        'login/email_login/lock_after_failures#statement (fr) — Lock after failures',
        'login/email_login#acceptance_criteria (user_story) — Agent signs in with email',
      ]),
    );
    expect(answer.text, contains('\n  '));
    expect(answer.text, contains('lock the account'));
  });
  test('f01/us06/s2, f01/us06/fr01/e02, f01/us06/fr01/e06, f01/us01/s7: a Thai phrase hits the untyped doc by DocPath and heading slug', () async {
    expect(heads(answerSearch(index, 'ค้นหา', const SearchOptions())), [
      'prds/d01_context.md#project-vision — D-01 — Project context',
    ]);
  });
  test(
    'f01/us06/s2, f01/us06/fr01/e03: a word part matches the longer word',
    () async {
      expect(
        heads(answerSearch(index, 'ount', const SearchOptions())),
        contains(
          'login/email_login/lock_after_failures#statement (fr) — Lock after failures',
        ),
      );
    },
  );
  test(
    'f01/us06/s3, f01/us06/fr01/e05: an alias hit points at the first section',
    () async {
      expect(
        heads(answerSearch(index, 'sign-in', const SearchOptions())),
        contains('login#problem (feature) — Login'),
      );
    },
  );
  test('f01/us06/s5, f01/us06/fr01/e04: quotes, asterisks, AND, and NEAR( are plain text', () async {
    for (final query in ['"lock', 'account*', 'the AND account', 'NEAR(lock']) {
      expect(answerSearch(index, query, const SearchOptions()).exitStatus, 0);
    }
  });
  test(
    'f01/us06/s6, f01/us06/fr01/e07: no hit is an empty answer and success',
    () async {
      final answer = answerSearch(index, 'zzqqxx', const SearchOptions());
      expect(answer.text, isEmpty);
      expect(answer.json['hits'], isEmpty);
      expect(answer.exitStatus, 0);
    },
  );
  test('f01/us06/s7, f01/us06/fr01/e01: fewer than 3 characters is query_too_short', () {
    expect(
      () => checkQuery('ui'),
      throwsA(
        isA<IndexFault>().having(
          (f) => f.message,
          'message',
          'a search needs at least 3 characters: ui',
        ),
      ),
    );
    expect(() => checkQuery('ค้น'), returnsNormally);
  });
  test('f01/us06/s4, f01/us06/fr02, f01/us06/fr02/e02: --type and --under narrow, --limit caps', () async {
    final answer = answerSearch(
      index,
      'system shall',
      const SearchOptions(docTypeId: 'fr', under: 'login', limit: 2),
    );
    expect(heads(answer), hasLength(2));
    expect(
      heads(answer)
          .every((h) => h.startsWith('login/') && h.contains(' (fr) ')),
      isTrue,
    );
  });
  test(
    'f01/us06/fr02/e01: 20 hits at most by default, untyped docs included',
    () async {
      final zebras = await indexWith({
        for (var i = 1; i <= 25; i++)
          'docs/z/zebra_$i.md': '# Z\n\n## Body\nzebra\n',
      });
      final hits = heads(answerSearch(zebras, 'zebra', const SearchOptions()));
      expect(hits, hasLength(20));
      expect(hits.every((h) => h.startsWith('z/zebra_')), isTrue);
    },
  );
  test('f01/us06/fr02/e03: an unknown --type is doc_type_unknown', () async {
    expect(
      () => answerSearch(index, 'login', const SearchOptions(docTypeId: 'frr')),
      throwsA(isA<TemplateFault>()),
    );
  });
  test(
    'f01/us06/fr02/e04: an --under no doc carries is doc_not_found',
    () async {
      expect(
        () => answerSearch(index, 'login', const SearchOptions(under: 'logn')),
        throwsA(isA<IndexFault>()),
      );
    },
  );
  test('f01/us06/fr02/e05: --type drops untyped docs', () async {
    expect(
      heads(
        answerSearch(index, 'ค้นหา', const SearchOptions(docTypeId: 'feature')),
      ),
      isEmpty,
    );
  });
  test('f01/us06/fr02/e06: a --limit that is not a positive integer is argument_invalid', () {
    for (final v in ['0', '-5', 'ten']) {
      expect(
        () => parsePositiveOption('--limit', v),
        throwsA(
          isA<IndexFault>().having(
            (f) => f.message,
            'message',
            '--limit takes a positive integer, not $v',
          ),
        ),
      );
    }
  });
  test(
    'plan decision 11: a title hit on a doc with no section prints no key',
    () async {
      final answer = answerSearch(index, 'Readme', const SearchOptions());
      expect(heads(answer), contains('README.md — Readme'));
      expect(
        (answer.json['hits']! as List)
            .cast<Map<String, Object?>>()
            .firstWhere((h) => h['name'] == 'README.md')
            .containsKey('section'),
        isFalse,
      );
    },
  );
  test('f01/us06/fr01: a snippet over several lines prints as one indented line, JSON keeps it as indexed', () async {
    final multi = await indexWith({
      'docs/m/multi.md': '# M\n\n## Body\nalpha beta\ngamma delta\n',
    });
    final answer = answerSearch(multi, 'alpha', const SearchOptions());
    expect(answer.text, 'm/multi.md#body — M\n  alpha beta gamma delta\n');
    expect(
      ((answer.json['hits']! as List).single as Map)['snippet'],
      'alpha beta\ngamma delta\n',
    );
  });
}
