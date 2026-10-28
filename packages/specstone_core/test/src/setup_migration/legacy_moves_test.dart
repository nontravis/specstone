import 'package:specstone_core/src/setup_migration/legacy_moves.dart';
import 'package:specstone_core/src/setup_migration/legacy_tree.dart';
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

    test('f06/us01/fr03/e12: a second cross-cutting folder of the same last '
        'segment never overwrites the first', () {
      final tree = {
        'docs/specs/INDEX.md': _specIndex([
          '| `a/` | `specs/a/shared/` | — |',
          '| `b/` | `specs/b/shared/` | — |',
        ]),
        'docs/specs/a/shared/s01_architecture.md': '# A\n',
        'docs/specs/b/shared/s01_architecture.md': '# B\n',
      };

      final plan = _plan(tree);

      expect(plan.moves, [
        (
          from: 'specs/a/shared/s01_architecture.md',
          to: 'specs/topics/shared/s01_architecture.md',
        ),
      ]);
      expect(plan.left, [
        'specs/INDEX.md',
        'specs/b/shared/s01_architecture.md',
      ]);
    });

    test('f06/us01/fr05/e09: a move onto a file already in place is '
        'dropped', () {
      final plan = _plan({
        ...acmeLegacy,
        'docs/prds/FEATURES.md': '# Features\n',
      });

      expect(
        plan.left,
        containsAll(['prds/d02_features.md', 'prds/FEATURES.md']),
      );
      expect(plan.kindOf, isNot(contains('prds/FEATURES.md')));
      expect(plan.moves.map((m) => m.to), isNot(contains('prds/FEATURES.md')));
      expect(plan.fromOf, isNot(contains('prds/FEATURES.md')));
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

    test('f06/us01/fr05/e09: no move lands on a path a later move has not '
        'yet left', () {
      final tree = {
        'docs/prds/features/f01_login/FEATURE.md': '# F-01 — Login\n',
        'docs/specs/INDEX.md': _specIndex([
          '| `topics/shared/` | `specs/topics/shared/` | `f01_login` |',
          '| `shared/` | `specs/shared/` | — |',
        ]),
        'docs/specs/shared/s01_architecture.md': '# Shared\n',
        'docs/specs/topics/shared/s01_architecture.md': '# Login\n',
      };

      final plan = _plan(tree);

      expect(plan.moves, [
        (
          from: 'specs/topics/shared/s01_architecture.md',
          to: 'specs/f01_login/ARCHITECTURE.md',
        ),
      ]);
      expect(plan.left, contains('specs/shared/s01_architecture.md'));
      expect(
        plan.fromOf,
        isNot(
          contains(
            'specs/topics/shared/'
            's01_architecture.md',
          ),
        ),
      );
    });

    test('f06/us01/fr05/e09: a dropped move blocks the move that targets '
        'its source', () {
      final tree = {
        'docs/prds/features/f01_login/FEATURE.md': '# F-01 — Login\n',
        'docs/specs/INDEX.md': _specIndex([
          '| `topics/shared/` | `specs/topics/shared/` | `f01_login` |',
          '| `shared/` | `specs/shared/` | — |',
        ]),
        'docs/specs/f01_login/ARCHITECTURE.md': '# In place\n',
        'docs/specs/shared/s01_architecture.md': '# Shared\n',
        'docs/specs/topics/shared/s01_architecture.md': '# Login\n',
      };

      final plan = _plan(tree);

      expect(plan.moves, isEmpty);
      expect(
        plan.left,
        containsAll([
          'specs/f01_login/ARCHITECTURE.md',
          'specs/shared/s01_architecture.md',
          'specs/topics/shared/s01_architecture.md',
        ]),
      );
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
