// The expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/record_fixture.dart' show recordsRootTemplates;
import '../../helpers/rulebook_fixture.dart';
import '../../helpers/shipped_pins.dart';

/// The fixture architecture doc with the Concerns section the pack shipped
/// before 1.21.0, which [concernsLayer] declares again.
final String _concernsArchitecture =
    '${checkProjectFiles()['docs/$loginArchitecture']!}\n## Concerns\n\n'
    '- Integration: see Components\n- Errors: see Components\n'
    '- Auth: see Components\n- Lifecycle: see Components\n'
    '- Events: see Components\n- Rollout: see Components\n'
    '- Observability: see Components\n';

/// Returns [concernsLayer] and the fixture architecture doc with its Concerns
/// section, [from] changed to [to] once.
Map<String, String> _archDoc(String from, String to) {
  if (!_concernsArchitecture.contains(from)) {
    throw ArgumentError.value(from, 'from', 'does not occur in the doc');
  }
  return {
    concernsLayerFile: concernsLayer,
    'docs/$loginArchitecture': _concernsArchitecture.replaceFirst(from, to),
  };
}

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
          ..._archDoc(
            '- Errors: see Components\n',
            '- Errors: see Components\n- Auth: see AUTH.md\n',
          ),
        },
      ),
    );
    expect(spots(report), [
      '$rules:6: listed_file_missing',
      '$loginArchitecture:21: concerns_target_unresolved',
    ]);
    expect(report.findings.last.toJson()['value'], 'AUTH.md');
  });

  test('a competitor files entry resolves under its folder, and a missing one '
      'is listed_file_missing', () async {
    const competitor = 'prds/competitors/acme/COMPETITOR.md';
    const text =
        '---\nsource: Acme site\nchecked: 2026-01-02\nkind: direct\nfiles:\n'
        '  - references/readme.txt\n  - references/gone.txt\n---\n\n# Acme\n\n'
        '## Summary\n\nA rival.\n';
    final report = await checkOf(
      await writeCheckProject(
        extra: {
          'docs/$competitor': text,
          'docs/prds/competitors/acme/references/readme.txt': 'text',
        },
      ),
    );
    final found = [
      for (final f in report.findings)
        if (f.kind == FindingKind.listedFileMissing) f,
    ];
    expect([for (final f in found) '${f.path}:${f.line}'], ['$competitor:8']);
    expect(found.single.keys, {'entry': 'references/gone.txt'});
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
          ..._archDoc(
            '- Errors: see Components\n',
            '- Errors: see Components\n- Auth: see ERROR.md ## Lifecycle\n',
          ),
          'docs/specs/f01_login/ERROR.md ': 'text',
        },
      ),
    );
    expect(spots(report), [
      '$rules:6: listed_file_missing',
      '$loginArchitecture:21: concerns_target_unresolved',
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

  test('an N/A line that still ends with see resolves its target', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: _archDoc(
          '- Errors: see Components\n',
          '- Errors: see Components\n- Events: N/A — none, see MISSING.md\n',
        ),
      ),
    );
    expect(spots(report, FindingKind.concernsTargetUnresolved), [
      '$loginArchitecture:21: concerns_target_unresolved',
    ]);
    expect(report.findings.last.toJson()['value'], 'MISSING.md');
  });

  test('a see target reads one way bare and as a link that spans it', () async {
    Future<CheckReport> reportOf(
      String concerns, {
      bool unparsed = false,
    }) async => await checkOf(
      await writeCheckProject(
        extra:
            {
              ..._archDoc('- Errors: see Components\n', concerns),
              'docs/specs/f01_login/API.md':
                  '# Api\n\n## Lifecycle\n\nSteps.\n',
              'docs/specs/f01_login/A_B.md': '# A b\n',
              'docs/specs/f01_login/a(b.md': '# A paren b\n',
              'docs/specs/f01_login/a(b).md': '# A paren b paren\n',
              'docs/specs/f01_login/My File.md': '# Mine\n',
              'docs/specs/f01_login/notes@v2.md': '# N\n',
              'docs/specs/f01_login/www.x.md': '# W\n',
              'docs/specs/f01_login/ERROR.md': '# Login errors\n\n## Known\n',
            }..update(
              'docs/$loginArchitecture',
              (text) =>
                  '$text\n## Observability\nLogs.\n\n### Deep dive\n\n'
                  '<a id="body-anchor"></a>\n'
                  '${unparsed ? '\n[a]:<b\\' : ''}',
            ),
      ),
    );
    List<String> targetsIn(CheckReport report) => [
      for (final f in report.findings)
        if (f.kind == FindingKind.concernsTargetUnresolved)
          f.toJson()['value']! as String,
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
      'ERROR.md.': true,
      '[the errors](ERROR.md)': true,
      '`ERROR.md`;': true,
      'Observability.': true,
      '#deep-dive': true,
      '#body-anchor': true,
      '#': true,
      '[top](#)': true,
      'ERROR.md#known': true,
      '[e](ERROR.md#known)': true,
      'ERROR.md#': true,
      '#no-such-anchor': false,
      '[gone](MISSING.md)': false,
      '[x](#also-missing)': false,
      'ERROR.md#missing': false,
      '[x]()': false,
      '?q': false,
      'a%2Fb.md': false,
      '[x](a(b).md)': true,
      '[x](<API.md>)': true,
      '[x](API.md "t")': true,
      '[x](<My File.md>)': true,
      '[x][mine]': true,
      '[x](<MISSING.md>)': false,
      'notes@v2.md': true,
      'www.x.md': true,
      '[x][okr]': true,
      '[x][gone]': false,
      '[x](#components)': true,
    };
    expect(
      targetsIn(
        await reportOf(
          [
            for (final form in resolves.keys) '- C: see $form\n',
            '\n[paren]: API.md)\n[open]: a(b.md\n[mine]: <My File.md>\n[okr]: API.md\n[gone]: GONE.md\n',
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
      '$loginArchitecture:20: link_target_missing',
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
      '- D: see [x](<API.md>)\n- E: see [x](A\\_B.md)\n- F: see [x](#components)\n'
      '- G: see #nothing\n',
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
            ...{
              ..._archDoc(
                '- Errors: see Components\n',
                '- Auth: see AUTH.md\n',
              ),
            }..remove(concernsLayerFile),
          },
        ),
      );
      expect(spots(report, FindingKind.concernsTargetUnresolved), isEmpty);
    },
  );

  test('a doc of a type built on architecture gets the Concerns rule', () async {
    const layer = '.specstone/templates/edge_architecture_root.yaml';
    const built = 'specs/EDGE_ARCHITECTURE_ROOT.md';
    const body =
        '# Edge architecture\n\n## Concerns\n\n- Auth: see MISSING.md\n- Errors: N/A — no errors\n';
    for (final (path, extra) in [
      (
        built,
        {
          layer:
              'id: edge_architecture_root\nextends: architecture\npath: $built\nparent:\n',
        },
      ),
      ('specs/ARCHITECTURE.md', <String, String>{}),
      (
        'specs/f01_login/EDGE_ARCHITECTURE.md',
        {
          '.specstone/templates/edge_architecture.yaml':
              'id: edge_architecture\nextends: architecture\n'
              'path: specs/f{nn}_{slug}/EDGE_ARCHITECTURE.md\n',
        },
      ),
    ]) {
      final report = await checkOf(
        await writeCheckProject(
          extra: {
            concernsLayerFile: concernsLayer,
            ...extra,
            'docs/$path': body,
          },
          unstamped: {'docs/$path'},
        ),
      );
      expect(spots(report, FindingKind.concernsTargetUnresolved), [
        '$path:5: concerns_target_unresolved',
      ], reason: path);
    }
  });

  test('a fenced line in the Concerns section names no target', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: _archDoc(
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
      '$loginArchitecture:20: concerns_target_unresolved',
    ]);
    expect(_targetsOf(report), ['[DOMAIN.md](DOMAIN.md)']);
  });

  test(
    'a see anchor resolves by a body tag id, an anchor name, or a deep heading',
    () async {
      final report = await _concernsReport(
        '- Rollout: see #rollout\n'
        '- Rollback: see #rollback\n'
        '- Undo: see #undo\n'
        '- Retry: see #retry\n'
        '- Missing: see #nothing\n',
        appended:
            '\n## Rollout\n\nOne stage.\n'
            '\n## Operations\n\n### Rollback\n\n<div id="undo">Undo.</div>\n\n'
            '<a name="retry"></a>\n',
      );
      expect(_targetsOf(report), ['#nothing']);
    },
  );

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
        '$loginArchitecture:20: concerns_target_unresolved',
        '$loginArchitecture:20: link_anchor_missing',
      },
    );
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

  group('see path outside the docs', () {
    const toRoot = '../../../';

    Future<CheckReport> reportOf(
      String concerns, {
      Map<String, String> files = const {},
      String appended = '',
    }) => _concernsReport(concerns, files: files, appended: appended);

    List<Finding> outsideOf(CheckReport report) => [
      for (final f in report.findings)
        if (f.kind == FindingKind.linkOutsideDocs) f,
    ];

    String message(String path) =>
        'links $path, outside the docs; move the file into the docs or drop the link';

    test('a Concerns line naming a code file in the project is link_outside_docs', () async {
      final report = await reportOf(
        '- Auth: see ${toRoot}lib/login.dart\n',
        files: {'lib/login.dart': 'void main() {}\n'},
      );
      final found = outsideOf(report);
      expect(
        [for (final f in found) f.textLine],
        ['$loginArchitecture:20: link_outside_docs: ${message('lib/login.dart')}'],
      );
      expect(found.single.keys, {
        'value': '${toRoot}lib/login.dart',
        'targetPath': 'lib/login.dart',
      });
      expect(found.single.waitsFor, WaitsFor.agent);
      expect(_targetsOf(report), isEmpty);
    });

    test('a concerns_target_unresolved and a see link_outside_docs name the see target as value', () async {
      final report = await reportOf(
        '- A: see AUTH.md\n- B: see ${toRoot}lib/login.dart\n',
        files: {'lib/login.dart': 'void main() {}\n'},
      );
      final findings = [
        for (final f in report.findings)
          if (f.kind == FindingKind.concernsTargetUnresolved ||
              f.kind == FindingKind.linkOutsideDocs)
            f,
      ];
      expect(
        {for (final f in findings) f.kind: f.keys['value']},
        {
          FindingKind.concernsTargetUnresolved: 'AUTH.md',
          FindingKind.linkOutsideDocs: '${toRoot}lib/login.dart',
        },
      );
      for (final f in findings) {
        expect(f.keys.containsKey('target'), isFalse, reason: '${f.kind}');
      }
    });

    test(
      'a backticked path with a full stop is read as the see target',
      () async {
        final report = await reportOf(
          '- Auth: see `${toRoot}lib/login.dart`.\n',
          files: {'lib/login.dart': 'void main() {}\n'},
        );
        expect(
          [for (final f in outsideOf(report)) f.keys],
          [
            {
              'value': '${toRoot}lib/login.dart',
              'targetPath': 'lib/login.dart',
            },
          ],
        );
        expect(_targetsOf(report), isEmpty);
      },
    );

    test(
      'a missing file and a folder outside the docs are reported like a file',
      () async {
        final report = await reportOf(
          '- A: see ${toRoot}lib/gone.dart\n- B: see ${toRoot}lib\n',
          files: {'lib/login.dart': 'void main() {}\n'},
        );
        expect(
          [for (final f in outsideOf(report)) f.keys['targetPath']],
          ['lib/gone.dart', 'lib'],
        );
        expect(_targetsOf(report), isEmpty);
      },
    );

    test('an #anchor is not read, so the path alone is reported', () async {
      final report = await reportOf(
        '- A: see ${toRoot}lib/login.dart#main\n',
        files: {'lib/login.dart': 'void main() {}\n'},
      );
      expect(
        [for (final f in outsideOf(report)) f.keys],
        [
          {
            'value': '${toRoot}lib/login.dart#main',
            'targetPath': 'lib/login.dart',
          },
        ],
      );
      expect(_targetsOf(report), isEmpty);
    });

    test('a path above the project root is no link_outside_docs and stays '
        'concerns_target_unresolved', () async {
      final report = await reportOf('- A: see $toRoot../gone.dart\n');
      expect(outsideOf(report), isEmpty);
      expect(_targetsOf(report), ['$toRoot../gone.dart']);
    });

    test(
      'a sibling spec doc and a section of the doc are no link_outside_docs',
      () async {
        final report = await reportOf(
          '- A: see ERROR.md\n- B: see Observability\n',
          files: {'docs/specs/f01_login/ERROR.md': '# Login errors\n'},
          appended: '\n## Observability\nLogs.\n',
        );
        expect(outsideOf(report), isEmpty);
        expect(_targetsOf(report), isEmpty);
      },
    );

    test('a see link outside the docs gets no concerns_target_unresolved and no second finding here', () async {
      final report = await reportOf(
        '- A: see [gone](${toRoot}lib/gone.dart)\n',
      );
      expect(
        [for (final f in outsideOf(report)) f.keys['targetPath']],
        ['lib/gone.dart'],
      );
      expect(_targetsOf(report), isEmpty);
    });
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
            ..._archDoc(
              '- Errors: see Components\n',
              '- Errors: see $toRecord#notes\n- Auth: see $toRecord#nope\n',
            ),
          },
        ),
      );

      expect(spots(report, FindingKind.concernsTargetUnresolved), [
        '$loginArchitecture:21: concerns_target_unresolved',
      ]);
      expect(
        report.findings.where(_isConcern).single.toJson()['value'],
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
            ..._archDoc(
              '- Errors: see Components\n',
              '- Errors: see $toError#known\n- Auth: see $toError#nope\n',
            ),
          },
        ),
      );

      expect(
        report.findings.where(_isConcern).map((f) => f.toJson()['value']),
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
    extra: {..._archDoc('- Errors: see Components\n', concerns), ...files}
      ..update('docs/$loginArchitecture', (text) => '$text$appended'),
  ),
);

List<String> _targetsOf(CheckReport report) => [
  for (final f in report.findings.where(_isConcern))
    f.toJson()['value']! as String,
];
