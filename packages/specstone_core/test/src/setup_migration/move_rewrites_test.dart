import 'package:specstone_core/src/document_writing/models/path_move.dart';
import 'package:specstone_core/src/setup_migration/move_rewrites.dart';
import 'package:test/test.dart';

const _frFolder = 'prds/features/f01_login/us01_email_login';

void main() {
  group('MoveRewrites.links', () {
    const moves = [
      PathMove(
        from: '$_frFolder/functional_requirements/fr01_validate_credentials.md',
        to: '$_frFolder/fr01_validate_credentials.md',
      ),
      PathMove(from: 'prds/features/NFR.md', to: 'prds/GNFR.md'),
      PathMove(
        from: 'specs/api/auth/s01_architecture.md',
        to: 'specs/api/auth/ARCHITECTURE.md',
      ),
    ];

    test('links to moved files point at the new paths', () {
      final result = MoveRewrites.links(
        '[FR-01](us01_email_login/functional_requirements/'
        'fr01_validate_credentials.md) and [NFRs](../NFR.md)\n',
        docPath: 'prds/features/f01_login/FEATURE.md',
        moves: moves,
      );

      expect(
        result.lf,
        contains('[FR-01](us01_email_login/fr01_validate_credentials.md)'),
      );
      expect(result.lf, contains('[NFRs](../../GNFR.md)'));
      expect(result.label, '2 links');
    });

    test('a doc moved one folder deeper keeps its code '
        'link pointing at the same file', () {
      final result = MoveRewrites.links(
        '[code](../../../lib/a.dart)\n',
        docPath: 'specs/f01/s01.md',
        moves: [
          const PathMove(from: 'specs/f01/s01.md', to: 'specs/f01/sub/s01.md'),
        ],
      );

      expect(result.lf, '[code](../../../../lib/a.dart)\n');
      expect(result.label, '1 link');
    });

    test('a link to a file that stays keeps its target, '
        "and a moved doc's link is recomputed", () {
      const fr = '''
# FR-01 — Validate credentials

See [story](../USER_STORY.md) and [index](../../../../../specs/INDEX.md).
''';

      final result = MoveRewrites.links(
        fr,
        docPath:
            '$_frFolder/functional_requirements/fr01_validate_credentials.md',
        moves: moves,
      );

      expect(
        result.lf,
        fr
            .replaceFirst('(../USER_STORY.md)', '(USER_STORY.md)')
            .replaceFirst(
              '(../../../../../specs/INDEX.md)',
              '(../../../../specs/INDEX.md)',
            ),
      );
      expect(result.label, '2 links');
    });

    test('a link to a moved file that is no .md file points at its new '
        'path', () {
      final result = MoveRewrites.links(
        'See [schema](schema.dbml) and [spec](api.apidog.json).\n',
        docPath: 'specs/INDEX.md',
        moves: [
          const PathMove(
            from: 'specs/schema.dbml',
            to: 'specs/f01_login/schema.dbml',
          ),
          const PathMove(
            from: 'specs/api.apidog.json',
            to: 'specs/f01_login/API.apidog.json',
          ),
        ],
      );

      expect(
        result.lf,
        'See [schema](f01_login/schema.dbml) and '
        '[spec](f01_login/API.apidog.json).\n',
      );
      expect(result.label, '2 links');
    });

    test('no link change gives a null label and the same '
        'text', () {
      const lf = 'See [web](https://x.dev/a.md).\n';

      final result = MoveRewrites.links(
        lf,
        docPath: 'specs/INDEX.md',
        moves: moves,
      );

      expect(result.lf, lf);
      expect(result.label, isNull);
    });

    test('an untyped moved doc gets the link rewrite '
        'only', () {
      const doc = '''
---
name: login
---

# S-02 — login API

[arch](s01_architecture.md)
''';

      final result = MoveRewrites.links(
        doc,
        docPath: 'specs/api/auth/s02_api_login.md',
        moves: moves,
      );

      expect(result.lf, doc.replaceFirst('s01_architecture', 'ARCHITECTURE'));
      expect(result.label, '1 link');
    });
  });

  group('MoveRewrites.headerRenamed', () {
    test('writes a new header over the old one', () {
      expect(
        MoveRewrites.headerRenamed(
          '# T\n\n## Old name\n\nBody.\n',
          'Old name',
          'New name',
        ),
        '# T\n\n## New name\n\nBody.\n',
      );
    });

    test('returns the text unchanged when it has no such header', () {
      const lf = '# T\n\n## Other\n\nBody.\n';

      expect(MoveRewrites.headerRenamed(lf, 'Old name', 'New name'), lf);
    });
  });

  group('MoveRewrites.mentions', () {
    test('asks for each mention from the docs root, a path outside the docs '
        'folder by ../, and follows a moved doc', () {
      final asked = <String>[];
      final result = MoveRewrites.mentions(
        'See b/c.md and ../../src/x.dart.\n',
        docPath: 'prds/a.md',
        moves: [const PathMove(from: 'prds/a.md', to: 'prds/sub/a.md')],
        exists: (path) {
          asked.add(path);
          return true;
        },
      );

      expect(asked, ['prds/b/c.md', '../src/x.dart']);
      expect(result.lf, 'See ../b/c.md and ../../../src/x.dart.\n');
      expect(result.label, '2 mentions');
    });

    test('keeps a mention the docs root does not hold', () {
      final result = MoveRewrites.mentions(
        'See b/c.md.\n',
        docPath: 'prds/a.md',
        moves: [const PathMove(from: 'prds/a.md', to: 'prds/sub/a.md')],
        exists: (path) => false,
      );

      expect(result.lf, 'See b/c.md.\n');
      expect(result.label, isNull);
    });
  });
}
