import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/document_writing/agent_file_walk.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';
import '../../helpers/posix_modes.dart';
import '../../helpers/target_fixture.dart';

const _fr = 'login/email_login/check_password';
const _featureDoc = 'prds/features/f01_login/FEATURE.md';

/// Returns `<path>:<line> <mention>` per `doc_cited_in_code` finding.
List<String> _cited(CheckReport report) => [
  for (final f in report.findings)
    if (f.kind == FindingKind.docCitedInCode)
      '${f.path}:${f.line} ${f.keys['mention']}',
];

/// A tech stack doc that lists no code root.
Map<String, String> get _noCodeRoots => {
  'docs/$techStack':
      '# Tech stack\n\n## Stack\n\n| Slot | Choice |\n'
      '|---|---|\n| Language | Dart |\n\n## Naming\n\n'
      '- snake_case file names\n',
};

void main() {
  group('docNamesInCode', () {
    test('a comment line naming a doc gives one finding at its line', () async {
      final report = checkOf(
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
      final report = checkOf(
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
      final report = checkOf(
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
      final report = checkOf(
        await writeCheckProject(
          extra: {'app/lib/auth.dart': '// `$_fr#statement`\n'},
        ),
      );
      expect(_cited(report), ['app/lib/auth.dart:1 $_fr#statement']);
    });

    test('text that resolves to no doc gives nothing', () async {
      final report = checkOf(
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
      final report = checkOf(
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
      'a bare one-slug span reads as a name only when a doc carries it',
      () async {
        final report = checkOf(
          await writeCheckProject(
            extra: {'app/lib/auth.dart': '// `user_id` and `login`.\n'},
          ),
        );
        expect(_cited(report), ['app/lib/auth.dart:1 login']);
      },
    );

    test('an agent file under a code root is never read', () async {
      final report = checkOf(
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
      'a test file is read under a code root and unread outside it',
      () async {
        final report = checkOf(
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
      final report = checkOf(project);
      expect(_cited(report), ['README.md:1 $_fr', 'app/lib/auth.dart:1 $_fr']);
    });

    test('a run with a doc target reports no code mention', () async {
      final project = await writeCheckProject(
        extra: {'app/lib/auth.dart': '// `$_fr`\n'},
      );
      expect(_cited(checkOf(project)), isNotEmpty);
      expect(_cited(checkOf(project, target: 'login')), isEmpty);
      expect(_cited(checkOf(project, docPath: _featureDoc)), isEmpty);
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
        CheckReport run({String? codeTarget}) {
          final session = openSession(project);
          try {
            return runCheck(session, codeTarget: codeTarget);
          } finally {
            session.close();
          }
        }

        expect(_cited(run()), [
          'flutter_ws/app/lib/a.dart:1 $_fr',
          'jaspr_ws/app/lib/b.dart:1 $_fr',
        ]);
        expect(_cited(run(codeTarget: 'jaspr')), [
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
      final report = checkOf(project);
      expect(_cited(report), ['app/lib/auth.dart:1 $_fr']);
      expect(report.warnings, [
        'app/lib/bad.dart: not UTF-8; doc names in it are not checked',
      ]);
    });

    test(
      'a file that cannot be read gives a warning and no stop',
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
        final report = checkOf(project);
        expect(_cited(report), ['app/lib/auth.dart:1 $_fr']);
        const warning =
            'app/lib/locked.dart: cannot read the file; '
            'doc names in it are not checked';
        expect(report.warnings, [warning]);
      },
    );

    test('a file of an extension with no comment mark is not read', () async {
      final project = await writeCheckProject(
        extra: {'app/lib/data.bin': '// `$_fr`\n'},
      );
      File('${project.path}/app/lib/image.png')
          .writeAsBytesSync([0x89, 0x50, 0xFF, 0xFE]);
      final report = checkOf(project);
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
      expect(isAgentFile('sub/.github/copilot-instructions.md'), isTrue);
      for (final folder in ['.claude', '.agents', '.codex', '.cursor']) {
        expect(isAgentFile('$folder/rules/a.md'), isTrue, reason: folder);
        expect(isAgentFile('sub/$folder/x.json'), isTrue, reason: folder);
      }
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
