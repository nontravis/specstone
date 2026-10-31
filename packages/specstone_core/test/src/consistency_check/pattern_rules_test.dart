// The expected texts are plan literals kept as written.

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';

const _frLayer = '.specstone/templates/fr.yaml';

String _banned(String entries) =>
    'lint:\n  banned_patterns:\n    add:\n$entries';

String _sectionLayer(String section, String lintBody) =>
    'sections:\n  - id: $section\n    lint:\n$lintBody';

Future<List<Finding>> _findings(
  String layer, {
  Map<String, String> edits = const {},
  FindingKind kind = FindingKind.patternBanned,
}) async {
  final report = checkOf(
    await writeCheckProject(extra: {_frLayer: layer, ...edits}),
  );
  return [
    for (final f in report.findings)
      if (f.kind == kind) f,
  ];
}

void main() {
  test('f04/us01/fr08/e01: a banned pattern reports its line, message, and three keys', () async {
    final found = await _findings(
      _banned(r'''
      - id: no-fast
        pattern: 'fast\w*'
        message: Say the number
'''),
      edits: fr(
        checkPasswordStatement,
        'The system shall refuse a wrong password fast.',
      ),
    );
    expect(found, hasLength(1));
    expect(found.single.line, 15);
    expect(found.single.message, 'Say the number: fast');
    expect(
      found.single.toJson(),
      allOf(
        containsPair('pattern', 'no-fast'),
        containsPair('section', 'statement'),
        containsPair('match', 'fast'),
      ),
    );
  });

  test('f04/us01/fr08/e02: text skips code spans, code reads only them, all reads the raw line', () async {
    final found = await _findings(
      _banned('''
      - id: t
        pattern: 'fooBar'
        message: text
      - id: c
        pattern: 'fooBar'
        message: code
        in: code
      - id: a
        pattern: 'fooBar'
        message: all
        in: all
'''),
      edits: fr(
        checkPasswordStatement,
        'The system shall refuse `fooBar` and fooBar within 1 s.',
      ),
    );
    expect(
      found.map((f) => f.toJson()['pattern']),
      unorderedEquals(['t', 'c', 'a', 'a']),
    );
  });

  test('f04/us01/fr08/e02: adjacent and empty code spans close in pairs, and '
      'an unclosed backtick leaves the rest of the line text', () async {
    final found = await _findings(
      _banned('''
      - id: t
        pattern: 'zed'
        message: text
      - id: c
        pattern: 'zed'
        message: code
        in: code
      - id: a
        pattern: 'zed'
        message: all
        in: all
'''),
      edits: fr(
        checkPasswordStatement,
        'The system shall refuse `zed``zed` zed `` zed ` zed within 1 s.',
      ),
    );
    final byScope = <Object?, int>{};
    for (final finding in found) {
      final id = finding.toJson()['pattern'];
      byScope[id] = (byScope[id] ?? 0) + 1;
    }
    expect(byScope, {'t': 3, 'c': 2, 'a': 5});
  });

  test('f04/us01/fr08/e03: except clears a full match only', () async {
    final found = await _findings(
      _banned(r'''
      - id: no-fast
        pattern: 'fast\w*'
        message: Say the number
        except: ['fast']
'''),
      edits: fr(
        checkPasswordStatement,
        'The system shall refuse fast and faster within 1 s.',
      ),
    );
    expect(found.map((f) => f.toJson()['match']), ['faster']);
  });

  test(
    'f04/us01/fr08/e04: fenced code, frontmatter, and the title give nothing',
    () async {
      final found = await _findings(
        _banned('''
      - id: zed
        pattern: 'zed'
        message: no zed
'''),
        edits: edit(loginFr, [
          ('# Check the password', '# Check the zed password'),
          ('verify_method: test', 'verify_method: test\nnote: zed'),
          (
            'A wrong password must not sign in.',
            '```\nzed\n```\nA wrong password must not sign in.',
          ),
        ]),
      );
      expect(found, isEmpty);
    },
  );

  test('f04/us01/fr08/e05: a section entry with line_prefix hits only on that line', () async {
    final found = await _findings(
      _sectionLayer('statement', '''
      line_prefix: '- **Statement:**'
      banned_patterns:
        add:
          - id: zed
            pattern: 'zed'
            message: no zed
'''),
      edits: fr(checkPasswordStatement, '- **Statement:** zed here\nzed there'),
    );
    expect(found, hasLength(1));
    expect(found.single.line, 15);
  });

  test('f04/us01/fr08/e07: a match naming a doc-tree folder, or a run of them, gives nothing', () async {
    final found = await _findings(
      _banned(r'''
      - id: code
        pattern: '^\S*_\S*$'
        message: no identifier
        in: code
'''),
      edits: fr(
        checkPasswordStatement,
        'The system shall refuse `f01_login` and `f01_login/us01_email_login` '
        'and `not_a_folder` and `f01_login/not_a_folder` within 1 s.',
      ),
    );
    expect(
      found.map((f) => f.toJson()['match']),
      unorderedEquals(['not_a_folder', 'f01_login/not_a_folder']),
    );

    final allScope = await _findings(
      _banned('''
      - id: tree
        pattern: 'docs/superpowers'
        message: no journal path
        in: all
'''),
      edits: {
        'docs/superpowers/specs/x.md': '# X\n',
        ...fr(
          checkPasswordStatement,
          'The system shall refuse a wrong password, see '
          'docs/superpowers/specs/x.md.',
        ),
      },
    );
    // The shipped doc_citation entry also fires here; only `tree` is ours.
    final own = allScope.where((f) => f.toJson()['pattern'] == 'tree');
    expect(own.map((f) => f.toJson()['match']), ['docs/superpowers']);
  });

  test('f04/us01/fr08/e06: a required pattern no line matches reports at the header; an absent section reports none', () async {
    const layer = '''
sections:
  - id: statement
    lint:
      required_patterns:
        - id: shall
          pattern: 'shall'
          message: Write a shall
''';
    final missing = await _findings(
      layer,
      edits: fr(checkPasswordStatement, 'The system refuses a wrong password.'),
      kind: FindingKind.patternMissing,
    );
    expect(missing, hasLength(1));
    expect(missing.single.line, 14);
    expect(missing.single.message, 'Write a shall');
    expect(
      missing.single.toJson(),
      allOf(
        containsPair('pattern', 'shall'),
        containsPair('section', 'statement'),
      ),
    );

    expect(await _findings(layer, kind: FindingKind.patternMissing), isEmpty);

    final absent = await _findings(
      layer,
      edits: fr('## Statement\n$checkPasswordStatement\n\n', ''),
      kind: FindingKind.patternMissing,
    );
    expect(absent, isEmpty);
  });
}
