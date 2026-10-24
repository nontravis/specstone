import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';

void main() {
  late DocIndex index;
  setUpAll(() async => index = await indexWith());
  List<String> paths(Iterable<IndexedDoc> docs) => [
    for (final d in docs) d.docPath,
  ];

  test('f01/us04/fr01, f01/us04/fr01/e01, s03/inv6: a bare name gives every doc carrying it, in tree order', () async {
    expect(paths(index.resolve('login')), [
      'prds/features/f01_login/FEATURE.md',
      'specs/f01_login/API.md',
      'specs/f01_login/ARCHITECTURE.md',
      'specs/f01_login/DOMAIN.md',
      'specs/f01_login/ERROR.md',
    ]);
  });
  test(
    'f01/us04/fr01/e02: a doc type prefix gives the one doc of that type',
    () async {
      expect(paths(index.resolve('architecture:login')), [
        'specs/f01_login/ARCHITECTURE.md',
      ]);
    },
  );
  test(
    'f01/us04/fr01/e03: a persona and an anti-persona share buyer',
    () async {
      expect(paths(index.resolve('buyer')), [
        'prds/personas/buyer/ANTI_PERSONA.md',
        'prds/personas/buyer/PERSONA.md',
      ]);
    },
  );
  test('f01/us04/fr01/e04: login never resolves to its stories; their own name does', () async {
    expect(paths(index.resolve('login/email_login')), [
      'prds/features/f01_login/us01_email_login/USER_STORY.md',
    ]);
  });
  test('f01/us04/fr01/e05: an untyped DocPath resolves to its doc', () async {
    expect(paths(index.resolve('prds/d01_context.md')), [
      'prds/d01_context.md',
    ]);
  });
  test('f01/us04/fr01/e05, s03/inv6: an untyped DocPath with a colon resolves to its doc when the text before it is no doc type', () async {
    final colon = await indexWith({'docs/notes/10:00.md': '# Standup\n'});
    expect(paths(colon.resolve('notes/10:00.md')), ['notes/10:00.md']);
  });
  test('f01/us04/fr01/e07: a colon argument whose prefix is no doc type and names no untyped doc is still doc_type_unknown', () async {
    final colon = await indexWith({'docs/notes/10:00.md': '# Standup\n'});
    expect(
      () => colon.resolve('notes/11:00.md'),
      throwsA(isA<TemplateFault>()),
    );
  });
  test(
    'f01/us04/fr01/e06, s05: a name no doc carries is doc_not_found, exit 64',
    () async {
      expect(
        () => index.resolve('nobody'),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.docNotFound)
              .having(
                (f) => f.message,
                'message',
                'no doc carries the name nobody',
              ),
        ),
      );
    },
  );
  test('f01/us04/fr01/e07: an unknown doc type prefix is doc_type_unknown, exit 64', () async {
    expect(
      () => index.resolve('architectur:login'),
      throwsA(
        isA<TemplateFault>()
            .having((f) => f.code, 'code', FaultCode.docTypeUnknown)
            .having(
              (f) => f.message,
              'message',
              'Could not find a doc type named "architectur".',
            ),
      ),
    );
  });
  test('f01/us04/fr01/e08: feature:billing when only a spec doc carries billing is doc_not_found', () async {
    final billing = await indexWith({
      'docs/specs/f05_billing/ARCHITECTURE.md': '# Billing\n',
    });
    expect(
      () => billing.resolve('feature:billing'),
      throwsA(
        isA<IndexFault>()
            .having((f) => f.code, 'code', IndexFaultCode.docNotFound)
            .having(
              (f) => f.message,
              'message',
              'no feature doc carries the name billing',
            ),
      ),
    );
    expect(paths(billing.resolve('architecture:billing')), [
      'specs/f05_billing/ARCHITECTURE.md',
    ]);
  });
  group('feature status', () {
    const written = '---\nstatus: implemented\n---\n\n# F\n';
    String story(String status) => '---\nstatus: $status\n---\n\n# S\n';
    late DocIndex statuses;
    String? statusOf(String folder) =>
        statuses.statusOf(statuses.at('prds/features/$folder/FEATURE.md')!);
    setUpAll(
      () async => statuses = await indexWith({
        'docs/prds/features/f03_empty/FEATURE.md': '# Empty\n',
        'docs/prds/features/f04_old/FEATURE.md': written,
        'docs/prds/features/f04_old/us01_a/USER_STORY.md': story('deprecated'),
        'docs/prds/features/f04_old/us02_b/USER_STORY.md': story('deprecated'),
        'docs/prds/features/f05_mixed/FEATURE.md': written,
        'docs/prds/features/f05_mixed/us01_a/USER_STORY.md': story(
          'implemented',
        ),
        'docs/prds/features/f05_mixed/us02_b/USER_STORY.md': story(
          'deprecated',
        ),
        'docs/prds/features/f06_half/FEATURE.md': written,
        'docs/prds/features/f06_half/us01_a/USER_STORY.md': story(
          'implemented',
        ),
        'docs/prds/features/f06_half/us02_b/USER_STORY.md': story('planned'),
      }),
    );
    test('f01/us02/fr02, f01/us02/fr02/e01, s03/inv17: a feature with no story is planned', () {
      expect(statusOf('f03_empty'), 'planned');
    });
    test('f01/us02/fr02/e02: every story deprecated gives deprecated', () {
      expect(statusOf('f04_old'), 'deprecated');
    });
    test(
      'f01/us02/fr02/e03: implemented and deprecated stories give implemented',
      () {
        expect(statusOf('f05_mixed'), 'implemented');
      },
    );
    test('f01/us02/fr02/e04, f01/us02/fr02/e05: one planned story gives planned, whatever the feature writes', () {
      expect(statusOf('f06_half'), 'planned');
      expect(statusOf('f02_signup'), 'implemented');
    });
  });
  test('s03/inv10: with prd-core and software-tech, feature, user_story, fr, and nf are the chain types', () async {
    expect(
      [
        for (final t in index.set.docTypes)
          if (index.isChainType(t.id)) t.id,
      ],
      ['feature', 'fr', 'nf', 'user_story'],
    );
  });
  test('s03/inv7, s03/inv11: children, subtree, and chain follow the parent doc in tree order', () async {
    final feature = index.at('prds/features/f01_login/FEATURE.md')!;
    expect(paths(index.childrenOf(feature)), [
      'prds/features/f01_login/us01_email_login/USER_STORY.md',
      'prds/features/f01_login/us02_reset_password/USER_STORY.md',
      'specs/f01_login/API.md',
      'specs/f01_login/ARCHITECTURE.md',
      'specs/f01_login/DOMAIN.md',
      'specs/f01_login/ERROR.md',
    ]);
    final fr = index.at(
      'prds/features/f01_login/us01_email_login/fr01_validate_credentials.md',
    )!;
    expect(paths(index.chainOf(fr)), [
      fr.docPath,
      'prds/features/f01_login/us01_email_login/USER_STORY.md',
      feature.docPath,
    ]);
    expect(index.subtreeOf(feature).length, 11);
    expect(index.under('login').length, 11);
  });
}
