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
import '../../helpers/shipped_pins.dart';
import '../../helpers/temp_tree.dart';

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
      () => colon.resolve('notes:11:00.md'),
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
  test('index_query/read_doc_section/resolve_doc_name E18: a target whose text before its first colon is no slug is doc_not_found, never doc_type_unknown', () async {
    for (final address in ['Grid:login', 'check architecture:login']) {
      expect(
        () => index.resolve(address),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.docNotFound)
              .having(
                (f) => f.message,
                'message',
                'no doc carries the name $address',
              ),
        ),
        reason: address,
      );
    }
  });
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
    const story = '# S\n';
    String record(List<String> statuses) =>
        '---\nstatuses:\n${[for (final s in statuses) "  - '$s'\n"].join()}'
        '---\n\n# Record\n';
    late DocIndex statuses;
    String? statusOf(String folder) =>
        statuses.statusOf(statuses.at('prds/features/$folder/FEATURE.md')!);
    setUpAll(
      () async => statuses = await indexWith({
        ...loginRecords,
        'docs/prds/features/f03_empty/FEATURE.md': '# Empty\n',
        'docs/prds/features/f04_old/FEATURE.md': written,
        'docs/prds/features/f04_old/us01_a/USER_STORY.md': story,
        'docs/prds/features/f04_old/us02_b/USER_STORY.md': story,
        'docs/specs/f04_old/IMPLEMENTATION.md': record([
          'a:deprecated',
          'b:deprecated',
        ]),
        'docs/prds/features/f05_mixed/FEATURE.md': written,
        'docs/prds/features/f05_mixed/us01_a/USER_STORY.md': story,
        'docs/prds/features/f05_mixed/us02_b/USER_STORY.md': story,
        'docs/specs/f05_mixed/IMPLEMENTATION.md': record([
          'a:implemented',
          'b:deprecated',
        ]),
        'docs/prds/features/f06_half/FEATURE.md': written,
        'docs/prds/features/f06_half/us01_a/USER_STORY.md': story,
        'docs/prds/features/f06_half/us02_b/USER_STORY.md': story,
        'docs/specs/f06_half/IMPLEMENTATION.md': record([
          'a:implemented',
          'b:planned',
        ]),
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
      final half = await nestedIndexWith(nestedRecords());
      expect(half.statusOf(half.at(shopFeature)!), 'planned');
      expect(half.statusOf(half.at(cartFeature)!), 'implemented');
      expect(half.statusOf(half.at(payFeature)!), 'planned');
      final done = await nestedIndexWith(nestedRecords(refund: 'implemented'));
      expect(done.statusOf(done.at(shopFeature)!), 'implemented');
    });
  });
  group('target-scoped names', () {
    const featurePath = 'prds/features/f02_feedback/f03_toast/FEATURE.md';
    const flutterArch = 'specs/flutter/f02_feedback/f03_toast/ARCHITECTURE.md';
    const jasprArch = 'specs/jaspr/f02_feedback/f03_toast/ARCHITECTURE.md';

    /// Returns the index of a two-target fixture: the feature `feedback/toast`,
    /// its architecture doc in both targets, its domain doc in flutter alone.
    Future<DocIndex> nameTargets() async {
      final root = await writeTree({
        '.specstone/templates/architecture.yaml':
            'id: architecture\nper_target: true\n',
        '.specstone/templates/domain.yaml': 'id: domain\nper_target: true\n',
        '.specstone/templates/implementation.yaml':
            'id: implementation\n'
            'description: One feature record per target.\n'
            'path: specs/f{nn}_{slug}/IMPLEMENTATION.md\n'
            'parent: feature\n'
            'per_target: true\n'
            'fields:\n'
            '  - id: statuses\n'
            '    type: record_status\n'
            '    list: true\n',
        '.specstone/templates/feature.yaml': 'max_depth: 1\n',
        '.specstone/config.yaml':
            '${shippedPinsConfig()}targets:\n'
            '  flutter:\n    code_root: flutter_lib\n'
            '  jaspr:\n    code_root: jaspr_lib\n',
        'flutter_lib/.keep': '',
        'jaspr_lib/.keep': '',
        'docs/$featurePath': '# Toast\n\n## Problem\nBurnt toast.\n',
        'docs/$flutterArch': '# Toast architecture\n',
        'docs/$jasprArch': '# Toast architecture\n',
        'docs/specs/flutter/f02_feedback/f03_toast/DOMAIN.md':
            '# Toast domain\n',
        'docs/specs/flutter/f02_feedback/IMPLEMENTATION.md': '# Record\n',
        'docs/specs/jaspr/f02_feedback/IMPLEMENTATION.md': '# Record\n',
      });
      final session = openSession(root);
      addTearDown(session.close);
      return session.index;
    }

    test('index_query/read_doc_section/resolve_doc_name E19: a typed name two targets twin resolves to both, in tree order', () async {
      final twins = await nameTargets();
      expect(paths(twins.resolve('architecture:feedback/toast')), [
        flutterArch,
        jasprArch,
      ]);
    });
    test("index_query/read_doc_section/resolve_doc_name E20: a name stays in its target, a bare name gives the feature and that target's spec docs", () async {
      final scoped = await nameTargets();
      expect(
        paths(
          scoped.resolve('architecture:feedback/toast', codeTarget: 'jaspr'),
        ),
        [jasprArch],
      );
      expect(
        () => scoped.resolve('domain:feedback/toast', codeTarget: 'jaspr'),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.docNotFound)
              .having(
                (f) => f.message,
                'message',
                'no domain doc carries the name feedback/toast',
              ),
        ),
      );
      expect(paths(scoped.resolve('feedback/toast', codeTarget: 'jaspr')), [
        featurePath,
        jasprArch,
      ]);
    });
    test('index_query/read_doc_section/resolve_doc_name E21: a DocPath names its doc whatever target the flag names', () async {
      final cross = await nameTargets();
      expect(
        paths(
          cross.resolve(
            'specs/flutter/f02_feedback/f03_toast/DOMAIN.md',
            codeTarget: 'jaspr',
          ),
        ),
        ['specs/flutter/f02_feedback/f03_toast/DOMAIN.md'],
      );
    });
    test('index_query/read_doc_section/resolve_doc_name E22: a target targets: holds none of, or any target where it names none, is argument_invalid', () async {
      final named = await nameTargets();
      expect(
        () => named.resolve('architecture:feedback/toast', codeTarget: 'web'),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
              .having(
                (f) => f.message,
                'message',
                '--target web: the code targets are flutter, jaspr',
              ),
        ),
      );
      expect(
        () => index.resolve('login', codeTarget: 'flutter'),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
              .having(
                (f) => f.message,
                'message',
                '--target flutter: this project names no code target',
              ),
        ),
      );
    });
  });
  group('status per code target', () {
    // The fixture writes `status: implemented` on every doc, so the tests
    // prove the per-target record reads replace it (INV-29), and the no-record
    // project keeps the written status (E12).
    const shopPath = 'prds/features/f01_shop/FEATURE.md';
    const cartPath = 'prds/features/f01_shop/f01_cart/FEATURE.md';
    const storyPath = 'prds/features/f01_shop/f01_cart/us01_add/USER_STORY.md';
    const frPath = 'prds/features/f01_shop/f01_cart/us01_add/fr01_check.md';
    const topStory = 'prds/features/f01_shop/us01_greet/USER_STORY.md';

    String feature(String title) =>
        '---\nstatus: implemented\n---\n\n# $title\n\n## Problem\nNeed it.\n';
    String story(String title) =>
        '---\nstatus: implemented\n---\n\n# $title\n\n## Use Case\nUse it.\n';
    String fr(String title) => '---\nstatus: implemented\n---\n\n# $title\n';
    String record(String lines) => lines.isEmpty
        ? '# Record\n'
        : '---\nstatuses:\n$lines---\n\n# Record\n';

    /// The record doc type `domain:index_query` INV-31 gives: found by its
    /// `record_status` field, per-target, its Name the feature's.
    const recordLayerPath = '.specstone/templates/implementation.yaml';
    const recordLayer =
        'id: implementation\n'
        'description: One feature record per target.\n'
        'path: specs/f{nn}_{slug}/IMPLEMENTATION.md\n'
        'parent: feature\n'
        'per_target: true\n'
        'fields:\n'
        '  - id: statuses\n'
        '    type: record_status\n'
        '    list: true\n';
    const nestingLayer = '.specstone/templates/feature.yaml';

    /// Returns the index of a two-target fixture whose docs and records
    /// [records] write, keyed by file path under the project root.
    ///
    /// [noRecordType] drops the record layer and reads a `prd-core`-only,
    /// `code_root:`-only config, whose unnamed target holds no record (E12).
    Future<DocIndex> targeted({
      Map<String, String> records = const {},
      Map<String, String> extra = const {},
      bool noRecordType = false,
    }) async {
      final root = await writeTree({
        if (!noRecordType) recordLayerPath: recordLayer,
        if (!noRecordType) nestingLayer: 'max_depth: 1\n',
        '.specstone/config.yaml': noRecordType
            ? '${shippedPinsConfig(['prd-core'])}code_root: app\n'
            : '${shippedPinsConfig()}targets:\n'
                  '  flutter:\n    code_root: flutter_lib\n'
                  '  jaspr:\n    code_root: jaspr_lib\n',
        'flutter_lib/.keep': '',
        'jaspr_lib/.keep': '',
        'docs/prds/features/f01_shop/FEATURE.md': feature('Shop'),
        'docs/$topStory': story('Agent greets'),
        'docs/prds/features/f01_shop/f01_cart/FEATURE.md': feature('Cart'),
        'docs/$storyPath': story('Agent adds an item'),
        'docs/$frPath': fr('Check the stock'),
        ...records,
        ...extra,
      });
      final session = openSession(root);
      addTearDown(session.close);
      return session.index;
    }

    test('f01/us02/fr02/e12: a merged set with no record doc type computes each status from the written status, with no target', () async {
      final plain = await targeted(noRecordType: true);
      expect(plain.set.recordDocType, isNull);
      expect(plain.statusOf(plain.at(shopPath)!), 'implemented');
      expect(plain.statusOf(plain.at(storyPath)!), 'implemented');
    });
    test("f01/us02/fr02/e07: a target's record skips the feature and each of its stories there, while the other target computes from its own records", () async {
      final skipped = await targeted(
        records: {
          'docs/specs/flutter/f01_shop/IMPLEMENTATION.md': record(
            '  - ":skipped:no shop on the web"\n',
          ),
          'docs/specs/jaspr/f01_shop/IMPLEMENTATION.md': record(''),
        },
      );
      final shop = skipped.at(shopPath)!;
      expect(skipped.statusOf(shop, codeTarget: 'flutter'), 'skipped');
      expect(
        skipped.statusOf(skipped.at(storyPath)!, codeTarget: 'flutter'),
        'skipped',
      );
      expect(skipped.statusOf(shop, codeTarget: 'jaspr'), 'planned');
    });
    test('f01/us02/fr02/e13: a skip on an ancestor record skips the nested feature itself, which holds no record of its own there', () async {
      final skipped = await targeted(
        records: {
          'docs/specs/flutter/f01_shop/IMPLEMENTATION.md': record(
            '  - ":skipped:no shop on the web"\n',
          ),
        },
      );
      final cart = skipped.at(cartPath)!;
      expect(cart.docTypeId, 'feature');
      expect(skipped.statusOf(cart, codeTarget: 'flutter'), 'skipped');
      expect(
        skipped.statusOf(skipped.at(storyPath)!, codeTarget: 'flutter'),
        'skipped',
        reason: 'a skip above a feature skips each of its stories too',
      );
    });
    test('f01/us02/fr02/e08: every story skipped with no feature entry gives skipped there', () async {
      final allSkipped = await targeted(
        records: {
          'docs/specs/flutter/f01_shop/IMPLEMENTATION.md': record(
            '  - greet:skipped\n  - cart:skipped\n'
            '  - cart/add:skipped\n  - cart/add/check:skipped\n',
          ),
        },
      );
      expect(
        allSkipped.statusOf(allSkipped.at(shopPath)!, codeTarget: 'flutter'),
        'skipped',
      );
    });
    test(
      'f01/us02/fr02/e09: one skipped story counts toward no other status',
      () async {
        final oneSkipped = await targeted(
          records: {
            'docs/specs/flutter/f01_shop/IMPLEMENTATION.md': record(
              '  - greet:skipped\n',
            ),
            'docs/specs/flutter/f01_shop/f01_cart/IMPLEMENTATION.md': record(
              '  - add:implemented\n  - add/check:implemented\n',
            ),
          },
        );
        expect(
          oneSkipped.statusOf(oneSkipped.at(shopPath)!, codeTarget: 'flutter'),
          'implemented',
        );
      },
    );
    test('f01/us02/fr02/e10: no record for the feature and no skip above gives planned per story entry, planned everywhere with none', () async {
      final bare = await targeted(
        records: {
          'docs/specs/jaspr/f01_shop/IMPLEMENTATION.md': record(
            '  - greet:planned\n  - cart/add:planned\n',
          ),
        },
      );
      expect(
        bare.statusOf(bare.at(storyPath)!, codeTarget: 'jaspr'),
        'planned',
      );
      final fresh = await targeted(
        records: {'docs/specs/flutter/f01_shop/IMPLEMENTATION.md': record('')},
      );
      expect(
        fresh.statusOf(fresh.at(shopPath)!, codeTarget: 'flutter'),
        'planned',
      );
    });
    test('f01/us02/fr02/e11: one sub-feature skipped, the other implemented, gives implemented there', () async {
      final nested = await targeted(
        records: {
          'docs/specs/flutter/f01_shop/IMPLEMENTATION.md': record(
            '  - cart:skipped\n  - greet:implemented\n',
          ),
        },
      );
      expect(
        nested.statusOf(nested.at(cartPath)!, codeTarget: 'flutter'),
        'skipped',
      );
      expect(
        nested.statusOf(nested.at(shopPath)!, codeTarget: 'flutter'),
        'implemented',
      );
    });
    test("domain:index_query INV-29, consistency_check/find_prd_spec_disagreements/check_record_entries: an entry an ancestor record writes for a nested feature's story gives it no status and no entry, as check resolves it nowhere", () async {
      final misplaced = await targeted(
        records: {
          'docs/specs/flutter/f01_shop/IMPLEMENTATION.md': record(
            '  - cart/add:implemented\n',
          ),
        },
      );
      final add = misplaced.at(storyPath)!;
      expect(misplaced.statusOf(add, codeTarget: 'flutter'), 'planned');
      expect(misplaced.recordEntryOf(add, codeTarget: 'flutter'), isNull);
    });
    test('f01/us02/fr02/e01: a feature with no story is planned outside every skip and skipped under one, with no story or no record of its own too', () async {
      final empty = await targeted(
        extra: {'docs/prds/features/f02_none/FEATURE.md': feature('None')},
        records: {
          'docs/specs/flutter/f02_none/IMPLEMENTATION.md': record(
            '  - ":skipped:no web view on the web"\n',
          ),
        },
      );
      final none = empty.at('prds/features/f02_none/FEATURE.md')!;
      expect(empty.statusOf(none, codeTarget: 'flutter'), 'skipped');
      expect(empty.statusOf(none, codeTarget: 'jaspr'), 'planned');
    });
  });
}
