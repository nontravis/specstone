import 'package:specstone_core/src/setup_migration/drop_section_step.dart';
import 'package:test/test.dart';

String _dropped(String lf, {String header = 'Open questions'}) =>
    withSectionDropped(lf, header: header);

void main() {
  group('withSectionDropped', () {
    test('a matching header and its body leave the doc', () {
      const lf =
          '# Doc\n\n## Goal\n\nKeep.\n\n'
          '## Open questions\n\nWho?\n\n- One\n\n'
          '## Rules\n\nKeep too.\n';

      expect(
        _dropped(lf),
        '# Doc\n\n## Goal\n\nKeep.\n\n## Rules\n\nKeep too.\n',
      );
    });

    test('the header matches by case and spacing', () {
      const lf =
          '# Doc\n\n## Goal\n\nKeep.\n\n##   OPEN   questions \n\nWho?\n';

      expect(_dropped(lf), '# Doc\n\n## Goal\n\nKeep.\n');
    });

    test('a doc with no such header is unchanged', () {
      const lf = '# Doc\n\n## Goal\n\nKeep.\n';

      expect(_dropped(lf), lf);
    });

    test('a fenced header line neither starts nor ends a section', () {
      const lf =
          '# Doc\n\n## Goal\n\n```\n## Open questions\n```\n\nKeep.\n\n'
          '## Open questions\n\nWho?\n\n```\n## Rules\n```\n\nStill gone.\n\n'
          '## Rules\n\nKeep too.\n';

      expect(
        _dropped(lf),
        '# Doc\n\n## Goal\n\n```\n## Open questions\n```\n\nKeep.\n\n'
        '## Rules\n\nKeep too.\n',
      );
    });

    test('frontmatter and the head stay as written', () {
      const lf =
          '---\nowner: sre\n---\n# Doc\n\nLead.\n\n## Open questions\n\n'
          'Who?\n\n## Goal\n\nKeep.\n';

      expect(
        _dropped(lf),
        '---\nowner: sre\n---\n# Doc\n\nLead.\n\n## Goal\n\nKeep.\n',
      );
    });

    test('two sections of the matching header both leave', () {
      const lf =
          '# Doc\n\n## Open questions\n\nFirst.\n\n## Goal\n\nKeep.\n\n'
          '## Open questions\n\nSecond.\n\n## Rules\n\nKeep too.\n';

      expect(
        _dropped(lf),
        '# Doc\n\n## Goal\n\nKeep.\n\n## Rules\n\nKeep too.\n',
      );
    });

    test('the last section leaves exactly one trailing newline', () {
      const lf = '# Doc\n\n## Goal\n\nKeep.\n\n## Open questions\n\nWho?\n';

      expect(_dropped(lf), '# Doc\n\n## Goal\n\nKeep.\n');
    });

    test('a kept last line keeps its trailing spaces when the last section '
        'drops', () {
      const lf = '# Doc\n\n## Goal\n\nKeep.  \n\n## Open questions\n\nWho?\n';

      expect(_dropped(lf), '# Doc\n\n## Goal\n\nKeep.  \n');
    });

    test('the last section with trailing blank lines leaves exactly one '
        'trailing newline', () {
      const lf = '# Doc\n\n## Goal\n\nKeep.\n\n## Open questions\n\nWho?\n\n\n';

      expect(_dropped(lf), '# Doc\n\n## Goal\n\nKeep.\n');
    });
  });
}
