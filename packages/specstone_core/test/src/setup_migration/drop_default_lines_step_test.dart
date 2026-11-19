import 'dart:convert';

import 'package:specstone_core/src/setup_migration/drop_default_lines_step.dart';
import 'package:specstone_core/src/setup_migration/legacy_rewrites.dart'
    show readDocText, writtenText;
import 'package:test/test.dart';

String _dropped(
  String lf, {
  String? defaultEnforcer = 'Account',
  bool dropsConsistency = true,
}) => withDefaultLinesDropped(
  lf,
  invariantsHeader: 'Invariants',
  defaultEnforcer: defaultEnforcer,
  dropsConsistency: dropsConsistency,
);

String _invariants(String body) => '# Domain\n\n## Invariants\n\n$body\n';

void main() {
  group('withDefaultLinesDropped', () {
    test('an exact immediate line goes', () {
      const lf =
          '---\nowner: sre\n---\n# Domain\n\n## Invariants\n\n'
          '- **INV-1** An email is unique.\n'
          '  - **Consistency:** immediate\n'
          '- **INV-2** A name is short.\n'
          '  - **Consistency:** immediate';

      expect(
        _dropped(lf),
        '---\nowner: sre\n---\n# Domain\n\n## Invariants\n\n'
        '- **INV-1** An email is unique.\n'
        '- **INV-2** A name is short.',
      );
    });

    test('under multi-line frontmatter the default lines go at their own '
        'lines and the frontmatter stays', () {
      const frontmatter =
          '---\nowner: sre\nnote: |\n'
          '  - **Consistency:** immediate\n'
          'tags: [a, b]\n---\n';
      const lf =
          '$frontmatter# Domain\n\nLead text.\n\n## Invariants\n\n'
          '- **INV-1** An email is unique.\n'
          '  - **Consistency:** immediate\n'
          '  - **Enforcer:** Account\n'
          '- **INV-2** A name is short.\n'
          '  - **Consistency:** eventual';

      final dropped = _dropped(lf);

      expect(dropped.startsWith(frontmatter), isTrue);
      expect(
        dropped,
        '$frontmatter# Domain\n\nLead text.\n\n## Invariants\n\n'
        '- **INV-1** An email is unique.\n'
        '- **INV-2** A name is short.\n'
        '  - **Consistency:** eventual',
      );
    });

    test('an Enforcer naming the default goes with its parenthesized '
        'link', () {
      final lf = _invariants(
        '- **INV-1** An email is unique.\n'
        '  - **Enforcer:** Account\n'
        '- **INV-2** A name is short.\n'
        '  - **Enforcer:** `Account` ([domain:accounts](../DOMAIN.md))\n'
        '- **INV-3** A mail is sent.\n'
        '  - **Enforcer:** Account (see below)',
      );

      expect(
        _dropped(lf),
        _invariants(
          '- **INV-1** An email is unique.\n'
          '- **INV-2** A name is short.\n'
          '- **INV-3** A mail is sent.\n'
          '  - **Enforcer:** Account (see below)',
        ),
      );
    });

    test('a capitalised or longer Consistency text stays', () {
      final lf = _invariants(
        '- **INV-1** One.\n'
        '  - **Consistency:** Immediate\n'
        '- **INV-2** Two.\n'
        '  - **Consistency:** immediate, within one request\n'
        '- **INV-3** Three.\n'
        '  - **Consistency:** immediately',
      );

      expect(_dropped(lf), lf);
    });

    test('an eventual line and its policy stay', () {
      final lf = _invariants(
        '- **INV-1** One.\n'
        '  - **Enforcer:** Account\n'
        '  - **Consistency:** eventual\n'
        '  - **Corrective policy:** Sweep each night.',
      );

      expect(
        _dropped(lf),
        _invariants(
          '- **INV-1** One.\n'
          '  - **Consistency:** eventual\n'
          '  - **Corrective policy:** Sweep each night.',
        ),
      );
    });

    test('an Enforcer naming a non-default entity stays', () {
      final lf = _invariants(
        '- **INV-1** One.\n'
        '  - **Enforcer:** Setup and migration engine\n'
        '  - **Consistency:** immediate\n'
        '- **INV-2** Two.\n'
        '  - **Enforcer:** account',
      );

      expect(
        _dropped(lf),
        _invariants(
          '- **INV-1** One.\n'
          '  - **Enforcer:** Setup and migration engine\n'
          '- **INV-2** Two.\n'
          '  - **Enforcer:** account',
        ),
      );
    });

    test('with no default every Enforcer stays', () {
      final lf = _invariants(
        '- **INV-1** One.\n'
        '  - **Enforcer:** Account\n'
        '  - **Consistency:** immediate',
      );

      expect(
        _dropped(lf, defaultEnforcer: null),
        _invariants('- **INV-1** One.\n  - **Enforcer:** Account'),
      );
    });

    test('a Consistency line stays when the caller does not free it', () {
      final lf = _invariants(
        '- **INV-1** One.\n'
        '  - **Enforcer:** Account\n'
        '  - **Consistency:** immediate',
      );

      expect(
        _dropped(lf, dropsConsistency: false),
        _invariants(
          '- **INV-1** One.\n'
          '  - **Consistency:** immediate',
        ),
      );
    });

    test('other nested bullets stay', () {
      final lf = _invariants(
        '- **INV-1** One.\n'
        '  - a condition\n'
        '  - **Note:** kept\n'
        '  - **Enforcer:** Account\n'
        '  - **Consistency:** immediate\n\n'
        '### Group\n\n'
        '- **INV-2** Two.\n'
        '  - **Consistency:** immediate',
      );

      expect(
        _dropped(lf),
        _invariants(
          '- **INV-1** One.\n'
          '  - a condition\n'
          '  - **Note:** kept\n\n'
          '### Group\n\n'
          '- **INV-2** Two.',
        ),
      );
    });

    test('a default line that holds a nested bullet stays with it', () {
      final lf = _invariants(
        '- **INV-1** One.\n'
        '  - **Consistency:** immediate\n'
        '    - a note on it\n'
        '  - **Enforcer:** Account\n'
        '    - another note\n'
        '- **INV-2** Two.\n'
        '  - **Enforcer:** Account\n'
        '  - **Consistency:** immediate',
      );

      expect(
        _dropped(lf),
        _invariants(
          '- **INV-1** One.\n'
          '  - **Consistency:** immediate\n'
          '    - a note on it\n'
          '  - **Enforcer:** Account\n'
          '    - another note\n'
          '- **INV-2** Two.',
        ),
      );
    });

    test('a default line outside the invariants section, outside fenced '
        'code, or not nested under an item stays', () {
      const stay =
          '- **Consistency:** immediate\n'
          '- **Enforcer:** Account\n'
          'Plain text.\n'
          '- **Enforcer:** Account\n'
          '```\n'
          '- **INV-9** Nine.\n'
          '  - **Consistency:** immediate\n'
          '```';
      const lf =
          '# Domain\n\n## Entities\n\n- **E1** One.\n'
          '  - **Consistency:** immediate\n\n'
          '## Invariants\n\n$stay\n\n'
          '## Notes\n\n- **N1** One.\n'
          '  - **Enforcer:** Account\n';

      expect(_dropped(lf), lf);
    });

    test('a doc with no invariants section is unchanged', () {
      const lf =
          '# Domain\n\n## Entities\n\n- **E1** One.\n  - **Enforcer:** '
          'Account\n';

      expect(_dropped(lf), lf);
    });

    test('a rerun leaves the text as it is', () {
      final lf = _invariants(
        '- **INV-1** One.\n'
        '  - **Enforcer:** Account\n'
        '  - **Consistency:** immediate\n'
        '- **INV-2** Two.\n'
        '  - **Enforcer:** Other\n'
        '  - **Consistency:** eventual',
      );

      final once = _dropped(lf);

      expect(once, isNot(lf));
      expect(_dropped(once), once);
    });

    test('CRLF input stays CRLF', () {
      const crlf =
          '# Domain\r\n\r\n## Invariants\r\n\r\n'
          '- **INV-1** One.\r\n'
          '  - **Enforcer:** Account\r\n'
          '  - **Consistency:** immediate\r\n';
      final original = readDocText(utf8.encode(crlf));

      final written = writtenText(original, _dropped(original.lf));

      expect(
        written,
        '# Domain\r\n\r\n## Invariants\r\n\r\n- **INV-1** One.\r\n',
      );
    });
  });

  group('defaultEnforcerAmong', () {
    String doc(String rows) =>
        '# Domain\n\n## Entities\n\n| Entity | Kind |\n|---|---|\n$rows\n';

    test('the doc decides when its table holds an aggregate root', () {
      final own = doc('| Account | Aggregate root |');
      final parent = doc('| Engine | Service |');

      expect(
        defaultEnforcerAmong([own, parent], entitiesHeader: 'Entities'),
        'Account',
      );
    });

    test('the nearest text with a root or service decides, and a text with '
        'no such table is passed over', () {
      final own = doc('| Finding | Entity |');
      const bare = '# Domain\n';
      final parent = doc('| Engine | Service |');
      final grand = doc('| Account | Aggregate root |');

      expect(
        defaultEnforcerAmong([
          own,
          bare,
          parent,
          grand,
        ], entitiesHeader: 'Entities'),
        'Engine',
      );
    });

    test('two aggregate roots in the doc give no default, though its parent '
        'holds one root', () {
      final own = doc(
        '| Account | Aggregate root |\n| Cart | Aggregate root |',
      );
      final parent = doc('| Engine | Aggregate root |');

      expect(
        defaultEnforcerAmong([own, parent], entitiesHeader: 'Entities'),
        isNull,
      );
    });

    test('no text with a root or service gives no default', () {
      expect(
        defaultEnforcerAmong([
          doc('| Finding | Entity |'),
        ], entitiesHeader: 'Entities'),
        isNull,
      );
    });
  });
}
