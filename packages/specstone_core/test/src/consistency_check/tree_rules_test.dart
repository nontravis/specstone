// The expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/tree_rules.dart'
    show checkedFoldersOf, isInCheckedFolder, missingSingularDocs;
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/fixture_doc_types.dart';
import '../../helpers/index_fixture.dart' show openSession;
import '../../helpers/nested_fixture.dart';
import '../../helpers/posix_modes.dart';
import '../../helpers/record_fixture.dart' show recordsRootTemplates;
import '../../helpers/shipped_pins.dart';
import '../../helpers/target_fixture.dart';
import '../../helpers/temp_tree.dart';

const _goalDoc = 'prds/GOAL.md';
const _glossaryDoc = 'prds/GLOSSARY.md';
const _styleLayer =
    'id: style\n'
    'description: House style.\n'
    'path: prds/STYLE.md\n';
const _missingMessage = 'the project holds no ';
const _jasprFirstConfig =
    'targets:\n'
    '  jaspr:\n    code_root: jaspr_ws\n'
    '  flutter:\n    code_root: flutter_ws\n';

List<Finding> _missingOf(CheckReport report) => [
  for (final f in report.findings)
    if (f.kind == FindingKind.singularDocMissing) f,
];

void main() {
  test('f04/us01/s5, f04/us01/fr06/e01, f04/us01/fr06/e02: a file in a checked folder no pattern matches is '
      'untyped; a file outside them gets no check', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          'docs/notes/2026-10-27-ideas.md':
              '---\npriority: high\n---\n\nNo title.\n',
          'docs/prds/features/f01_login/us02_Reset_Password/USER_STORY.md':
              '# Capitals\n',
        },
      ),
    );
    expect(spots(report), [
      'prds/features/f01_login/us02_Reset_Password/USER_STORY.md:1: untyped_doc',
    ]);
  });

  test('f04/us01/fr06/e05, f04/us01/fr06/e06: a project path pattern adds its folder; two matching patterns are '
      'doc_type_ambiguous, and its warning is not printed', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          '.specstone/templates/runbook.yaml': 'id: runbook\ndescription: Run steps.\npath: ops/{slug}/runbook.md\n',
          '.specstone/templates/playbook.yaml':
              'id: playbook\ndescription: Plays.\npath: ops/deploy/{slug}.md\n',
          'docs/ops/deploy/runbook.md': '# Deploy\n',
          'docs/ops/other.md': '# Other\n',
        },
      ),
    );
    expect(spots(report), [
      'ops/deploy/runbook.md:1: doc_type_ambiguous',
      'ops/other.md:1: untyped_doc',
    ]);
    expect(
      report.findings.first.toJson()['docTypes'],
      unorderedEquals(['runbook', 'playbook']),
    );
    expect(report.warnings, isEmpty);
  });

  test('f04/us01/fr07/e01, f04/us01/fr07/e02: two stories numbered us01 under one feature are reported on each; '
      'an fr01 and an nf01 are no siblings', () async {
    const reset = 'prds/features/f01_login/us01_reset_password/USER_STORY.md';
    final report = checkOf(
      await writeCheckProject(extra: {'docs/$reset': '# Reset\n'}),
    );
    expect(spots(report, FindingKind.orderNumberDuplicate), [
      '$loginStory:1: order_number_duplicate',
      '$reset:1: order_number_duplicate',
    ]);
    expect(
      report.findings
          .firstWhere((f) => f.kind == FindingKind.orderNumberDuplicate)
          .toJson()['siblings'],
      [reset],
    );
  });

  group('a feature path with a group folder before f{nn}', () {
    const groupedFeature = {
      '.specstone/templates/feature.yaml':
          'path: prds/features/{slug}/f{nn}_{slug}/FEATURE.md\n',
    };
    const audio = 'prds/features/control/f01_audio_player/FEATURE.md';
    const banner = 'prds/features/display/f01_banner/FEATURE.md';
    const video = 'prds/features/control/f01_video_player/FEATURE.md';

    test('an f01 in each of two groups is no order_number_duplicate', () async {
      final report = checkOf(
        await writeCheckProject(
          extra: {
            ...groupedFeature,
            'docs/$audio': '# Audio player\n',
            'docs/$banner': '# Banner\n',
          },
        ),
      );

      expect(spots(report, FindingKind.orderNumberDuplicate), isEmpty);
    });

    test('two f01 in one group are reported on each, siblings naming only the same-group doc', () async {
      final report = checkOf(
        await writeCheckProject(
          extra: {
            ...groupedFeature,
            'docs/$audio': '# Audio player\n',
            'docs/$banner': '# Banner\n',
            'docs/$video': '# Video player\n',
          },
        ),
      );

      expect(spots(report, FindingKind.orderNumberDuplicate), [
        '$audio:1: order_number_duplicate',
        '$video:1: order_number_duplicate',
      ]);
      expect(
        {
          for (final f in report.findings)
            if (f.kind == FindingKind.orderNumberDuplicate)
              f.path: f.toJson()['siblings'],
        },
        {
          audio: [video],
          video: [audio],
        },
      );
    });
  });

  test('f04/us01/s7, f04/us01/fr07/e03, f04/us04/fr01/e09, cc-s03/inv13: a requirement whose story is gone has no '
      'parent and no trace or suspect finding', () async {
    final report = checkOf(
      await writeCheckProject(without: {'docs/$loginStory'}),
    );
    expect(
      [
        for (final f in report.findings)
          if (f.path == loginFr) f.kind,
      ],
      [FindingKind.parentMissing],
    );
    expect(
      [
        for (final f in report.findings)
          if (f.path == loginNf) f.kind,
      ],
      [FindingKind.parentMissing],
    );
  });

  test('a spec doc whose feature does not exist is parent_missing', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          'docs/specs/f03_billing/API.md':
              '# Billing API\n\n## FR trace\n\n| FR | Operation |\n|---|---|\n\n'
              '## Operations\n\nNone.\n',
        },
      ),
    );
    expect(spots(report), ['specs/f03_billing/API.md:1: parent_missing']);
  });

  test('two features named login make their children parent_ambiguous, warning not printed', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          'docs/prds/features/f02_login/FEATURE.md':
              checkProjectFiles()['docs/$loginFeature']!,
        },
      ),
    );
    expect(spots(report, FindingKind.parentAmbiguous), [
      '$loginRecord:1: parent_ambiguous',
      '$loginStory:1: parent_ambiguous',
      '$loginApi:1: parent_ambiguous',
      '$loginArchitecture:1: parent_ambiguous',
    ]);
    expect(report.warnings, isEmpty);
  });

  test('a Latin-1 file is file_not_utf8, its warning not printed', () async {
    final project = await writeCheckProject();
    const reset = 'prds/features/f01_login/us02_reset/USER_STORY.md';
    File('${project.path}/docs/$reset')
      ..createSync(recursive: true)
      ..writeAsBytesSync(
        latin1.encode('---\nstatus: planned\n---\n\n# Reset at the café\n'),
      );
    final report = checkOf(project);
    expect(spots(report, FindingKind.fileNotUtf8), ['$reset:1: file_not_utf8']);
    expect(report.warnings, isEmpty);
  });

  test(
    'a doc whose mode refuses reading is file_unreadable',
    skip: unreadablePathSkipReason(),
    () async {
      final project = await writeCheckProject();
      final path = '${project.path}/docs/$loginNf';
      Process.runSync('chmod', ['000', path]);
      addTearDown(() => Process.runSync('chmod', ['644', path]));
      final report = checkOf(project);
      expect(spots(report, FindingKind.fileUnreadable), [
        '$loginNf:1: file_unreadable',
      ]);
      expect(
        report.findings
            .firstWhere((f) => f.kind == FindingKind.fileUnreadable)
            .name,
        isNull,
      );
      expect(report.warnings, isEmpty);
      final targeted = checkOf(project, target: 'login');
      expect(spots(targeted, FindingKind.fileUnreadable), [
        '$loginNf:1: file_unreadable',
      ]);
      expect(targeted.warnings, isEmpty);
    },
  );

  test(
    'a doc of an extending type with a cleared parent gets no parent_missing',
    () async {
      final report = checkOf(
        await writeCheckProject(
          extra: {
            '.specstone/templates/edge_api_root.yaml': 'id: edge_api_root\nextends: api\npath: specs/EDGE_API_ROOT.md\nparent:\n',
            'docs/specs/EDGE_API_ROOT.md': '# Edge API root\n',
          },
        ),
      );
      expect(spots(report, FindingKind.parentMissing), isEmpty);
      expect(spots(report, FindingKind.requiredSectionMissing), [
        'specs/EDGE_API_ROOT.md:1: required_section_missing',
        'specs/EDGE_API_ROOT.md:1: required_section_missing',
      ]);
    },
  );

  group('override lines and the parent gate', () {
    const malformedLine = '- Overrides: INV-3 — carts expire after 7 days';
    const ghostDomain = 'specs/f09_ghost/DOMAIN.md';
    const topic = 'specs/topics/rules.md';

    Future<CheckReport> run(Map<String, String> files) async => checkOf(
      await writeCheckProject(
        extra: files,
        unstamped: {for (final path in files.keys) path},
      ),
    );

    test(
      'a doc whose type names a parent but has none gets no suspect finding',
      () async {
        final report = await run({
          'docs/$ghostDomain': '# Domain\n\n## Invariants\n\n$malformedLine\n',
        });
        expect([
          for (final f in report.findings)
            if (f.path == ghostDomain) f.kind,
        ], contains(FindingKind.parentMissing));
        expect(spots(report, FindingKind.overrideLineMalformed), isEmpty);
        expect(spots(report, FindingKind.overrideNotInChain), isEmpty);
        expect(spots(report, FindingKind.suspect), isEmpty);
        expect(spots(report, FindingKind.unconfirmed), isEmpty);
      },
    );

    test('a topic with no parent still gets its override findings', () async {
      final report = await run({
        'docs/$topic':
            '---\ncovers:\n  - app/lib/\n---\n\n# Rules\n\n## Rules\n\n$malformedLine\n',
      });
      expect(spots(report, FindingKind.overrideLineMalformed), [
        '$topic:10: override_line_malformed',
      ]);
      expect(spots(report, FindingKind.parentMissing), isEmpty);
    });
  });

  test('a doc type with no parent is never parent_missing', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          '.specstone/templates/runbook.yaml': 'id: runbook\ndescription: Run steps.\npath: ops/{slug}/runbook.md\n',
          'docs/ops/deploy/runbook.md': '# Deploy\n',
        },
      ),
    );
    expect(spots(report, FindingKind.parentMissing), isEmpty);
  });

  test(
    'a merged set with no project doc type runs no vision quote rule',
    () async {
      final project = await fixtureProject({
        'docs/prds/d01_context.md':
            '# Context\n\n## Project vision\n### PV-01 — X\nNo quote line.\n',
      });
      final session = ReadSession.open(
        templates: TemplateResolver(shippedFiles: fixturePackFiles()),
        workingDirectory: project,
        homeDirectory: null,
      );
      addTearDown(session.close);
      expect(spots(runCheck(session), FindingKind.visionQuoteMissing), isEmpty);
    },
  );
  group('nested features', () {
    test('f04/us01/fr07/e11, sf-c11: cart with no shop FEATURE.md is parent_missing', () async {
      final report = checkOf(
        await writeNestedProject(without: {'docs/$shopFeature'}),
      );
      final found = spots(report, FindingKind.parentMissing);
      expect(
        found,
        containsAll([
          '$cartFeature:1: parent_missing',
          '$payFeature:1: parent_missing',
          '$shopDomain:1: parent_missing',
        ]),
      );
      expect(found, isNot(contains('$cartAdd:1: parent_missing')));
      expect(
        report.findings
            .singleWhere(
              (f) =>
                  f.path == cartFeature && f.kind == FindingKind.parentMissing,
            )
            .message,
        'no feature doc is the parent of shop/cart',
      );
    });

    test('nested siblings cart/pay and add_item/drop_item give no order_number_duplicate; a second f01_x beside cart gives one', () async {
      const kind = FindingKind.orderNumberDuplicate;
      expect(spots(checkOf(await writeNestedProject()), kind), isEmpty);
      const twin = 'prds/features/f02_shop/f01_x/FEATURE.md';
      final report = checkOf(
        await writeNestedProject(
          extra: {'docs/$twin': nestedFiles()['docs/$cartFeature']!},
        ),
      );
      expect(
        spots(report, kind),
        unorderedEquals([
          '$cartFeature:1: order_number_duplicate',
          '$twin:1: order_number_duplicate',
        ]),
      );
    });
  });

  test('a FEATURE.md past max_depth is nesting_over_limit, not untyped_doc, and a note in its folder reports no untyped_doc and no link finding', () async {
    const folder = 'prds/features/f02_shop/f01_cart/f01_a/f01_b/f01_c';
    final report = checkOf(
      await writeNestedProject(
        extra: {
          'docs/$folder/FEATURE.md': nestedFiles()['docs/$cartFeature']!,
          'docs/$folder/NOTES.md': '# Notes\n\nSee [x](../../nowhere.md).\n',
          'docs/prds/features/f02_shop/NOTES.md':
              '# Notes\n\nSee [x](../../nowhere.md).\n',
        },
      ),
    );
    expect(spots(report, FindingKind.nestingOverLimit), [
      '$folder/FEATURE.md:1: nesting_over_limit',
    ]);
    expect(
      spots(report).where((s) => s.contains('NOTES.md')),
      unorderedEquals([
        'prds/features/f02_shop/NOTES.md:1: untyped_doc',
        'prds/features/f02_shop/NOTES.md:3: link_unresolved',
      ]),
    );
  });

  test('the checked folders of the shipped set hold prds, specs, and '
      'measurements', () async {
    final project = await writeTree({
      '.specstone/config.yaml': shippedPinsConfig(),
    });
    final set = TemplateResolver(shippedFiles: shippedPackFiles)
        .resolve(workingDirectory: project, homeDirectory: null);
    expect(
      checkedFoldersOf(set),
      containsAll(['prds', 'specs', 'measurements']),
    );
  });

  test('a records path is one two-segment checked folder, and only docs below '
      'it lie in it', () async {
    final project = await writeTree({
      '.specstone/config.yaml': shippedPinsConfig(),
      ...recordsRootTemplates,
    });
    final set = TemplateResolver(shippedFiles: shippedPackFiles)
        .resolve(workingDirectory: project, homeDirectory: null);
    final folders = checkedFoldersOf(set);
    expect(folders, contains('.specstone/records'));
    expect(folders, isNot(contains('.specstone')));
    expect(
      isInCheckedFolder(folders, '.specstone/records/f01_x/IMPLEMENTATION.md'),
      isTrue,
    );
    expect(isInCheckedFolder(folders, '.specstone/notes/x.md'), isFalse);
    expect(isInCheckedFolder(folders, 'prds/FEATURES.md'), isTrue);
  });

  group('f04/us01/fr07 singular_doc_missing', () {
    test('f04/us01/fr07/e13: a goal doc type and no prds/GOAL.md is one '
        'finding at line 1 with the type key and no name', () async {
      final report = checkOf(
        await writeCheckProject(without: {'docs/$_goalDoc'}),
      );
      final missing = _missingOf(report);
      expect(spots(report, FindingKind.singularDocMissing), [
        '$_goalDoc:1: singular_doc_missing',
      ]);
      expect(missing.single.name, isNull);
      expect(missing.single.keys, {'type': 'goal'});
      expect(
        missing.single.message,
        'the project holds no goal doc; run `specstone new goal`',
      );
    });

    test('f04/us01/fr07/e14: no project doc is one finding at its path, '
        'type project', () async {
      final report = checkOf(
        await writeCheckProject(without: {'docs/$projectDoc'}),
      );
      expect(spots(report, FindingKind.singularDocMissing), [
        '$projectDoc:1: singular_doc_missing',
      ]);
      expect(_missingOf(report).single.keys, {'type': 'project'});
      expect(_missingOf(report).single.name, isNull);
    });

    test('f04/us01/fr07/e15: a project-layer type at prds/STYLE.md with no '
        'file is one finding', () async {
      final report = checkOf(
        await writeCheckProject(
          extra: {'.specstone/templates/style.yaml': _styleLayer},
        ),
      );
      expect(spots(report, FindingKind.singularDocMissing), [
        'prds/STYLE.md:1: singular_doc_missing',
      ]);
      expect(_missingOf(report).single.keys, {'type': 'style'});
      expect(_missingOf(report).single.name, isNull);
    });

    test('f04/us01/fr07/e15: a per_target type is one finding per target that '
        'lacks it, each with its target key', () async {
      final report = checkOf(
        await writeTwinProject(
          extra: {
            '.specstone/templates/style.yaml':
                '${_styleLayer}per_target: true\n',
            'docs/prds/flutter/STYLE.md': '# Terms\n',
          },
        ),
      );
      final missing = [
        for (final f in _missingOf(report))
          if (f.keys['type'] == 'style') f,
      ];
      expect([for (final f in missing) f.path], ['prds/jaspr/STYLE.md']);
      expect(missing.single.line, 1);
      expect(missing.single.name, isNull);
      expect(missing.single.keys, {'type': 'style', 'target': 'jaspr'});
    });

    test('f04/us01/fr07/e21: a project on the shipped pins with no glossary '
        'doc is one finding at its path, type glossary', () async {
      final report = checkOf(
        await writeCheckProject(without: {'docs/$_glossaryDoc'}),
      );
      expect(spots(report, FindingKind.singularDocMissing), [
        '$_glossaryDoc:1: singular_doc_missing',
      ]);
      expect(_missingOf(report).single.keys, {'type': 'glossary'});
      expect(_missingOf(report).single.name, isNull);
      expect(
        _missingOf(report).single.message,
        'the project holds no glossary doc; run `specstone new glossary`',
      );
    });

    test('ship_glossary_doc_type/e07: a project pinned below the pack that '
        'ships the glossary type holds no glossary finding', () async {
      final files = {...shippedPackFiles}..remove('prd-core/glossary.yaml');
      const pinned = '1.14.0';
      files['prd-core/pack.yaml'] = Uint8List.fromList(
        utf8.encode('name: prd-core\nversion: $pinned\n'),
      );
      final shipped = shippedPackVersions()['prd-core'];
      final project = await writeCheckProject(
        extra: {
          '.specstone/config.yaml': shippedPinsConfig().replaceFirst(
            'prd-core: $shipped',
            'prd-core: $pinned',
          ),
        },
        without: {'docs/$_glossaryDoc'},
      );
      final session = ReadSession.open(
        templates: TemplateResolver(shippedFiles: files),
        workingDirectory: project,
        homeDirectory: null,
      );
      addTearDown(session.close);

      expect([
        for (final type in session.index.set.docTypes) type.id,
      ], isNot(contains('glossary')));
      expect(
        _missingOf(runCheck(session)).map((f) => f.keys['type']),
        isNot(contains('glossary')),
      );
    });

    test('f04/us01/fr07/e16: one code target and no tech stack doc is one '
        'finding with no target key', () async {
      final report = checkOf(
        await writeCheckProject(without: {'docs/$techStack'}),
      );
      expect(spots(report, FindingKind.singularDocMissing), [
        '$techStack:1: singular_doc_missing',
      ]);
      expect(_missingOf(report).single.keys, {'type': 'tech_stack'});
      expect(_missingOf(report).single.name, isNull);
      expect(_missingOf(report).single.message, isNot(contains('--target')));
    });

    test('f04/us01/fr07/e17: flutter and jaspr with no jaspr tech stack is '
        'one finding for jaspr, its message ending --target jaspr', () async {
      final report = checkOf(
        await writeTwinProject(without: {'docs/specs/jaspr/TECH_STACK.md'}),
      );
      final missing = _missingOf(report);
      expect(spots(report, FindingKind.singularDocMissing), [
        'specs/jaspr/TECH_STACK.md:1: singular_doc_missing',
      ]);
      expect(missing.single.name, isNull);
      expect(missing.single.keys, {'type': 'tech_stack', 'target': 'jaspr'});
      expect(missing.single.message, startsWith(_missingMessage));
      expect(missing.single.message, endsWith(' --target jaspr'));
    });

    test('f04/us01/fr07/e18: a project spec doc type with no doc is no '
        'finding', () async {
      final report = checkOf(
        await writeCheckProject(without: {'docs/$loginArchitecture'}),
      );
      expect([
        for (final f in _missingOf(report)) f.keys['type'],
      ], isNot(contains('architecture')));
      expect(spots(report, FindingKind.singularDocMissing), isEmpty);
    });

    test('f04/us01/fr07/e19: a merged set with no goal doc type is no goal '
        'finding', () async {
      final project = await fixtureProject({});
      final session = ReadSession.open(
        templates: TemplateResolver(
          shippedFiles: fixturePackFiles(
            extra: {
              'project.yaml': 'id: project\ndescription: The project.\npath: prds/PROJECT.md\n',
            },
          ),
        ),
        workingDirectory: project,
        homeDirectory: null,
      );
      addTearDown(session.close);
      expect([
        for (final type in session.index.set.docTypes) type.id,
      ], isNot(contains('goal')));
      final report = runCheck(session);
      expect(_missingOf(report).map((f) => f.keys['type']), ['project']);
    });

    test(
      'one finding per target lacking TECH_STACK, in targets order',
      () async {
        final project = await writeTwinProject(
          without: {
            'docs/specs/flutter/TECH_STACK.md',
            'docs/specs/jaspr/TECH_STACK.md',
          },
          extra: {
            '.specstone/config.yaml': shippedPinsConfig() + _jasprFirstConfig,
          },
        );
        final session = openSession(project);
        addTearDown(session.close);
        final missing = [
          for (final f in missingSingularDocs(CheckContext(session)))
            if (f.keys['type'] == 'tech_stack') f,
        ];
        expect(
          [for (final f in missing) f.path],
          ['specs/jaspr/TECH_STACK.md', 'specs/flutter/TECH_STACK.md'],
        );
        expect([for (final f in missing) f.line], [1, 1]);
        expect(
          [for (final f in missing) f.keys],
          [
            {'type': 'tech_stack', 'target': 'jaspr'},
            {'type': 'tech_stack', 'target': 'flutter'},
          ],
        );
        expect(
          [for (final f in missing) f.message.split(' ').last],
          ['jaspr', 'flutter'],
        );
      },
    );

    test('an empty goal file is present', () async {
      final report = checkOf(
        await writeCheckProject(
          extra: {'docs/$_goalDoc': ''},
          unstamped: {'docs/$_goalDoc'},
        ),
      );
      expect(spots(report, FindingKind.singularDocMissing), isEmpty);
    });

    test('an empty glossary file is present', () async {
      final report = checkOf(
        await writeCheckProject(
          extra: {'docs/$_glossaryDoc': ''},
          unstamped: {'docs/$_glossaryDoc'},
        ),
      );
      expect(spots(report, FindingKind.singularDocMissing), isEmpty);
      expect(spots(report, FindingKind.fileNotUtf8), isEmpty);
      expect(spots(report, FindingKind.fileUnreadable), isEmpty);
    });
  });
}
