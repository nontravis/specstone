import 'dart:io';

import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';
import '../../helpers/nested_fixture.dart';

void main() {
  const colonSkip = 'Windows forbids : in file names, so no such doc exists';
  late DocIndex index;
  setUpAll(() async => index = await indexWith());
  List<String> paths(Iterable<IndexedDoc> docs) => [
    for (final d in docs) d.docPath,
  ];

  test('f01/us04/fr01: an address with a #<section key> or an @<hash> is argument_invalid naming it', () async {
    for (final address in [
      'feature:login#problem',
      'login#problem',
      'feature:login@7e11fc4a24d2',
    ]) {
      expect(
        () => index.resolve(address),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
              .having((f) => f.message, 'message', contains(address)),
        ),
        reason: address,
      );
    }
  });
  test('f01/us04/fr01: resolve reads the path first, so a whole text naming a doc wins over its #, and a # or @ '
      'suffix on text that names no doc is doc_not_found', () async {
    final root = await writeLoginProject();
    for (final name in ['c#_tips.md', 'a@7e11fc4a24d2.md']) {
      File('${root.path}/docs/notes/$name')
        ..createSync(recursive: true)
        ..writeAsStringSync('# Note\n');
    }
    final session = openSession(root);
    addTearDown(session.close);
    final hashed = session.index;
    for (final address in [
      'notes/c#_tips.md',
      'docs/notes/c#_tips.md',
      'notes/a@7e11fc4a24d2.md',
    ]) {
      expect(paths(hashed.resolve(address)), [
        address.replaceFirst('docs/', ''),
      ], reason: address);
    }
    for (final address in ['nosuch#problem', 'nosuch@7e11fc4a24d2']) {
      expect(
        () => hashed.resolve(address),
        throwsA(
          isA<IndexFault>().having(
            (f) => f.code,
            'code',
            IndexFaultCode.docNotFound,
          ),
        ),
        reason: address,
      );
    }
  });
  test('f01/us04/fr01: ofTypeNamed reads the docs of one type and Name from the index map, in tree order', () async {
    expect(paths(index.ofTypeNamed('feature', 'login')), [
      'prds/features/f01_login/FEATURE.md',
    ]);
    expect(index.ofTypeNamed('user_story', 'login'), isEmpty);
    expect(index.ofTypeNamed('nosuch', 'login'), isEmpty);
  });
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
  }, skip: Platform.isWindows ? colonSkip : false);
  test('f01/us04/fr01/e07: a colon argument whose prefix is no doc type and names no untyped doc is still doc_type_unknown', () async {
    final colon = await indexWith({'docs/notes/10:00.md': '# Standup\n'});
    expect(
      () => colon.resolve('notes/11:00.md'),
      throwsA(isA<TemplateFault>()),
    );
  }, skip: Platform.isWindows ? colonSkip : false);
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
  group('a path to a doc', () {
    const story = 'prds/features/f01_login/us01_email_login/USER_STORY.md';
    TypeMatcher<IndexFault> notFound(String message) => isA<IndexFault>()
        .having((f) => f.code, 'code', IndexFaultCode.docNotFound)
        .having((f) => f.message, 'message', message);

    /// Returns the index of a login project read from [folder] under it.
    Future<DocIndex> indexFrom(
      String folder, [
      Map<String, String> extra = const {},
    ]) async {
      final root = await writeLoginProject(extra: extra);
      final session = ReadSession.open(
        templates: TemplateResolver(),
        workingDirectory: Directory.fromUri(root.uri.resolve(folder)),
        homeDirectory: null,
      );
      addTearDown(session.close);
      return session.index;
    }

    test("f01/us04/fr01/e09: a typed doc's DocPath resolves to that doc", () {
      expect(paths(index.resolve(featureDoc)), [featureDoc]);
      expect(paths(index.resolve(story)), [story]);
    });
    test('f01/us04/fr01/e10: docs/ and a DocPath resolves to that doc', () {
      expect(paths(index.resolve('docs/$featureDoc')), [featureDoc]);
      expect(paths(index.resolve('docs/prds/d01_context.md')), [
        'prds/d01_context.md',
      ]);
    });
    test('f01/us04/fr01/e11: a file path from the working directory resolves when the file lies inside the docs root', () async {
      final nested = await indexFrom('docs/prds/features/f01_login/');
      expect(paths(nested.resolve('FEATURE.md')), [featureDoc]);
      expect(paths(nested.resolve('us01_email_login/USER_STORY.md')), [story]);
      expect(paths(nested.resolve('../../d01_context.md')), [
        'prds/d01_context.md',
      ]);
      final root = await writeLoginProject();
      final session = openSession(root);
      addTearDown(session.close);
      final absolute = File.fromUri(root.uri.resolve(featureKey)).path;
      expect(paths(session.index.resolve(absolute)), [featureDoc]);
    });
    test('f01/us04/fr01/e11: a path to a file outside the docs root, or to a folder, is doc_not_found', () async {
      final nested = await indexFrom('docs/prds/', {'NOTES.md': '# Notes\n'});
      for (final outside in [
        '../../NOTES.md',
        '../../.specstone/config.yaml',
        'features/f01_login',
      ]) {
        expect(
          () => nested.resolve(outside),
          throwsA(notFound('no doc carries the name $outside')),
        );
      }
    });
    test('f01/us04/fr01/e12: <doc type>:<path> resolves to the doc at the path only when it has that doc type', () {
      expect(paths(index.resolve('feature:$featureDoc')), [featureDoc]);
      expect(paths(index.resolve('feature:docs/$featureDoc')), [featureDoc]);
      expect(
        () => index.resolve('architecture:$featureDoc'),
        throwsA(notFound('no architecture doc carries the name $featureDoc')),
      );
    });
    test('f01/us04/fr01/e13: a name wins over a path, and a DocPath over a path from the working directory', () async {
      final nested = await indexFrom('docs/prds/', {
        'docs/docs/README.md': '# Docs readme\n',
        'docs/prds/prds/PROJECT.md': '# Nested project\n',
      });
      expect(paths(nested.resolve('docs/README.md')), ['docs/README.md']);
      expect(paths(nested.resolve('prds/PROJECT.md')), ['prds/PROJECT.md']);
      expect(paths(nested.resolve('PROJECT.md')), ['prds/PROJECT.md']);
    });
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
  group('nested feature status', () {
    test('f01/us02/fr02/e06, sf-c3: shop is planned while pay/refund is, and implemented once all four stories are', () async {
      final half = await nestedIndexWith();
      expect(half.statusOf(half.at(shopFeature)!), 'planned');
      expect(half.statusOf(half.at(cartFeature)!), 'implemented');
      expect(half.statusOf(half.at(payFeature)!), 'planned');
      final done = await nestedIndexWith({
        'docs/$payRefund': nestedFiles()['docs/$payRefund']!.replaceFirst(
          'status: planned',
          'status: implemented',
        ),
      });
      expect(done.statusOf(done.at(shopFeature)!), 'implemented');
    });
  });
}
