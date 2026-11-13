import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/list_docs.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';
import '../../helpers/nested_fixture.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/temp_tree.dart';

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
  test('f01/us03/fr02/e08: list user_story --under shop lists add_item, drop_item, card, refund in tree order', () async {
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
              'path: specs/f{nn}_{slug}/IMPLEMENTATION.md\n'
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
          'docs/specs/flutter/f01_login/IMPLEMENTATION.md': record(
            flutterStatuses,
            flutterImplements,
          ),
          'docs/specs/jaspr/f01_login/IMPLEMENTATION.md': record(
            jasprStatuses,
            jasprImplements,
          ),
        }),
      );
      addTearDown(session.close);
      return session.index;
    }

    test('f01/us03/fr02/e09: list fr --no-implements --target jaspr keeps the FRs that name no code in jaspr', () async {
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

    test('f01/us03/fr02/e10: --status or --no-implements with two targets and no --target is argument_missing', () async {
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

    test('f01/us03/fr02/e11: list user_story --status skipped --target jaspr keeps the stories jaspr skips', () async {
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

    test('f01/us03/fr02/e11: a feature-level skip covers each story under it, and the story list line shows the target status', () async {
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

    test('f01/us03/fr02/e12: one target judges its status and code with no --target', () async {
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

    test('f01/us03/fr02/e12: one named target judges --no-implements with no --target', () async {
      String record(String implements) => implements.isEmpty
          ? '# Record\n'
          : '---\nimplements:\n$implements---\n\n# Record\n';
      final session = openSession(
        await writeTree({
          '.specstone/templates/implementation.yaml':
              'id: implementation\n'
              'description: One feature record per target.\n'
              'path: specs/f{nn}_{slug}/IMPLEMENTATION.md\n'
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
          'docs/specs/f01_login/IMPLEMENTATION.md': record(
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

    test('index_query/read_doc_section/resolve_doc_name E22: a target targets: holds none of is argument_invalid', () async {
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
