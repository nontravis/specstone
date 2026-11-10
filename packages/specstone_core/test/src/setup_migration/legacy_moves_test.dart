import 'package:specstone_core/src/document_writing/rewrite_refs.dart'
    show PathMove;
import 'package:specstone_core/src/setup_migration/legacy_moves.dart';
import 'package:specstone_core/src/setup_migration/legacy_tree.dart';
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:test/test.dart';

import '../../helpers/legacy_fixture.dart';

/// The fixture's paths relative to its `docs/` folder.
List<String> _docPaths(Map<String, String> tree) => [
  for (final key in tree.keys) key.substring('docs/'.length),
];

LegacyMoves _plan(Map<String, String> tree) => planLegacyMoves(
  _docPaths(tree),
  specMap: readSpecMap(tree['docs/specs/INDEX.md'] ?? ''),
  features: scanLegacyFeatures(_docPaths(tree)),
);

String? _movedTo(LegacyMoves plan, String from) {
  for (final move in plan.moves) {
    if (move.from == from) return move.to;
  }
  return null;
}

/// The refusal [tree] draws, the fault first and its `more` lines after.
List<MigrateFault> _refusal(Map<String, String> tree) {
  try {
    _plan(tree);
  } on MigrateFault catch (fault) {
    expect(fault.code, MigrateFaultCode.legacyCollision);
    return [fault, ...fault.more];
  }
  fail('planLegacyMoves did not refuse');
}

/// Fails unless the moved, the staying typed, and the left paths of [plan]
/// together are the input paths of [tree], each once.
void _expectNoDrop(Map<String, String> tree, LegacyMoves plan) {
  final covered = [
    for (final move in plan.moves) move.from,
    ...plan.left,
    for (final MapEntry(key: to, value: from) in plan.fromOf.entries)
      if (to == from) from,
  ];
  expect(covered..sort(), _docPaths(tree)..sort());
}

String _folderOf(String file) => file.substring(0, file.lastIndexOf('/'));

/// Flat features `f01_alpha`, `f02_beta`, and `f03_gamma`.
const _threeFeatures = <String, String>{
  'docs/prds/features/f01_alpha/FEATURE.md': '# F-01 — Alpha\n',
  'docs/prds/features/f02_beta/FEATURE.md': '# F-02 — Beta\n',
  'docs/prds/features/f03_gamma/FEATURE.md': '# F-03 — Gamma\n',
};

/// A tree of [_threeFeatures] with a spec folder per `folder: feature` entry
/// of [rows], each holding the files [files] names.
Map<String, String> _specTree(Map<String, String> rows, List<String> files) => {
  ..._threeFeatures,
  'docs/specs/INDEX.md': _specIndex([
    for (final MapEntry(key: folder, value: feature) in rows.entries)
      '| `c/` | `specs/$folder/` | $feature |',
  ]),
  for (final folder in rows.keys)
    for (final file in files) 'docs/specs/$folder/$file': '# S\n',
};

/// Two cycles, a-b and c-d, and two moves that lead from the second to the
/// first: `d` to `e` waits on `e` to `a`, which waits on `a` to `b`.
///
/// The bridge moves lie on no cycle. No legacy tree plans this graph, since
/// the bridge shares a source with `d` to `c` and a target with `b` to `a`;
/// the cycle finder takes any moves.
const _twoCyclesAndABridge = <PathMove>[
  (from: 'a', to: 'b'),
  (from: 'b', to: 'a'),
  (from: 'e', to: 'a'),
  (from: 'c', to: 'd'),
  (from: 'd', to: 'c'),
  (from: 'd', to: 'e'),
];

String _specIndex(List<String> rows) =>
    '''
## Spec map

| Code path | Spec path | feature_id |
|-----------|-----------|------------|
${rows.join('\n')}
''';

void main() {
  group('planLegacyMoves', () {
    test("f06/us01/fr03: the acme moves are the dry-run example's eight "
        'moves in order', () {
      final plan = _plan(acmeLegacy);

      expect(plan.moves, [
        (from: 'prds/d01_context.md', to: 'prds/PROJECT.md'),
        (from: 'prds/d02_features.md', to: 'prds/FEATURES.md'),
        (from: 'prds/d03_non_functional.md', to: 'prds/GNFR.md'),
        (
          from:
              'prds/features/f01_login/us01_email_login/'
              'functional_requirements/fr01_validate_credentials.md',
          to:
              'prds/features/f01_login/us01_email_login/'
              'fr01_validate_credentials.md',
        ),
        (
          from: 'specs/api/auth/s01_architecture.md',
          to: 'specs/f01_login/ARCHITECTURE.md',
        ),
        (
          from: 'specs/api/auth/s02_api_login.md',
          to: 'specs/f01_login/s02_api_login.md',
        ),
        (
          from: 'specs/api/auth/s02_api_session.md',
          to: 'specs/f01_login/s02_api_session.md',
        ),
        (
          from: 'specs/shared/s01_architecture.md',
          to: 'specs/topics/shared/s01_architecture.md',
        ),
      ]);
    });

    test('f06/us01/fr03/e01: the three project docs take fixed names and '
        'd04 stays', () {
      final plan = _plan(specEdgeLegacy);

      expect(plan.kindOf['prds/PROJECT.md'], LegacyKind.project);
      expect(plan.kindOf['prds/FEATURES.md'], LegacyKind.features);
      expect(plan.kindOf['prds/GNFR.md'], LegacyKind.gnfr);
      expect(plan.fromOf['prds/PROJECT.md'], 'prds/d01_context.md');
      expect(plan.left, contains('prds/d04_glossary.md'));
      expect(_movedTo(plan, 'prds/d04_glossary.md'), isNull);
    });

    test('f06/us01/fr03/e02: a flat feature keeps its folder and its '
        'requirements move up into the story folder', () {
      final plan = _plan(acmeLegacy);
      const feature = 'prds/features/f01_login/';
      const story = '${feature}us01_email_login/';

      expect(plan.kindOf['${feature}FEATURE.md'], LegacyKind.feature);
      expect(plan.kindOf['${story}USER_STORY.md'], LegacyKind.userStory);
      expect(
        plan.kindOf['${story}fr01_validate_credentials.md'],
        LegacyKind.fr,
      );
      expect(plan.fromOf['${feature}FEATURE.md'], '${feature}FEATURE.md');
      expect(_movedTo(plan, '${feature}FEATURE.md'), isNull);
      expect(_movedTo(plan, '${story}USER_STORY.md'), isNull);
    });

    test('f06/us01/fr03/e02: a non-functional requirement moves up beside '
        'its story and any other file of the feature stays', () {
      final tree = {
        'docs/prds/features/f01_login/FEATURE.md': '# F-01\n',
        'docs/prds/features/f01_login/us01_a/non_functional_requirements/'
                'nf02_speed.md':
            '# NF-02\n',
        'docs/prds/features/f01_login/us01_a/notes.md': '# notes\n',
      };

      final plan = _plan(tree);

      expect(plan.moves, [
        (
          from:
              'prds/features/f01_login/us01_a/non_functional_requirements/'
              'nf02_speed.md',
          to: 'prds/features/f01_login/us01_a/nf02_speed.md',
        ),
      ]);
      expect(
        plan.kindOf['prds/features/f01_login/us01_a/nf02_speed.md'],
        LegacyKind.nf,
      );
      expect(plan.left, ['prds/features/f01_login/us01_a/notes.md']);
    });

    test('f06/us01/fr03/e04, f06/us01/fr03/e06: a grouped feature moves '
        'under its group and the container doc beside it, untyped', () {
      final plan = _plan(containerLegacy);

      expect(
        _movedTo(
          plan,
          'prds/features/components/co01_utilities/co01_01_slot/FEATURE.md',
        ),
        'prds/features/utilities/f01_slot/FEATURE.md',
      );
      expect(
        plan.kindOf['prds/features/utilities/f01_slot/FEATURE.md'],
        LegacyKind.feature,
      );
      expect(
        _movedTo(plan, 'prds/features/components/co01_utilities/FEATURE.md'),
        'prds/features/utilities/FEATURE.md',
      );
      expect(
        plan.kindOf,
        isNot(contains('prds/features/utilities/FEATURE.md')),
      );
      expect(
        plan.fromOf['prds/features/utilities/FEATURE.md'],
        'prds/features/components/co01_utilities/FEATURE.md',
      );
    });

    test('f06/us01/fr03/e05: a file a folder above a group holds stays', () {
      final plan = _plan(groupedLegacy);

      expect(plan.left, ['prds/features/brick_module/README.md']);
      expect(
        _movedTo(
          plan,
          'prds/features/brick_module/tool_module/tm01_stripe/FEATURE.md',
        ),
        'prds/features/tool_module/f01_stripe/FEATURE.md',
      );
    });

    test('f06/us01/fr03/e07: a flat feature of a grouped tree stays whole', () {
      final plan = _plan(mixedLegacy);

      expect(plan.left, ['prds/features/f01_login/FEATURE.md']);
      expect(
        plan.kindOf,
        isNot(contains('prds/features/f01_login/FEATURE.md')),
      );
      expect(plan.moves.map((m) => m.from), [
        'prds/features/ai_module/ai05_chat/FEATURE.md',
      ]);
    });

    test('f06/us01/fr03/e08: spec files map by name, never by number', () {
      final plan = _plan(specEdgeLegacy);

      expect(
        _movedTo(plan, 'specs/api/billing/s04_domain.md'),
        'specs/f02_billing/DOMAIN.md',
      );
      expect(
        _movedTo(plan, 'specs/api/billing/s02_errors.md'),
        'specs/f02_billing/ERROR.md',
      );
      expect(plan.kindOf['specs/f02_billing/DOMAIN.md'], LegacyKind.domain);
      expect(plan.kindOf['specs/f02_billing/ERROR.md'], LegacyKind.error);
      expect(
        plan.kindOf['specs/f01_login/ARCHITECTURE.md'],
        LegacyKind.architecture,
      );
    });

    test('f06/us01/fr03/e08: a spec folder of a grouped feature maps under '
        'its group', () {
      final tree = {
        ...containerLegacy,
        'docs/specs/INDEX.md': _specIndex([
          '| `ui/slot/` | `specs/ui/slot/` | `co01_01_slot` |',
        ]),
        'docs/specs/ui/slot/s01_architecture.md': '# S-01\n',
        'docs/specs/ui/slot/s03_integration.md': '# S-03\n',
        'docs/specs/ui/slot/s06_auth.md': '# S-06\n',
        'docs/specs/ui/slot/s02_api_slot.md': '# S-02\n',
      };

      final plan = _plan(tree);

      expect(plan.kindOf, {
        'prds/features/utilities/f01_slot/FEATURE.md': LegacyKind.feature,
        'prds/features/components/f07_navigation/FEATURE.md':
            LegacyKind.feature,
        'specs/utilities/f01_slot/ARCHITECTURE.md': LegacyKind.architecture,
        'specs/utilities/f01_slot/INTEGRATION.md': LegacyKind.integration,
        'specs/utilities/f01_slot/AUTH.md': LegacyKind.auth,
        'specs/utilities/f01_slot/API.md': LegacyKind.api,
      });
    });

    group('a spec folder of one feature', () {
      Map<String, String> slotTree(List<String> files) => {
        ...containerLegacy,
        'docs/specs/INDEX.md': _specIndex([
          '| `ui/slot/` | `specs/ui/slot/` | `co01_01_slot` |',
        ]),
        for (final file in files) 'docs/specs/ui/slot/$file': '# S\n',
      };

      test('f06/us01/fr03/e08: a bare s02_api.md maps to API.md', () {
        final plan = _plan(slotTree(['s02_api.md']));

        expect(
          _movedTo(plan, 'specs/ui/slot/s02_api.md'),
          'specs/utilities/f01_slot/API.md',
        );
        expect(plan.kindOf['specs/utilities/f01_slot/API.md'], LegacyKind.api);
      });

      test('f06/us01/fr03/e08: each of the six kinds takes a suffix', () {
        final plan = _plan(
          slotTree([
            's01_architecture_overview.md',
            's02_api_login.md',
            's03_domain_actor_and_keys.md',
            's04_integration_payments.md',
            's05_errors_codes.md',
            's06_auth_tokens.md',
          ]),
        );

        expect(plan.kindOf, {
          'prds/features/utilities/f01_slot/FEATURE.md': LegacyKind.feature,
          'prds/features/components/f07_navigation/FEATURE.md':
              LegacyKind.feature,
          'specs/utilities/f01_slot/ARCHITECTURE.md': LegacyKind.architecture,
          'specs/utilities/f01_slot/API.md': LegacyKind.api,
          'specs/utilities/f01_slot/DOMAIN.md': LegacyKind.domain,
          'specs/utilities/f01_slot/INTEGRATION.md': LegacyKind.integration,
          'specs/utilities/f01_slot/ERROR.md': LegacyKind.error,
          'specs/utilities/f01_slot/AUTH.md': LegacyKind.auth,
        });
      });

      test('f06/us01/fr03/e13: s04_authentication.md matches no kind and '
          'stays', () {
        final plan = _plan(slotTree(['s04_authentication.md']));

        expect(plan.left, contains('specs/ui/slot/s04_authentication.md'));
        expect(_movedTo(plan, 'specs/ui/slot/s04_authentication.md'), isNull);
      });

      test('f06/us01/fr03/e08: a bare file of each other kind maps to its '
          'doc file', () {
        final plan = _plan(
          slotTree([
            's01_architecture.md',
            's03_domain.md',
            's04_integration.md',
            's05_errors.md',
            's06_auth.md',
          ]),
        );

        expect(plan.kindOf, {
          'prds/features/utilities/f01_slot/FEATURE.md': LegacyKind.feature,
          'prds/features/components/f07_navigation/FEATURE.md':
              LegacyKind.feature,
          'specs/utilities/f01_slot/ARCHITECTURE.md': LegacyKind.architecture,
          'specs/utilities/f01_slot/DOMAIN.md': LegacyKind.domain,
          'specs/utilities/f01_slot/INTEGRATION.md': LegacyKind.integration,
          'specs/utilities/f01_slot/ERROR.md': LegacyKind.error,
          'specs/utilities/f01_slot/AUTH.md': LegacyKind.auth,
        });
      });

      test('f06/us01/fr03/e13: an empty suffix or a kind that does not end at '
          '_ or .md stays', () {
        final plan = _plan(slotTree(['s02_api_.md', 's02_error.md']));

        expect(
          plan.left,
          containsAll([
            'specs/ui/slot/s02_api_.md',
            'specs/ui/slot/s02_error.md',
          ]),
        );
        expect(plan.moves.where((m) => m.from.startsWith('specs/')), isEmpty);
      });

      test('f06/us01/fr03/e10: s02_errors.md beside s02_errors_v2.md keeps '
          'both old names', () {
        final plan = _plan(slotTree(['s02_errors.md', 's02_errors_v2.md']));

        expect(
          _movedTo(plan, 'specs/ui/slot/s02_errors.md'),
          'specs/utilities/f01_slot/s02_errors.md',
        );
        expect(
          _movedTo(plan, 'specs/ui/slot/s02_errors_v2.md'),
          'specs/utilities/f01_slot/s02_errors_v2.md',
        );
        expect(
          plan.kindOf,
          isNot(contains('specs/utilities/f01_slot/ERROR.md')),
        );
      });

      test('f06/us01/fr03/e10: s02_api.md beside s02_api_login.md keeps both '
          'old names', () {
        final plan = _plan(slotTree(['s02_api.md', 's02_api_login.md']));

        expect(
          _movedTo(plan, 'specs/ui/slot/s02_api.md'),
          'specs/utilities/f01_slot/s02_api.md',
        );
        expect(
          _movedTo(plan, 'specs/ui/slot/s02_api_login.md'),
          'specs/utilities/f01_slot/s02_api_login.md',
        );
        expect(plan.kindOf, isNot(contains('specs/utilities/f01_slot/API.md')));
      });
    });

    test('f06/us01/fr03/e10, f06/us01/s4: two API files of one feature keep '
        'their old names, untyped', () {
      final plan = _plan(acmeLegacy);

      expect(plan.kindOf, isNot(contains('specs/f01_login/API.md')));
      expect(plan.kindOf, isNot(contains('specs/f01_login/s02_api_login.md')));
      expect(
        plan.fromOf['specs/f01_login/s02_api_session.md'],
        'specs/api/auth/s02_api_session.md',
      );
    });

    test('f06/us01/fr03/e11: two files of one name go under their old '
        'folder names', () {
      final plan = _plan(specEdgeLegacy);

      expect(
        _movedTo(plan, 'specs/api/billing/s01_architecture.md'),
        'specs/f02_billing/billing/s01_architecture.md',
      );
      expect(
        _movedTo(plan, 'specs/web/billing_ui/s01_architecture.md'),
        'specs/f02_billing/billing_ui/s01_architecture.md',
      );
      expect(plan.kindOf, isNot(contains('specs/f02_billing/ARCHITECTURE.md')));
    });

    test('f06/us01/fr03/e12: architecture topics and cross-cutting folders '
        'move under specs/topics', () {
      final plan = _plan(specEdgeLegacy);

      expect(
        _movedTo(plan, 'specs/shared/s01_architecture.md'),
        'specs/topics/shared/s01_architecture.md',
      );
      expect(
        plan.kindOf,
        isNot(contains('specs/topics/shared/s01_architecture.md')),
      );
      expect(
        _movedTo(plan, 'specs/architecture/caching.md'),
        'specs/topics/caching.md',
      );
      expect(plan.kindOf['specs/topics/caching.md'], LegacyKind.topic);
      expect(plan.left, contains('specs/architecture/caching.schema.json'));
    });

    test('f06/us01/fr03/e13: files no rule places stay', () {
      final plan = _plan(specEdgeLegacy);

      expect(
        plan.left,
        containsAll([
          'specs/INDEX.md',
          'specs/schema.dbml',
          'specs/api/billing/s07_sequence.md',
          'specs/orphan/s01_architecture.md',
        ]),
      );
      expect(plan.left, [...plan.left]..sort());
    });

    test('f06/us01/fr03: a folder of two feature_ids and a feature_id no '
        'folder carries stay', () {
      final plan = _plan(specEdgeLegacy);

      expect(
        plan.left,
        containsAll([
          'specs/two/s01_architecture.md',
          'specs/ghost/s01_architecture.md',
        ]),
      );
    });

    test('f06/us01/fr03: no move has from == to, and moves follow code point '
        'order of from', () {
      final plan = _plan(specEdgeLegacy);
      final froms = plan.moves.map((m) => m.from).toList();

      expect(plan.moves.where((m) => m.from == m.to), isEmpty);
      expect(froms, [...froms]..sort());
    });

    test('f06/us01/fr03/e06: a container inside a container keeps its outer '
        'one and takes the last folder name as its slug', () {
      final plan = _plan({
        'docs/prds/features/a/FEATURE.md': '# A\n',
        'docs/prds/features/a/b/FEATURE.md': '# B\n',
        'docs/prds/features/a/b/x01_f/FEATURE.md': '# F-01 — F\n',
      });

      expect(plan.left, contains('prds/features/a/FEATURE.md'));
      expect(
        _movedTo(plan, 'prds/features/a/b/FEATURE.md'),
        'prds/features/b/FEATURE.md',
      );
      expect(plan.kindOf, isNot(contains('prds/features/b/FEATURE.md')));
    });

    test('f06/us01/fr03/e12: a cross-cutting row for the architecture folder '
        'leaves its non-markdown file where it lands without the row', () {
      final tree = {
        ...specEdgeLegacy,
        'docs/specs/INDEX.md': _specIndex([
          '| `architecture/` | `specs/architecture/` | — |',
        ]),
      };

      final plan = _plan(tree);

      expect(plan.left, contains('specs/architecture/caching.schema.json'));
      expect(
        _movedTo(plan, 'specs/architecture/caching.md'),
        'specs/topics/caching.md',
      );
      expect(plan.kindOf['specs/topics/caching.md'], LegacyKind.topic);
    });

    group('e11 same-name spec files', () {
      Map<String, String> sameName(Map<String, String> files) => {
        ..._threeFeatures,
        'docs/specs/INDEX.md': _specIndex([
          for (final file in files.keys)
            '| `c/` | `specs/${_folderOf(file)}/` | `f01_alpha` |',
        ]),
        for (final MapEntry(:key, :value) in files.entries)
          'docs/specs/$key': value,
      };

      test('f06/us01/fr03/e11: server and client folders of one name give '
          'two subfolders', () {
        final plan = _plan(
          sameName({
            'server/ai05_chat_generation/s01_architecture.md': '#',
            'client/ai05_chat_generation/s01_architecture.md': '#',
          }),
        );

        expect(plan.moves, [
          (
            from: 'specs/client/ai05_chat_generation/s01_architecture.md',
            to:
                'specs/f01_alpha/client/ai05_chat_generation/'
                's01_architecture.md',
          ),
          (
            from: 'specs/server/ai05_chat_generation/s01_architecture.md',
            to:
                'specs/f01_alpha/server/ai05_chat_generation/'
                's01_architecture.md',
          ),
        ]);
      });

      test('f06/us01/fr03/e11: x/ and a/x/, one a trailing run of the other, '
          'give two distinct subfolders', () {
        final tree = sameName({
          'x/s01_architecture.md': '#',
          'a/x/s01_architecture.md': '#',
        });
        final plan = _plan(tree);

        expect(
          _movedTo(plan, 'specs/x/s01_architecture.md'),
          'specs/f01_alpha/x/s01_architecture.md',
        );
        expect(
          _movedTo(plan, 'specs/a/x/s01_architecture.md'),
          'specs/f01_alpha/a/x/s01_architecture.md',
        );
        _expectNoDrop(tree, plan);
      });

      test('f06/us01/fr03/e11: p/Q/ and r/q/ take p/Q and r/q, no fault', () {
        final plan = _plan(
          sameName({
            'p/Q/s01_architecture.md': '#',
            'r/q/s01_architecture.md': '#',
          }),
        );

        expect(
          _movedTo(plan, 'specs/p/Q/s01_architecture.md'),
          'specs/f01_alpha/p/Q/s01_architecture.md',
        );
        expect(
          _movedTo(plan, 'specs/r/q/s01_architecture.md'),
          'specs/f01_alpha/r/q/s01_architecture.md',
        );
      });

      test('f06/us01/fr03/e11: one name in another letter case in two '
          'folders is still one name', () {
        final plan = _plan(
          sameName({
            'server/x/s02_api_Users.md': '#',
            'client/x/s02_api_users.md': '#',
          }),
        );

        expect(
          _movedTo(plan, 'specs/server/x/s02_api_Users.md'),
          'specs/f01_alpha/server/x/s02_api_Users.md',
        );
        expect(
          _movedTo(plan, 'specs/client/x/s02_api_users.md'),
          'specs/f01_alpha/client/x/s02_api_users.md',
        );
      });

      test('f06/us01/fr03/e11, e14: two files of one name in one old folder '
          'take its whole path and E14 refuses the targets', () {
        final lines = _refusal(
          sameName({'x/s02_api_Users.md': '#', 'x/s02_api_users.md': '#'}),
        );

        expect(lines.map((l) => l.file), [
          'specs/f01_alpha/x/s02_api_Users.md',
        ]);
        expect(lines.single.message, contains('specs/x/s02_api_Users.md'));
        expect(lines.single.message, contains('specs/x/s02_api_users.md'));
      });

      test('f06/us01/fr03/e11, e14: Server/ and server/ folders of one name '
          'take their whole paths and E14 refuses the targets', () {
        final lines = _refusal(
          sameName({
            'Server/ai05_chat_generation/s01_architecture.md': '#',
            'server/ai05_chat_generation/s01_architecture.md': '#',
          }),
        );

        expect(lines.map((l) => l.file), [
          'specs/f01_alpha/Server/ai05_chat_generation/s01_architecture.md',
        ]);
        expect(
          lines.single.message,
          allOf(
            contains('specs/Server/ai05_chat_generation/s01_architecture.md'),
            contains('specs/server/ai05_chat_generation/s01_architecture.md'),
          ),
        );
      });

      test('f06/us01/fr03/e11, e14: each whole-path fallback in one tree '
          'gives its own target line, in code point order', () {
        final lines = _refusal(
          sameName({
            'x/s02_api_Users.md': '#',
            'x/s02_api_users.md': '#',
            'Server/x/s01_architecture.md': '#',
            'server/x/s01_architecture.md': '#',
          }),
        );

        expect(lines.map((l) => l.file), [
          'specs/f01_alpha/Server/x/s01_architecture.md',
          'specs/f01_alpha/x/s02_api_Users.md',
        ]);
      });

      test('f06/us01/fr03/e11: a Spec map row of specs/ itself beside one of '
          'specs/server/ plans, the specs/ file keeping its old name in the '
          'feature spec folder', () {
        final tree = {
          ..._threeFeatures,
          'docs/specs/INDEX.md': _specIndex([
            '| `c/` | `specs/` | `f01_alpha` |',
            '| `s/` | `specs/server/` | `f01_alpha` |',
          ]),
          'docs/specs/s01_architecture.md': '#',
          'docs/specs/server/s01_architecture.md': '#',
        };
        final plan = _plan(tree);

        expect(
          _movedTo(plan, 'specs/s01_architecture.md'),
          'specs/f01_alpha/s01_architecture.md',
        );
        expect(
          _movedTo(plan, 'specs/server/s01_architecture.md'),
          'specs/f01_alpha/server/s01_architecture.md',
        );
        _expectNoDrop(tree, plan);
      });

      test('f06/us01/fr03/e11: three files where two share a trailing run '
          'take a/x, b/x, and y', () {
        final plan = _plan(
          sameName({
            'a/x/s01_architecture.md': '#',
            'b/x/s01_architecture.md': '#',
            'c/y/s01_architecture.md': '#',
          }),
        );

        expect(plan.moves.map((m) => m.to), [
          'specs/f01_alpha/a/x/s01_architecture.md',
          'specs/f01_alpha/b/x/s01_architecture.md',
          'specs/f01_alpha/y/s01_architecture.md',
        ]);
      });

      test('f06/us01/fr03/e11: x/, a/x/, and b/a/x/ take x, a/x, and '
          'b/a/x', () {
        final plan = _plan(
          sameName({
            'x/s01_architecture.md': '#',
            'a/x/s01_architecture.md': '#',
            'b/a/x/s01_architecture.md': '#',
          }),
        );

        expect(plan.moves.map((m) => m.to), [
          'specs/f01_alpha/a/x/s01_architecture.md',
          'specs/f01_alpha/b/a/x/s01_architecture.md',
          'specs/f01_alpha/x/s01_architecture.md',
        ]);
      });

      test('f06/us01/fr03/e11, e14: a case pair in the nested folder a/x/ '
          'beside b/x/ takes the whole path a/x, not x', () {
        final lines = _refusal(
          sameName({
            'a/x/s02_api_Users.md': '#',
            'a/x/s02_api_users.md': '#',
            'b/x/s02_api_users.md': '#',
          }),
        );

        expect(lines.map((l) => l.file), [
          'specs/f01_alpha/a/x/s02_api_Users.md',
        ]);
      });

      test('f06/us01/fr03/e11, e12: a cross-cutting folder of the same file '
          'name leaves the set and lands in specs/topics/', () {
        final tree = _specTree(
          {'a': '`f01_alpha`', 'b': '`f01_alpha`', 'auth': '—'},
          ['s01_architecture.md'],
        );
        final plan = _plan(tree);

        expect(plan.moves.map((m) => m.to), [
          'specs/f01_alpha/a/s01_architecture.md',
          'specs/topics/auth/s01_architecture.md',
          'specs/f01_alpha/b/s01_architecture.md',
        ]);
        _expectNoDrop(tree, plan);
      });
    });

    group('trailingRunNames', () {
      test('f06/us01/fr03/e11: the shortest run that differs names each '
          'folder', () {
        expect(
          trailingRunNames([
            'specs/server/ai05_chat_generation/',
            'specs/client/ai05_chat_generation/',
          ]),
          ['server/ai05_chat_generation', 'client/ai05_chat_generation'],
        );
        expect(
          trailingRunNames(['specs/api/billing/', 'specs/web/billing_ui/']),
          ['billing', 'billing_ui'],
        );
      });

      test('f06/us01/fr03/e11: a folder whose whole path is a trailing run '
          'of another takes its whole path', () {
        expect(trailingRunNames(['specs/x/', 'specs/a/x/']), ['x', 'a/x']);
      });

      test('f06/us01/fr03/e11: runs compare ignoring letter case', () {
        expect(trailingRunNames(['specs/p/Q/', 'specs/r/q/']), ['p/Q', 'r/q']);
        expect(trailingRunNames(['specs/p/x/', 'specs/r/X/']), ['p/x', 'r/X']);
      });

      test('f06/us01/fr03/e11: entries compare by position, so a folder '
          'listed twice takes its whole path beside one listed once', () {
        expect(trailingRunNames(['specs/a/x/', 'specs/a/x/', 'specs/b/x/']), [
          'a/x',
          'a/x',
          'b/x',
        ]);
      });

      test('f06/us01/fr03/e11: the bare specs/ folder takes no subfolder '
          'name', () {
        expect(trailingRunNames(['specs/', 'specs/server/']), ['', 'server']);
      });

      test('f06/us01/fr03/e11: an entry outside specs/ breaks the '
          'precondition', () {
        expect(
          () => trailingRunNames(['x/api/', 'specs/a/api/']),
          throwsA(isA<AssertionError>()),
        );
      });
    });

    group('e12 cross-cutting folders', () {
      test('f06/us01/fr03/e12: folders sharing a last segment each move '
          'under their trailing run and none stays', () {
        final tree = {
          'docs/specs/INDEX.md': _specIndex([
            '| `a/` | `specs/a/shared/` | — |',
            '| `b/` | `specs/b/shared/` | — |',
            '| `c/` | `specs/c/solo/` | — |',
          ]),
          'docs/specs/a/shared/s01_architecture.md': '# A\n',
          'docs/specs/b/shared/s01_architecture.md': '# B\n',
          'docs/specs/c/solo/s01_architecture.md': '# C\n',
        };
        final plan = _plan(tree);

        expect(plan.moves, [
          (
            from: 'specs/a/shared/s01_architecture.md',
            to: 'specs/topics/a/shared/s01_architecture.md',
          ),
          (
            from: 'specs/b/shared/s01_architecture.md',
            to: 'specs/topics/b/shared/s01_architecture.md',
          ),
          (
            from: 'specs/c/solo/s01_architecture.md',
            to: 'specs/topics/solo/s01_architecture.md',
          ),
        ]);
        expect(plan.left, ['specs/INDEX.md']);
        _expectNoDrop(tree, plan);
      });

      test('f06/us01/fr03/e12: last segments that match only in letter case '
          'move under their whole paths, no fault', () {
        final plan = _plan({
          'docs/specs/INDEX.md': _specIndex([
            '| `a/` | `specs/a/Auth/` | — |',
            '| `b/` | `specs/b/auth/` | — |',
          ]),
          'docs/specs/a/Auth/x.md': '# A\n',
          'docs/specs/b/auth/x.md': '# B\n',
        });

        expect(plan.moves, [
          (from: 'specs/a/Auth/x.md', to: 'specs/topics/a/Auth/x.md'),
          (from: 'specs/b/auth/x.md', to: 'specs/topics/b/auth/x.md'),
        ]);
      });

      test('f06/us01/fr03/e12: cross-cutting rows outside specs/ or sharing '
          'a last segment with no file plan without a throw', () {
        for (final rows in [
          ['auth/', 'lib/auth/'],
          ['a/x/', 'b/x/'],
          ['x/specs/', 'y/specs/'],
        ]) {
          final tree = {
            'docs/prds/d01_context.md': '# D\n',
            'docs/specs/INDEX.md': _specIndex([
              for (final row in rows) '| `c/` | `$row` | — |',
            ]),
          };
          final plan = _plan(tree);

          expect(plan.moves, [
            (from: 'prds/d01_context.md', to: 'prds/PROJECT.md'),
          ]);
          _expectNoDrop(tree, plan);
        }
      });

      test('f06/us01/fr03/e12: a cross-cutting row of specs/ moves its files '
          'to specs/topics/specs/, beside a row of x/specs/ that plans', () {
        final tree = {
          'docs/specs/INDEX.md': _specIndex([
            '| `c/` | `specs/` | — |',
            '| `x/` | `x/specs/` | — |',
          ]),
          'docs/specs/s01_notes.md': '# N\n',
        };
        final plan = _plan(tree);

        expect(
          _movedTo(plan, 'specs/s01_notes.md'),
          'specs/topics/specs/s01_notes.md',
        );
        _expectNoDrop(tree, plan);
      });

      test('f06/us01/fr03/e12: a cross-cutting row with no file does not '
          'count as sharing a last segment', () {
        final plan = _plan({
          'docs/specs/INDEX.md': _specIndex([
            '| `a/` | `specs/old/auth/` | — |',
            '| `b/` | `specs/ui/auth/` | — |',
          ]),
          'docs/specs/ui/auth/x.md': '# A\n',
        });

        expect(plan.moves, [
          (from: 'specs/ui/auth/x.md', to: 'specs/topics/auth/x.md'),
        ]);
      });
    });

    group('e14 collisions', () {
      test('f06/us01/fr03/e14: a move onto a file that stays refuses with '
          'the target as file and says the file stays', () {
        final lines = _refusal({
          ...acmeLegacy,
          'docs/prds/FEATURES.md': '# Features\n',
        });

        expect(lines.map((l) => l.file), ['prds/FEATURES.md']);
        expect(
          lines.single.message,
          allOf(
            contains('prds/d02_features.md moves to prds/FEATURES.md'),
            contains('prds/FEATURES.md stays'),
          ),
        );
        expect(lines.single.exitStatus, 65);
      });

      test('f06/us01/fr03/e14: two moves onto one path refuse and each '
          'old path is named', () {
        final tree = {
          'docs/prds/features/co01_utilities/co01_01_slot/FEATURE.md': '# A\n',
          'docs/prds/features/co01_utilities/ai01_slot/FEATURE.md': '# B\n',
        };
        final lines = _refusal(tree);

        expect(lines.map((l) => l.file), [
          'prds/features/utilities/f01_slot/FEATURE.md',
        ]);
        expect(
          lines.single.message,
          allOf(
            contains(
              'prds/features/co01_utilities/ai01_slot/FEATURE.md moves to',
            ),
            contains(
              'prds/features/co01_utilities/co01_01_slot/FEATURE.md moves to',
            ),
          ),
        );
      });

      test('f06/us01/fr03/e14: two targets give the fault and one more '
          'entry in code point order', () {
        final lines = _refusal({
          ...acmeLegacy,
          'docs/prds/FEATURES.md': '# Features\n',
          'docs/prds/PROJECT.md': '# Project\n',
        });

        expect(lines.map((l) => l.file), [
          'prds/FEATURES.md',
          'prds/PROJECT.md',
        ]);
      });

      test('f06/us01/fr03/e14: a move onto a path a later move leaves runs '
          'after it, and the other moves keep code point order', () {
        final tree = {
          ..._threeFeatures,
          'docs/prds/d01_context.md': '# D\n',
          'docs/specs/INDEX.md': _specIndex([
            '| `topics/shared/` | `specs/topics/shared/` | `f01_alpha` |',
            '| `shared/` | `specs/shared/` | — |',
          ]),
          'docs/specs/shared/s01_architecture.md': '# Shared\n',
          'docs/specs/topics/shared/s01_architecture.md': '# Alpha\n',
        };
        final plan = _plan(tree);

        expect(plan.moves, [
          (from: 'prds/d01_context.md', to: 'prds/PROJECT.md'),
          (
            from: 'specs/topics/shared/s01_architecture.md',
            to: 'specs/f01_alpha/ARCHITECTURE.md',
          ),
          (
            from: 'specs/shared/s01_architecture.md',
            to: 'specs/topics/shared/s01_architecture.md',
          ),
        ]);
        _expectNoDrop(tree, plan);
      });

      test('f06/us01/fr03/e14: a cycle refuses with one line per target in '
          'the cycle', () {
        final lines = _refusal(
          _specTree(
            {
              'f01_alpha/q': '`f02_beta`',
              'z': '`f02_beta`',
              'f02_beta/q': '`f01_alpha`',
              'y': '`f01_alpha`',
            },
            ['s02_api_n.md'],
          ),
        );

        expect(lines.map((l) => l.file), [
          'specs/f01_alpha/q/s02_api_n.md',
          'specs/f02_beta/q/s02_api_n.md',
        ]);
      });

      test('f06/us01/fr03/e14: a chain of three moves, each onto the next '
          "one's old path, runs last first", () {
        final tree = {
          ..._specTree(
            {
              'f01_alpha/q': '`f02_beta`',
              'z': '`f02_beta`',
              'f02_beta/q': '`f03_gamma`',
              'y': '`f03_gamma`',
              'f03_gamma/q': '`f04_delta`',
              'x': '`f04_delta`',
            },
            ['s02_api_n.md'],
          ),
          'docs/prds/features/f04_delta/FEATURE.md': '# F-04 — Delta\n',
        };
        final plan = _plan(tree);

        expect(plan.moves.map((m) => m.from), [
          'specs/f03_gamma/q/s02_api_n.md',
          'specs/f02_beta/q/s02_api_n.md',
          'specs/f01_alpha/q/s02_api_n.md',
          'specs/x/s02_api_n.md',
          'specs/y/s02_api_n.md',
          'specs/z/s02_api_n.md',
        ]);
        _expectNoDrop(tree, plan);
      });

      test('f06/us01/fr03/e14: a cycle of three moves refuses with one line '
          'per target', () {
        final lines = _refusal(
          _specTree(
            {
              'f01_alpha/q': '`f02_beta`',
              'z': '`f02_beta`',
              'f02_beta/q': '`f03_gamma`',
              'y': '`f03_gamma`',
              'f03_gamma/q': '`f01_alpha`',
              'x': '`f01_alpha`',
            },
            ['s02_api_n.md'],
          ),
        );

        expect(lines.map((l) => l.file), [
          'specs/f01_alpha/q/s02_api_n.md',
          'specs/f02_beta/q/s02_api_n.md',
          'specs/f03_gamma/q/s02_api_n.md',
        ]);
      });

      test('f06/us01/fr03/e14: moves that lead from one cycle to another lie '
          'on no cycle', () {
        expect(movesOnCycles(_twoCyclesAndABridge), [
          (from: 'a', to: 'b'),
          (from: 'b', to: 'a'),
          (from: 'c', to: 'd'),
          (from: 'd', to: 'c'),
        ]);
      });

      test('f06/us01/fr03/e14: d01_context.md moving onto a staying '
          'PROJECT.md or project.md refuses and says it stays', () {
        for (final staying in ['PROJECT.md', 'project.md']) {
          final lines = _refusal({
            'docs/prds/d01_context.md': '# D\n',
            'docs/prds/$staying': '# P\n',
          });

          expect(lines.map((l) => l.file), ['prds/PROJECT.md']);
          expect(
            lines.single.message,
            allOf(
              contains('prds/d01_context.md moves to prds/PROJECT.md'),
              contains('prds/$staying stays'),
            ),
          );
        }
      });

      test('f06/us01/fr03/e14: an FR moving up onto a staying fr01_x.md or '
          'FR01_X.md refuses and says it stays', () {
        const story = 'prds/features/f01_login/us01_email';
        for (final staying in ['fr01_x.md', 'FR01_X.md']) {
          final lines = _refusal({
            'docs/prds/features/f01_login/FEATURE.md': '# F-01 — Login\n',
            'docs/$story/USER_STORY.md': '# US-01\n',
            'docs/$story/functional_requirements/fr01_x.md': '# FR-01\n',
            'docs/$story/$staying': '# S\n',
          });

          expect(lines.map((l) => l.file), ['$story/$staying']);
          expect(
            lines.single.message,
            allOf(
              contains('$story/functional_requirements/fr01_x.md moves to'),
              contains('$story/$staying stays'),
            ),
          );
        }
      });

      test('f06/us01/fr03/e14: an empty specs/ holding one file leaves it '
          'where it is', () {
        final tree = {'docs/specs/INDEX.md': '# Index\n'};
        final plan = _plan(tree);

        expect(plan.moves, isEmpty);
        expect(plan.left, ['specs/INDEX.md']);
        _expectNoDrop(tree, plan);
      });

      test('f06/us01/fr03/e14: a tree with no file plans nothing', () {
        final plan = _plan({});

        expect(plan.moves, isEmpty);
        expect(plan.left, isEmpty);
      });
    });

    group('e14 case-blind', () {
      test('f06/us01/fr03/e14: a move onto ARCHITECTURE.md beside a staying '
          'architecture.md refuses and says it stays', () {
        final lines = _refusal(
          _specTree(
            {'f01_alpha': '`f01_alpha`'},
            ['s01_architecture.md', 'architecture.md'],
          ),
        );

        expect(lines.map((l) => l.file), ['specs/f01_alpha/ARCHITECTURE.md']);
        expect(
          lines.single.message,
          allOf(
            contains(
              'specs/f01_alpha/s01_architecture.md moves to '
              'specs/f01_alpha/ARCHITECTURE.md',
            ),
            contains('specs/f01_alpha/architecture.md stays'),
          ),
        );
      });

      test('f06/us01/fr03/e14: two targets that differ only in case form '
          'one line naming both old paths', () {
        final lines = _refusal({
          'docs/specs/INDEX.md': _specIndex([
            '| `a/` | `specs/Auth/` | — |',
            '| `b/` | `specs/auth/` | — |',
          ]),
          'docs/specs/Auth/x.md': '# A\n',
          'docs/specs/auth/x.md': '# B\n',
        });

        expect(lines.map((l) => l.file), ['specs/topics/Auth/x.md']);
        expect(
          lines.single.message,
          allOf(contains('specs/Auth/x.md'), contains('specs/auth/x.md')),
        );
      });

      test('f06/us01/fr03/e14: a move onto a path another move leaves in '
          'another letter case runs after that move', () {
        final tree = _specTree(
          {
            'A1/q': '`f02_beta`',
            'z': '`f02_beta`',
            'F02_beta/q': '`f03_gamma`',
          },
          ['s02_api_n.md'],
        );
        final plan = _plan(tree);

        expect(plan.moves.map((m) => m.from), [
          'specs/F02_beta/q/s02_api_n.md',
          'specs/A1/q/s02_api_n.md',
          'specs/z/s02_api_n.md',
        ]);
        _expectNoDrop(tree, plan);
      });

      test('f06/us01/fr03/e14: a cycle that closes only ignoring letter '
          'case refuses', () {
        final lines = _refusal(
          _specTree(
            {
              'f01_alpha/q': '`f02_beta`',
              'z': '`f02_beta`',
              'F02_beta/q': '`f01_alpha`',
              'y': '`f01_alpha`',
            },
            ['s02_api_n.md'],
          ),
        );

        expect(lines.map((l) => l.file), [
          'specs/f01_alpha/q/s02_api_n.md',
          'specs/f02_beta/q/s02_api_n.md',
        ]);
      });

      test('f06/us01/fr03/e14: a move onto its own old path in another '
          'letter case is a move, no collision and no cycle', () {
        final tree = {
          'docs/specs/INDEX.md': _specIndex([
            '| `a/` | `specs/Topics/auth/` | — |',
          ]),
          'docs/specs/Topics/auth/x.md': '# A\n',
        };
        final plan = _plan(tree);

        expect(plan.moves, [
          (from: 'specs/Topics/auth/x.md', to: 'specs/topics/auth/x.md'),
        ]);
        _expectNoDrop(tree, plan);
      });

      test('f06/us01/fr03/e14: a non-ASCII pair refuses too', () {
        final lines = _refusal({
          'docs/specs/architecture/Ä.md': '# A\n',
          'docs/specs/topics/ä.md': '# B\n',
        });

        expect(lines.map((l) => l.file), ['specs/topics/Ä.md']);
        expect(lines.single.message, contains('specs/topics/ä.md stays'));
      });
    });

    test('f06/us01/fr03/e14: for every planned fixture the moved, staying, '
        'and left paths are the input paths', () {
      for (final tree in [
        acmeLegacy,
        specEdgeLegacy,
        containerLegacy,
        mixedLegacy,
      ]) {
        _expectNoDrop(tree, _plan(tree));
      }
    });

    test('f06/us01/fr03/e08: a cross-cutting row beside one feature_id for '
        'the same folder places the folder by that one id', () {
      final tree = {
        'docs/prds/features/f01_login/FEATURE.md': '# F-01 — Login\n',
        'docs/specs/INDEX.md': _specIndex([
          '| `a/` | `specs/a/` | — |',
          '| `a/` | `specs/a/` | `f01_login` |',
        ]),
        'docs/specs/a/s01_architecture.md': '# A\n',
      };

      final plan = _plan(tree);

      expect(
        _movedTo(plan, 'specs/a/s01_architecture.md'),
        'specs/f01_login/ARCHITECTURE.md',
      );
    });

    test('f06/us01/fr03/e08: a feature_id two feature folders carry places '
        'nothing', () {
      final tree = {
        'docs/prds/features/g1/f01_login/FEATURE.md': '# F-01 — Login\n',
        'docs/prds/features/g2/f01_login/FEATURE.md': '# F-01 — Login\n',
        'docs/specs/INDEX.md': _specIndex([
          '| `x/` | `specs/x/` | `f01_login` |',
        ]),
        'docs/specs/x/s01_architecture.md': '# X\n',
      };

      final plan = _plan(tree);

      expect(plan.left, contains('specs/x/s01_architecture.md'));
      expect(
        plan.moves.map((m) => m.from),
        isNot(contains('specs/x/s01_architecture.md')),
      );
    });
  });
}
