// The expected texts are plan literals kept as written.

import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';

const _frLayer = '.specstone/templates/fr.yaml';

late Directory _project;

String _banned(String entries) =>
    'lint:\n  banned_patterns:\n    add:\n$entries';

String _sectionLayer(String section, String lintBody) =>
    'sections:\n  - id: $section\n    lint:\n$lintBody';

Future<List<Finding>> _findings(
  String layer, {
  Map<String, String> edits = const {},
  FindingKind kind = FindingKind.patternBanned,
}) async {
  final report = await checkOf(
    await writeCheckProject(extra: {_frLayer: layer, ...edits}),
  );
  return [
    for (final f in report.findings)
      if (f.kind == kind) f,
  ];
}

void main() {
  test('a banned pattern reports its line, message, and three keys', () async {
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

  test(
    'text skips code spans, code reads only them, all reads the raw line',
    () async {
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
    },
  );

  test('adjacent and empty code spans close in pairs, and '
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

  test('except clears a full match only', () async {
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

  test('fenced code, frontmatter, and the title give nothing', () async {
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
  });

  test('a section entry with line_prefix hits only on that line', () async {
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

  test('doc-level entries hit every line of a line_prefix section, a section '
      'entry only the prefixed one', () async {
    final found = await _findings(
      '${_banned('''
      - id: zed
        pattern: 'zed'
        message: no zed
''')}${_sectionLayer('statement', '''
      line_prefix: '- **Statement:**'
      banned_patterns:
        add:
          - id: here
            pattern: 'here'
            message: no here
''')}',
      edits: fr(checkPasswordStatement, '- **Statement:** zed here\nzed there'),
    );
    expect([
      for (final f in found) (f.toJson()['pattern'], f.line),
    ], unorderedEquals([('zed', 14), ('zed', 15), ('here', 14)]));
  });

  test('a match naming a doc-tree folder, or a run of them, '
      'gives nothing', () async {
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

  test('text and all entries still report a bare folder name', () async {
    final found = await _findings(
      _banned('''
      - id: by-text
        pattern: 'f01_login'
        message: no folder
      - id: by-all
        pattern: 'us01_email_login'
        message: no folder
        in: all
'''),
      edits: fr(
        checkPasswordStatement,
        'The system shall refuse f01_login and `us01_email_login` within 1 s.',
      ),
    );
    expect(
      [for (final f in found) (f.toJson()['pattern'], f.toJson()['match'])],
      unorderedEquals([
        ('by-text', 'f01_login'),
        ('by-all', 'us01_email_login'),
      ]),
    );
  });

  test('a span naming a doc the project holds is no hit, as an absent '
      'name is none', () async {
    final found = await _findings(
      _banned(r'''
      - id: any_code
        pattern: '\S+'
        message: no code
        in: code
'''),
      edits: fr(
        checkPasswordStatement,
        'The system shall refuse `login/email_login` and '
        '`fr:login/email_login/check_password` and `feature:login` '
        'and `parseDoc()` within 1 s.',
      ),
    );
    expect(found.map((f) => f.toJson()['match']).toSet(), {'parseDoc()'});
  });

  test('a code span the grammar reads as a doc address with no lookup is no '
      'hit, under the '
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

  test('a code span whose text before its first colon is no slug is no '
      'doc address, so an in: code '
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

  test(
    'an edited pattern applies on the next check over the same index',
    () async {
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
      Future<List<Object?>> matched() async => [
        for (final f in (await checkOf(project)).findings)
          if (f.kind == FindingKind.patternBanned) f.toJson()['match'],
      ];
      expect(await matched(), ['fast']);
      File('${project.path}/$_frLayer').writeAsStringSync(layer('slow'));
      expect(await matched(), ['slow']);
    },
  );

  test('a doc edited after a check reports its new match and drops the removed '
      'one', () async {
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
    Future<List<Object?>> matched() async => [
      for (final f in (await checkOf(project)).findings)
        if (f.kind == FindingKind.patternBanned) f.toJson()['match'],
    ];
    expect(await matched(), ['fast']);
    final file = File('${project.path}/docs/$loginFr');
    file.writeAsStringSync(
      file.readAsStringSync().replaceFirst('refuse fast.', 'refuse slowly.'),
    );
    expect(await matched(), ['slow']);
  });

  test('a required pattern no line matches reports at the header; an absent '
      'section reports none', () async {
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

  group('per_subsection', () {
    const layer = '''
sections:
  - id: edge_cases
    lint:
      required_patterns:
        - id: labelled
          pattern: 'Label:'
          message: Write a Label
          per_subsection: true
''';

    Map<String, String> edgeCases(String body) =>
        fr('1. E01 — An empty password → refused.', body);

    test('a subsection lacking the pattern reports at its heading with the '
        'subsection key', () async {
      final found = await _findings(
        layer,
        edits: edgeCases(
          '### First\n\nLabel: set\n\n### Second\n\nno label here',
        ),
        kind: FindingKind.patternMissing,
      );
      expect(found, hasLength(1));
      expect(found.single.line, 22);
      expect(found.single.message, 'Write a Label');
      expect(
        found.single.toJson(),
        allOf(
          containsPair('pattern', 'labelled'),
          containsPair('section', 'edge_cases'),
          containsPair('subsection', 'Second'),
        ),
      );
      expect(found.single.waitsFor, WaitsFor.agent);
    });

    test('a pattern held by one subsection does not cover the other', () async {
      final found = await _findings(
        layer,
        edits: edgeCases('### First\n\nLabel: set\n\n### Second\n\nnone'),
        kind: FindingKind.patternMissing,
      );
      expect(found.map((f) => f.toJson()['subsection']), ['Second']);
    });

    test('a section with no subsection has no finding', () async {
      final found = await _findings(layer, kind: FindingKind.patternMissing);
      expect(found, isEmpty);
    });

    test('a fenced ### line opens no subsection', () async {
      final found = await _findings(
        layer,
        edits: edgeCases('### First\n\nLabel: set\n\n```\n### Fake\n```'),
        kind: FindingKind.patternMissing,
      );
      expect(found, isEmpty);
    });
  });

  group('on a prose field value', () {
    const featureLayer = '.specstone/templates/feature.yaml';
    const summaryLine = 'summary: Lets an agent sign in.';

    Future<List<Finding>> fieldFindings(
      String summary, {
      String layer = '',
    }) async {
      _project = await writeCheckProject(
        extra: {
          if (layer.isNotEmpty) featureLayer: layer,
          ...doc(loginFeature, summaryLine, 'summary: $summary'),
        },
      );
      final report = await checkOf(_project);
      return [
        for (final f in report.findings)
          if (f.kind == FindingKind.patternBanned) f,
      ];
    }

    String codeEntry(String pattern) => _banned(
      '      - id: code-name\n'
      "        pattern: '$pattern'\n"
      '        message: Name it\n'
      '        in: code\n',
    );

    test('a doc-level pattern reports on the key line under field', () async {
      final found = await fieldFindings('Applies the ruling to sign in.');
      expect(found, hasLength(1));
      expect(found.single.path, loginFeature);
      expect(
        found.single.line,
        lineOfFirst(_project, loginFeature, 'summary:'),
      );
      expect(
        found.single.toJson(),
        allOf(
          containsPair('pattern', 'doc_citation'),
          containsPair('field', 'summary'),
          containsPair('match', 'ruling'),
          isNot(contains('section')),
        ),
      );
    });

    test('a section entry and a required entry never read the value', () async {
      _project = await writeCheckProject(
        extra: {
          featureLayer: '''
sections:
  - id: problem
    lint:
      banned_patterns:
        add:
          - id: sign-word
            pattern: 'sign in'
            message: no sign
      required_patterns:
        - id: sign-needed
          pattern: 'sign in'
          message: Write sign in
''',
        },
      );
      final report = await checkOf(_project);
      final own = [
        for (final f in report.findings)
          if (f.toJson()['pattern'] == 'sign-word' ||
              f.toJson()['pattern'] == 'sign-needed')
            (f.kind, f.toJson()['pattern']),
      ];
      expect(own, [(FindingKind.patternMissing, 'sign-needed')]);
    });

    test('a code span the grammar reads as an address is no hit', () async {
      final found = await fieldFindings(
        'Uses `index_query/read_doc` today.',
        layer: codeEntry('[a-z_]+/[a-z_]+'),
      );
      expect(found, isEmpty);
    });

    test('a code span of another form still reports', () async {
      final found = await fieldFindings(
        'Uses `parseDoc()` today.',
        layer: codeEntry(r'\w+\(\)'),
      );
      expect(
        found.map((f) => f.toJson()['pattern']),
        containsAll(['code-name', 'code_identifier']),
      );
    });
  });

  group('in a closed generated block', () {
    final open = generatedOpenMarker('feature_catalog');
    const features = 'prds/FEATURES.md';

    Future<List<Finding>> citationsIn(String body) async {
      final report = await checkOf(
        await writeCheckProject(extra: doc(features, 'One feature.', body)),
      );
      return [
        for (final f in report.findings)
          if (f.kind == FindingKind.patternBanned) f,
      ];
    }

    test('a banned pattern match is not reported', () async {
      expect(
        await citationsIn('$open\n- Applies the ruling.\n$generatedEndMarker'),
        isEmpty,
      );
    });

    test('a history match is not reported', () async {
      expect(
        await citationsIn(
          '$open\n- Previously the login was slow.\n$generatedEndMarker',
        ),
        isEmpty,
      );
    });

    test('a history match beside the block is reported', () async {
      final found = await citationsIn(
        '$open\n- A login.\n$generatedEndMarker\n\nPreviously slow.',
      );
      expect(found.map((f) => f.toJson()['pattern']), ['history']);
    });

    test('the same text beside the block is reported', () async {
      final found = await citationsIn(
        '$open\n- A login.\n$generatedEndMarker\n\nApplies the ruling.',
      );
      expect(found.map((f) => f.toJson()['pattern']), ['doc_citation']);
    });
  });
}
