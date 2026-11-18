import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/code_link_rules.dart';
import 'package:specstone_core/src/consistency_check/code_mention_rules.dart';
import 'package:specstone_core/src/consistency_check/code_rules.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/implements_rule.dart';
import 'package:specstone_core/src/document_writing/agent_file_walk.dart';
import 'package:specstone_core/src/document_writing/reference_links.dart';
import 'package:specstone_core/src/rendering/skill_references.dart';
import 'package:test/test.dart';

import '../../helpers/agent_skills.dart' show skillDocText;
import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';
import '../../helpers/posix_modes.dart';
import '../../helpers/skill_doc_fixture.dart' show skillPinsConfig;
import '../../helpers/target_fixture.dart';

const _fr = 'login/email_login/check_password';
const _featureDoc = 'prds/features/f01_login/FEATURE.md';

/// Returns `<path>:<line> <mention>` per `doc_cited_in_code` finding.
List<String> _cited(CheckReport report) => [
  for (final f in report.findings)
    if (f.kind == FindingKind.docCitedInCode)
      '${f.path}:${f.line} ${f.keys['mention']}',
];

const _seededReference =
    'skills/review/references/specs/design_system/TOKENS.md';

/// The files of a skill doc with [output], its skill file and reference file
/// each naming a doc, beside two skills' files that are not its references.
Map<String, String> _skillFiles(String output) => {
  '.specstone/config.yaml': skillPinsConfig(),
  ...doc(techStack, '  - app/lib/\n', '  - app/lib/\n  - skills/\n'),
  'docs/specs/skills/review.md': skillDocText(output: output),
  'skills/review/SKILL.md': 'Use `feature:login`.\n',
  _seededReference: 'Use `feature:login`.\n',
  'skills/review-x/references/NOTES.md': 'Use `feature:login`.\n',
  'skills/other/references/NOTES.md': 'Use `feature:login`.\n',
};

/// A tech stack doc that lists no code root.
Map<String, String> get _noCodeRoots => {
  'docs/$techStack':
      '# Tech stack\n\n## Stack\n\n| Slot | Choice |\n'
      '|---|---|\n| Language | Dart |\n\n## Naming\n\n'
      '- snake_case file names\n',
};

void main() {
  group('docNamesInCode', () {
    test(
      'reads a file the Symbol rule read before it from that read',
      skip: unreadablePathSkipReason(),
      () async {
        final project = await writeCheckProject();
        final session = openSession(project);
        addTearDown(session.close);
        final context = CheckContext(session);
        checkImplements(context, session.index.at(loginRecord)!).toList();
        final path = '${project.path}/app/lib/login.dart';
        Process.runSync('chmod', ['000', path]);
        addTearDown(() => Process.runSync('chmod', ['644', path]));

        docNamesInCode(
          context,
          ImplementedWork(context, context.targets),
        ).toList();

        expect(context.unstatedWarnings, isEmpty);
        expect(context.codeFilesRead, 1);
      },
    );

    test('a file an implements entry, a code link, and the scan all read is '
        'read once', () async {
      final project = await writeCheckProject();
      final session = openSession(project);
      addTearDown(session.close);
      final context = CheckContext(session);
      final work = ImplementedWork(context, context.targets);
      final record = session.index.at(loginRecord)!;

      checkImplements(context, record).toList();
      File('${project.path}/app/lib/login.dart')
          .writeAsStringSync('class SignInPage {}\n// Implements `$_fr`.\n');
      final linkFindings = checkCodeLinks(context, work, record).toList();
      final mentions = docNamesInCode(context, work).toList();

      expect(linkFindings, isEmpty);
      expect(mentions, isEmpty);
      expect(context.unstatedWarnings, isEmpty);
      expect(context.codeFilesRead, 1);
    });

    test('a comment line naming a doc gives one finding at its line', () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: {'app/lib/auth.dart': 'class A {}\n// Implements `$_fr`.\n'},
        ),
      );
      expect(_cited(report), ['app/lib/auth.dart:2 $_fr']);
      final finding = report.findings.singleWhere(
        (f) => f.kind == FindingKind.docCitedInCode,
      );
      expect(
        finding.message,
        '$_fr names a doc; the doc names the code, never the reverse',
      );
      expect(finding.waitsFor, WaitsFor.agent);
      expect(finding.toJson()['docPath'], 'app/lib/auth.dart');
      expect(finding.toJson().containsKey('name'), isFalse);
    });

    test('a path read from the docs root or the project root names a doc, '
        'one read from the own folder names none', () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: {
            'app/lib/auth.dart':
                '// See $_featureDoc for more.\n'
                '// See `docs/$_featureDoc`.\n'
                '// See ../../docs/$_featureDoc.\n'
                '// See FEATURE.md.\n',
          },
        ),
      );
      expect(_cited(report), [
        'app/lib/auth.dart:1 $_featureDoc',
        'app/lib/auth.dart:2 docs/$_featureDoc',
      ]);
    });

    test('a markdown file reads its code spans outside fenced code, not its '
        'frontmatter', () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: {
            'app/lib/SKILL.md':
                '---\ndescription: `feature:login`\n---\n\n'
                'Use `feature:login` first.\n\n'
                '```\n`feature:login`\n```\n',
          },
        ),
      );
      expect(_cited(report), ['app/lib/SKILL.md:5 feature:login']);
    });

    test('a mention with a section key is reported whole', () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: {'app/lib/auth.dart': '// `$_fr#statement`\n'},
        ),
      );
      expect(_cited(report), ['app/lib/auth.dart:1 $_fr#statement']);
    });

    test('text that resolves to no doc gives nothing', () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: {
            'app/lib/auth.dart':
                '// Layout `specs/<FeaturePath>/API.md`, item E21,\n'
                '// label `f<nn>/us<nn>/fr<nn>`, name `nope/missing`.\n',
          },
        ),
      );
      expect(_cited(report), isEmpty);
    });

    test('a name inside a string literal is no comment line', () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: {
            'app/lib/auth_test.dart':
                "void main() { test('$_fr: refuses', () {}); }\n"
                "final s = '`$_fr`';\n",
          },
        ),
      );
      expect(_cited(report), isEmpty);
    });

    test(
      'a lone-word span raises nothing, whether a doc has that name or not',
      () async {
        final report = await checkOf(
          await writeCheckProject(
            extra: {
              'app/lib/auth.dart':
                  '// `user_id`, `login`, `login#problem`.\n'
                  '// `feature:login`\n',
            },
          ),
        );
        expect(_cited(report), ['app/lib/auth.dart:2 feature:login']);
      },
    );

    test("a singular type's layout path in a comment or a skill file raises "
        'nothing', () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: {
            'app/lib/auth.dart':
                '// see $goalDoc\n'
                '// see $_featureDoc\n',
            'app/lib/SKILL.md': 'Read `docs/$goalDoc`.\n',
          },
        ),
      );
      expect(_cited(report), ['app/lib/auth.dart:2 $_featureDoc']);
    });

    test(
      "a project spec type's layout path in a skill file raises nothing",
      () async {
        final report = await checkOf(
          await writeCheckProject(
            extra: {
              'docs/specs/DOMAIN.md': '# Project domain\n',
              'app/lib/SKILL.md': 'Read `specs/DOMAIN.md`.\n',
            },
          ),
        );
        expect(_cited(report), isEmpty);
      },
    );

    for (final output in [
      'skills/review/',
      './skills/review/',
      'skills/../skills/review/',
    ]) {
      test('a skill reference file is not read, its skill file is, '
          'with output $output', () async {
        final report = await checkOf(
          await writeCheckProject(extra: _skillFiles(output)),
        );
        expect(_cited(report), [
          'skills/other/references/NOTES.md:1 feature:login',
          'skills/review-x/references/NOTES.md:1 feature:login',
          'skills/review/SKILL.md:1 feature:login',
        ]);
      });
    }

    test('a reference file the writer wrote gives no finding', () async {
      final project = await writeCheckProject(
        extra: {
          ..._skillFiles('skills/review/')..remove(_seededReference),
          'docs/$_featureDoc':
              '---\nsummary: Lets an agent sign in.\nvision:\n  - PV-01\n'
              'goals:\n  - PG-01\n---\n\n# Login\n\n'
              '## Problem\n\nUsers forget passwords.\n\n'
              '## Benefit hypothesis\n\nFewer resets.\n\n'
              '## Success measures\n\nResets per week.\n\n'
              '## Current alternatives\n\nEmail links.\n\n'
              '## Feature flow\n\nSign in with `feature:login`.\n\n'
              '## Out-of-scope\n\n- Social sign-in — not planned\n',
          'docs/specs/skills/review.md': skillDocText(
            output: 'skills/review/',
            sources: ['[Login](../../prds/features/f01_login/FEATURE.md)'],
          ),
        },
      );
      final session = openSession(project);
      final plan = SkillReferences.plan(
        session.project,
        session.project.resolveTarget(
          null,
          workingDirectory: project,
          defaultsToDocsRoot: true,
          includeRecordsRoot: true,
        ),
        rewriteLinks: rewriteReferenceLinks,
      );
      session.close();
      final written = [
        for (final skill in plan.skills.whereType<ExportedSkill>())
          for (final file in skill.files) file,
      ];
      for (final file in written) {
        file.file.parent.createSync(recursive: true);
        file.file.writeAsBytesSync(file.bytes);
      }

      expect(
        written.map((file) => file.text),
        contains(contains('`feature:login`')),
      );
      expect(
        _cited(await checkOf(project)),
        isNot(contains(startsWith('skills/review/references/'))),
      );
    });

    test('an agent file under a code root is never read', () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: {
            'app/lib/CLAUDE.md': 'Use `$_fr`.\n',
            'app/lib/AGENTS.md': 'Use `$_fr`.\n',
            'app/lib/GEMINI.md': 'Use `$_fr`.\n',
            'app/lib/other.md': 'Use `$_fr`.\n',
          },
        ),
      );
      expect(_cited(report), ['app/lib/other.md:1 $_fr']);
    });

    test(
      'a copilot file below the project root is read, the root one is not',
      () async {
        final report = await checkOf(
          await writeCheckProject(
            extra: {
              ...doc(
                techStack,
                '  - app/lib/\n',
                '  - app/lib/\n  - app/lib/pkg/.github/\n  - .github/\n',
              ),
              'app/lib/pkg/.github/copilot-instructions.md': 'Use `$_fr`.\n',
              '.github/copilot-instructions.md': 'Use `$_fr`.\n',
            },
          ),
        );
        expect(_cited(report), [
          'app/lib/pkg/.github/copilot-instructions.md:1 $_fr',
        ]);
      },
    );

    test(
      'a test file is read under a code root and unread outside it',
      () async {
        final report = await checkOf(
          await writeCheckProject(
            extra: {
              'app/lib/auth_test.dart': '// `$_fr`\n',
              'test/auth_test.dart': '// `$_fr`\n',
            },
          ),
        );
        expect(_cited(report), ['app/lib/auth_test.dart:1 $_fr']);
      },
    );

    test('a target with no code root entry reads its code root but the docs '
        'root, hidden folders, and nested checkouts', () async {
      final project = await writeCheckProject(
        extra: {
          ..._noCodeRoots,
          'app/lib/auth.dart': '// `$_fr`\n',
          'README.md': 'Use `$_fr`.\n',
          '.specstone/note.md': 'Use `$_fr`.\n',
          'vendor/pkg/lib/x.dart': '// `$_fr`\n',
          'vendor/pkg/.git/HEAD': 'ref\n',
        },
      );
      final report = await checkOf(project);
      expect(_cited(report), ['README.md:1 $_fr', 'app/lib/auth.dart:1 $_fr']);
    });

    test('a doc under the docs root that names a doc gives no finding when '
        'the code list is empty', () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: {
            ..._noCodeRoots,
            'README.md': 'Use `$_fr`.\n',
            'docs/notes/README.md': 'Use `$_fr`.\n',
            'docs/specs/notes.md': '// `$_featureDoc`\n',
          },
        ),
      );
      expect(_cited(report), ['README.md:1 $_fr']);
    });

    test("a per-target type's layout path in a comment or a skill file raises "
        'nothing with two targets', () async {
      const flutterStack = 'specs/flutter/TECH_STACK.md';
      const jasprStack = 'specs/jaspr/TECH_STACK.md';
      final report = await checkOf(
        await writeTwinProject(
          extra: {
            'flutter_ws/app/lib/auth.dart':
                '// see $flutterStack\n'
                '// see $_featureDoc\n',
            'jaspr_ws/app/lib/auth.dart': '// see `docs/$jasprStack`\n',
            'flutter_ws/app/lib/SKILL.md':
                'Read `$flutterStack` and `$jasprStack`.\n',
          },
        ),
      );
      expect(_cited(report), ['flutter_ws/app/lib/auth.dart:2 $_featureDoc']);
    });

    test('a run with a doc target reports no code mention', () async {
      final project = await writeCheckProject(
        extra: {'app/lib/auth.dart': '// `$_fr`\n'},
      );
      expect(_cited(await checkOf(project)), isNotEmpty);
      expect(_cited(await checkOf(project, target: 'login')), isEmpty);
      expect(_cited(await checkOf(project, docPath: _featureDoc)), isEmpty);
    });

    test(
      'each target reads its own code, and a target option keeps one',
      () async {
        final project = await writeTwinProject(
          extra: {
            'flutter_ws/app/lib/a.dart': '// `$_fr`\n',
            'jaspr_ws/app/lib/b.dart': '// `$_fr`\n',
          },
        );
        Future<CheckReport> run({String? codeTarget}) async {
          final session = openSession(project);
          try {
            return await runCheck(session, codeTarget: codeTarget);
          } finally {
            session.close();
          }
        }

        expect(_cited(await run()), [
          'flutter_ws/app/lib/a.dart:1 $_fr',
          'jaspr_ws/app/lib/b.dart:1 $_fr',
        ]);
        expect(_cited(await run(codeTarget: 'jaspr')), [
          'jaspr_ws/app/lib/b.dart:1 $_fr',
        ]);
      },
    );

    test('a file that is not UTF-8 gives a warning and no stop', () async {
      final project = await writeCheckProject(
        extra: {'app/lib/auth.dart': '// `$_fr`\n'},
      );
      File('${project.path}/app/lib/bad.dart')
          .writeAsBytesSync([0x2F, 0x2F, 0x20, 0xFF, 0xFE, 0x0A]);
      final report = await checkOf(project);
      expect(_cited(report), ['app/lib/auth.dart:1 $_fr']);
      expect(report.warnings, [
        'app/lib/bad.dart: not UTF-8; doc names in it are not checked',
      ]);
    });

    test(
      'a file that only covers reaches and cannot be read gives a warning and '
      'no stop',
      skip: unreadablePathSkipReason(),
      () async {
        final project = await writeCheckProject(
          extra: {
            'app/lib/auth.dart': '// `$_fr`\n',
            'app/lib/locked.dart': '// `$_fr`\n',
          },
        );
        final path = '${project.path}/app/lib/locked.dart';
        Process.runSync('chmod', ['000', path]);
        addTearDown(() => Process.runSync('chmod', ['644', path]));
        final report = await checkOf(project);
        expect(_cited(report), ['app/lib/auth.dart:1 $_fr']);
        expect(report.warnings, [
          'app/lib/locked.dart: cannot read the file; the code links that reach it are not checked',
          'app/lib/locked.dart: cannot read the file; doc names in it are not checked',
        ]);
      },
    );

    test('a file of an extension with no comment mark is not read', () async {
      final project = await writeCheckProject(
        extra: {'app/lib/data.bin': '// `$_fr`\n'},
      );
      File('${project.path}/app/lib/image.png')
          .writeAsBytesSync([0x89, 0x50, 0xFF, 0xFE]);
      final report = await checkOf(project);
      expect(_cited(report), isEmpty);
      expect(report.warnings, isEmpty);
    });
  });

  group('isAgentFile', () {
    test('a file named for an agent is one at any depth', () {
      for (final name in ['CLAUDE.md', 'AGENTS.md', 'GEMINI.md']) {
        expect(isAgentFile(name), isTrue, reason: name);
        expect(isAgentFile('packages/app/$name'), isTrue, reason: name);
      }
    });

    test('the copilot instructions file and any file under an agent folder '
        'are agent files', () {
      expect(isAgentFile('.github/copilot-instructions.md'), isTrue);
      for (final folder in ['.claude', '.agents', '.codex', '.cursor']) {
        expect(isAgentFile('$folder/rules/a.md'), isTrue, reason: folder);
        expect(isAgentFile('sub/$folder/x.json'), isTrue, reason: folder);
      }
    });

    test('the copilot file is an agent file at the project root only', () {
      expect(isAgentFile('sub/.github/copilot-instructions.md'), isFalse);
    });

    test('other files are not', () {
      expect(isAgentFile('lib/claude.md'), isFalse);
      expect(isAgentFile('lib/CLAUDE.md.bak'), isFalse);
      expect(isAgentFile('.github/workflows/ci.yml'), isFalse);
      expect(isAgentFile('claude/rules/a.md'), isFalse);
      expect(isAgentFile('README.md'), isFalse);
    });
  });
}
