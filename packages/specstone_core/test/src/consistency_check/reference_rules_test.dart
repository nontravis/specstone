// The expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/shipped_pins.dart';

void main() {
  const rules = 'prds/references/login_rules/REFERENCE.md';
  const ruleDoc =
      '---\nsource: Team wiki\nfiles:\n  - spec.pdf\n  - notes.md\n---\n\n# Login rules\n\n'
      '## Summary\n\nThe rules.\n';
  const template =
      'reference:\n  add:\n    - title: Login rules\n      doc: login_rules\n';

  test('f04/us02/fr05/e01, f04/us02/fr05/e02: a template reference doc no doc carries is reported at the template, '
      'on a whole-project run only', () async {
    final project = await writeCheckProject(
      extra: {'.specstone/templates/fr.yaml': template},
    );
    expect(spots(checkOf(project)), [
      '.specstone/templates/fr.yaml:3: reference_doc_unresolved',
    ]);
    expect(checkOf(project).findings.single.name, isNull);
    expect(spots(checkOf(project, target: 'login')), isEmpty);
    final found = await writeCheckProject(
      extra: {
        '.specstone/templates/fr.yaml': template,
        'docs/$rules': ruleDoc.replaceFirst('  - notes.md\n', ''),
        'docs/prds/references/login_rules/spec.pdf': 'pdf',
      },
    );
    expect(spots(checkOf(found)), isEmpty);
  });

  test('f04/us02/s9, f04/us02/fr05/e03, f04/us02/fr05/e05: a listed file missing beside its reference doc, and a '
      'Concerns line pointing nowhere, are one finding each', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          'docs/$rules': ruleDoc,
          'docs/prds/references/login_rules/spec.pdf': 'pdf',
          ...doc(
            loginArchitecture,
            '- Errors: see Components\n',
            '- Errors: see Components\n- Auth: see AUTH.md\n',
          ),
        },
      ),
    );
    expect(spots(report), [
      '$rules:6: listed_file_missing',
      '$loginArchitecture:20: concerns_target_unresolved',
    ]);
    expect(report.findings.last.toJson()['target'], 'AUTH.md');
  });

  test('f04/us02/fr05/e03, f04/us02/fr05/e05: a name that ends in a space is '
      'no file on any OS, though a POSIX disk holds one', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          'docs/$rules': ruleDoc.replaceFirst(
            '  - notes.md\n',
            "  - 'notes.md '\n",
          ),
          'docs/prds/references/login_rules/spec.pdf': 'pdf',
          'docs/prds/references/login_rules/notes.md ': 'text',
          ...doc(
            loginArchitecture,
            '- Errors: see Components\n',
            '- Errors: see Components\n- Auth: see ERROR.md ## Lifecycle\n',
          ),
          'docs/specs/f01_login/ERROR.md ': 'text',
        },
      ),
    );
    expect(spots(report), [
      '$rules:6: listed_file_missing',
      '$loginArchitecture:20: concerns_target_unresolved',
    ]);
  }, skip: Platform.isWindows ? 'Windows cannot hold such a name' : null);

  test('f04/us02/fr05/e03: a listed name with a backslash is no file on any '
      'OS, though a POSIX disk holds one', () async {
    final root = await writeCheckProject(
      extra: {
        'docs/$rules': ruleDoc.replaceFirst(
          '  - notes.md\n',
          "  - 'a\\b.pdf'\n",
        ),
        'docs/prds/references/login_rules/spec.pdf': 'pdf',
      },
    );
    File('${root.path}/docs/prds/references/login_rules/a\\b.pdf')
        .writeAsStringSync('text');

    expect(spots(checkOf(root)), ['$rules:6: listed_file_missing']);
  }, skip: Platform.isWindows ? 'Windows cannot hold such a name' : null);

  test('f04/us02/fr05/e04, f04/us02/fr05/e06: a sibling file, a section of the doc, or N/A resolves', () async {
    final report = checkOf(
      await writeCheckProject(
        extra:
            {
              ...doc(
                loginArchitecture,
                '- Errors: see Components\n',
                '- Errors: see ERROR.md\n- Events: N/A — one request, one reply\n- Observability: see observability\n',
              ),
              'docs/specs/f01_login/ERROR.md': '# Login errors\n',
            }..update(
              'docs/$loginArchitecture',
              (text) => '$text\n## Observability\nLogs.\n',
            ),
      ),
    );
    expect(spots(report, FindingKind.concernsTargetUnresolved), isEmpty);
  });

  test('f04/us02/fr05/e08-e12: a see target reads through the link grammar, trailing punctuation dropped', () async {
    Future<List<String>> targetsOf(String concerns) async {
      final report = checkOf(
        await writeCheckProject(
          extra:
              {
                ...doc(
                  loginArchitecture,
                  '- Errors: see Components\n',
                  concerns,
                ),
                'docs/specs/f01_login/ERROR.md': '# Login errors\n\n## Known\n',
                'docs/specs/f01_login/a/b.md': '# B\n',
              }..update(
                'docs/$loginArchitecture',
                (text) =>
                    '$text\n## Observability\nLogs.\n\n### Deep dive\n\n'
                    '<a id="body-anchor"></a>\n',
              ),
        ),
      );
      return [
        for (final f in report.findings)
          if (f.kind == FindingKind.concernsTargetUnresolved)
            f.toJson()['target']! as String,
      ];
    }

    expect(
      await targetsOf(
        '- A: see ERROR.md.\n'
        '- B: see [the errors](ERROR.md)\n'
        '- C: see `ERROR.md`;\n'
        '- D: see Observability.\n'
        '- E: see #deep-dive\n'
        '- F: see #body-anchor\n'
        '- G: see #\n'
        '- H: see [top](#)\n'
        '- I: see ERROR.md#known\n'
        '- J: see [e](ERROR.md#known)\n'
        '- K: see ERROR.md#\n',
      ),
      isEmpty,
    );
    expect(
      await targetsOf(
        '- A: see #no-such-anchor.\n'
        '- B: see [gone](MISSING.md)\n'
        '- C: see MISSING.md.\n'
        '- D: see [x](#also-missing)\n'
        '- E: see ERROR.md#missing\n'
        '- X: see [x]()\n'
        '- Y: see ?q\n'
        '- Z: see a%2Fb.md\n',
      ),
      [
        '#no-such-anchor',
        '[gone](MISSING.md)',
        'MISSING.md',
        '[x](#also-missing)',
        'ERROR.md#missing',
        '[x]()',
        '?q',
        'a%2Fb.md',
      ],
    );
  });

  test('f04/us02/fr05: a see link target reads every CommonMark link form the link rule reads', () async {
    Future<List<String>> targetsOf(String concerns) async {
      final report = checkOf(
        await writeCheckProject(
          extra: {
            ...doc(loginArchitecture, '- Errors: see Components\n', concerns),
            'docs/specs/f01_login/a(b).md': '# B\n',
            'docs/specs/f01_login/API.md': '# Api\n',
            'docs/specs/f01_login/My File.md': '# Mine\n',
          },
        ),
      );
      return [
        for (final f in report.findings)
          if (f.kind == FindingKind.concernsTargetUnresolved)
            f.toJson()['target']! as String,
      ];
    }

    expect(
      await targetsOf(
        '- A: see [x](a(b).md)\n'
        '- B: see [x](<API.md>)\n'
        '- C: see [x](API.md "t")\n'
        '- D: see [x](<My File.md>)\n'
        '- E: see [x][mine]\n\n[mine]: <My File.md>\n',
      ),
      isEmpty,
    );
    expect(await targetsOf('- A: see [x](<MISSING.md>)\n'), [
      '[x](<MISSING.md>)',
    ]);
  });

  test('f04/us02/fr05: a bare see path stays a path and a reference-style link reads the doc definitions', () async {
    Future<List<String>> targetsOf(
      String concerns,
      Map<String, String> files,
    ) async {
      final report = checkOf(
        await writeCheckProject(
          extra: {
            ...doc(loginArchitecture, '- Errors: see Components\n', concerns),
            ...files,
          },
        ),
      );
      return [
        for (final f in report.findings)
          if (f.kind == FindingKind.concernsTargetUnresolved)
            f.toJson()['target']! as String,
      ];
    }

    expect(
      await targetsOf('- A: see notes@v2.md\n- B: see www.x.md\n', {
        'docs/specs/f01_login/notes@v2.md': '# N\n',
        'docs/specs/f01_login/www.x.md': '# W\n',
      }),
      isEmpty,
    );
    expect(
      await targetsOf('- A: see [x][r]\n\n[r]: API.md\n', {
        'docs/specs/f01_login/API.md': '# Api\n',
      }),
      isEmpty,
    );
    expect(await targetsOf('- A: see [x][r]\n\n[r]: GONE.md\n', {}), [
      '[x][r]',
    ]);
    expect(
      await targetsOf('- A: [log](MISSING.md), see [x](API.md)\n', {
        'docs/specs/f01_login/API.md': '# Api\n',
      }),
      isEmpty,
    );
    expect(
      await targetsOf('- A: [log](API.md), see [x][r]\n\n[r]: GONE.md\n', {
        'docs/specs/f01_login/API.md': '# Api\n',
      }),
      ['[x][r]'],
    );
    expect(
      await targetsOf('- A: [log](API.md), see [x](MISSING.md)\n', {
        'docs/specs/f01_login/API.md': '# Api\n',
      }),
      ['[x](MISSING.md)'],
    );
  });

  test('f04/us02/fr05/e08, f04/us02/fr05/e11, f04/us02/fr05/e14: a see target reads one way bare and as a link that spans it', () async {
    Future<CheckReport> reportOf(
      String concerns, {
      bool unparsed = false,
    }) async => checkOf(
      await writeCheckProject(
        extra:
            {
              ...doc(loginArchitecture, '- Errors: see Components\n', concerns),
              'docs/specs/f01_login/API.md':
                  '# Api\n\n## Lifecycle\n\nSteps.\n',
              'docs/specs/f01_login/A_B.md': '# A b\n',
              'docs/specs/f01_login/a(b.md': '# A paren b\n',
            }..update(
              'docs/$loginArchitecture',
              (text) => unparsed ? '$text\n[a]:<b\\' : text,
            ),
      ),
    );
    List<String> targetsIn(CheckReport report) => [
      for (final f in report.findings)
        if (f.kind == FindingKind.concernsTargetUnresolved)
          f.toJson()['target']! as String,
    ];

    const resolves = {
      'API.md': true,
      '[x](API.md)': true,
      'API.md ## Lifecycle': false,
      '[x](API.md ## Lifecycle)': false,
      'ARCHITECTURE.md': true,
      '[x](ARCHITECTURE.md)': true,
      'MISSING.md': false,
      '[x](MISSING.md)': false,
      'API.md#missing-anchor': false,
      '[x](API.md#missing-anchor)': false,
      'A_B.md': true,
      r'[x](A\_B.md)': true,
      '[x](API&#46;md)': true,
      'API.md .': true,
      '[x](API.md) .': true,
      'Components': true,
      '[x](Components)': false,
      '[x][paren]': false,
      '[x][open]': true,
      '[x](a( "t")b.md)': true,
      '[x](API.md&#35;lifecycle)': true,
      '[x](API.md#&#108;ifecycle)': true,
      r'[x](API.md#a\)b)': false,
    };
    expect(
      targetsIn(
        await reportOf(
          [
            for (final form in resolves.keys) '- C: see $form\n',
            '\n[paren]: API.md)\n[open]: a(b.md\n',
          ].join(),
        ),
      ),
      [
        for (final MapEntry(key: form, value: resolved) in resolves.entries)
          if (!resolved) form,
      ],
    );

    final headerLink = await reportOf('- C: see [x](Components)\n');
    expect(targetsIn(headerLink), ['[x](Components)']);
    expect(spots(headerLink, FindingKind.linkTargetMissing), [
      '$loginArchitecture:19: link_target_missing',
    ]);

    expect(
      targetsIn(
        await reportOf(
          '- C: see [x](API.md\n  "t")\n- D: see [x](MISSING.md\n  "t")\n',
        ),
      ),
      ['[x](MISSING.md'],
    );

    final unparsed = await reportOf(
      '- A: see MISSING.md\n- B: see [x](MISSING.md)\n- C: see [x](API.md)\n'
      '- D: see [x](<API.md>)\n- E: see [x](A\\_B.md)\n- F: see [x](#components)\n',
      unparsed: true,
    );
    expect(spots(unparsed, FindingKind.markdownUnparsed), [
      '$loginArchitecture:1: markdown_unparsed',
    ]);
    expect(targetsIn(unparsed), ['MISSING.md']);

    expect(
      targetsIn(
        await reportOf(
          '- B: see [x](MISSING.md)\n- C: see [x](API.md)\n\n'
          '[^1]: Also [y](other.md).\n',
        ),
      ),
      ['[x](MISSING.md)'],
    );

    expect(
      targetsIn(
        await reportOf(
          '- A: see [a](API.md) and [b](nope.md)\n'
          '- B: see [a](API.md) and more words\n'
          '- C: see [a](API.md) ## Lifecycle\n'
          '- D: see [log](MISSING.md), see [x](API.md)\n'
          '- E: see ![flow](API.md).\n',
        ),
      ),
      [
        '[a](API.md) and [b](nope.md)',
        '[a](API.md) and more words',
        '[a](API.md) ## Lifecycle',
      ],
    );
  });

  test('f04/us02/fr05/e07, cc-s03/inv2: a merged set with no architecture doc type runs no Concerns rule', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          '.specstone/config.yaml': shippedPinsConfig(['prd-core']),
          ...doc(
            loginArchitecture,
            '- Errors: see Components\n',
            '- Auth: see AUTH.md\n',
          ),
        },
      ),
    );
    expect(spots(report, FindingKind.concernsTargetUnresolved), isEmpty);
  });

  test(
    'f04/us02/fr05: a fenced line in the Concerns section names no target',
    () async {
      final report = checkOf(
        await writeCheckProject(
          extra: doc(
            loginArchitecture,
            '- Errors: see Components\n',
            '- Errors: see Components\n```\n- Auth: see MISSING.md\n```\n',
          ),
        ),
      );
      expect(spots(report, FindingKind.concernsTargetUnresolved), isEmpty);
    },
  );
}
