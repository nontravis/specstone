// The expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/record_fixture.dart' show recordsRootTemplates;
import '../../helpers/shipped_pins.dart';

void main() {
  const rules = 'prds/references/login_rules/REFERENCE.md';
  const ruleDoc =
      '---\nsource: Team wiki\nfiles:\n  - spec.pdf\n  - notes.md\n---\n\n# Login rules\n\n'
      '## Summary\n\nThe rules.\n';
  const template =
      'reference:\n  add:\n    - title: Login rules\n      doc: login_rules\n';

  test('a template reference doc no doc carries is reported at the template, '
      'on a whole-project run only', () async {
    final project = await writeCheckProject(
      extra: {'.specstone/templates/fr.yaml': template},
    );
    expect(spots(await checkOf(project)), [
      '.specstone/templates/fr.yaml:3: reference_doc_unresolved',
    ]);
    expect((await checkOf(project)).findings.single.name, isNull);
    expect(spots(await checkOf(project, target: 'login')), isEmpty);
    final found = await writeCheckProject(
      extra: {
        '.specstone/templates/fr.yaml': template,
        'docs/$rules': ruleDoc.replaceFirst('  - notes.md\n', ''),
        'docs/prds/references/login_rules/spec.pdf': 'pdf',
      },
    );
    expect(spots(await checkOf(found)), isEmpty);
  });

  test('a listed file missing beside its reference doc, and a '
      'Concerns line pointing nowhere, are one finding each', () async {
    final report = await checkOf(
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
      '$loginArchitecture:23: concerns_target_unresolved',
    ]);
    expect(report.findings.last.toJson()['target'], 'AUTH.md');
  });

  test('a name that ends in a space is '
      'no file on any OS, though a POSIX disk holds one', () async {
    final report = await checkOf(
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
      '$loginArchitecture:23: concerns_target_unresolved',
    ]);
  }, skip: Platform.isWindows ? 'Windows cannot hold such a name' : null);

  test('a listed name with a backslash is no file on any '
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

    expect(spots(await checkOf(root)), ['$rules:6: listed_file_missing']);
  }, skip: Platform.isWindows ? 'Windows cannot hold such a name' : null);

  test('a sibling file, a section of the doc, or N/A resolves', () async {
    final report = await checkOf(
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

  test(
    'a see target reads through the link grammar, trailing punctuation dropped',
    () async {
      Future<List<String>> targetsOf(String concerns) async {
        final report = await checkOf(
          await writeCheckProject(
            extra:
                {
                  ...doc(
                    loginArchitecture,
                    '- Errors: see Components\n',
                    concerns,
                  ),
                  'docs/specs/f01_login/ERROR.md':
                      '# Login errors\n\n## Known\n',
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
    },
  );

  test(
    'a see link target reads every CommonMark link form the link rule reads',
    () async {
      Future<List<String>> targetsOf(String concerns) async {
        final report = await checkOf(
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
    },
  );

  test('a bare see path stays a path and a reference-style link reads the doc definitions', () async {
    Future<List<String>> targetsOf(
      String concerns,
      Map<String, String> files,
    ) async {
      final report = await checkOf(
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

  test('a see target reads one way bare and as a link that spans it', () async {
    Future<CheckReport> reportOf(
      String concerns, {
      bool unparsed = false,
    }) async => await checkOf(
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
      '$loginArchitecture:22: link_target_missing',
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

  test(
    'a merged set with no architecture doc type runs no Concerns rule',
    () async {
      final report = await checkOf(
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
    },
  );

  test('a doc of a type built on architecture gets the Concerns rule', () async {
    const layer = '.specstone/templates/edge_architecture_root.yaml';
    const built = 'specs/EDGE_ARCHITECTURE_ROOT.md';
    final report = await checkOf(
      await writeCheckProject(
        extra: {
          layer:
              'id: edge_architecture_root\nextends: architecture\npath: $built\nparent:\n',
          'docs/$built': '# Edge architecture\n\n## Concerns\n\n- Auth: see MISSING.md\n- Errors: N/A — no errors\n',
        },
        unstamped: {'docs/$built'},
      ),
    );
    expect(spots(report, FindingKind.concernsTargetUnresolved), [
      '$built:5: concerns_target_unresolved',
    ]);
  });

  test('a fenced line in the Concerns section names no target', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: doc(
          loginArchitecture,
          '- Errors: see Components\n',
          '- Errors: see Components\n```\n- Auth: see MISSING.md\n```\n',
        ),
      ),
    );
    expect(spots(report, FindingKind.concernsTargetUnresolved), isEmpty);
  });

  test(
    'a see path to an existing file outside the doc folder resolves',
    () async {
      final report = await _concernsReport(
        '- NFRs: see ../../prds/GNFR.md\n'
        '- Linked: see [gnfr](../../prds/GNFR.md)\n'
        '- Gone: see ../../prds/GONE.md\n',
        files: {'docs/prds/GNFR.md': '# Global NFRs\n'},
      );
      expect(_targetsOf(report), ['../../prds/GONE.md']);
    },
  );

  test('a link written inside a code span names its own text as an unresolved target', () async {
    final report = await _concernsReport(
      '- Domain: see `[DOMAIN.md](DOMAIN.md)`\n- Plain: see `DOMAIN.md`;\n',
      files: {'docs/specs/f01_login/DOMAIN.md': '# Domain\n'},
    );
    expect(spots(report, FindingKind.concernsTargetUnresolved), [
      '$loginArchitecture:22: concerns_target_unresolved',
    ]);
    expect(_targetsOf(report), ['[DOMAIN.md](DOMAIN.md)']);
  });

  test('a see anchor resolves by the slug of a section heading', () async {
    final report = await _concernsReport(
      '- Rollout: see #rollout\n- Missing: see #nothing\n',
      appended: '\n## Rollout\n\nOne stage.\n',
    );
    expect(_targetsOf(report), ['#nothing']);
    expect(spots(report, FindingKind.concernsTargetUnresolved), [
      '$loginArchitecture:23: concerns_target_unresolved',
    ]);
  });

  test(
    'a see anchor resolves by a body tag id, an anchor name, or a deep heading',
    () async {
      final report = await _concernsReport(
        '- Rollback: see #rollback\n'
        '- Undo: see #undo\n'
        '- Retry: see #retry\n'
        '- Missing: see #nothing\n',
        appended:
            '\n## Operations\n\n### Rollback\n\n<div id="undo">Undo.</div>\n\n'
            '<a name="retry"></a>\n',
      );
      expect(_targetsOf(report), ['#nothing']);
    },
  );

  test('a section link to the slug of a heading resolves while a bare section link does not', () async {
    final report = await _concernsReport(
      '- Parts: see [x](#components)\n'
      '- Bare: see Components\n'
      '- Link: see [x](Components)\n',
    );
    expect(_targetsOf(report), ['[x](Components)']);
  });

  test('a link to a missing anchor of a file is both an unresolved target and a missing link anchor on one line', () async {
    final report = await _concernsReport(
      '- Domain: see [DOMAIN.md](DOMAIN.md#nothing)\n',
      files: {'docs/specs/f01_login/DOMAIN.md': '# Domain\n\n## Lifecycle\n'},
    );
    expect(_targetsOf(report), ['[DOMAIN.md](DOMAIN.md#nothing)']);
    expect(
      spots(report)
          .where(
            (s) =>
                s.contains('concerns_target_unresolved') ||
                s.contains('link_anchor_missing'),
          )
          .toSet(),
      {
        '$loginArchitecture:22: concerns_target_unresolved',
        '$loginArchitecture:22: link_anchor_missing',
      },
    );
  });

  test('a bare see anchor in a doc the parser fails on raises nothing while a bare missing file still does', () async {
    final report = await _concernsReport(
      '- A: see #nothing\n- B: see MISSING.md\n',
      appended: '\n[a]:<b\\',
    );
    expect(spots(report, FindingKind.markdownUnparsed), [
      '$loginArchitecture:1: markdown_unparsed',
    ]);
    expect(_targetsOf(report), ['MISSING.md']);
  });

  test('a see anchor of a file no doc indexes or of a doc the parser fails on raises nothing', () async {
    final report = await _concernsReport(
      '- A: see NOTES.txt#nothing\n'
      '- B: see BROKEN.md#nothing\n'
      '- C: see ERROR.md#nothing\n'
      '- D: see ERROR.md#\n',
      files: {
        'docs/specs/f01_login/NOTES.txt': 'plain\n',
        'docs/specs/f01_login/BROKEN.md': '# Broken\n\n[a]:<b\\',
        'docs/specs/f01_login/ERROR.md': '# Login errors\n\n## Known\n',
      },
    );
    expect(_targetsOf(report), ['ERROR.md#nothing']);
  });

  test('a type built on architecture takes the Concerns rule yet does not stand for the architecture doc of a feature with implemented code', () async {
    const built = 'specs/f01_login/EDGE_ARCHITECTURE.md';
    const record = '.specstone/records/f01_login/IMPLEMENTATION.md';
    final report = await checkOf(
      await writeCheckProject(
        extra: {
          '.specstone/templates/implementation.yaml':
              'id: implementation\n'
              'description: One feature record per target.\n'
              'path: .specstone/records/f{nn}_{slug}/IMPLEMENTATION.md\n'
              'parent: feature\n'
              'per_target: true\n'
              'fields:\n'
              '  - id: statuses\n'
              '    type: record_status\n'
              '    list: true\n'
              '  - id: implements\n'
              '    type: output_ref\n'
              '    list: true\n'
              '    pointer: item_exact\n',
          '.specstone/templates/edge_architecture.yaml':
              'id: edge_architecture\nextends: architecture\n'
              'path: specs/f{nn}_{slug}/EDGE_ARCHITECTURE.md\n',
          'docs/$built':
              '# Edge architecture\n\n## Concerns\n\n- Auth: see AUTH.md\n',
          record:
              "---\nstatuses:\n  - 'email_login/check_password:implemented'\n"
              "implements:\n  - 'email_login/check_password:app/lib/login.dart:checkPassword'\n"
              '---\n\n# Record\n',
        },
        without: {'docs/$loginArchitecture'},
        unstamped: {record, 'docs/$built'},
      ),
    );
    expect(spots(report, FindingKind.concernsTargetUnresolved), [
      '$built:5: concerns_target_unresolved',
    ]);
    expect(spots(report, FindingKind.architectureMissing), [
      '$loginFeature:1: architecture_missing',
    ]);
  });

  test('a covers entry of a type built on architecture waits on any feature entry, which the architecture doc itself does not', () async {
    const built = 'specs/f01_login/EDGE_ARCHITECTURE.md';
    const layer =
        'id: implementation\n'
        'description: One feature record per target.\n'
        'path: .specstone/records/f{nn}_{slug}/IMPLEMENTATION.md\n'
        'parent: feature\n'
        'per_target: true\n'
        'fields:\n'
        '  - id: statuses\n'
        '    type: record_status\n'
        '    list: true\n';
    const loginRecord = '.specstone/records/f01_login/IMPLEMENTATION.md';
    const shopRecord = '.specstone/records/f02_shop/IMPLEMENTATION.md';
    String record(String status) =>
        "---\nstatuses:\n  - 'email_login:$status'\n---\n\n# Record\n";
    final shared = {
      '.specstone/templates/implementation.yaml': layer,
      loginRecord: record('planned'),
      shopRecord: record('implemented'),
      'docs/prds/features/f02_shop/FEATURE.md':
          checkProjectFiles()['docs/$loginFeature']!,
      'docs/prds/features/f02_shop/us01_email_login/USER_STORY.md':
          checkProjectFiles()['docs/$loginStory']!,
    };

    final edge = await checkOf(
      await writeCheckProject(
        extra: {
          ...shared,
          '.specstone/templates/edge_architecture.yaml':
              'id: edge_architecture\nextends: architecture\n'
              'path: specs/f{nn}_{slug}/EDGE_ARCHITECTURE.md\n',
          'docs/$built':
              '---\ncovers:\n  - app/lib/gone/\n---\n\n# Edge architecture\n',
        },
        without: {'docs/$loginArchitecture'},
        unstamped: {loginRecord, shopRecord, 'docs/$built'},
      ),
    );
    expect(spots(edge, FindingKind.coversPathMissing), [
      '$built:3: covers_path_missing',
    ]);

    final exact = await checkOf(
      await writeCheckProject(
        extra: {
          ...shared,
          ...doc(loginArchitecture, 'app/lib/', 'app/lib/gone/'),
        },
        unstamped: {loginRecord, shopRecord},
      ),
    );
    expect(spots(exact, FindingKind.coversPathMissing), isEmpty);
  });

  group('see targets in the other root', () {
    const record = '.specstone/records/f01_login/IMPLEMENTATION.md';
    const toRecord = '../../../$record';

    test('an anchor of a record is checked from a docs doc', () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: {
            ...recordsRootTemplates,
            record: '# Login implementation\n\n## Notes\n\nNone.\n',
            ...doc(
              loginArchitecture,
              '- Errors: see Components\n',
              '- Errors: see $toRecord#notes\n- Auth: see $toRecord#nope\n',
            ),
          },
        ),
      );

      expect(spots(report, FindingKind.concernsTargetUnresolved), [
        '$loginArchitecture:23: concerns_target_unresolved',
      ]);
      expect(
        report.findings.where(_isConcern).single.toJson()['target'],
        '$toRecord#nope',
      );
    });

    test('an anchor of a docs doc reached by leaving the docs root is '
        'checked', () async {
      const toError = '../../../docs/specs/f01_login/ERROR.md';
      final report = await checkOf(
        await writeCheckProject(
          extra: {
            'docs/specs/f01_login/ERROR.md': '# Login errors\n\n## Known\n',
            ...doc(
              loginArchitecture,
              '- Errors: see Components\n',
              '- Errors: see $toError#known\n- Auth: see $toError#nope\n',
            ),
          },
        ),
      );

      expect(
        report.findings.where(_isConcern).map((f) => f.toJson()['target']),
        ['$toError#nope'],
      );
    });
  });
}

bool _isConcern(Finding finding) =>
    finding.kind == FindingKind.concernsTargetUnresolved;

Future<CheckReport> _concernsReport(
  String concerns, {
  Map<String, String> files = const {},
  String appended = '',
}) async => await checkOf(
  await writeCheckProject(
    extra: {
      ...doc(loginArchitecture, '- Errors: see Components\n', concerns),
      ...files,
    }..update('docs/$loginArchitecture', (text) => '$text$appended'),
  ),
);

List<String> _targetsOf(CheckReport report) => [
  for (final f in report.findings.where(_isConcern))
    f.toJson()['target']! as String,
];
