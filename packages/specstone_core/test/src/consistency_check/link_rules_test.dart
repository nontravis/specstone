// The expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/record_fixture.dart' show recordsRootTemplates;
import '../../helpers/shipped_pins.dart';
import '../../helpers/target_fixture.dart';

void main() {
  test("f04/us02/fr04/e01, cc-s03/inv14, FM5: a broken link's line comes from the index, so check parses no doc text", () async {
    final project = await writeCheckProject(
      extra: doc(
        loginFeature,
        'Users forget passwords.',
        'Users forget passwords; see [reset](us02_reset_password/USER_STORY.md).',
      ),
    );
    final anHourAgo = DateTime.now().subtract(const Duration(hours: 1));
    for (final file in Directory(
      '${project.path}/docs',
    ).listSync(recursive: true).whereType<File>()) {
      file.setLastModifiedSync(anHourAgo);
    }
    await checkOf(project);
    // The stat is unchanged, so the next refresh keeps the row with its text
    // edited to hold no link.
    sqlite3.open('${project.path}/$indexFilePath')
      ..execute(
        "UPDATE docs SET text = replace(text, '](', '] (') WHERE doc_path = ?",
        [loginFeature],
      )
      ..close();
    final report = await checkOf(project);
    expect(
      report.findings.single.textLine,
      '$loginFeature:13: link_unresolved: link target us02_reset_password/USER_STORY.md is no doc',
    );
  });

  test('f04/us02/s5, f04/us02/fr04/e01: a link to a deleted story names the link and its line', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: doc(
          loginFeature,
          'Users forget passwords.',
          'Users forget passwords; see [reset](us02_reset_password/USER_STORY.md).',
        ),
      ),
    );
    expect(
      report.findings.single.textLine,
      '$loginFeature:13: link_unresolved: link target us02_reset_password/USER_STORY.md is no doc',
    );
  });

  test('a persona value no persona carries is doc_ref_unresolved', () async {
    final story = doc(
      loginStory,
      'goals:\n  - PG-01\n',
      'goals:\n  - PG-01\npersona:\n  - buyer\n',
    );
    final report = await checkOf(await writeCheckProject(extra: story));
    expect(spots(report), ['$loginStory:6: doc_ref_unresolved']);
    expect(
      report.findings.single.toJson(),
      allOf(containsPair('field', 'persona'), containsPair('value', 'buyer')),
    );
    expect(report.findings.single.message, 'persona value buyer names no doc');
    final withBuyer = await checkOf(
      await writeCheckProject(
        extra: {
          ...story,
          'docs/prds/personas/buyer/PERSONA.md': '---\nrole: Agent\npriority: primary\nbasis: proto\n---\n\n# Buyer\n',
        },
      ),
    );
    expect(spots(withBuyer, FindingKind.docRefUnresolved), isEmpty);
  });

  test('E02: an empty '
      'depends_on list reports nothing', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: doc(
          loginFeature,
          '  - PG-01\n---',
          '  - PG-01\ndepends_on: []\n---',
        ),
      ),
    );
    expect(report.findings, isEmpty);
  });

  test('E02: a scalar '
      'depends_on is field_value_mismatch at the key line', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: doc(
          loginFeature,
          '  - PG-01\n---',
          '  - PG-01\ndepends_on: login\n---',
        ),
      ),
    );
    expect(spots(report), [
      '$loginFeature:7: doc_ref_self',
      '$loginFeature:7: field_value_mismatch',
    ]);
  });

  test('E02: an empty '
      'depends_on item is doc_ref_unresolved at the item line', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: doc(
          loginFeature,
          '  - PG-01\n---',
          '  - PG-01\ndepends_on:\n  - ""\n---',
        ),
      ),
    );
    expect(spots(report), ['$loginFeature:8: doc_ref_unresolved']);
  });

  test(
    'E02: a depends_on value '
    'no feature carries is doc_ref_unresolved; a feature resolves only',
    () async {
      final dependsOn = doc(
        loginFeature,
        '  - PG-01\n---',
        '  - PG-01\ndepends_on:\n  - checkout\n  - login/email_login\n  - login\n---',
      );
      final report = await checkOf(await writeCheckProject(extra: dependsOn));
      expect(spots(report), [
        '$loginFeature:8: doc_ref_unresolved',
        '$loginFeature:9: doc_ref_unresolved',
        '$loginFeature:10: doc_ref_self',
      ]);
      expect(
        report.findings.first.message,
        'depends_on value checkout names no doc',
      );
      final withCheckout = await checkOf(
        await writeCheckProject(
          extra: {
            ...dependsOn,
            'docs/prds/features/f02_checkout/FEATURE.md':
                checkProjectFiles()['docs/$loginFeature']!.replaceFirst(
                  '# Login',
                  '# Checkout',
                ),
          },
        ),
      );
      expect(spots(withCheckout, FindingKind.docRefUnresolved), [
        '$loginFeature:9: doc_ref_unresolved',
      ]);
    },
  );

  test('f04/us02/fr04/e03, f04/us02/fr04/e04, f04/us02/fr04/e06, f04/us02/fr04/e07, f04/us01/fr06/e04: an anchor, a '
      'URL, a picture, a link outside the checked folders, and prose resolve or are no link', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: {
          ...doc(
            loginFeature,
            'Users forget passwords.',
            'Users forget passwords: [roles](../../PROJECT.md#role), [site](https://example.com), '
                '![diagram](diagram.png), [idea](../../../notes/idea.md), and USER_STORY.md in prose.',
          ),
          'docs/notes/idea.md': '# Idea\n\n[gone](gone.md)\n',
          'docs/prds/features/f01_login/diagram.png': 'png',
        },
      ),
    );
    // One doc carries USER_STORY.md, so the prose path is an old cite form.
    expect(spots(report), ['$loginFeature:13: cite_unlinked']);
  });

  group('link_target_missing', () {
    const picture = 'docs/prds/features/f01_login/flow chart.png';

    Future<List<String>> missingOf(Directory project) async => [
      for (final f in (await checkOf(project)).findings)
        if (f.kind == FindingKind.linkTargetMissing) f.textLine,
    ];

    Map<String, String> linking(String text) => doc(
      loginFeature,
      'Users forget passwords.',
      'Users forget passwords; $text',
    );

    test('f04/us02/fr04/e10, PS-R2, M6: a link out of the docs root to a file that is not there names the project path', () async {
      final project = await writeCheckProject(
        extra: doc(
          gnfrDoc,
          'N/A — none applies.',
          'See [x](../../../docs/prds/d03_non_functional.md).',
        ),
      );
      expect(spots(await checkOf(project), FindingKind.linkTargetMissing), [
        'prds/GNFR.md:16: link_target_missing',
      ]);
      expect(await missingOf(project), [
        'prds/GNFR.md:16: link_target_missing: link target ../../../docs/prds/d03_non_functional.md is missing at ../docs/prds/d03_non_functional.md',
      ]);
      final finding = (await checkOf(project)).findings
          .firstWhere((f) => f.kind == FindingKind.linkTargetMissing);
      expect(
        finding.toJson(),
        allOf(
          containsPair('target', '../../../docs/prds/d03_non_functional.md'),
          containsPair('path', '../docs/prds/d03_non_functional.md'),
        ),
      );
      expect(finding.kind.isProjectLevel, isFalse);
    });

    test('f04/us02/fr04/e11, PS-R3: a picture with no file is a finding inside docs too', () async {
      final project = await writeCheckProject(
        extra: linking('![flow](flow.png)'),
      );
      expect(await missingOf(project), [
        '$loginFeature:13: link_target_missing: link target flow.png is missing at docs/prds/features/f01_login/flow.png',
      ]);
    });

    test('a picture whose file is there is no finding', () async {
      final project = await writeCheckProject(
        extra: {
          ...linking('![flow](flow.png)'),
          'docs/prds/features/f01_login/flow.png': 'png',
        },
      );
      expect(await missingOf(project), isEmpty);
    });

    test(
      'a picture whose name holds a backslash or ends '
      'in a dot is missing on any OS, though a POSIX disk holds the file',
      () async {
        for (final (href, name) in [
          ('a%5Cb.png', r'a\b.png'),
          ('flow.png.', 'flow.png.'),
        ]) {
          final project = await writeCheckProject(
            extra: linking('![x]($href)'),
          );
          File('${project.path}/docs/prds/features/f01_login/$name')
              .writeAsStringSync('png');

          expect(await missingOf(project), hasLength(1), reason: href);
        }
      },
      skip: Platform.isWindows ? 'Windows cannot hold such a name' : null,
    );

    test('f04/us02/fr04/e11, PS-R2: the target is reported as written while the escape is checked decoded', () async {
      final missing = await writeCheckProject(
        extra: linking('![flow](flow%20chart.png#top)'),
      );
      expect(await missingOf(missing), [
        '$loginFeature:13: link_target_missing: link target flow%20chart.png#top is missing at docs/prds/features/f01_login/flow chart.png',
      ]);
      final present = await writeCheckProject(
        extra: {...linking('![flow](flow%20chart.png#top)'), picture: 'png'},
      );
      expect(await missingOf(present), isEmpty);
    });

    test('a query is left out of the checked path', () async {
      final missing = await writeCheckProject(
        extra: linking('![a](a.png?raw=1)'),
      );
      expect(await missingOf(missing), [
        '$loginFeature:13: link_target_missing: link target a.png?raw=1 is missing at docs/prds/features/f01_login/a.png',
      ]);
      final present = await writeCheckProject(
        extra: {
          ...linking('![a](a.png?raw=1)'),
          'docs/prds/features/f01_login/a.png': 'png',
        },
      );
      expect(await missingOf(present), isEmpty);
    });

    test('f04/us02/fr04, M6: an existing folder counts as present', () async {
      final project = await writeCheckProject(
        extra: {
          ...linking('[assets](assets/)'),
          'docs/prds/features/f01_login/assets/a.txt': 'a',
        },
      );
      expect(await missingOf(project), isEmpty);
    });

    test('a link to an existing file outside the project is no finding', () async {
      final outside = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}specstone_e12_${DateTime.now().microsecondsSinceEpoch}.txt',
      )..writeAsStringSync('x');
      addTearDown(outside.deleteSync);
      final project = await writeCheckProject(
        extra: linking('[o](../../../../../${outside.uri.pathSegments.last})'),
      );
      expect(project.parent.path, Directory.systemTemp.path);
      expect(await missingOf(project), isEmpty);
    });

    test('a web address, mailto, and a rooted path are no finding', () async {
      final project = await writeCheckProject(
        extra: linking(
          '[w](https://example.com/a.png) [m](mailto:a@b.c) [r](/abs/x.md) [s](#top)',
        ),
      );
      expect(await missingOf(project), isEmpty);
    });

    test('f04/us02/fr04/e14, PS-R3: a missing in-tree .md link stays link_unresolved only', () async {
      final project = await writeCheckProject(extra: linking('[g](gone.md)'));
      expect(await missingOf(project), isEmpty);
      expect(spots(await checkOf(project), FindingKind.linkUnresolved), [
        '$loginFeature:13: link_unresolved',
      ]);
    });
  });

  test('f04/us02/fr04/e05, f04/us01/fr01/e04, f04/us01/fr06/e03: an old-format, untyped doc gets its links checked, '
      'and a DocPath target checks it alone', () async {
    final project = await writeCheckProject(
      extra: {'docs/prds/d01_context.md': '# Context\n\n[gone](gone.md)\n'},
    );
    const expected = [
      'prds/d01_context.md:1: untyped_doc',
      'prds/d01_context.md:3: link_unresolved',
    ];
    expect(spots(await checkOf(project)), expected);
    expect(
      spots(await checkOf(project, target: 'prds/d01_context.md')),
      expected,
    );
  });

  test('two links to one deleted doc are two findings', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: doc(
          loginFeature,
          'Users forget passwords.',
          'See [a](gone.md).\nSee [b](gone.md) again.',
        ),
      ),
    );
    expect(spots(report), [
      '$loginFeature:13: link_unresolved',
      '$loginFeature:14: link_unresolved',
    ]);
  });

  test('a broken link to a file outside the checked folders is reported', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: doc(
          loginFeature,
          'Users forget passwords.',
          'See [idea](../../../notes/gone.md).',
        ),
      ),
    );
    expect(
      report.findings.single.textLine,
      '$loginFeature:13: link_unresolved: link target ../../../notes/gone.md is no doc',
    );
  });

  test(
    'an angle-bracket destination with a space is shown as written',
    () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: doc(
            loginFeature,
            'Users forget passwords.',
            'See [a](<gone one.md>).',
          ),
        ),
      );
      expect(
        report.findings.single.textLine,
        '$loginFeature:13: link_unresolved: link target gone one.md is no doc',
      );
    },
  );

  test('a non-ASCII destination is shown as written', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: doc(
          loginFeature,
          'Users forget passwords.',
          'x\nSee [a](ไทย.md).',
        ),
      ),
    );
    expect(
      report.findings.single.textLine,
      '$loginFeature:14: link_unresolved: link target ไทย.md is no doc',
    );
  });

  test(
    'reference links sit on the line of their use, definitions in any order',
    () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: doc(
            loginFeature,
            'Users forget passwords.',
            'See [a][r2].\nAnd [b][r1].\n\n[r1]: x.md\n[r2]: y.md\n\n```\n[c](fenced.md)\n```',
          ),
        ),
      );
      expect(
        [for (final f in report.findings) f.textLine],
        [
          '$loginFeature:13: link_unresolved: link target y.md is no doc',
          '$loginFeature:14: link_unresolved: link target x.md is no doc',
        ],
      );
    },
  );

  test('wrapped link text does not displace the next broken link', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: doc(
          loginFeature,
          'Users forget passwords.',
          'See [long\ntext](gone-a.md).\n\nAnd [b](gone-b.md).',
        ),
      ),
    );
    expect(
      [for (final f in report.findings) f.textLine],
      [
        '$loginFeature:13: link_unresolved: link target gone-a.md is no doc',
        '$loginFeature:16: link_unresolved: link target gone-b.md is no doc',
      ],
    );
  });

  test(
    'a balanced () in a destination and [] in link text are placed',
    () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: doc(
            loginFeature,
            'Users forget passwords.',
            'See [a](x(1).md).\nAnd [see [x]](gone.md).',
          ),
        ),
      );
      expect(
        [for (final f in report.findings) f.textLine],
        [
          '$loginFeature:13: link_unresolved: link target x(1).md is no doc',
          '$loginFeature:14: link_unresolved: link target gone.md is no doc',
        ],
      );
    },
  );

  test('f04/us02/fr04/e09, cc-s03/inv15, LP4: a doc the parser fails on gets markdown_unparsed at line 1', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: doc(
          loginFeature,
          'Users forget passwords.',
          'Users forget passwords.\n\n[a]:<b\\',
        ),
      ),
    );
    expect(
      [for (final f in report.findings) f.textLine],
      [
        '$loginFeature:1: markdown_unparsed: the markdown parser failed on this doc; its links are not checked',
      ],
    );
    expect(report.warnings, isEmpty);
  });

  group('resolve_doc_links anchors, self links, malformed links, and doc_ref values', () {
    const pointerKinds = {
      FindingKind.docRefUnresolved,
      FindingKind.docRefDuplicate,
      FindingKind.docRefSelf,
      FindingKind.linkUnresolved,
      FindingKind.linkAnchorMissing,
      FindingKind.linkSelf,
      FindingKind.referenceMalformed,
      FindingKind.linkTargetMissing,
    };
    const d03 = 'prds/d03_non_functional.md';

    Future<List<Finding>> pointersOf(Directory project) async => [
      for (final f in (await checkOf(project)).findings)
        if (pointerKinds.contains(f.kind)) f,
    ];

    List<String> textOf(List<Finding> findings) => [
      for (final f in findings) f.textLine,
    ];

    List<Map<String, Object>> keysOf(List<Finding> findings) => [
      for (final f in findings) f.keys,
    ];

    Map<String, String> featureLinking(String text) => doc(
      loginFeature,
      'Users forget passwords.',
      'Users forget passwords; $text',
    );

    Map<String, String> gnfrLinking(String text) =>
        doc(gnfrDoc, 'N/A — none applies.', text);

    test('E03: an anchor that is the slug of a heading of '
        'its target resolves', () async {
      final findings = await pointersOf(
        await writeCheckProject(
          extra: {
            ...featureLinking(
              '[d03](../../d03_non_functional.md#performance).',
            ),
            'docs/$d03': '# Non-functional\n\n## Performance\n\nFast.\n',
          },
        ),
      );
      expect(findings, isEmpty);
    });

    test('E15: an anchor no heading, id, or name of its '
        'target carries is link_anchor_missing; a link to no doc is link_unresolved only', () async {
      final findings = await pointersOf(
        await writeCheckProject(
          extra: {
            ...featureLinking(
              '[d03](../../d03_non_functional.md#performance) and [g](gone.md#performance).',
            ),
            'docs/$d03': '# Non-functional\n\n## Speed\n\nFast.\n',
          },
        ),
      );
      expect(textOf(findings), [
        '$loginFeature:13: link_anchor_missing: link target ../../d03_non_functional.md#performance names anchor performance, which $d03 does not hold',
        '$loginFeature:13: link_unresolved: link target gone.md#performance is no doc',
      ]);
      expect(keysOf(findings), [
        {
          'target': '../../d03_non_functional.md#performance',
          'anchor': 'performance',
        },
        {'target': 'gone.md#performance'},
      ]);
    });

    test('E16: a bare #anchor resolves against the linking '
        "doc's own headings, ids, and names; one it lacks, a footnote's id included, is link_anchor_missing", () async {
      const rules = 'prds/d02_rules.md';
      const notes = 'prds/d04_notes.md';
      final findings = await pointersOf(
        await writeCheckProject(
          extra: {
            'docs/$rules':
                '# Rules doc\n\n## Rules\n\n'
                '[rules](#rules), [a](#my-a), [s](#my-span), [n](#my-name), and [x](#nothing).\n\n'
                '<a id="my-a"></a> <span id="my-span"></span> <a name="my-name"></a>\n',
            'docs/$notes': '# Notes\n\nA claim.[^1] See [x](#fn-1).\n\n[^1]: The source.\n',
          },
        ),
      );
      expect(textOf(findings), [
        '$rules:5: link_anchor_missing: link target #nothing names anchor nothing, which $rules does not hold',
        '$notes:3: link_anchor_missing: link target #fn-1 names anchor fn-1, which $notes does not hold',
      ]);
      expect(keysOf(findings), [
        {'target': '#nothing', 'anchor': 'nothing'},
        {'target': '#fn-1', 'anchor': 'fn-1'},
      ]);
    });

    test("E17: a heading's anchor is its rendered text's "
        'slug, a repeat suffixed', () async {
      const moves = 'prds/d05_moves.md';
      final findings = await pointersOf(
        await writeCheckProject(
          extra: {
            'docs/$moves':
                '# Moves\n\n### `move` — FR-01\n\n## Notes\n\n## Notes\n\n'
                '[m](#move--fr-01), [n](#notes-1), and [o](#notes-2).\n',
          },
        ),
      );
      expect(textOf(findings), [
        '$moves:9: link_anchor_missing: link target #notes-2 names anchor notes-2, which $moves does not hold',
      ]);
    });

    test('E18: a link to its own doc with no anchor is '
        'link_self; with a heading anchor it resolves', () async {
      final findings = await pointersOf(
        await writeCheckProject(
          extra: gnfrLinking(
            '[self](../../docs/prds/GNFR.md) and [perf](../../docs/prds/GNFR.md#performance).',
          ),
        ),
      );
      expect(textOf(findings), [
        '$gnfrDoc:16: link_self: link target ../../docs/prds/GNFR.md names the doc that holds it',
      ]);
      expect(keysOf(findings), [
        {'target': '../../docs/prds/GNFR.md'},
      ]);
    });

    test('E18: an empty link target is link_self, its '
        'message showing (empty) for the target', () async {
      final findings = await pointersOf(
        await writeCheckProject(extra: gnfrLinking('[TBD]() here.')),
      );
      expect(textOf(findings), [
        '$gnfrDoc:16: link_self: link target (empty) names the doc that holds it',
      ]);
      expect(keysOf(findings), [
        {'target': ''},
      ]);
    });

    test('E19: a doc_ref value one list field holds a '
        'second time is doc_ref_duplicate at the second value; another field is its own list', () async {
      const checkout = 'prds/features/f02_checkout/FEATURE.md';
      final report = await checkOf(
        await writeCheckProject(
          extra: {
            'docs/$checkout': checkProjectFiles()['docs/$loginFeature']!
                .replaceFirst('# Login', '# Checkout')
                .replaceFirst(
                  '  - PG-01\n---',
                  '  - PG-01\ndepends_on:\n  - login\n  - login\npersona:\n  - login\n---',
                ),
          },
        ),
      );
      final repeats = [
        for (final f in report.findings)
          if (f.kind == FindingKind.docRefDuplicate) f,
      ];
      expect(textOf(repeats), [
        '$checkout:9: doc_ref_duplicate: depends_on holds login a second time',
      ]);
      expect(keysOf(repeats), [
        {'field': 'depends_on', 'value': 'login'},
      ]);
    });

    test('E20: a doc_ref value naming the doc that holds '
        'it is doc_ref_self; a value naming a doc of another type is not', () async {
      final findings = await pointersOf(
        await writeCheckProject(
          extra: {
            ...doc(
              loginFeature,
              '  - PG-01\n---',
              '  - PG-01\ndepends_on:\n  - login\npersona:\n  - login\n---',
            ),
            'docs/prds/personas/login/PERSONA.md': '---\nrole: Agent\npriority: primary\nbasis: proto\n---\n\n# Login\n',
          },
        ),
      );
      expect(textOf(findings), [
        '$loginFeature:8: doc_ref_self: depends_on value login names the doc that holds it',
      ]);
      expect(keysOf(findings), [
        {'field': 'depends_on', 'value': 'login'},
      ]);
    });

    test(
      'a malformed absolute URL gives no finding; a lone % stays in the path',
      () async {
        final findings = await pointersOf(
          await writeCheckProject(
            extra: featureLinking('[x](http://h:abc/x.md) and [y](a%zz.md).'),
          ),
        );
        expect(textOf(findings), [
          '$loginFeature:13: link_unresolved: link target a%zz.md is no doc',
        ]);
        expect(keysOf(findings), [
          {'target': 'a%zz.md'},
        ]);
      },
    );

    test("E22: an empty fragment names its doc's top, so "
        'it is neither link_self nor link_anchor_missing; a self link with no # is link_self', () async {
      final findings = await pointersOf(
        await writeCheckProject(
          extra: gnfrLinking(
            '[top](#), [top](GNFR.md#), [up](../../docs/prds/GNFR.md#), [x](PROJECT.md#), and [self](GNFR.md).',
          ),
        ),
      );
      expect(textOf(findings), [
        '$gnfrDoc:16: link_self: link target GNFR.md names the doc that holds it',
      ]);
    });

    test("a web link's fragment is never read; a doc "
        "link's anchor is read past its query", () async {
      final findings = await pointersOf(
        await writeCheckProject(
          extra: gnfrLinking(
            '[w](https://example.com/x#nothing) and [q](PROJECT.md?x=1#missing).',
          ),
        ),
      );
      expect(textOf(findings), [
        '$gnfrDoc:16: link_anchor_missing: link target PROJECT.md?x=1#missing names anchor missing, which $projectDoc does not hold',
      ]);
      expect(keysOf(findings), [
        {'target': 'PROJECT.md?x=1#missing', 'anchor': 'missing'},
      ]);
    });

    test('an anchor of a doc whose anchor set is unknown '
        'is no link_anchor_missing', () async {
      final findings = await pointersOf(
        await writeCheckProject(
          extra: {
            ...featureLinking('[x](../../d09_broken.md#gone).'),
            'docs/prds/d09_broken.md': '# Broken\n\n[a]:<b\\',
          },
        ),
      );
      expect(findings, isEmpty);
    });
  });

  group('resolve_doc_links doc-name mentions', () {
    Future<List<Finding>> mentionsOf(Directory project) async => [
      for (final f in (await checkOf(project)).findings)
        if (f.kind == FindingKind.docNameUnresolved) f,
    ];

    Map<String, String> featureWriting(String text) => doc(
      loginFeature,
      'Users forget passwords.',
      'Users forget passwords; $text',
    );

    test('E25: a typed '
        'name one letter short under a top-level feature is '
        'doc_name_unresolved, the name as written', () async {
      final findings = await mentionsOf(
        await writeCheckProject(
          extra: featureWriting(
            'see `fr:login/email_login/check_pasword#statement`.',
          ),
        ),
      );
      expect(
        [for (final f in findings) f.textLine],
        [
          '$loginFeature:13: doc_name_unresolved: doc name fr:login/email_login/check_pasword#statement names no doc',
        ],
      );
      expect(
        [for (final f in findings) f.keys],
        [
          {'name': 'fr:login/email_login/check_pasword#statement'},
        ],
      );
    });

    Map<String, String> featureWithMermaid(String lines) => doc(
      loginFeature,
      'Users forget passwords.',
      'Users forget passwords.\n\n```mermaid\nflowchart LR\n$lines\n```',
    );

    test('a stale mermaid name under a top-level feature is doc_name_unresolved at its line', () async {
      final findings = await mentionsOf(
        await writeCheckProject(
          extra: featureWithMermaid('  N[login/email_login/check_pasword E06]'),
        ),
      );
      expect(
        [for (final f in findings) f.textLine],
        [
          '$loginFeature:17: doc_name_unresolved: doc name login/email_login/check_pasword names no doc',
        ],
      );
      expect(
        [for (final f in findings) f.keys],
        [
          {'name': 'login/email_login/check_pasword'},
        ],
      );
    });

    test('a mermaid token under no top-level feature is left alone', () async {
      final findings = await mentionsOf(
        await writeCheckProject(
          extra: featureWithMermaid(
            '  N[origin/develop]\n  M[https://example.com/a/b]\n'
            '  K[login/email_login/check_password]',
          ),
        ),
      );
      expect(findings, isEmpty);
    });

    test('E26: a '
        'name whose first slug names no top-level feature, a git ref, and a '
        'skill name raise nothing', () async {
      final findings = await mentionsOf(
        await writeCheckProject(
          extra: featureWriting(
            'see `shop/checkout`, `architecture:shop`, `origin/develop`, '
            '`superpowers:writing-plans`, `user_id`, and '
            '`check architecture:login`.',
          ),
        ),
      );
      expect(findings, isEmpty);
    });

    test('E27: names '
        'that resolve raise nothing, and a section key the doc lacks is '
        'never read', () async {
      final findings = await mentionsOf(
        await writeCheckProject(
          extra: featureWriting(
            'see `feature:login`, `login/email_login#nothing_here`, and '
            '`login/email_login/check_password`.',
          ),
        ),
      );
      expect(findings, isEmpty);
    });

    test('E07: a name '
        'in plain text and one in fenced code raise nothing', () async {
      final findings = await mentionsOf(
        await writeCheckProject(
          extra: featureWriting(
            'see login/email_login/check_pasword.\n\n```text\n'
            '`login/email_login/check_pasword`\n```',
          ),
        ),
      );
      expect(findings, isEmpty);
    });

    /// The login feature with a `crud` feature beside it, listing [patterns]
    /// and holding [skips] under its Out-of-scope section.
    Future<Directory> skipProject({
      List<String> patterns = const ['crud'],
      required List<String> skips,
    }) => writeCheckProject(
      extra: {
        '.specstone/templates/feature.yaml':
            'fields:\n  - id: patterns\n    type: string\n    list: true\n',
        'docs/prds/features/f02_crud/FEATURE.md': '# Crud\n',
        ...edit(loginFeature, [
          (
            'goals:\n  - PG-01\n',
            'goals:\n  - PG-01\npatterns:\n${[for (final id in patterns) '  - $id\n'].join()}',
          ),
          (
            '- Social sign-in — not planned\n',
            '- Social sign-in — not planned\n${skips.join('\n')}\n',
          ),
        ]),
      },
    );

    test('a skip line of a listed pattern is no doc-name mention, even '
        'when a feature of the pattern name exists', () async {
      final findings = await mentionsOf(
        await skipProject(skips: ['- `crud/paged_list` — one page is enough']),
      );
      expect(findings, isEmpty);
    });

    test('the same span in a feature that does not list the pattern is '
        'read as any doc-name mention', () async {
      final project = await skipProject(
        patterns: const [],
        skips: ['- `crud/paged_list` — one page is enough'],
      );
      expect(
        [for (final f in await mentionsOf(project)) f.keys],
        [
          {'name': 'crud/paged_list'},
        ],
      );
    });

    test(
      'a second span on a skip line still reads as a doc-name mention',
      () async {
        final findings = await mentionsOf(
          await skipProject(
            skips: ['- `crud/paged_list` — instead of `crud/paged_lis`'],
          ),
        );
        expect(
          [for (final f in findings) f.keys],
          [
            {'name': 'crud/paged_lis'},
          ],
        );
      },
    );

    test('guard: a bullet with a hyphen or two as its separator is no skip '
        'line, so its span reads as any doc-name mention', () async {
      final findings = await mentionsOf(
        await skipProject(
          skips: [
            '- `crud/paged_list` - one page is enough',
            '- `crud/paged_list` -- one page is enough',
          ],
        ),
      );
      expect(
        [for (final f in findings) f.keys],
        [
          {'name': 'crud/paged_list'},
          {'name': 'crud/paged_list'},
        ],
      );
    });

    test('S14: an '
        'untyped doc is checked and the finding names the doc, the line, and '
        'the name', () async {
      const notes = 'prds/d07_notes.md';
      final findings = await mentionsOf(
        await writeCheckProject(
          extra: {'docs/$notes': '# Notes\n\nOne `login/email_logn`.\n'},
        ),
      );
      expect(
        [for (final f in findings) f.textLine],
        ['$notes:3: doc_name_unresolved: doc name login/email_logn names no doc'],
      );
    });
  });

  group('two targets', () {
    const flutterRecord =
        '.specstone/records/flutter/f01_login/IMPLEMENTATION.md';
    const jasprRecord = '.specstone/records/jaspr/f01_login/IMPLEMENTATION.md';
    const record = '# Record\n';
    const relatedLayer =
        'id: architecture\n'
        'per_target: true\n'
        'fields:\n'
        '  - id: related\n'
        '    type: doc_ref\n'
        '    list: true\n'
        '    doc_types: [implementation]\n';

    /// Returns the login architecture text with [sentence] after its box.
    String twin(String sentence, {String? related}) =>
        checkProjectFiles()['docs/$loginArchitecture']!
            .replaceFirst('One box.', 'One box. $sentence')
            .replaceFirst(
              '  - app/lib/\n---',
              '  - app/lib/\n${related ?? ''}---',
            );

    /// Returns the sign-in time NFR, a shared doc the twin project leaves
    /// alone, with [sentence] in its rationale.
    Map<String, String> shared(String sentence) =>
        doc(loginNf, 'Users wait.', 'Users wait. $sentence');

    int lineOf(Directory project, String docPath, String needle) =>
        File('${project.path}/docs/$docPath')
            .readAsLinesSync()
            .indexWhere((line) => line.contains(needle)) +
        1;

    Future<List<Finding>> found(
      Directory project,
      FindingKind kind, {
      String? at,
    }) async => [
      for (final f in (await checkOf(project)).findings)
        if (f.kind == kind && (at == null || f.path == at)) f,
    ];

    test('E30: a '
        'shared doc naming a per-target doc by name gets '
        'per_target_reference at the mention', () async {
      final project = await writeTwinProject(
        extra: shared('See `architecture:login`.'),
      );

      final findings = await found(project, FindingKind.perTargetReference);

      expect(
        [for (final f in findings) '${f.path}:${f.line}'],
        ['$loginNf:${lineOf(project, loginNf, 'architecture:login')}'],
      );
      expect(findings.single.keys, {
        'reference': 'architecture:login',
        'target': 'flutter, jaspr',
      });
      expect(
        findings.single.message,
        'architecture:login names a per-target doc of flutter, jaspr',
      );
    });

    test("a shared doc's mermaid node naming a per-target doc is per_target_reference", () async {
      final project = await writeTwinProject(
        extra: shared(
          'See below.\n\n```mermaid\nflowchart LR\n  N[architecture:login]\n```',
        ),
      );

      final findings = await found(project, FindingKind.perTargetReference);

      expect(
        [for (final f in findings) '${f.path}:${f.line}'],
        ['$loginNf:${lineOf(project, loginNf, 'architecture:login')}'],
      );
      expect(findings.single.keys, {
        'reference': 'architecture:login',
        'target': 'flutter, jaspr',
      });
    });

    test("a per-target doc's mermaid node naming only another target's doc is doc_name_unresolved", () async {
      final mention = twin(
        'See below.\n\n```mermaid\nflowchart LR\n'
        '  N[implementation:login]\n```',
      );
      Future<Directory> project({bool jasprHoldsOne = false}) =>
          writeTwinProject(
            extra: {
              'docs/$flutterArchitecture': mention,
              'docs/$jasprArchitecture': mention,
              flutterRecord: record,
              if (jasprHoldsOne) jasprRecord: record,
            },
          );

      final lone = await project();
      final both = await project(jasprHoldsOne: true);

      final findings = await found(lone, FindingKind.docNameUnresolved);
      expect([for (final f in findings) f.path], [jasprArchitecture]);
      expect(
        findings.single.line,
        lineOf(lone, jasprArchitecture, 'implementation:login'),
      );
      expect(await found(both, FindingKind.docNameUnresolved), isEmpty);
    });

    test('E30: a '
        'mention a shared doc resolves too gives none', () async {
      final project = await writeTwinProject(
        extra: shared('See `feature:login` and `login/email_login`.'),
      );

      expect(await found(project, FindingKind.perTargetReference), isEmpty);
    });

    test('E30: a '
        '.md link to a per-target doc is reported as written', () async {
      const written = '../../../../specs/flutter/f01_login/ARCHITECTURE.md';
      final project = await writeTwinProject(
        extra: shared('See [arch]($written).'),
      );

      final findings = await found(project, FindingKind.perTargetReference);

      expect(
        [for (final f in findings) f.keys],
        [
          {'reference': written, 'target': 'flutter'},
        ],
      );
      expect(findings.single.line, lineOf(project, loginNf, written));
      expect(
        await found(project, FindingKind.linkUnresolved, at: loginNf),
        isEmpty,
      );
    });

    test('E30: a '
        'DocPath in text is reported once, a shared doc path never', () async {
      const path = 'specs/jaspr/f01_login/ARCHITECTURE.md';
      final project = await writeTwinProject(
        extra: shared('See `$path`, then `specs/f01_login/API.md`.'),
      );

      final findings = await found(project, FindingKind.perTargetReference);

      expect(
        [for (final f in findings) f.keys],
        [
          {'reference': path, 'target': 'jaspr'},
        ],
      );
      expect(findings.single.line, lineOf(project, loginNf, path));
    });

    test('E30: a '
        'DocPath with a #anchor, one closing a sentence, and a docs/ path '
        'are reported; a fenced one is not', () async {
      const path = 'specs/jaspr/f01_login/ARCHITECTURE.md';
      final project = await writeTwinProject(
        extra: shared(
          'See `$path#boxes`.\n\nAlso $path.\n\nAnd `docs/$path`.\n\n'
          '```text\n$path\n```',
        ),
      );

      final findings = await found(project, FindingKind.perTargetReference);

      expect(
        [for (final f in findings) f.keys['reference']],
        [path, path, 'docs/$path'],
      );
    });

    test('E30: a '
        'link whose text is the path it points to is reported once', () async {
      const path = 'specs/flutter/f01_login/ARCHITECTURE.md';
      final project = await writeTwinProject(
        extra: shared('See [$path](../../../../$path).'),
      );

      expect(
        await found(project, FindingKind.perTargetReference),
        hasLength(1),
      );
    });

    test('E30: a '
        'link whose destination runs onto a later line is reported once', () async {
      final project = await writeTwinProject(
        extra: shared(
          'See [arch](\n../../../../specs/flutter/f01_login/ARCHITECTURE.md).',
        ),
      );

      expect(
        await found(project, FindingKind.perTargetReference),
        hasLength(1),
      );
    });

    test(
      'E30: a '
      'doc_ref value naming a per-target doc is reported at the value',
      () async {
        final project = await writeTwinProject(
          extra: {
            '.specstone/templates/feature.yaml':
                'id: feature\n'
                'fields:\n'
                '  - id: related\n'
                '    type: doc_ref\n'
                '    list: true\n'
                '    doc_types: [architecture]\n',
            ...edit(loginFeature, [
              ('Users forget passwords.', 'Users forget passwords.$brokenLink'),
              ('  - PG-01\n---', '  - PG-01\nrelated:\n  - login\n---'),
            ]),
          },
        );

        final findings = await found(project, FindingKind.perTargetReference);

        expect(
          [for (final f in findings) f.keys],
          [
            {'reference': 'login', 'target': 'flutter, jaspr'},
          ],
        );
        expect(findings.single.path, loginFeature);
        expect(
          findings.single.line,
          lineOf(project, loginFeature, '  - login'),
        );
      },
    );

    test('E29: a '
        'per-target doc names another target by path or link and gets no '
        'finding', () async {
      final project = await writeTwinProject(
        extra: {
          'docs/$jasprArchitecture': twin(
            'See `$flutterArchitecture` and '
            '[flutter](../../flutter/f01_login/ARCHITECTURE.md).',
          ),
        },
      );

      for (final kind in [
        FindingKind.perTargetReference,
        FindingKind.docNameUnresolved,
        FindingKind.linkUnresolved,
      ]) {
        expect(await found(project, kind, at: jasprArchitecture), isEmpty);
      }
    });

    test('E28: a '
        'name only another target holds is doc_name_unresolved in a '
        'per-target doc', () async {
      final mention = twin('See `implementation:login`.');
      Future<Directory> project({bool jasprHoldsOne = false}) =>
          writeTwinProject(
            extra: {
              'docs/$flutterArchitecture': mention,
              'docs/$jasprArchitecture': mention,
              flutterRecord: record,
              if (jasprHoldsOne) jasprRecord: record,
            },
          );

      final lone = await project();
      final both = await project(jasprHoldsOne: true);

      expect(
        [
          for (final f in await found(lone, FindingKind.docNameUnresolved))
            f.path,
        ],
        [jasprArchitecture],
      );
      expect(await found(both, FindingKind.docNameUnresolved), isEmpty);
      expect(await found(lone, FindingKind.perTargetReference), isEmpty);
    });

    test('E28: a '
        'doc_ref value only another target holds is doc_ref_unresolved in a '
        'per-target doc', () async {
      final related = twin('', related: 'related:\n  - login\n');
      Future<Directory> project({bool jasprHoldsOne = false}) =>
          writeTwinProject(
            extra: {
              '.specstone/templates/architecture.yaml': relatedLayer,
              'docs/$flutterArchitecture': related,
              'docs/$jasprArchitecture': related,
              flutterRecord: record,
              if (jasprHoldsOne) jasprRecord: record,
            },
          );

      final lone = await project();
      final both = await project(jasprHoldsOne: true);

      final findings = await found(lone, FindingKind.docRefUnresolved);
      expect([for (final f in findings) f.path], [jasprArchitecture]);
      expect(findings.single.keys, {'field': 'related', 'value': 'login'});
      expect(await found(both, FindingKind.docRefUnresolved), isEmpty);
    });
  });

  group('one target', () {
    // One target, named or not: no shared doc's reference is per-target.
    final configs = {
      'unnamed': <String, String>{},
      'named': {
        '.specstone/config.yaml':
            '${shippedPinsConfig()}targets:\n  flutter:\n    code_root: ws\n',
        'ws/app/lib/login.dart': 'class SignInPage {}\n',
        // A named target owns records, so the set must hold their type.
        '.specstone/templates/implementation.yaml':
            'id: implementation\n'
            'description: One feature record per target.\n'
            'path: .specstone/records/f{nn}_{slug}/IMPLEMENTATION.md\n'
            'parent: feature\n'
            'per_target: true\n'
            'fields:\n'
            '  - id: statuses\n'
            '    type: record_status\n'
            '    list: true\n',
      },
    };
    for (final MapEntry(key: name, value: files) in configs.entries) {
      test('E31: a '
          'shared doc names a per-target doc, $name target, and gets no '
          'per_target_reference', () async {
        final project = await writeCheckProject(
          extra: {
            '.specstone/templates/architecture.yaml':
                'id: architecture\nper_target: true\n',
            ...files,
            ...doc(
              loginNf,
              'Users wait.',
              'Users wait. See `architecture:login`, '
                  '`specs/f01_login/ARCHITECTURE.md`, and '
                  '[arch](../../../../specs/f01_login/ARCHITECTURE.md).',
            ),
          },
        );

        expect([
          for (final f in (await checkOf(project)).findings)
            if (f.kind == FindingKind.perTargetReference ||
                f.kind == FindingKind.docNameUnresolved ||
                f.kind == FindingKind.linkUnresolved)
              f.textLine,
        ], isEmpty);
      });
    }
  });

  group('resolve_item_links', () {
    const itemKinds = {
      FindingKind.linkItemMissing,
      FindingKind.linkAnchorMissing,
    };
    const gnfrPerformance = '../../GNFR.md#performance';

    Future<List<Finding>> itemFindingsOf(Directory project) async => [
      for (final f in (await checkOf(project)).findings)
        if (itemKinds.contains(f.kind)) f,
    ];

    Map<String, String> featureLinking(String text) => doc(
      loginFeature,
      'Users forget passwords.',
      'Users forget passwords; $text',
    );

    Map<String, String> gnfrWithP03() => edit(gnfrDoc, [
      (
        '- **Rationale:** Users wait.\n\n',
        '- **Rationale:** Users wait.\n\n### NFR-P03 — Load time\n\nFast.\n\n',
      ),
    ]);

    test(
      'an item link whose section holds the item gives no finding',
      () async {
        final findings = await itemFindingsOf(
          await writeCheckProject(
            extra: featureLinking('[NFR-P01]($gnfrPerformance).'),
          ),
        );
        expect(findings, isEmpty);
      },
    );

    test('an item link whose section lacks the item is link_item_missing with target and item', () async {
      final findings = await itemFindingsOf(
        await writeCheckProject(
          extra: featureLinking('[NFR-P09]($gnfrPerformance).'),
        ),
      );
      expect([for (final f in findings) f.kind], [FindingKind.linkItemMissing]);
      expect(findings.single.line, 13);
      expect(findings.single.waitsFor, WaitsFor.agent);
      expect(findings.single.keys, {
        'target': gnfrPerformance,
        'item': 'NFR-P09',
      });
    });

    test(
      'an S<N> link to a scenario the story lacks is link_item_missing',
      () async {
        const story = 'us01_email_login/USER_STORY.md#acceptance-criteria';
        final findings = await itemFindingsOf(
          await writeCheckProject(
            extra: featureLinking('[S2]($story) and [S7]($story).'),
          ),
        );
        expect(
          [for (final f in findings) f.keys],
          [
            {'target': story, 'item': 'S7'},
          ],
        );
      },
    );

    test(
      'a fragment that names no anchor is link_anchor_missing only',
      () async {
        final findings = await itemFindingsOf(
          await writeCheckProject(
            extra: featureLinking('[NFR-P09](../../GNFR.md#speed).'),
          ),
        );
        expect(
          [for (final f in findings) f.kind],
          [FindingKind.linkAnchorMissing],
        );
      },
    );

    test(
      'an anchor of a doc whose anchor set is unknown gives neither finding',
      () async {
        final findings = await itemFindingsOf(
          await writeCheckProject(
            extra: {
              ...featureLinking('[NFR-P09]($gnfrPerformance).'),
              ...edit(gnfrDoc, [
                ('## Performance', '[a]:<b\\\n\n## Performance'),
              ]),
            },
          ),
        );
        expect(findings, isEmpty);
      },
    );

    test(
      'two spellings of one destination on a line each keep their own target',
      () async {
        const plain = '../../GNFR.md#performance';
        const dotted = './../../GNFR.md#performance';
        final findings = await itemFindingsOf(
          await writeCheckProject(
            extra: featureLinking('[NFR-P08]($plain) and [NFR-P09]($dotted).'),
          ),
        );
        expect(
          [for (final f in findings) f.keys],
          [
            {'target': plain, 'item': 'NFR-P08'},
            {'target': dotted, 'item': 'NFR-P09'},
          ],
        );
      },
    );

    test('a text that is no item ID of the section prefix is a section link', () async {
      final findings = await itemFindingsOf(
        await writeCheckProject(
          extra: featureLinking(
            '[NFR-9]($gnfrPerformance), [the NFR-P09 rule]($gnfrPerformance), and [rules](../../GNFR.md#performance).',
          ),
        ),
      );
      expect(findings, isEmpty);
    });

    test(
      'a fragment that names a ### heading gives no finding of this rule',
      () async {
        final findings = await itemFindingsOf(
          await writeCheckProject(
            extra: featureLinking(
              '[NFR-P09](../../GNFR.md#nfr-p01--sign-in-time).',
            ),
          ),
        );
        expect(findings, isEmpty);
      },
    );

    test('each end of a range is checked alone, and the middle numbers are not', () async {
      final project = await writeCheckProject(
        extra: {
          ...gnfrWithP03(),
          ...featureLinking(
            '[NFR-P01]($gnfrPerformance) to [NFR-P03]($gnfrPerformance).\n\n'
            'Then [NFR-P01]($gnfrPerformance) to [NFR-P09]($gnfrPerformance).',
          ),
        },
      );
      final findings = await itemFindingsOf(project);
      expect(
        [for (final f in findings) f.keys],
        [
          {'target': gnfrPerformance, 'item': 'NFR-P09'},
        ],
      );
      expect(findings.single.line, 15);
    });

    test(
      'a bare #anchor link is checked against the linking doc own section',
      () async {
        final findings = await itemFindingsOf(
          await writeCheckProject(
            extra: doc(
              gnfrDoc,
              '## Security\n\nN/A — none applies.',
              '## Security\n\n[NFR-P01](#performance) and [NFR-P09](#performance).',
            ),
          ),
        );
        expect([for (final f in findings) f.path], [gnfrDoc]);
        expect(
          [for (final f in findings) f.keys],
          [
            {'target': '#performance', 'item': 'NFR-P09'},
          ],
        );
      },
    );

    test('the rule reads the stored item facts, never a file', () async {
      final project = await writeCheckProject(
        extra: featureLinking('[NFR-P01]($gnfrPerformance).'),
      );
      final anHourAgo = DateTime.now().subtract(const Duration(hours: 1));
      for (final file in Directory(
        '${project.path}/docs',
      ).listSync(recursive: true).whereType<File>()) {
        file.setLastModifiedSync(anHourAgo);
      }
      expect(await itemFindingsOf(project), isEmpty);
      // The stat is unchanged, so the next refresh keeps the row with its
      // item facts edited to hold no NFR-P01.
      sqlite3.open('${project.path}/$indexFilePath')
        ..execute(
          "UPDATE docs SET item_facts = replace(item_facts, '\"NFR-P01\"', 'null') WHERE doc_path = ?",
          [gnfrDoc],
        )
        ..close();
      expect(
        [for (final f in await itemFindingsOf(project)) f.keys],
        [
          {'target': gnfrPerformance, 'item': 'NFR-P01'},
        ],
      );
    });
  });

  group('a link across the docs root and the records root', () {
    const record = '.specstone/records/f01_login/IMPLEMENTATION.md';
    const rulesDoc = 'docs/specs/topics/rules.md';

    Map<String, String> records(String recordBody, {String? rulesBody}) => {
      ...recordsRootTemplates,
      record:
          '---\nstatuses:\n  - "email_login:planned"\n---\n\n# Record\n\n$recordBody\n',
      rulesDoc: rulesBody ?? '# Rules\n\n## Purpose\nRules.\n',
    };

    Future<List<String>> linkFindings(Directory project) async => [
      for (final f in (await checkOf(project)).findings)
        if (f.kind == FindingKind.linkUnresolved ||
            f.kind == FindingKind.linkTargetMissing)
          f.textLine,
    ];

    test(
      'a record link to a docs doc resolves from the project root',
      () async {
        final project = await writeCheckProject(
          extra: records(
            'See [rules](../../../docs/specs/topics/rules.md#purpose).',
          ),
        );
        expect(await linkFindings(project), isEmpty);
      },
    );

    test('a record link to a missing docs doc is link_unresolved', () async {
      final project = await writeCheckProject(
        extra: records('See [gone](../../../docs/specs/topics/gone.md).'),
      );
      expect(await linkFindings(project), [
        '$record:9: link_unresolved: link target ../../../docs/specs/topics/gone.md is no doc',
      ]);
    });

    test('a docs doc link to a record resolves to that record', () async {
      final project = await writeCheckProject(
        extra: records(
          'Record.',
          rulesBody: '# Rules\n\n## Purpose\nSee [record](../../../.specstone/records/f01_login/IMPLEMENTATION.md).\n',
        ),
      );
      expect(await linkFindings(project), isEmpty);
    });
  });
}
