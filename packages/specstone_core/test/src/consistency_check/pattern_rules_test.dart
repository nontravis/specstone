// The expected texts are plan literals kept as written.

import 'dart:io';

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
    expect(found.single.line, 14);
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
    expect(found.single.line, 14);
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
      // `f01_login/not_a_folder` is a 2-slug Name: the grammar drops it (E08).
      ['not_a_folder'],
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

  test('f04/us01/fr08/e08: a code span the grammar reads as a doc address with no lookup is no hit, under the '
      'shipped code_identifier and a project in: code entry', () async {
    const kept = [
      'parseDoc()',
      'doc_model.dart',
      'user_id',
      'prds/features/f01_login/FEATURE.md',
    ];
    const dropped = [
      'affiliate_module/profile',
      'fr:index_query/read_doc_section/resolve_doc_name',
      'feature:index_query',
      'ai:ghost',
    ];
    String lineOf(List<String> spans) =>
        [for (final s in spans) '`$s`'].join(' and ');

    final story = doc(
      loginStory,
      '- **so that** I reach my work',
      '- **so that** I reach my work\n${lineOf([...dropped.take(3), ...kept])}',
    );
    final shipped = await _findings('sections: []\n', edits: story);
    expect(
      shipped
          .where((f) => f.toJson()['pattern'] == 'code_identifier')
          .map((f) => f.toJson()['match']),
      unorderedEquals(kept),
    );

    final project = await _findings(
      _banned(r'''
      - id: any_code
        pattern: '\S+'
        message: no code
        in: code
'''),
      edits: fr(
        checkPasswordStatement,
        'The system shall refuse ${lineOf([...dropped, ...kept])}.',
      ),
    );
    expect(
      project
          .where((f) => f.toJson()['pattern'] == 'any_code')
          .map((f) => f.toJson()['match']),
      unorderedEquals(kept),
    );

    final allScope = await _findings(
      _banned('''
      - id: any_all
        pattern: 'affiliate_module/profile'
        message: all
        in: all
'''),
      edits: fr(
        checkPasswordStatement,
        'The system shall refuse ${lineOf(dropped)}.',
      ),
    );
    expect(
      allScope.where((f) => f.toJson()['pattern'] == 'any_all'),
      hasLength(1),
    );
  });

  test('consistency_check/find_template_breaks/check_patterns E08: a code span whose text before its first colon is no slug is no doc address, so an in: code '
      'entry reports it', () async {
    final findings = await _findings(
      _banned('''
      - id: any_code
        pattern: 'check architecture:login'
        message: no code
        in: code
'''),
      edits: fr(
        checkPasswordStatement,
        'The system shall refuse `check architecture:login`.',
      ),
    );
    expect(
      findings
          .where((f) => f.toJson()['pattern'] == 'any_code')
          .map((f) => f.toJson()['match']),
      ['check architecture:login'],
    );
  });

  test('f04/us01/fr08, f04/nfr-p03, s03/inv2: an edited pattern applies on the next check over the same index', () async {
    String layer(String pattern) => _banned('''
      - id: word
        pattern: '$pattern'
        message: no word
''');
    final project = await writeCheckProject(
      extra: {
        _frLayer: layer('fast'),
        ...fr(checkPasswordStatement, 'The system shall refuse fast, slow.'),
      },
    );
    List<Object?> matched() => [
      for (final f in checkOf(project).findings)
        if (f.kind == FindingKind.patternBanned) f.toJson()['match'],
    ];
    expect(matched(), ['fast']);
    File('${project.path}/$_frLayer').writeAsStringSync(layer('slow'));
    expect(matched(), ['slow']);
  });

  test('f04/us01/fr08, f04/nfr-p03: a doc edited after a check reports its new match and drops the removed one', () async {
    final layer = _banned('''
      - id: word
        pattern: '(fast|slow)'
        message: no word
''');
    final project = await writeCheckProject(
      extra: {
        _frLayer: layer,
        ...fr(checkPasswordStatement, 'The system shall refuse fast.'),
      },
    );
    List<Object?> matched() => [
      for (final f in checkOf(project).findings)
        if (f.kind == FindingKind.patternBanned) f.toJson()['match'],
    ];
    expect(matched(), ['fast']);
    final file = File('${project.path}/docs/$loginFr');
    file.writeAsStringSync(
      file.readAsStringSync().replaceFirst('refuse fast.', 'refuse slowly.'),
    );
    expect(matched(), ['slow']);
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
    expect(missing.single.line, 12);
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
      edits: fr('## Statement\n\n$checkPasswordStatement\n\n', ''),
      kind: FindingKind.patternMissing,
    );
    expect(absent, isEmpty);
  });
}
