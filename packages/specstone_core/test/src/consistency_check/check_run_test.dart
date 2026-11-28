// The test names and expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/check_scope.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/document_writing/delete_doc.dart';
import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/bundle_file.dart';
import 'package:specstone_core/src/index_query/bundle_render.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/templates/code_target.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/cold_node.dart';
import '../../helpers/grouped_fixture.dart';
import '../../helpers/index_fixture.dart';
import '../../helpers/nested_fixture.dart';
import '../../helpers/no_generators.dart';
import '../../helpers/posix_modes.dart';
import '../../helpers/prd_core.dart';
import '../../helpers/shipped_pins.dart' show shippedPinsConfig;
import '../../helpers/target_fixture.dart';
import '../../helpers/temp_tree.dart' show writeTree;
import '../../helpers/write_fixture.dart' show writeIn;

/// Letters that put a story or doc over the bound by a margin of 2,000 est.
/// tokens (characters / 4).
const int _overBound = (readRangeTokenLimit + 2000) * 4;

const _brokenRecord = '.specstone/records/f01_login/IMPLEMENTATION.md';

/// Returns the files that plant a code path to nothing in the login record.
Map<String, String> _brokenRecordFiles() => {
  _brokenRecord:
      "---\nstatuses:\n  - 'email_login/check_password:implemented'\n"
      "  - 'email_login:planned'\n"
      "  - 'email_login/copy:planned'\n"
      "implements:\n  - 'email_login/check_password:app/lib/gone.dart:X'\n"
      '---\n\n# Record\n',
};

void main() {
  useColdHostNode();

  test('the fixture project has zero findings', () async {
    final report = await checkOf(await writeCheckProject());
    expect(report.findings, isEmpty);
    expect(report.exitStatus, 0);
  });

  test('a feature-only grouped project types every child doc '
      'and finds its feature', () async {
    final report = await checkOf(await writeFeatureGroupedProject());

    expect(spots(report, FindingKind.parentMissing), isEmpty);
    expect(spots(report, FindingKind.untypedDoc), isEmpty);
  });

  test('two rules stating the same warning text print it once, in the order '
      'of first appearance', () async {
    final session = openSession(await writeCheckProject());
    addTearDown(session.close);
    final context = CheckContext(session)
      ..warn('b: first')
      ..warn('a: second')
      ..warn('b: first');

    expect(context.unstatedWarnings, ['b: first', 'a: second']);
  });

  test('check login keeps the feature and the docs under it', () async {
    final project = await writeCheckProject(
      extra: {
        'docs/$loginFr': checkProjectFiles()['docs/$loginFr']!.replaceFirst(
          'verify_method: test\n',
          '',
        ),
        'docs/prds/features/f02_signup/FEATURE.md':
            '---\nsummary: Lets a visitor sign up.\n---\n\n# Sign up\n',
        'docs/prds/features/f02_signup/us01_create/fr01_store.md':
            '---\ntraced_from:\n  - S1\n---\n\n# Store\n',
      },
    );
    const missing = FindingKind.requiredFieldMissing;
    expect(spots(await checkOf(project), missing), [
      '$loginFr:1: required_field_missing',
      'prds/features/f02_signup/us01_create/fr01_store.md:1: required_field_missing',
    ]);
    expect(spots(await checkOf(project, target: 'login'), missing), [
      '$loginFr:1: required_field_missing',
    ]);
  });

  const orphanFr = 'prds/features/f01_login/us03_export/fr01_send_file.md';
  const siblingOrphanFr = 'prds/features/f02_signup/us01_create/fr01_store.md';
  const orphanText = '---\ntraced_from:\n  - S9\n---\n\n# Send file\n';

  test('an orphan FR under the target feature folder is '
      'parent_missing and runs no trace rule; one under another feature stays out', () async {
    final project = await writeCheckProject(
      extra: {
        'docs/$orphanFr': orphanText,
        'docs/$siblingOrphanFr': orphanText,
      },
    );
    expect(spots(await checkOf(project), FindingKind.parentMissing), [
      '$orphanFr:1: parent_missing',
      '$siblingOrphanFr:1: parent_missing',
    ]);
    final targeted = await checkOf(project, target: 'login');
    expect(spots(targeted, FindingKind.parentMissing), [
      '$orphanFr:1: parent_missing',
    ]);
    expect(spots(targeted, FindingKind.scenarioTraceUnresolved), isEmpty);
  });

  test('an untyped file and a file that is not UTF-8 under the target folder get their own findings', () async {
    const untyped = 'prds/features/f01_login/notes.md';
    const latin = 'prds/features/f01_login/us02_reset/USER_STORY.md';
    const outside = 'prds/features/f02_signup/notes.md';
    final project = await writeCheckProject(
      extra: {'docs/$untyped': '# Notes\n', 'docs/$outside': '# Notes\n'},
    );
    File('${project.path}/docs/$latin')
      ..createSync(recursive: true)
      ..writeAsBytesSync(
        latin1.encode('---\nstatus: planned\n---\n\n# Café\n'),
      );
    final report = await checkOf(project, target: 'login');
    expect(spots(report, FindingKind.untypedDoc), ['$untyped:1: untyped_doc']);
    expect(spots(report, FindingKind.fileNotUtf8), ['$latin:1: file_not_utf8']);
    expect(report.warnings, isEmpty);
  });

  test(
    'an unreadable file under the target folder is file_unreadable; '
    'an fr target adds no folder, so the warning stays',
    skip: unreadablePathSkipReason(),
    () async {
      final project = await writeCheckProject();
      final path = '${project.path}/docs/$loginNf';
      Process.runSync('chmod', ['000', path]);
      addTearDown(() => Process.runSync('chmod', ['644', path]));
      final whole = await checkOf(project);
      expect(spots(whole, FindingKind.fileUnreadable), [
        '$loginNf:1: file_unreadable',
      ]);
      expect(
        whole.findings
            .firstWhere((f) => f.kind == FindingKind.fileUnreadable)
            .name,
        isNull,
      );
      expect(whole.warnings, isEmpty);
      final targeted = await checkOf(project, target: 'login');
      expect(spots(targeted, FindingKind.fileUnreadable), [
        '$loginNf:1: file_unreadable',
      ]);
      expect(targeted.warnings, isEmpty);
      final fr = await checkOf(
        project,
        target: 'fr:login/email_login/check_password',
      );
      expect(spots(fr, FindingKind.fileUnreadable), isEmpty);
      expect(fr.warnings, ['$loginNf: cannot be read; skipped']);
    },
  );

  test(
    'an fr target adds no folder; a sibling file and a sibling FR stay out',
    () async {
      const notes = 'prds/features/f01_login/us01_email_login/notes.md';
      const sibling = 'prds/features/f01_login/us01_email_login/fr02_other.md';
      final project = await writeCheckProject(
        extra: {
          'docs/$notes': '# Notes\n',
          'docs/$sibling': checkProjectFiles()['docs/$loginFr']!.replaceFirst(
            'verify_method: test\n',
            '',
          ),
        },
      );
      final report = await checkOf(
        project,
        target: 'fr:login/email_login/check_password',
      );
      expect(spots(report), isNot(contains('$notes:1: untyped_doc')));
      expect(spots(report, FindingKind.requiredFieldMissing), isEmpty);
      expect(
        spots(
          await checkOf(project, target: 'login'),
          FindingKind.requiredFieldMissing,
        ),
        ['$sibling:1: required_field_missing'],
      );
    },
  );

  test(
    'a spec doc target reports its own file, not the spec doc beside it',
    () async {
      final project = await writeCheckProject(
        extra: {
          ...doc(
            loginApi,
            'Signs the Agent in.',
            'Signs the Agent in. See [x](../../../../nowhere.md).',
          ),
          ...doc(
            loginArchitecture,
            'One box.',
            'One box. See [y](../../../../nowhere.md).',
          ),
        },
      );
      const missing = FindingKind.linkTargetMissing;
      expect(
        spots(await checkOf(project, target: 'architecture:login'), missing),
        ['$loginArchitecture:9: link_target_missing'],
      );
      expect(spots(await checkOf(project, target: 'api:login'), missing), [
        '$loginApi:19: link_target_missing',
      ]);
    },
  );

  test(
    'a feature target reports the feature folder and its spec folder',
    () async {
      final project = await writeCheckProject(
        extra: {
          ...doc(
            loginApi,
            'Signs the Agent in.',
            'Signs the Agent in. See [x](../../../../nowhere.md).',
          ),
          'docs/specs/f02_signup/API.md':
              '# Sign up API\n\nSee [z](../../../../nowhere.md).\n',
          'docs/prds/features/f01_login/notes.md': '# Notes\n',
          'docs/prds/features/f02_signup/notes.md': '# Notes\n',
        },
      );
      final report = await checkOf(project, target: 'feature:login');
      expect(spots(report, FindingKind.linkTargetMissing), [
        '$loginApi:19: link_target_missing',
      ]);
      expect(spots(report, FindingKind.untypedDoc), [
        'prds/features/f01_login/notes.md:1: untyped_doc',
      ]);
    },
  );

  test('a typed name checks that doc only', () async {
    final project = await writeCheckProject(
      extra: {
        'docs/$loginStory': checkProjectFiles()['docs/$loginStory']!
            .replaceFirst('---\n\n', 'priority: high\n---\n\n'),
        'docs/$loginFr': checkProjectFiles()['docs/$loginFr']!.replaceFirst(
          'verify_method: test\n',
          'priority: high\nverify_method: test\n',
        ),
      },
    );
    expect(
      spots(await checkOf(project), FindingKind.fieldUndeclared),
      hasLength(2),
    );
    expect(
      spots(
        await checkOf(project, target: 'fr:login/email_login/check_password'),
        FindingKind.fieldUndeclared,
      ),
      ['$loginFr:5: field_undeclared'],
    );
  });

  test('a name no doc carries, or an unknown doc type, is a fault', () async {
    final project = await writeCheckProject();
    await expectLater(
      () => checkOf(project, target: 'login/emial_login'),
      throwsA(
        isA<IndexFault>().having(
          (f) => f.code,
          'code',
          IndexFaultCode.docNotFound,
        ),
      ),
    );
    await expectLater(
      () => checkOf(project, target: 'nope:login'),
      throwsA(
        isA<TemplateFault>().having(
          (f) => f.code,
          'code',
          FaultCode.docTypeUnknown,
        ),
      ),
    );
  });

  test('a check writes no file of its own, a run that parses diagrams with Node included', () async {
    const parsing = 'sequenceDiagram\n  A->>B: ok';
    const refused = 'sequenceDiagram\n  A->>B: ok\n  A->>B: x;y';
    final project = await writeCheckProject(
      extra: {
        'docs/$loginArchitecture':
            '---\ncovers:\n  - app/lib/\n---\n\n# Login architecture\n\n'
            '## Technical diagram\n\n```mermaid\n$parsing\n```\n\n'
            '```mermaid\n$refused\n```\n\n## Components\n\n'
            '| Component | Responsibility |\n|---|---|\n| Sign-in page | Takes the form |\n',
      },
      unstamped: {'docs/$loginArchitecture'},
    );
    int refusedBlocks(CheckReport report) => report.findings
        .where((f) => f.kind == FindingKind.diagramParseFailed)
        .length;
    // The ignore file the Index makes beside its database.
    final indexIgnore = File.fromUri(
      project.uri.resolve('.specstone/.gitignore'),
    ).path;
    Map<String, String> snapshot() => {
      for (final f in project.listSync(recursive: true).whereType<File>())
        if (!f.path.contains('index.sqlite') && f.path != indexIgnore)
          f.path: base64.encode(f.readAsBytesSync()),
    };
    // No Index yet, so no stored parse row: the run below parses with Node.
    final index = File.fromUri(project.uri.resolve(indexFilePath));
    expect(index.existsSync(), isFalse);
    final before = snapshot();
    final report = await checkOf(project);
    // A skipped Node parse also counts 0 refused blocks; this names its reason.
    expect(
      report.warnings,
      everyElement(isNot(startsWith('Mermaid parse skipped: '))),
    );
    expect(refusedBlocks(report), 1);
    expect(index.existsSync(), isTrue);
    expect(snapshot(), before);
  });

  test('the fixture edit helper names an anchor that does not occur', () {
    expect(
      () => fr('no such anchor', 'x'),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.toString(),
          'message',
          contains('no such anchor'),
        ),
      ),
    );
  });

  test("a doc check gives that doc's findings only", () async {
    final project = await writeCheckProject(
      extra: {
        ..._brokenRecordFiles(),
        ...edit(loginStory, [
          (
            'I reach my work',
            'I reach my work, see [gone](gone/USER_STORY.md)',
          ),
        ]),
      },
    );
    final story = await checkOf(project, docPath: loginStory);
    expect(story.findings, isNotEmpty);
    expect(story.findings.map((f) => f.path).toSet(), {loginStory});
    expect(
      story.findings.map((f) => f.kind),
      contains(FindingKind.linkUnresolved),
    );
    final requirement = await checkOf(project, docPath: _brokenRecord);
    expect(requirement.findings, isNotEmpty);
    expect(requirement.findings.where((f) => f.path == loginStory), isEmpty);
  });

  test('a feature doc check leaves out the docs under it', () async {
    final project = await writeCheckProject(extra: _brokenRecordFiles());
    expect(
      (await checkOf(
        project,
        target: 'feature:login',
      )).findings.map((f) => f.path),
      contains(_brokenRecord),
    );
    expect(
      (await checkOf(
        project,
        docPath: loginFeature,
      )).findings.map((f) => f.path),
      isNot(contains(_brokenRecord)),
    );
  });

  group('a feature whose design read-first file is over the bound', () {
    const signupFeature = 'prds/features/f02_signup/FEATURE.md';
    Map<String, String> oversize() => {
      ...edit(loginFeature, [
        ('## Problem\n\n', '## Problem\n\n${'a' * _overBound}\n\n'),
      ]),
      'docs/$signupFeature': '# Sign up\n\n## Problem\n\n${'a' * _overBound}\n',
    };

    test(
      "check <target> reports each feature in the target's unit, once",
      () async {
        final project = await writeCheckProject(extra: oversize());

        expect(spots(await checkOf(project), FindingKind.bundleOverLimit), [
          '$loginFeature:1: bundle_over_limit',
          '$signupFeature:1: bundle_over_limit',
        ]);
        expect(
          spots(
            await checkOf(project, target: 'feature:login'),
            FindingKind.bundleOverLimit,
          ),
          ['$loginFeature:1: bundle_over_limit'],
        );
      },
    );

    test(
      'a docPath scope on the feature or on a story reports that feature alone',
      () async {
        final project = await writeCheckProject(extra: oversize());

        for (final docPath in [loginFeature, loginStory]) {
          expect(
            spots(
              await checkOf(project, docPath: docPath),
              FindingKind.bundleOverLimit,
            ),
            ['$loginFeature:1: bundle_over_limit'],
            reason: docPath,
          );
        }
      },
    );

    test('a docPath scope on an FR, and a story target, report none', () async {
      final project = await writeCheckProject(extra: oversize());

      expect(
        spots(
          await checkOf(project, docPath: loginFr),
          FindingKind.bundleOverLimit,
        ),
        isEmpty,
      );
      expect(
        spots(
          await checkOf(project, target: 'login/email_login'),
          FindingKind.bundleOverLimit,
        ),
        isEmpty,
      );
    });

    test(
      'two features sharing a name are each reported on their own',
      () async {
        const twin = 'prds/features/f03_login/FEATURE.md';
        final project = await writeCheckProject(
          extra: {
            ...oversize(),
            'docs/$twin':
                '# Login again\n\n## Problem\n\n${'a' * _overBound}\n',
          },
        );

        final found = (await checkOf(project)).findings
            .where((f) => f.kind == FindingKind.bundleOverLimit);

        expect(
          [for (final f in found) f.path],
          [loginFeature, signupFeature, twin],
        );
        final session = openSession(project);
        addTearDown(session.close);
        final index = session.index;
        for (final f in found.where((f) => f.path != signupFeature)) {
          expect(
            f.keys['actual'],
            readFirstTokensOf(
              index,
              pickBundle(
                index,
                [f.path],
                BundleMode.design,
                noProject: false,
                summary: index.childrenOf(index.at(f.path)!).isNotEmpty,
              ),
            ),
            reason: f.path,
          );
        }
      },
    );
  });

  test('an untyped .md file in prds/ gets its untyped_doc finding', () async {
    final project = await writeCheckProject(
      extra: {'docs/prds/notes.md': '# Notes\n'},
    );
    expect(
      spots(
        await checkOf(project, docPath: 'prds/notes.md'),
        FindingKind.untypedDoc,
      ),
      ['prds/notes.md:1: untyped_doc'],
    );
  });

  test(
    'a doc beside an over-limit feature takes no link_outside_docs',
    () async {
      const folder = 'prds/features/f02_shop/f01_cart/f01_a/f01_b/f01_c';
      final report = await checkOf(
        await writeNestedProject(
          extra: {
            'docs/$folder/FEATURE.md': nestedFiles()['docs/$cartFeature']!,
            'docs/$folder/NOTES.md': '# Notes\n\nSee [x](../../../../../../../superpowers/design.md).\n',
            'docs/prds/features/f02_shop/NOTES.md':
                '# Notes\n\nSee [x](../../../superpowers/design.md).\n',
          },
        ),
      );
      expect(spots(report, FindingKind.linkOutsideDocs), [
        'prds/features/f02_shop/NOTES.md:3: link_outside_docs',
      ]);
    },
  );

  test(
    'runCheck with both a target and a docPath throws ArgumentError',
    () async {
      final project = await writeCheckProject();
      await expectLater(
        () => checkOf(project, target: 'login', docPath: loginStory),
        throwsArgumentError,
      );
    },
  );

  test(
    'checking a sub-feature scopes to its subtree and its spec folder',
    () async {
      final project = await writeNestedProject(
        extra: {
          'docs/$cartAddFr': '# Check the stock\n',
          'docs/$payCard': '# Agent pays by card\n',
          'docs/$cartDomain': '# Cart domain\n',
          'docs/$shopDomain': '# Shop domain\n',
        },
      );
      final paths = {
        for (final f in (await checkOf(
          project,
          target: 'feature:shop/cart',
        )).findings)
          f.path,
      };
      expect(paths, isNotEmpty);
      expect(
        paths.where(
          (p) =>
              !p.startsWith('prds/features/f02_shop/f01_cart/') &&
              !p.startsWith('specs/f02_shop/f01_cart/'),
        ),
        isEmpty,
      );
    },
  );
  test(
    'a project doc still holding Domain glossary '
    'and no glossary doc is section_undeclared and singular_doc_missing',
    () async {
      final project = await writeCheckProject(
        extra: edit(projectDoc, [
          (
            '- Billing — not planned\n',
            '- Billing — not planned\n\n## Domain glossary\n\n'
                '- **Agent** — the coding agent that writes the docs.\n',
          ),
        ]),
        without: {'docs/prds/GLOSSARY.md'},
      );
      final report = await checkOf(project);

      expect(
        [
          for (final f in report.findings)
            if (f.kind == FindingKind.sectionUndeclared ||
                f.kind == FindingKind.singularDocMissing)
              '${f.path}: ${f.kind.wire}',
        ],
        [
          'prds/GLOSSARY.md: singular_doc_missing',
          '$projectDoc: section_undeclared',
        ],
      );
      expect(report.findings, hasLength(2));
      final undeclared = report.findings.firstWhere(
        (f) => f.kind == FindingKind.sectionUndeclared,
      );
      final headerLine = File('${project.path}/docs/$projectDoc')
          .readAsLinesSync()
          .indexOf('## Domain glossary');
      expect(undeclared.line, headerLine + 1);
      expect(undeclared.toJson()['header'], 'Domain glossary');
    },
  );

  test('layer_doc_type_dropped is held by a run with no target, not by a doc, name, or --target run', () async {
    final project = await writeTwinProject(
      extra: {
        '.specstone/config.yaml':
            '${shippedPinsConfig()}  acme: 1.2.0\ntargets:\n'
            '  flutter:\n    code_root: flutter_ws\n'
            '  jaspr:\n    code_root: jaspr_ws\n',
        '.specstone/templates/x.yaml': 'description: X.\n',
      },
    );
    final home = await writeTree({
      '.specstone/packs/acme/pack.yaml':
          'name: acme\nversion: 1.2.0\nextends: software-tech\n'
          'migrations:\n  - from: 1.0.0\n    steps:\n'
          '      - merge_doc: {from: {id: x, path: specs/X.md}, to: fr, '
          'sections: [{from: {id: moves, header: Moves}, to: statement}]}\n',
    });
    Future<List<String>> run({
      String? target,
      String? docPath,
      String? codeTarget,
    }) async {
      final session = ReadSession.open(
        templates: TemplateResolver(),
        workingDirectory: project,
        homeDirectory: home,
      );
      addTearDown(session.close);
      final report = await runCheck(
        session,
        target: target,
        docPath: docPath,
        codeTarget: codeTarget,
      );
      return spots(report, FindingKind.layerDocTypeDropped);
    }

    expect(await run(), [
      '.specstone/templates/x.yaml:1: layer_doc_type_dropped',
    ]);
    expect(await run(docPath: loginFr), isEmpty);
    expect(await run(target: 'login'), isEmpty);
    expect(await run(target: 'login', codeTarget: 'jaspr'), isEmpty);
    expect(await run(codeTarget: 'jaspr'), isEmpty);
  });

  test(
    'a doc check holds no singular_doc_missing and no agent_block_stale',
    () async {
      final project = await writeCheckProject(
        without: {'docs/$projectDoc'},
        extra: {'.specstone/AGENT.md': 'hand edit\n'},
      );
      final whole = await checkOf(project);
      expect(spots(whole, FindingKind.singularDocMissing), [
        '$projectDoc:1: singular_doc_missing',
      ]);
      expect(spots(whole, FindingKind.agentBlockStale), [
        '.specstone/AGENT.md:1: agent_block_stale',
      ]);

      final doc = await checkOf(project, docPath: loginStory);

      expect(spots(doc, FindingKind.singularDocMissing), isEmpty);
      expect(spots(doc, FindingKind.agentBlockStale), isEmpty);

      final targeted = await checkOf(project, target: 'login');

      expect(spots(targeted, FindingKind.singularDocMissing), isEmpty);
      expect(spots(targeted, FindingKind.agentBlockStale), isEmpty);
    },
  );

  test('a targeted run holds no doc_cited_in_code finding', () async {
    final project = await writeCheckProject(
      extra: {
        ...doc(loginRecord, '  - app/lib/\n', '  - app/lib/login.dart\n'),
        'app/lib/extra.dart': 'class Extra {}\n// Implements `login/email_login/check_password`.\n',
      },
    );
    final whole = await checkOf(project);
    expect(spots(whole, FindingKind.docCitedInCode), isNotEmpty);

    final targeted = await checkOf(project, target: 'login');

    expect(spots(targeted, FindingKind.docCitedInCode), isEmpty);
  });

  test(
    'an fr target keeps a trace finding that reads its parent story',
    () async {
      final project = await writeCheckProject(
        extra: fr('traced_from:\n  - S2\n', 'traced_from:\n  - S9\n'),
      );
      final whole = spots(
        await checkOf(project),
        FindingKind.scenarioTraceUnresolved,
      );
      expect(whole, isNotEmpty);

      final targeted = await checkOf(
        project,
        target: 'fr:login/email_login/check_password',
      );

      expect(spots(targeted, FindingKind.scenarioTraceUnresolved), whole);
      expect(whole.single, startsWith('$loginFr:'));
    },
  );

  test('an untyped DocPath target reports the broken links of the doc beside '
      'its untyped finding', () async {
    const notes = 'prds/features/f01_login/notes.md';
    const sibling = 'prds/features/f01_login/other.md';
    final project = await writeCheckProject(
      extra: {
        'docs/$notes': '# Notes\n\nSee [x](../nowhere.md).\n',
        'docs/$sibling': '# Other\n\nSee [y](../nowhere.md).\n',
      },
    );

    final report = await checkOf(project, target: notes);

    expect(spots(report), [
      '$notes:1: untyped_doc',
      '$notes:3: link_unresolved',
    ]);
  });

  test('a user_story target reports the story, its FRs, and its nfs, and no '
      'file of the sibling story', () async {
    const sibling = 'prds/features/f01_login/us02_reset/notes.md';
    final project = await writeCheckProject(
      extra: {
        ...edit(loginStory, [
          (
            'I reach my work',
            'I reach my work, see [gone](gone/USER_STORY.md)',
          ),
        ]),
        ...fr('verify_method: test\n', ''),
        ...edit(loginNf, [('verify_method: test\n', '')]),
        'docs/$sibling': '# Notes\n',
      },
    );

    final report = await checkOf(
      project,
      target: 'user_story:login/email_login',
    );

    expect(
      {for (final f in report.findings) f.path},
      {loginStory, loginFr, loginNf},
    );
    expect(
      spots(await checkOf(project, target: 'login')),
      contains('$sibling:1: untyped_doc'),
    );
  });

  test('check of an untyped file whose name holds a hash reports that one '
      'file', () async {
    const draft = 'prds/notes#draft.md';
    const other = 'prds/notes.md';
    final project = await writeCheckProject(
      extra: {'docs/$draft': '# Draft\n', 'docs/$other': '# Other\n'},
    );

    final report = await checkOf(project, target: draft);

    expect(spots(report), ['$draft:1: untyped_doc']);
  });

  test(
    'a check target scopes to the files the delete of that target removes',
    () async {
      const notes = [
        'prds/notes.md',
        'prds/features/f01_login/notes.md',
        'prds/features/f01_login/us01_email_login/notes.md',
        'prds/features/f01_login/us02_reset/notes.md',
        'specs/f01_login/notes.md',
      ];
      // The feature map's catalog links the feature, which a delete refuses.
      final project = await writeCheckProject(
        without: {'docs/prds/FEATURES.md'},
        extra: {for (final path in notes) 'docs/$path': '# Notes\n'},
      );

      for (final target in [
        'feature:login',
        'user_story:login/email_login',
        'architecture:login',
        'fr:login/email_login/check_password',
        'prds/features/f01_login/notes.md',
      ]) {
        final removed = writeIn(
          project,
          (s) =>
              answerDeleteDryRun(s, [
                    target,
                  ], generators: noGenerators).json['files']!
                  as List<Object?>,
        );
        final checked = [
          for (final f in (await checkOf(project, target: target)).findings)
            if (f.kind == FindingKind.untypedDoc) f.path,
        ];

        expect(checked, [
          for (final path in notes)
            if (removed.contains(path)) path,
        ], reason: target);
      }
      expect([
        for (final f in (await checkOf(
          project,
          target: 'feature:login',
        )).findings)
          if (f.kind == FindingKind.untypedDoc) f.path,
      ], notes.sublist(1));
    },
  );

  test('a check with no target runs every rule over every doc and lists no '
      'repeat', () async {
    const copy = 'prds/features/f01_login/us01_email_login/fr02_copy.md';
    final project = await writeCheckProject(
      without: {'docs/prds/GLOSSARY.md'},
      extra: {
        ..._brokenRecordFiles(),
        ...fr('verify_method: test\n', ''),
        ...doc(
          loginApi,
          'Signs the Agent in.',
          'Signs the Agent in. See [x](../../../../nowhere.md).',
        ),
        _brokenRecord: _brokenRecordFiles()[_brokenRecord]!.replaceFirst(
          '---\n\n',
          'covers:\n  - app/lib/login.dart\n---\n\n',
        ),
        'docs/$copy': checkProjectFiles()['docs/$loginFr']!,
        'docs/prds/features/f01_login/notes.md': '# Notes\n',
        'app/lib/extra.dart': 'class Extra {}\n// Implements `login/email_login/check_password`.\n',
        '.specstone/AGENT.md': 'hand edit\n',
      },
    );

    final report = await checkOf(project);

    expect(spots(report), [
      '.specstone/AGENT.md:1: agent_block_stale',
      '$_brokenRecord:8: implements_path_unresolved',
      'app/lib/extra.dart:2: doc_cited_in_code',
      // The broken record changes the status the feature map's catalog shows.
      'prds/FEATURES.md:9: generated_block_stale',
      'prds/GLOSSARY.md:1: singular_doc_missing',
      'prds/features/f01_login/notes.md:1: untyped_doc',
      '$loginFr:1: required_field_missing',
      '$loginApi:19: link_target_missing',
    ]);
    final session = openSession(project);
    addTearDown(session.close);
    final repeated = runRepeats(session).groups.single;
    expect([for (final item in repeated.items) item.docPath], [loginFr, copy]);
  });

  test('an agent file finding sorts by path with the doc findings', () async {
    final project = await writeCheckProject(
      extra: {'.specstone/AGENT.md': 'hand edit\n'},
    );
    final paths = [for (final f in (await checkOf(project)).findings) f.path];

    expect(paths, contains('.specstone/AGENT.md'));
    expect(paths, [...paths]..sort());
  });

  test('an owner '
      'finding counts, sorts, and exits 1 beside an agent finding', () async {
    final project = await writeCheckProject(
      extra: {
        '.specstone/AGENT.md': 'hand edit\n',
        'docs/prds/d01_context.md': '# Context\n',
      },
    );
    final report = await checkOf(project);

    expect(
      {for (final f in report.findings) f.kind: f.waitsFor},
      {
        FindingKind.agentBlockStale: WaitsFor.owner,
        FindingKind.untypedDoc: WaitsFor.agent,
      },
    );
    expect(report.exitStatus, 1);
    expect(report.json['count'], 2);
    expect(report.text, contains('2 findings\n'));
    expect(
      report.text
          .split('\n')
          .where((l) => l.endsWith(' (waits for the Owner)')),
      hasLength(1),
    );
  });

  test('the run '
      'reports an open TBR of each typed doc in scope, counted and exit 1, '
      'and none outside the target', () async {
    const open = 'TBR \u2014 2 s';
    final project = await writeCheckProject(
      extra: {
        ...fr(checkPasswordStatement, '$checkPasswordStatement $open'),
        'docs/prds/features/f02_signup/FEATURE.md': '# Sign up\n',
      },
    );
    final whole = await checkOf(project);
    final tbr = [
      for (final f in whole.findings)
        if (f.kind == FindingKind.tbrOpen) f,
    ];

    expect(tbr, hasLength(1));
    expect(tbr.single.path, loginFr);
    expect(tbr.single.waitsFor, WaitsFor.owner);
    expect(whole.exitStatus, 1);
    expect(
      whole.text,
      contains('${tbr.single.textLine} (waits for the Owner)\n'),
    );
    expect(
      spots(await checkOf(project, target: 'login'), FindingKind.tbrOpen),
      ['$loginFr:${tbr.single.line}: tbr_open'],
    );
    expect(
      spots(
        await checkOf(project, target: 'feature:signup'),
        FindingKind.tbrOpen,
      ),
      isEmpty,
    );
  });

  test('a fresh init PROJECT name section gives template_text_left and no code_line pattern_missing', () async {
    final template = sectionOf(
      prdCoreDocType(await resolvePrdCore(), 'project'),
      'name',
    ).template!;
    final project = await writeCheckProject(
      extra: doc(
        projectDoc,
        'Login demo\n\n- **Code:** `login_demo`',
        template,
      ),
    );
    final report = await checkOf(project);
    final own = [
      for (final f in report.findings)
        if (f.path == projectDoc) '${f.kind.wire} ${f.toJson()['section']}',
    ];

    expect(own, ['template_text_left name']);
  });

  test('a required pattern reads the line by its in key: text blanks the code spans, code reads each span, all reads the line as written', () async {
    const spanned = 'The system shall refuse a wrong password `within 1 s`.';
    Future<List<String>> missing(String? scope, String pattern) async {
      final layer =
          'sections:\n  - id: statement\n    lint:\n      required_patterns:\n'
          "        - id: spanned\n          pattern: '$pattern'\n          message: Write it\n"
          '${scope == null ? '' : '          in: $scope\n'}';
      final report = await checkOf(
        await writeCheckProject(
          extra: {
            '.specstone/templates/fr.yaml': layer,
            ...fr(checkPasswordStatement, spanned),
          },
        ),
      );
      return [
        for (final f in report.findings)
          if (f.kind == FindingKind.patternMissing) '${f.toJson()['pattern']}',
      ];
    }

    expect(await missing(null, 'within 1 s'), ['spanned']);
    expect(await missing('text', 'within 1 s'), ['spanned']);
    expect(await missing('text', 'shall refuse'), isEmpty);
    expect(await missing('code', 'within 1 s'), isEmpty);
    expect(await missing('code', 'shall refuse'), ['spanned']);
    expect(await missing('all', 'within 1 s'), isEmpty);
    expect(await missing('all', 'password `within'), isEmpty);
  });

  test('a per_subsection required pattern reads by its in key, so only all matches text inside a code span', () async {
    Future<List<String>> missing(String scope, String body) async {
      final layer =
          'sections:\n  - id: edge_cases\n    lint:\n      required_patterns:\n'
          "        - id: spanned\n          pattern: 'Label: set'\n          message: Write Label\n          per_subsection: true\n"
          '          in: $scope\n';
      final report = await checkOf(
        await writeCheckProject(
          extra: {
            '.specstone/templates/fr.yaml': layer,
            ...fr('1. E01 — An empty password → refused.', body),
          },
        ),
      );
      return [
        for (final f in report.findings)
          if (f.kind == FindingKind.patternMissing)
            '${f.toJson()['subsection']}',
      ];
    }

    const spanned = '### First\n\n`Label: set`\n\n### Second\n\n`Label: set`';
    expect(await missing('text', spanned), ['First', 'Second']);
    expect(await missing('all', spanned), isEmpty);
    expect(
      await missing('all', '### First\n\n`Label: set`\n\n### Second\n\nnone'),
      ['Second'],
    );
  });

  group('code targets', () {
    const flutter = CodeTarget('flutter', codeRoot: 'flutter_ws');
    const jaspr = CodeTarget('jaspr', codeRoot: 'jaspr_ws');
    const flutterArch = flutterArchitecture;
    const jasprArch = jasprArchitecture;

    Future<CheckReport> runTwin(
      Directory project, {
      String? target,
      String? codeTarget,
    }) async {
      final session = openSession(project);
      addTearDown(session.close);
      return await runCheck(session, target: target, codeTarget: codeTarget);
    }

    Set<String> pathsOf(CheckReport report) => {
      for (final finding in report.findings) finding.path,
    };

    test('the two-target fixture reads each doc once: only the planted links are findings', () async {
      final report = await runTwin(await writeTwinProject());
      expect(pathsOf(report), {loginFeature, loginApi, flutterArch, jasprArch});
      expect(spots(report).length, 4, reason: spots(report).join('\n'));
    });

    // `login` names the feature and each twin; `feature:login` names the
    // feature alone, so the spec folders come from its unit.
    for (final name in ['login', 'feature:login']) {
      test(
        'check $name with two targets reports the feature folder and each target spec folder',
        () async {
          final project = await writeTwinProject();
          expect(pathsOf(await runTwin(project, target: name)), {
            loginFeature,
            loginApi,
            flutterArch,
            jasprArch,
          });
        },
      );

      test(
        'check $name --target jaspr keeps the PRD files, the shared docs, and that target spec folder',
        () async {
          final project = await writeTwinProject();
          expect(
            pathsOf(await runTwin(project, target: name, codeTarget: 'jaspr')),
            {loginFeature, loginApi, jasprArch},
          );
          expect(
            pathsOf(
              await runTwin(project, target: name, codeTarget: 'flutter'),
            ),
            {loginFeature, loginApi, flutterArch},
          );
        },
      );
    }

    test('check with no target reports every target, each finding at the DocPath of its target', () async {
      final project = await writeTwinProject(
        extra: {'.specstone/AGENT.md': 'hand edit\n'},
      );
      final report = await runTwin(project);
      expect(pathsOf(report), containsAll([flutterArch, jasprArch]));
      expect(spots(report, FindingKind.agentBlockStale), [
        '.specstone/AGENT.md:1: agent_block_stale',
      ]);
    });

    test('check --target jaspr keeps the shared docs and jaspr, the project-level findings too', () async {
      final project = await writeTwinProject(
        extra: {'.specstone/AGENT.md': 'hand edit\n'},
      );
      final report = await runTwin(project, codeTarget: 'jaspr');
      expect(pathsOf(report), containsAll([loginFeature, loginApi, jasprArch]));
      expect(pathsOf(report), isNot(contains(flutterArch)));
      expect(spots(report, FindingKind.agentBlockStale), [
        '.specstone/AGENT.md:1: agent_block_stale',
      ]);
    });

    test('a --target name targets: lacks is argument_invalid naming the targets, alone or beside a doc target', () async {
      final project = await writeTwinProject();
      for (final target in [null, 'login']) {
        await expectLater(
          () => runTwin(project, target: target, codeTarget: 'web'),
          throwsA(
            isA<IndexFault>()
                .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
                .having(
                  (f) => f.message,
                  'message',
                  '--target web: the code targets are flutter, jaspr',
                ),
          ),
          reason: 'target: $target',
        );
      }
    });

    test('an empty --target is argument_missing naming the targets', () async {
      final project = await writeTwinProject();
      await expectLater(
        () => runTwin(project, codeTarget: ''),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.argumentMissing)
              .having(
                (f) => f.message,
                'message',
                '--target needs a code target name: the code targets are flutter, jaspr',
              ),
        ),
      );
    });

    test('an untyped file under another target spec folder stays out of --target, and in without it', () async {
      const notes = 'specs/flutter/f01_login/notes.md';
      final project = await writeTwinProject(
        extra: {'docs/$notes': '# Notes\n'},
      );
      expect(pathsOf(await runTwin(project)), contains(notes));
      expect(
        pathsOf(await runTwin(project, codeTarget: 'jaspr')),
        isNot(contains(notes)),
      );
      expect(
        pathsOf(await runTwin(project, codeTarget: 'flutter')),
        contains(notes),
      );
    });

    test('a --target name on a project with one unnamed target is argument_invalid', () async {
      final project = await writeCheckProject();
      await expectLater(
        () => runTwin(project, codeTarget: 'web'),
        throwsA(
          isA<IndexFault>().having(
            (f) => f.message,
            'message',
            '--target web: this project names no code target',
          ),
        ),
      );
    });

    test('a missing singular doc of one target stays under --target for that '
        'target and drops under the other', () async {
      final project = await writeTwinProject(
        without: {'docs/specs/jaspr/TECH_STACK.md'},
      );
      const kind = FindingKind.singularDocMissing;
      const missing = 'specs/jaspr/TECH_STACK.md:1: singular_doc_missing';

      expect(spots(await runTwin(project), kind), [missing]);
      expect(spots(await runTwin(project, codeTarget: 'jaspr'), kind), [
        missing,
      ]);
      expect(
        spots(await runTwin(project, codeTarget: 'flutter'), kind),
        isEmpty,
      );
    });

    test('each rule that reads one target code or records runs once per '
        'target', () async {
      const flutterRecord =
          '.specstone/records/flutter/f01_login/IMPLEMENTATION.md';
      const jasprRecord =
          '.specstone/records/jaspr/f01_login/IMPLEMENTATION.md';
      String record(String target) =>
          "---\nstatuses:\n  - 'email_login/check_password:implemented'\n"
          "implements:\n  - 'email_login/check_password:app/lib/gone.dart:X'\n"
          '---\n\n# $target record\n';
      final project = await writeTwinProject(
        extra: {
          flutterRecord: record('F'),
          jasprRecord: record('J'),
          'flutter_ws/app/lib/auth.dart':
              'class A {}\n// Implements `login/email_login/check_password`.\n',
          'jaspr_ws/app/lib/auth.dart':
              'class A {}\n// Implements `login/email_login/check_password`.\n',
        },
      );

      final report = await runTwin(project);

      expect(spots(report, FindingKind.implementsPathUnresolved), [
        '$flutterRecord:5: implements_path_unresolved',
        '$jasprRecord:5: implements_path_unresolved',
      ]);
      expect(spots(report, FindingKind.docCitedInCode), [
        'flutter_ws/app/lib/auth.dart:2: doc_cited_in_code',
        'jaspr_ws/app/lib/auth.dart:2: doc_cited_in_code',
      ]);
    });

    test('CheckScope.targets holds every target, or the one named', () async {
      final session = openSession(await writeTwinProject());
      addTearDown(session.close);
      final context = CheckContext(session);
      expect(CheckScope.project(context).targets, [flutter, jaspr]);
      expect(CheckScope.project(context, codeTarget: 'jaspr').targets, [jaspr]);
      expect(CheckScope.of(context, 'login').targets, [flutter, jaspr]);
      expect(CheckScope.of(context, 'login', codeTarget: 'flutter').targets, [
        flutter,
      ]);
      expect(CheckScope.doc(context, loginFr).targets, [flutter, jaspr]);
      final plain = openSession(await writeCheckProject());
      addTearDown(plain.close);
      expect(CheckScope.project(CheckContext(plain)).targets, [
        const CodeTarget(null, codeRoot: '.'),
      ]);
    });

    test(
      'the context reads each target code root and code text apart',
      () async {
        final session = openSession(await writeTwinProject());
        addTearDown(session.close);
        final context = CheckContext(session);
        expect(context.codeRootOf(flutter).path, endsWith('flutter_ws'));
        expect(context.codeRootOf(jaspr).path, endsWith('jaspr_ws'));
        expect(
          context.codeTextOf(flutter, 'app/lib/login.dart'),
          contains('FlutterSignIn'),
        );
        expect(
          context.codeTextOf(jaspr, 'app/lib/login.dart'),
          contains('JasprSignIn'),
        );
        expect(context.codeFilesRead, 2);
        expect(context.codeTextOf(jaspr, 'app/lib/gone.dart'), isNull);
        const warning =
            'jaspr: app/lib/gone.dart: cannot read the file; '
            'implements Symbols in it are not checked';
        expect(context.unstatedWarnings, [warning]);
      },
    );
  });
}
