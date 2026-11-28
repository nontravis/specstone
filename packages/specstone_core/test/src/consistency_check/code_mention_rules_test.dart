@Tags(['integration'])
library;

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
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';
import '../../helpers/posix_modes.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/skill_doc_fixture.dart'
    show skillDocFile, skillPinsConfig;
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

/// The files of a skill doc covering `skills/review/`, its skill file and
/// reference file each naming a doc, beside two skills' files that are not its
/// references.
Map<String, String> _skillFiles() => {
  '.specstone/config.yaml': skillPinsConfig(),
  ...doc(techStack, '  - app/lib/\n', '  - app/lib/\n  - skills/\n'),
  ...skillDocFile(['skills/review/']),
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

/// A config that lists [prefix] as a number label prefix.
String _prefixConfig(String prefix) =>
    '${shippedPinsConfig()}number_label_prefixes: [$prefix]\n';

/// Sets the mtime of each code file of [project] an hour back, so none lies in
/// the racy window and the cache stores it.
void _ageCodeFiles(Directory project) {
  final then = DateTime.now().subtract(const Duration(hours: 1));
  final prefix = '${project.path}/';
  for (final file in project.listSync(recursive: true).whereType<File>()) {
    final path = file.path.substring(prefix.length);
    if (path.startsWith('docs/') || path.startsWith('.specstone/')) continue;
    file.setLastModifiedSync(then);
  }
}

void main() {
  group('docNamesInCode', () {
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
      expect(finding.toJson()['path'], 'app/lib/auth.dart');
      expect(finding.toJson().containsKey('name'), isFalse);
    });

    // D14
    test(
      'a comment naming a doc in an ignored file gives no finding',
      () async {
        final report = await checkOf(
          await writeCheckProject(
            extra: {
              '.gitignore': 'app/lib/gen/\n*.g.dart\n',
              'app/lib/gen/a.dart': '// Implements `$_fr`.\n',
              'app/lib/b.g.dart': '// Implements `$_fr`.\n',
              'app/lib/auth.dart': '// Implements `$_fr`.\n',
            },
          ),
        );
        expect(_cited(report), ['app/lib/auth.dart:1 $_fr']);
      },
    );

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

    test(
      'a markdown file in a skill folder is read like any code file',
      () async {
        final report = await checkOf(
          await writeCheckProject(extra: _skillFiles()),
        );
        expect(_cited(report), [
          'skills/other/references/NOTES.md:1 feature:login',
          'skills/review-x/references/NOTES.md:1 feature:login',
          'skills/review/SKILL.md:1 feature:login',
          'skills/review/references/specs/design_system/TOKENS.md:1 feature:login',
        ]);
      },
    );

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

    test('with nested code roots a file is read for the target of the longest '
        'root only', () async {
      String techListing(String code) => checkProjectFiles()['docs/$techStack']!
          .replaceFirst('  - app/lib/\n', code);
      final report = await checkOf(
        await writeTwinProject(
          extra: {
            '.specstone/config.yaml':
                '${shippedPinsConfig()}targets:\n'
                '  flutter:\n    code_root: ws\n'
                '  jaspr:\n    code_root: ws/web\n',
            'docs/specs/flutter/TECH_STACK.md': techListing(
              '  - lib/\n  - web/\n',
            ),
            'docs/specs/jaspr/TECH_STACK.md': techListing('  - lib/\n'),
            'ws/lib/a.dart': '// `$_fr`\n',
            'ws/web/lib/b.dart': '// `$_fr`\n',
          },
          without: {
            'flutter_ws/app/lib/login.dart',
            'jaspr_ws/app/lib/login.dart',
          },
        ),
      );
      expect(_cited(report), [
        'ws/lib/a.dart:1 $_fr',
        'ws/web/lib/b.dart:1 $_fr',
      ]);
    });

    test(
      'a folder that cannot be listed gives a warning and no stop',
      skip: unreadablePathSkipReason(),
      () async {
        final project = await writeCheckProject(
          extra: {
            'app/lib/auth.dart': '// `$_fr`\n',
            'app/lib/sealed/a.dart': '// `$_fr`\n',
          },
        );
        final path = '${project.path}/app/lib/sealed';
        Process.runSync('chmod', ['000', path]);
        addTearDown(() => Process.runSync('chmod', ['755', path]));
        final report = await checkOf(project);
        expect(_cited(report), ['app/lib/auth.dart:1 $_fr']);
        expect(
          report.warnings,
          contains(
            'app/lib/sealed: cannot list the folder; files under it are not '
            'checked for doc names',
          ),
        );
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

    // D8
    test('a comment line holding a number label gives doc_cited_in_code at '
        'its line', () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: {
            '.specstone/config.yaml': _prefixConfig('NFR-'),
            'app/lib/a.dart': '// see FR-03\n// see NFR-01\n',
          },
        ),
      );
      expect(_cited(report), [
        'app/lib/a.dart:1 FR-03',
        'app/lib/a.dart:2 NFR-01',
      ]);
    });

    // D8
    test('a number label in a string literal, an end-of-line comment, a '
        'markdown code span, or an unlisted prefix gives nothing', () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: {
            '.specstone/config.yaml': _prefixConfig('NFR-'),
            'app/lib/a.dart':
                "const cite = '// see FR-03';\n"
                'final n = 1; // see FR-04\n'
                '// see QA-01\n',
            'app/lib/notes.md': 'See `FR-05` and `NFR-02`.\n',
          },
        ),
      );
      expect(_cited(report), isEmpty);
    });

    // D8
    test('a cached file is read again once its stored label takes a listed '
        'prefix', () async {
      final project = await writeCheckProject(
        extra: {
          '.specstone/config.yaml': _prefixConfig('NFR-'),
          'app/lib/a.dart': '// see QA-01\n',
        },
      );
      _ageCodeFiles(project);
      expect(_cited(await checkOf(project)), isEmpty);

      File('${project.path}/.specstone/config.yaml')
          .writeAsStringSync(_prefixConfig('QA-'));

      expect(_cited(await checkOf(project)), ['app/lib/a.dart:1 QA-01']);
    });

    // D8
    test('a markdown code file with frontmatter gives a number label in its '
        'prose at its exact file line', () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: {'app/lib/guide.md': '---\ntitle: Guide\n---\n\nSee FR-03.\n'},
        ),
      );
      expect(_cited(report), ['app/lib/guide.md:5 FR-03']);
    });

    // D8
    test('a number label in a fenced block, a mermaid block included, gives '
        'nothing', () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: {
            'app/lib/README.md':
                '```mermaid\nflowchart LR\n  A[FR-01 login]\n```\n\n'
                '```text\nFR-02\n```\n',
          },
        ),
      );
      expect(_cited(report), isEmpty);
    });

    // D8
    test('a cached file holding a built-in number label gives its finding on '
        'the first and the second run', () async {
      final project = await writeCheckProject(
        extra: {'app/lib/a.dart': '// see FR-03\n'},
      );
      _ageCodeFiles(project);
      expect(_cited(await checkOf(project)), ['app/lib/a.dart:1 FR-03']);
      expect(_cited(await checkOf(project)), ['app/lib/a.dart:1 FR-03']);
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
