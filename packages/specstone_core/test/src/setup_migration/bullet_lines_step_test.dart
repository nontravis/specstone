import 'package:specstone_core/src/setup_migration/bullet_lines_step.dart';
import 'package:test/test.dart';

const _prefixes = ['**Serves:**', '**Statement:**', '**Metric:**', '**By:**'];

String _bulleted(String lf, {String header = 'Project goals'}) =>
    withLinesBulleted(lf, header: header, prefixes: _prefixes);

void main() {
  group('withLinesBulleted', () {
    test('bullets a line that opens with a listed prefix and keeps a bullet '
        'line as written', () {
      const lf =
          '# Project\n\n## Project goals\n\n### PG-01 — Cost\n\n'
          '**Serves:** PV-01\n- **By:** v1.0 release\n';

      expect(
        _bulleted(lf),
        '# Project\n\n## Project goals\n\n### PG-01 — Cost\n\n'
        '- **Serves:** PV-01\n- **By:** v1.0 release\n',
      );
    });

    test('leaves other sections and a bullet line as written', () {
      const lf =
          '# Project\n\n## Vision\n\n**Serves:** PV-01\n\n'
          '## Project goals\n\n**Statement:** Cut cost.\n'
          '- **Metric:** 3 calls\n**Other:** kept\n\n'
          '## Roles\n\n**By:** Owner\n';

      expect(
        _bulleted(lf),
        '# Project\n\n## Vision\n\n**Serves:** PV-01\n\n'
        '## Project goals\n\n- **Statement:** Cut cost.\n'
        '- **Metric:** 3 calls\n**Other:** kept\n\n'
        '## Roles\n\n**By:** Owner\n',
      );
    });

    test('returns a doc with no such section unchanged', () {
      const lf = '# Project\n\n## Vision\n\n**Serves:** PV-01\n';

      expect(_bulleted(lf), lf);
    });

    test('bullets a prefix line inside fenced code', () {
      const lf =
          '## Project goals\n\n```\n**Serves:** PV-01\n```\n'
          '\n## Roles\n\n**Serves:** x\n';

      expect(
        _bulleted(lf),
        '## Project goals\n\n```\n- **Serves:** PV-01\n```\n'
        '\n## Roles\n\n**Serves:** x\n',
      );
    });

    test('matches the section by header key, so a renamed case or spacing '
        'still matches', () {
      const lf = '## project   GOALS\n\n**By:** v1\n';

      expect(_bulleted(lf), '## project   GOALS\n\n- **By:** v1\n');
    });

    test('keeps the frontmatter and the end of the text as written', () {
      const lf = '---\nowner: sre\n---\n# P\n\n## Project goals\n\n**By:** v1';

      expect(
        _bulleted(lf),
        '---\nowner: sre\n---\n# P\n\n## Project goals\n\n- **By:** v1',
      );
    });
  });
}
