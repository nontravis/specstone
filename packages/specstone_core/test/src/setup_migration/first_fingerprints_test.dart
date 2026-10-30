import 'package:specstone_core/src/consistency_check/fingerprint.dart';
import 'package:specstone_core/src/setup_migration/first_fingerprints.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const _fr =
    'prds/features/f04_check/us01_find_template_breaks/functional_requirements/fr01_check_target.md';
const _frText =
    '---\nname: fr01_check_target\n---\n\n# FR-01 — Check target\n'
    '\n## Statement\nWhen check runs, the system shall read the target.\n'
    '\n## Edge cases\n1. E01 — none.\n';
const _statement = 'When check runs, the system shall read the target.\n';

String _api(List<String> cells, {String frontmatter = '---\n---\n'}) =>
    '$frontmatter\n# check API\n\n## FR trace\n\n| FR id | Method |\n'
    '|-------|--------|\n${cells.map((cell) => '| $cell | CLI |\n').join()}';

void main() {
  group('writeFirstFingerprints', () {
    test('f06/us01/fr06/e01: a cell naming one existing FR becomes its FRRef and gains a confirmed entry', () {
      final api = _api(['`us01/fr01_check_target`']);

      final out = writeFirstFingerprints(api, featureFrs: {_fr: _frText});

      final fp = fingerprintOf(_statement);
      expect(out.lf, contains('| `find_template_breaks/check_target` | CLI |'));
      expect(
        out.lf,
        startsWith(
          '---\nconfirmed:\n  - find_template_breaks/check_target $fp\n---\n',
        ),
      );
      expect(fp, matches(RegExp(r'^[0-9a-f]{12}$')));
      expect(out.label, 'confirmed (1)');
    });

    test('f06/us01/fr06, s03/inv12: a flow-list confirmed stays as written, '
        'with no entry, and the FR cell is still rewritten', () {
      final api = _api([
        '`us01/fr01_check_target`',
      ], frontmatter: '---\nconfirmed: [x]\n---\n');

      final out = writeFirstFingerprints(api, featureFrs: {_fr: _frText});

      expect(
        out.lf,
        api.replaceFirst(
          '`us01/fr01_check_target`',
          '`find_template_breaks/check_target`',
        ),
      );
      expect(out.label, isNull);
    });

    test('f06/us01/fr06/e02: a cell naming no FR, two FRs, or a missing FR stays and gets no entry', () {
      final api = _api([
        '—',
        '`us01/fr01, us01/fr02`',
        '`us01/fr09_gone`',
        '`us02/fr01`',
      ]);

      final out = writeFirstFingerprints(api, featureFrs: {_fr: _frText});

      expect(out.lf, api);
      expect(out.label, isNull);
    });

    test('f06/us01/fr06/e02: a cell whose numbers match two FR files stays', () {
      const twin =
          'prds/features/f04_check/us01_other_story/functional_requirements/fr01_other.md';
      final api = _api(['`us01/fr01`']);

      final out = writeFirstFingerprints(
        api,
        featureFrs: {_fr: _frText, twin: _frText},
      );

      expect(out.lf, api);
      expect(out.label, isNull);
    });

    test('f06/us01/fr06: a cell may omit the slugs or the backticks', () {
      final api = _api(['`us01/fr01`', 'us1/fr1_check_target']);

      final out = writeFirstFingerprints(api, featureFrs: {_fr: _frText});

      final fp = fingerprintOf(_statement);
      expect(out.lf, contains('| `find_template_breaks/check_target` | CLI |'));
      expect(out.lf, contains('| find_template_breaks/check_target | CLI |'));
      expect(
        out.lf,
        startsWith(
          '---\nconfirmed:\n  - find_template_breaks/check_target $fp\n---\n',
        ),
      );
      expect(out.label, 'confirmed (1)');
    });

    test('f06/us01/fr06: a written slug that differs keeps the cell', () {
      final api = _api(['`us01_wrong_story/fr01`', '`us01/fr01_wrong`']);

      final out = writeFirstFingerprints(api, featureFrs: {_fr: _frText});

      expect(out.lf, api);
      expect(out.label, isNull);
    });

    test('f06/us01/fr06: an FR with no Statement hashes the empty text', () {
      const bare =
          '---\nname: fr01_check_target\n---\n\n# FR-01 — Check target\n';
      final api = _api(['`us01/fr01`']);

      final out = writeFirstFingerprints(api, featureFrs: {_fr: bare});

      expect(
        out.lf,
        startsWith(
          '---\nconfirmed:\n  - find_template_breaks/check_target ${fingerprintOf('')}\n---\n',
        ),
      );
    });

    test('f06/us01/fr06: an existing confirmed block gains the entry', () {
      final api = _api(
        ['`us01/fr01`'],
        frontmatter:
            '---\nstatus: planned\nconfirmed:\n  - S1 0123456789ab\n---\n',
      );

      final out = writeFirstFingerprints(api, featureFrs: {_fr: _frText});

      expect(
        out.lf,
        startsWith(
          '---\nstatus: planned\nconfirmed:\n  - S1 0123456789ab\n'
          '  - find_template_breaks/check_target ${fingerprintOf(_statement)}\n---\n',
        ),
      );
    });

    for (final (name, prefix) in [
      ('zero-indent', '- '),
      ('four-space', '    - '),
    ])
      test('f06/us01/fr06: a $name confirmed list gains the entry with its '
          'own prefix, as its own item', () {
        final api = _api([
          '`us01/fr01`',
        ], frontmatter: '---\nconfirmed:\n${prefix}S1 0123456789ab\n---\n');

        final out = writeFirstFingerprints(api, featureFrs: {_fr: _frText});

        final front = out.lf.substring(4, out.lf.indexOf('\n---\n', 4) + 1);
        expect((loadYaml(front) as YamlMap)['confirmed'], [
          'S1 0123456789ab',
          'find_template_breaks/check_target ${fingerprintOf(_statement)}',
        ]);
        expect(out.lf, contains('${prefix}find_template_breaks/'));
      });

    test('f06/us01/fr06: a doc without frontmatter gains one', () {
      const api =
          '# check API\n\n## FR trace\n\n| FR id | Method |\n|---|---|\n| `us01/fr01` | CLI |\n';

      final out = writeFirstFingerprints(api, featureFrs: {_fr: _frText});

      expect(
        out.lf,
        startsWith(
          '---\nconfirmed:\n  - find_template_breaks/check_target ${fingerprintOf(_statement)}\n---\n# check API',
        ),
      );
    });

    test('f06/us01/fr06: one FR named by two rows gets one entry', () {
      final api = _api(['`us01/fr01`', '`us01/fr01_check_target`']);

      final out = writeFirstFingerprints(api, featureFrs: {_fr: _frText});

      final entry =
          'find_template_breaks/check_target ${fingerprintOf(_statement)}';
      expect(entry.allMatches(out.lf), hasLength(1));
      expect(
        '`find_template_breaks/check_target`'.allMatches(out.lf),
        hasLength(2),
      );
      expect(out.label, 'confirmed (1)');
    });

    test('f06/us01/fr06: a doc without an FR trace section is unchanged', () {
      const api =
          '---\n---\n\n# check API\n\n## Models\n\n| `us01/fr01` | x |\n';

      final out = writeFirstFingerprints(api, featureFrs: {_fr: _frText});

      expect(out.lf, api);
      expect(out.label, isNull);
    });

    test('f06/us01/fr06: a fenced example row is neither rewritten '
        'nor fingerprinted', () {
      const api =
          '---\n---\n\n# check API\n\n## FR trace\n\n| FR id | Method |\n'
          '|---|---|\n```\n| us01/fr01 | CLI |\n```\n';

      final out = writeFirstFingerprints(api, featureFrs: {_fr: _frText});

      expect(out.lf, api);
      expect(out.label, isNull);
    });

    test('f06/us01/fr06: a fenced ## line does not end the trace', () {
      const api =
          '---\n---\n\n# check API\n\n## FR trace\n\n| FR id | Method |\n'
          '|---|---|\n```\n## not a header\n```\n| `us01/fr01` | CLI |\n';

      final out = writeFirstFingerprints(api, featureFrs: {_fr: _frText});

      expect(out.lf, contains('| `find_template_breaks/check_target` | CLI |'));
      expect(out.label, 'confirmed (1)');
    });

    test('f06/us01/fr06: two FR files sharing a slug keep their own '
        'statements', () {
      const first =
          'prds/features/f04_check/us01_find/functional_requirements/'
          'fr01_check.md';
      const second =
          'prds/features/f04_check/us01_find/functional_requirements/'
          'fr02_check.md';
      String fr(String statement) =>
          '---\n---\n\n# FR\n\n## Statement\n'
          '$statement\n';
      final api = _api(['`us01/fr01`']);

      final out = writeFirstFingerprints(
        api,
        featureFrs: {first: fr('First.'), second: fr('Second.')},
      );

      expect(out.lf, contains('  - find/check ${fingerprintOf('First.\n')}\n'));
    });
  });
}
