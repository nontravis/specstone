// The expected lines are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/structure.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';

void main() {
  late DocIndex index;
  setUpAll(() async => index = await indexWith());
  int tokensOf(String key) => tokenSizeOf(loginProject[key]!);

  test('f01/us02/s1, f01/us02/fr01/e01: the whole tree, tops in tree order, children two spaces deeper', () async {
    final lines = answerStructure(index).text.split('\n');
    expect(lines.take(4), [
      'features (features) — Feature index · ${tokensOf('docs/prds/FEATURES.md')} tokens',
      'gnfr (gnfr) — Global non-functional requirements · ${tokensOf('docs/prds/GNFR.md')} tokens',
      'project (project) — Project context · ${tokensOf('docs/prds/PROJECT.md')} tokens',
      'login (feature) — Login · planned · ${tokensOf('docs/prds/features/f01_login/FEATURE.md')} tokens',
    ]);
    expect(
      lines[4],
      '  login/email_login (user_story) — Agent signs in with email · planned · draft · '
      '${tokensOf('docs/prds/features/f01_login/us01_email_login/USER_STORY.md')} tokens',
    );
    expect(lines.sublist(5, 8).map((l) => l.trim().split(' ').first), [
      'login/email_login/validate_credentials',
      'login/email_login/login_latency',
      'login/email_login/lock_after_failures',
    ]);
  });
  test('f01/us02/s4, f01/us02/fr01/e01, s03/inv8: untyped docs follow under their folder line', () async {
    final text = answerStructure(index).text;
    expect(
      text,
      endsWith(
        './\n  README.md — Readme · ${tokensOf('docs/README.md')} tokens\n'
        'prds/\n  prds/d01_context.md — D-01 — Project context · ${tokensOf('docs/prds/d01_context.md')} tokens\n',
      ),
    );
  });
  test('f01/us02/s2, f01/us02/fr01/e02: login prints the feature subtree once, spec docs inside it', () async {
    final lines = answerStructure(
      index,
      target: 'login',
    ).text.trim().split('\n');
    expect(lines, hasLength(11));
    expect(lines.first, startsWith('login (feature)'));
  });
  test(
    'f01/us02/s3, f01/us02/fr02: a feature line shows the computed status',
    () async {
      expect(
        answerStructure(index, target: 'signup').text,
        startsWith('signup (feature) — Sign up · implemented · '),
      );
    },
  );
  test('f01/us02/fr01/e03: a target no doc carries is doc_not_found', () async {
    expect(
      () => answerStructure(index, target: 'logn'),
      throwsA(isA<IndexFault>()),
    );
  });
  test(
    'f01/us02/fr01/e04: an unknown doc type prefix is doc_type_unknown',
    () async {
      expect(
        () => answerStructure(index, target: 'featur:login'),
        throwsA(isA<TemplateFault>()),
      );
    },
  );
  test('f01/us02/fr01/e05: an untyped DocPath target prints its one line', () async {
    expect(
      answerStructure(index, target: 'prds/d01_context.md').text,
      'prds/d01_context.md — D-01 — Project context · ${tokensOf('docs/prds/d01_context.md')} tokens\n',
    );
  });
  test(
    'f01/us02/fr01: --json nests children and lists untyped docs by folder',
    () async {
      final json = answerStructure(index, target: 'login/email_login').json;
      final story = (json['docs']! as List).single as Map<String, Object?>;
      expect(story.keys.toList(), [
        'name',
        'docType',
        'path',
        'title',
        'status',
        'draft',
        'tokens',
        'children',
      ]);
      expect(
        ((story['children']! as List).first as Map)['name'],
        'login/email_login/validate_credentials',
      );
      expect(answerStructure(index).json['untyped'], [
        {
          'folder': './',
          'docs': [
            {
              'name': 'README.md',
              'path': 'README.md',
              'title': 'Readme',
              'draft': false,
              'tokens': tokensOf('docs/README.md'),
            },
          ],
        },
        {
          'folder': 'prds/',
          'docs': [
            {
              'name': 'prds/d01_context.md',
              'path': 'prds/d01_context.md',
              'title': 'D-01 — Project context',
              'draft': false,
              'tokens': tokensOf('docs/prds/d01_context.md'),
            },
          ],
        },
      ]);
    },
  );
  test('plan ruling: resolve and childrenOf return lists that cannot be sorted in place', () async {
    final feature = index.resolve('login').first;
    int keep(IndexedDoc a, IndexedDoc b) => 0;
    expect(() => index.resolve('login').sort(keep), throwsUnsupportedError);
    expect(() => index.childrenOf(feature).sort(keep), throwsUnsupportedError);
  });
}
