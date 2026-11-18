import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/feature_catalog.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/list_docs.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/index_query/structure.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart' as check;
import '../../helpers/index_fixture.dart';
import '../../helpers/nested_fixture.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/temp_tree.dart';

void main() {
  late DocIndex index;
  setUpAll(() async => index = await indexWith(loginRecords));
  List<String> names(ReadAnswer a) => [
    for (final d in a.json['docs']! as List) (d as Map)['name']! as String,
  ];

  test(
    'list feature gives every feature, one line each, in tree order',
    () async {
      final answer = answerList(index, 'feature', const ListFilters());
      expect(names(answer), ['login', 'signup']);
      expect(
        answer.text.split('\n').first,
        docLine(index, index.at('prds/features/f01_login/FEATURE.md')!),
      );
    },
  );
  group('summary', () {
    const loginFeature = 'docs/prds/features/f01_login/FEATURE.md';

    Future<DocIndex> withSummaries(String loginValue) => indexWith({
      loginFeature: '---\nsummary: $loginValue\n---\n\n# Login\n',
    });

    test('list appends the summary of a feature that holds one', () async {
      final answer = answerList(
        await withSummaries('Grounds a task in one call.'),
        'feature',
        const ListFilters(),
      );
      final lines = answer.text.trimRight().split('\n');
      expect(lines.first, endsWith(' — Grounds a task in one call.'));
      expect(lines.first, contains(' · '));
    });

    test('structure prints no summary', () async {
      final withSummary = await withSummaries('Grounds a task in one call.');
      final doc = withSummary.at('prds/features/f01_login/FEATURE.md')!;
      expect(docLine(withSummary, doc), isNot(contains('Grounds a task')));
    });

    test('json adds a summary key to the doc that holds one alone', () async {
      final answer = answerList(
        await withSummaries('Grounds a task in one call.'),
        'feature',
        const ListFilters(),
      );
      final docs = (answer.json['docs']! as List).cast<Map<String, Object?>>();
      expect(
        docs.first,
        containsPair('summary', 'Grounds a task in one call.'),
      );
      expect(docs.last.containsKey('summary'), isFalse);
    });

    for (final (label, value, one) in [
      ('a block scalar', '|\n  Grounds a task.\n  In one call.', true),
      ('a blank', '""', false),
      ('a whitespace-only value', r'"  \n "', false),
    ]) {
      test('$label reads as one line in list, json, and the catalog', () async {
        final feature = await withSummaries(value);
        final answer = answerList(feature, 'feature', const ListFilters());
        final lines = answer.text.trimRight().split('\n');
        expect(lines, hasLength(2), reason: 'one line per feature');
        final json = (answer.json['docs']! as List)
            .cast<Map<String, Object?>>()
            .first;
        final cell = featureCatalogText(
          feature,
          'prds/FEATURES.md',
        ).split('\n').firstWhere((l) => l.startsWith('| [Login]'));
        if (one) {
          expect(lines.first, endsWith(' — Grounds a task. In one call.'));
          expect(json['summary'], 'Grounds a task. In one call.');
          expect(cell, contains('| Grounds a task. In one call. |'));
        } else {
          expect(
            lines.first,
            docLine(feature, feature.at('prds/features/f01_login/FEATURE.md')!),
          );
          expect(json.containsKey('summary'), isFalse);
          expect(cell, contains('| — |'));
        }
      });
    }

    test('a number summary adds no suffix and no json key', () async {
      final numbered = await withSummaries('42');
      final answer = answerList(numbered, 'feature', const ListFilters());
      expect(
        answer.text.split('\n').first,
        docLine(numbered, numbered.at('prds/features/f01_login/FEATURE.md')!),
      );
      final docs = (answer.json['docs']! as List).cast<Map<String, Object?>>();
      expect(docs.first.containsKey('summary'), isFalse);
    });

    test('structure answer on a feature with a summary omits it', () async {
      final withSummary = await withSummaries('Grounds a task in one call.');
      final answer = answerStructure(withSummary, target: 'login');
      expect(answer.text.split('\n').first, startsWith('login (feature)'));
      expect(answer.text, isNot(contains('Grounds a task')));
      expect(answer.json.toString(), isNot(contains('Grounds a task')));
    });

    test(
      'check reports a summary of 42 as field_value_mismatch at its line',
      () async {
        final report = await check.checkOf(
          await check.writeCheckProject(
            extra: check.doc(
              check.loginFeature,
              'summary: Lets an agent sign in.',
              'summary: 42',
            ),
          ),
        );
        expect(check.spots(report, FindingKind.fieldValueMismatch), [
          '${check.loginFeature}:3: field_value_mismatch',
        ]);
      },
    );

    test(
      'a blank line inside a block scalar summary reads as one space',
      () async {
        final answer = answerList(
          await withSummaries('|\n  Finds docs.\n\n  Lists them.'),
          'feature',
          const ListFilters(),
        );
        expect(
          answer.text.split('\n').first,
          endsWith(' — Finds docs. Lists them.'),
        );
      },
    );
  });
  test(
    '--under a story keeps only its FRs; --under a feature its stories',
    () async {
      expect(
        names(
          answerList(
            index,
            'fr',
            const ListFilters(under: 'login/email_login'),
          ),
        ),
        [
          'login/email_login/validate_credentials',
          'login/email_login/lock_after_failures',
        ],
      );
      expect(
        names(
          answerList(index, 'user_story', const ListFilters(under: 'login')),
        ),
        ['login/email_login', 'login/reset_password'],
      );
    },
  );
  test('--cites reads frontmatter only', () async {
    const reset =
        'docs/prds/features/f01_login/us02_reset_password/USER_STORY.md';
    final cited = await indexWith({
      reset: '${loginProject[reset]}\nIt serves PG-01.\n',
    });
    expect(
      names(answerList(cited, 'user_story', const ListFilters(cites: 'PG-01'))),
      ['login/email_login'],
    );
  });
  test('--cites a persona name', () async {
    expect(
      names(answerList(index, 'user_story', const ListFilters(cites: 'buyer'))),
      ['login/email_login'],
    );
  });
  test("--status uses a feature's computed status", () async {
    expect(
      names(
        answerList(index, 'feature', const ListFilters(status: 'implemented')),
      ),
      ['signup'],
    );
  });
  test('--status and --draft together', () async {
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
  });
  test('--no-implements keeps FRs with no implements entry', () async {
    expect(
      names(answerList(index, 'fr', const ListFilters(noImplements: true))),
      [
        'login/email_login/lock_after_failures',
        'login/reset_password/send_reset_link',
      ],
    );
  });
  test('--slug keeps docs whose aliases hold it', () async {
    expect(
      names(answerList(index, 'feature', const ListFilters(slug: 'sign-in'))),
      ['login'],
    );
  });
  test('--under a name no doc carries is doc_not_found', () async {
    expect(
      () => answerList(index, 'fr', const ListFilters(under: 'logn')),
      throwsA(isA<IndexFault>()),
    );
  });
  test('no match is an empty list and success', () async {
    final answer = answerList(
      index,
      'feature',
      const ListFilters(status: 'deprecated'),
    );
    expect(answer.text, isEmpty);
    expect(answer.json['docs'], isEmpty);
    expect(answer.exitStatus, 0);
  });
  test('a doc type that holds no doc is an empty list and success', () async {
    expect(index.docs.any((d) => d.docTypeId == 'measurement'), isFalse);
    final answer = answerList(index, 'measurement', const ListFilters());
    expect(answer.text, isEmpty);
    expect(answer.json['docs'], isEmpty);
    expect(answer.exitStatus, 0);
  });
  test('doc_type_unknown for featur carries exit status 64', () async {
    expect(
      () => answerList(index, 'featur', const ListFilters()),
      throwsA(
        isA<TemplateFault>()
            .having((f) => f.code, 'code', FaultCode.docTypeUnknown)
            .having((f) => f.exitStatus, 'exit status', 64),
      ),
    );
  });
  test('--under logn is doc_not_found, exit 64, naming logn', () async {
    expect(
      () => answerList(index, 'fr', const ListFilters(under: 'logn')),
      throwsA(
        isA<IndexFault>()
            .having((f) => f.code, 'code', IndexFaultCode.docNotFound)
            .having((f) => f.exitStatus, 'exit status', 64)
            .having((f) => f.message, 'message', contains('logn')),
      ),
    );
  });
  test('an unknown doc type is doc_type_unknown naming it', () async {
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
  test('untyped docs are never listed', () async {
    expect([
      for (final t in index.set.docTypes)
        ...names(answerList(index, t.id, const ListFilters())),
    ], isNot(contains('prds/d01_context.md')));
  });
  test('list user_story --under shop lists add_item, drop_item, card, refund '
      'in tree order', () async {
    final nested = await nestedIndexWith();
    expect(
      names(answerList(nested, 'user_story', const ListFilters(under: 'shop'))),
      [
        'shop/cart/add_item',
        'shop/cart/drop_item',
        'shop/pay/card',
        'shop/pay/refund',
      ],
    );
  });

  group('per code target', () {
    /// Returns the index of the two-target fixture: the feature `login`, its
    /// two stories with their FRs, and each target's record, built from its
    /// `statuses` and `implements` lines.
    Future<DocIndex> twoTargets({
      String flutterStatuses = '',
      String flutterImplements = '',
      String jasprStatuses = '',
      String jasprImplements = '',
    }) async {
      String record(String statuses, String implements) {
        final lines = [
          if (statuses.isNotEmpty) 'statuses:\n$statuses',
          if (implements.isNotEmpty) 'implements:\n$implements',
        ];
        return lines.isEmpty
            ? '# Record\n'
            : '---\n${lines.join()}---\n\n# Record\n';
      }

      final session = openSession(
        await writeTree({
          '.specstone/templates/implementation.yaml':
              'id: implementation\n'
              'description: One feature record per target.\n'
              'path: .specstone/records/f{nn}_{slug}/IMPLEMENTATION.md\n'
              'parent: feature\n'
              'per_target: true\n'
              'fields:\n'
              '  - id: statuses\n'
              '    type: record_status\n'
              '    list: true\n'
              '  - id: implements\n'
              '    type: output_ref\n'
              '    list: true\n'
              '    pointer: item_exact\n',
          '.specstone/config.yaml':
              '${shippedPinsConfig()}targets:\n'
              '  flutter:\n    code_root: flutter_lib\n'
              '  jaspr:\n    code_root: jaspr_lib\n',
          'flutter_lib/.keep': '',
          'jaspr_lib/.keep': '',
          'docs/prds/features/f01_login/FEATURE.md': '# Login\n\n## Problem\n.',
          'docs/prds/features/f01_login/us01_show/USER_STORY.md': '---\nstatus: implemented\n---\n\n# Agent sees it\n\n## Use Case\n.\n',
          'docs/prds/features/f01_login/us01_show/fr01_open.md':
              '---\nstatus: implemented\n---\n\n# Open it\n',
          'docs/prds/features/f01_login/us02_hide/USER_STORY.md': '---\nstatus: implemented\n---\n\n# Agent hides it\n\n## Use Case\n.\n',
          'docs/prds/features/f01_login/us02_hide/fr01_close.md':
              '---\nstatus: implemented\n---\n\n# Close it\n',
          '.specstone/records/flutter/f01_login/IMPLEMENTATION.md': record(
            flutterStatuses,
            flutterImplements,
          ),
          '.specstone/records/jaspr/f01_login/IMPLEMENTATION.md': record(
            jasprStatuses,
            jasprImplements,
          ),
        }),
      );
      addTearDown(session.close);
      return session.index;
    }

    test('list fr --no-implements --target jaspr keeps the FRs that name no '
        'code in jaspr', () async {
      final index = await twoTargets(
        flutterImplements:
            '  - show/open:lib/flutter_open.dart\n'
            '  - show:lib/flutter_show.dart\n'
            '  - hide/close:lib/flutter_close.dart\n'
            '  - hide:lib/flutter_hide.dart\n',
        jasprImplements: '  - show/open:lib/jaspr_open.dart\n',
      );
      expect(
        names(
          answerList(
            index,
            'fr',
            const ListFilters(noImplements: true, codeTarget: 'jaspr'),
          ),
        ),
        ['login/hide/close'],
        reason: 'flutter names code for it, jaspr does not',
      );
    });

    test('--status or --no-implements with two targets and no --target is '
        'argument_missing', () async {
      final index = await twoTargets();
      for (final filters in const [
        ListFilters(status: 'implemented'),
        ListFilters(noImplements: true),
      ]) {
        expect(
          () => answerList(index, 'fr', filters),
          throwsA(
            isA<IndexFault>()
                .having((f) => f.code, 'code', IndexFaultCode.argumentMissing)
                .having(
                  (f) => f.message,
                  'message',
                  '--status and --no-implements need --target with two or '
                      'more code targets; the targets are flutter, jaspr',
                ),
          ),
        );
      }
    });

    test(
      'two targets and no --target refuse --status with exit status 64',
      () async {
        final index = await twoTargets();
        expect(
          () => answerList(index, 'fr', const ListFilters(status: 'planned')),
          throwsA(
            isA<IndexFault>().having((f) => f.exitStatus, 'exit status', 64),
          ),
        );
      },
    );

    test('list user_story --status skipped --target jaspr keeps the stories '
        'jaspr skips', () async {
      final index = await twoTargets(
        flutterImplements:
            '  - show:lib/flutter_show.dart\n  - hide:lib/flutter_hide.dart\n',
        jasprStatuses: '  - hide:skipped:no hide on the web\n',
      );
      expect(
        names(
          answerList(
            index,
            'user_story',
            const ListFilters(status: 'skipped', codeTarget: 'jaspr'),
          ),
        ),
        ['login/hide'],
        reason: "jaspr's story entry skips it",
      );
    });

    test('a feature-level skip covers each story under it, and the story list '
        'line shows the target status', () async {
      final index = await twoTargets(
        flutterImplements:
            '  - show:lib/flutter_show.dart\n  - hide:lib/flutter_hide.dart\n',
        jasprStatuses: '  - :skipped:no hide on the web\n',
      );
      expect(
        names(
          answerList(
            index,
            'user_story',
            const ListFilters(status: 'skipped', codeTarget: 'jaspr'),
          ),
        ),
        ['login/show', 'login/hide'],
        reason: "the feature's own entry skips every story under it",
      );
      final answer = answerList(
        index,
        'user_story',
        const ListFilters(status: 'skipped', codeTarget: 'jaspr'),
      );
      expect(answer.text, contains(' · skipped · '));
      final json = (answer.json['docs']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere((d) => d['name'] == 'login/hide');
      expect(json['status'], 'skipped');
    });

    test('one target judges its status and code with no --target', () async {
      expect(
        names(
          answerList(index, 'user_story', const ListFilters(status: 'planned')),
        ),
        ['login/email_login', 'login/reset_password'],
      );
      expect(
        names(answerList(index, 'fr', const ListFilters(noImplements: true))),
        [
          'login/email_login/lock_after_failures',
          'login/reset_password/send_reset_link',
        ],
      );
    });

    test('one named target judges --no-implements with no --target', () async {
      String record(String implements) => implements.isEmpty
          ? '# Record\n'
          : '---\nimplements:\n$implements---\n\n# Record\n';
      final session = openSession(
        await writeTree({
          '.specstone/templates/implementation.yaml':
              'id: implementation\n'
              'description: One feature record per target.\n'
              'path: .specstone/records/f{nn}_{slug}/IMPLEMENTATION.md\n'
              'parent: feature\n'
              'per_target: true\n'
              'fields:\n'
              '  - id: statuses\n'
              '    type: record_status\n'
              '    list: true\n'
              '  - id: implements\n'
              '    type: output_ref\n'
              '    list: true\n'
              '    pointer: item_exact\n',
          '.specstone/config.yaml':
              '${shippedPinsConfig()}targets:\n'
              '  flutter:\n    code_root: flutter_lib\n',
          'flutter_lib/.keep': '',
          'docs/prds/features/f01_login/FEATURE.md': '# Login\n\n## Problem\n.',
          'docs/prds/features/f01_login/us01_show/USER_STORY.md': '---\nstatus: implemented\n---\n\n# Agent sees it\n\n## Use Case\n.\n',
          'docs/prds/features/f01_login/us01_show/fr01_open.md':
              '---\nstatus: implemented\n---\n\n# Open it\n',
          'docs/prds/features/f01_login/us02_hide/USER_STORY.md': '---\nstatus: implemented\n---\n\n# Agent hides it\n\n## Use Case\n.\n',
          'docs/prds/features/f01_login/us02_hide/fr01_close.md':
              '---\nstatus: implemented\n---\n\n# Close it\n',
          '.specstone/records/f01_login/IMPLEMENTATION.md': record(
            '  - show/open:lib/open.dart\n  - show:lib/show.dart\n'
            '  - hide/close:lib/close.dart\n  - hide:lib/hide.dart\n',
          ),
        }),
      );
      addTearDown(session.close);
      expect(
        names(
          answerList(
            session.index,
            'fr',
            const ListFilters(noImplements: true),
          ),
        ),
        isEmpty,
        reason: 'the one named target names code for every FR',
      );
    });

    test('a target targets: holds none of is argument_invalid', () async {
      final targeted = await twoTargets();
      expect(
        () => answerList(targeted, 'fr', const ListFilters(codeTarget: 'web')),
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
    });
  });
}
