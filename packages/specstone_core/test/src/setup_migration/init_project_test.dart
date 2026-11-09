import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/new_doc.dart';
import 'package:specstone_core/src/document_writing/owner_confirmation.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/git_process.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/setup_migration/agent_files.dart';
import 'package:specstone_core/src/setup_migration/init_project.dart';
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/setup_migration/migrate_run.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:specstone_core/src/version.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart' show checkOf, spots;
import '../../helpers/git_repo.dart';
import '../../helpers/legacy_fixture.dart';
import '../../helpers/posix_modes.dart';
import '../../helpers/relative_link.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/temp_tree.dart';
import '../../helpers/write_fixture.dart' show testHome;

const _draftPaths = [
  'docs/prds/PROJECT.md',
  'docs/prds/FEATURES.md',
  'docs/prds/GNFR.md',
  'docs/specs/TECH_STACK.md',
];

/// Runs `init` on [root] and returns its status with the printed lines.
(int, List<String>) _run(
  Directory root, {
  OwnerConfirmation confirmation = OwnerConfirmation.missing,
  List<String?> answers = const [],
  RunGit runGit = _noGit,
  String? planHash,
  List<String>? warnings,
}) {
  final out = StringBuffer();
  var call = 0;
  final status = runInit(
    InitRequest(
      workingDirectory: root,
      homeDirectory: testHome(),
      templates: TemplateResolver(),
      confirmation: confirmation,
      readLine: () => call++ < answers.length ? answers[call - 1] : null,
      out: out,
      planHash: planHash,
      runGit: runGit,
      warn: (warnings ?? <String>[]).add,
    ),
  );
  return (status, out.toString().split('\n')..removeLast());
}

/// Fails the test: the scaffold path starts no git process (E06).
ProcessResult _noGit(
  List<String> arguments, {
  required String workingDirectory,
  Map<String, String>? environment,
}) {
  throw StateError('init must start no git process: git $arguments');
}

String _configLine() {
  final versions = shippedPackVersions();
  return 'created .specstone/config.yaml: '
      'prd-core ${versions['prd-core']}, '
      'software-tech ${versions['software-tech']}';
}

String _read(Directory root, String relative) =>
    File.fromUri(root.uri.resolve(relative)).readAsStringSync();

/// The text of every file under [root] outside `.git`, keyed by its
/// `/`-separated path relative to [root].
Map<String, String> _bytesUnder(Directory root) {
  final prefix = '${root.path}${Platform.pathSeparator}';
  return {
    for (final entity in root.listSync(recursive: true, followLinks: false))
      if (entity is File &&
          !entity.path.startsWith('$prefix.git${Platform.pathSeparator}'))
        entity.path
            .substring(prefix.length)
            .replaceAll(Platform.pathSeparator, '/'): entity
            .readAsStringSync(),
  };
}

void main() {
  test('f06/us03/fr02, f06/us03/s1: an empty folder gets four empty drafts, '
      'then the config', () async {
    final root = await writeTree({'keep.txt': 'x\n'});

    final (status, lines) = _run(root);

    expect(status, 0);
    expect(lines, [
      'created docs/prds/PROJECT.md (draft)',
      'created docs/prds/FEATURES.md (draft)',
      'created docs/prds/GNFR.md (draft)',
      'created docs/specs/TECH_STACK.md (draft)',
      'created .specstone/AGENT.md',
      'created AGENTS.md',
      _configLine(),
    ]);
    expect(_read(root, '.specstone/config.yaml'), shippedPinsConfig());
    for (final path in _draftPaths) {
      expect(_read(root, path), startsWith('---\ndraft: true\n'), reason: path);
    }
  });

  test('rendering/format_docs/normalize_layout_whitespace: init then check reports no format_drift on the four drafts', () async {
    final root = await writeTree({'keep.txt': 'x\n'});

    final (status, _) = _run(root);

    expect(status, 0);
    expect(spots(checkOf(root), FindingKind.formatDrift), isEmpty);
  });

  test(
    'f06/us03/fr02/e01, f06/us03/s3: an existing doc is kept and named',
    () async {
      final root = await writeTree({'docs/prds/PROJECT.md': '# Mine\n'});

      final (status, lines) = _run(root);

      expect(status, 0);
      expect(lines, [
        'kept docs/prds/PROJECT.md: exists',
        'created docs/prds/FEATURES.md (draft)',
        'created docs/prds/GNFR.md (draft)',
        'created docs/specs/TECH_STACK.md (draft)',
        'created .specstone/AGENT.md',
        'created AGENTS.md',
        _configLine(),
      ]);
      expect(_read(root, 'docs/prds/PROJECT.md'), '# Mine\n');
    },
  );

  test('f06/us03/fr02/e08: a run stopped before the config is finished by '
      'the next init', () async {
    // A full run supplies the two drafts a crash after them leaves.
    final whole = await writeTree({'keep.txt': 'x\n'});
    _run(whole);
    final project = _read(whole, _draftPaths[0]);
    final features = _read(whole, _draftPaths[1]);
    final root = await writeTree({
      _draftPaths[0]: project,
      _draftPaths[1]: features,
    });

    final (status, lines) = _run(root);

    expect(status, 0);
    expect(lines, [
      'kept docs/prds/PROJECT.md: exists',
      'kept docs/prds/FEATURES.md: exists',
      'created docs/prds/GNFR.md (draft)',
      'created docs/specs/TECH_STACK.md (draft)',
      'created .specstone/AGENT.md',
      'created AGENTS.md',
      _configLine(),
    ]);
    expect(_read(root, _draftPaths[0]), project);
    expect(_read(root, _draftPaths[1]), features);
  });

  test('setup_migration/set_up_new_project/write_agent_files verification: '
      'init upserts each file, keeps the Owner bytes, and prints them before '
      'the config', () async {
    final root = await writeTree({
      'CLAUDE.md': "Owner's rules\n",
      'AGENTS.md':
          'before\n<!-- BEGIN specstone v0.0.1 -->\nold\n'
          '<!-- END specstone -->\nafter\n',
      '.cursor/keep': 'x',
    });

    final (status, lines) = _run(root);

    expect(status, 0);
    expect(lines.sublist(lines.length - 5), [
      'created .specstone/AGENT.md',
      'updated CLAUDE.md',
      'updated AGENTS.md',
      'created .cursor/rules/specstone.mdc',
      _configLine(),
    ]);
    expect(_read(root, '.specstone/AGENT.md'), agentMdText);
    final imports = importBlock(
      cliVersion: specstoneVersion,
      agentMdPath: '.specstone/AGENT.md',
      projectDocPath: 'docs/prds/PROJECT.md',
    );
    expect(_read(root, 'CLAUDE.md'), "Owner's rules\n$imports");
    expect(
      _read(root, 'AGENTS.md'),
      'before\n${inlineBlock(cliVersion: specstoneVersion)}after\n',
    );
    expect(
      _read(root, '.cursor/rules/specstone.mdc'),
      cursorRulesText(cliVersion: specstoneVersion),
    );
  });

  test('setup_migration/set_up_new_project/write_agent_files E05: a '
      'malformed file refuses before any write', () async {
    final root = await writeTree({
      'CLAUDE.md': '<!-- BEGIN specstone v1.0.0 -->\nno end\n',
    });
    final before = _bytesUnder(root);

    expect(
      () => _run(root),
      throwsA(
        isA<MigrateFault>()
            .having((f) => f.code, 'code', MigrateFaultCode.agentBlockMalformed)
            .having((f) => f.exitStatus, 'exitStatus', 65)
            .having((f) => f.file, 'file', 'CLAUDE.md')
            .having((f) => f.line, 'line', 1),
      ),
    );
    expect(_bytesUnder(root), before);
  });

  test(
    'setup_migration/set_up_new_project/write_agent_files E09: a rerun '
    'after a stop before the config changes 0 bytes of the agent files',
    () async {
      final root = await writeTree({'CLAUDE.md': "Owner's rules\n"});
      _run(root);
      File.fromUri(root.uri.resolve('.specstone/config.yaml')).deleteSync();
      final before = _bytesUnder(root)..remove('.specstone/config.yaml');

      final (status, lines) = _run(root);

      expect(status, 0);
      expect(lines.where((line) => line.contains('AGENT')), isEmpty);
      expect(lines.last, _configLine());
      expect(_bytesUnder(root)..remove('.specstone/config.yaml'), before);
    },
  );

  test('setup_migration/set_up_new_project/write_agent_files: a symbolic '
      'link CLAUDE.md stays a link and its target takes the block', () async {
    final root = await writeTree({'shared/rules.md': 'shared\n'});
    try {
      createRelativeLink('${root.path}/CLAUDE.md', 'shared/rules.md');
    } on FileSystemException {
      markTestSkipped('symbolic links are not available');
      return;
    }

    final (status, _) = _run(root);

    expect(status, 0);
    expect(
      FileSystemEntity.typeSync('${root.path}/CLAUDE.md', followLinks: false),
      FileSystemEntityType.link,
    );
    expect(_read(root, 'shared/rules.md'), startsWith('shared\n'));
    expect(_read(root, 'shared/rules.md'), contains('@.specstone/AGENT.md'));
  });

  test('setup_migration/set_up_new_project/write_agent_files E18: a repository '
      'top inside the project that a code entry reaches is upserted, printed, '
      'and listed in the config', () async {
    final base = await writeTree({
      'project/docs/specs/TECH_STACK.md':
          '---\ncode:\n  - other/\n---\n# Tech stack\n',
      'project/other/.git/HEAD': 'ref\n',
      'project/other/AGENTS.md': 'Owner\n',
    });
    final project = Directory('${base.path}/project');

    final (status, lines) = _run(project);

    expect(status, 0);
    final topLine = lines.indexOf('updated other/AGENTS.md');
    expect(topLine, isNonNegative);
    expect(lines.indexOf(_configLine()), greaterThan(topLine));
    expect(
      File('${base.path}/project/other/AGENTS.md').readAsStringSync(),
      'Owner\n${inlineBlock(cliVersion: specstoneVersion)}',
    );
    expect(
      _read(project, '.specstone/config.yaml'),
      contains('agent_file_roots:\n  - other\n'),
    );
  });

  test('setup_migration/set_up_new_project/write_agent_files R99: a '
      'repository top outside the project root is named, never written, and '
      'not listed', () async {
    final base = await writeTree({
      'project/docs/specs/TECH_STACK.md':
          '---\ncode:\n  - ../other/\n---\n# Tech stack\n',
      'other/.git/HEAD': 'ref\n',
      'other/AGENTS.md': 'Owner\n',
    });
    final project = Directory('${base.path}/project');
    final warnings = <String>[];

    final (status, lines) = _run(project, warnings: warnings);

    expect(status, 0);
    expect(warnings, [
      '../other/AGENTS.md reaches outside the project root; left as it is',
    ]);
    expect(lines, isNot(contains(contains('other'))));
    expect(File('${base.path}/other/AGENTS.md').readAsStringSync(), 'Owner\n');
    expect(
      _read(project, '.specstone/config.yaml'),
      isNot(contains('agent_file_roots')),
    );
  });

  group('setup_migration/set_up_new_project/write_agent_files: a link that '
      'leads out of the write bounds', () {
    final skipLinks = Platform.isWindows
        ? 'symbolic links need a privilege'
        : null;

    test('a linked .specstone/AGENT.md leading outside the project is named '
        'and left, and the file outside keeps its bytes', () async {
      final base = await writeTree({
        'victim.txt': 'mine\n',
        'proj/.specstone/keep.txt': '',
      });
      Link('${base.path}/proj/.specstone/AGENT.md')
          .createSync('../../victim.txt');
      final warnings = <String>[];

      final (status, lines) = _run(
        Directory('${base.path}/proj'),
        warnings: warnings,
      );

      expect(status, 0);
      expect(warnings, [
        '.specstone/AGENT.md reaches outside the project root; left as it is',
      ]);
      expect(lines, isNot(contains(contains('AGENT.md'))));
      expect(File('${base.path}/victim.txt').readAsStringSync(), 'mine\n');
    }, skip: skipLinks);

    test('a CLAUDE.md linked into .git is named and left, and .git/config '
        'keeps its bytes', () async {
      final base = await writeTree({
        'proj/.git/config': '[core]\n\tbare = false\n',
        'proj/keep.txt': '',
      });
      Link('${base.path}/proj/CLAUDE.md').createSync('.git/config');
      final warnings = <String>[];

      final (status, lines) = _run(
        Directory('${base.path}/proj'),
        warnings: warnings,
      );

      expect(status, 0);
      expect(warnings, [
        'CLAUDE.md reaches outside the project root; left as it is',
      ]);
      expect(lines, isNot(contains('updated CLAUDE.md')));
      expect(
        File('${base.path}/proj/.git/config').readAsStringSync(),
        '[core]\n\tbare = false\n',
      );
    }, skip: skipLinks);

    test('a docs folder linked outside the project refuses a draft written '
        'through it, and the folder outside is unchanged', () async {
      final base = await writeTree({
        'outside/keep.txt': 'mine\n',
        'proj/docs/keep.md': '',
      });
      Link('${base.path}/proj/docs/prds').createSync('../../outside');

      expect(
        () => _run(Directory('${base.path}/proj')),
        throwsA(
          isA<RenderFault>()
              .having((f) => f.exitStatus, 'exit', 73)
              .having((f) => f.file, 'file', isNotNull),
        ),
      );

      expect(
        Directory('${base.path}/outside')
            .listSync()
            .map((e) => e.uri.pathSegments.lastWhere((s) => s.isNotEmpty)),
        ['keep.txt'],
      );
    }, skip: skipLinks);
  });

  test('setup_migration/set_up_new_project/write_agent_files: a repository '
      'top folder named with a # gets its agent file at that folder, not at '
      'a URI fragment', () async {
    final base = await writeTree({
      'project/docs/specs/TECH_STACK.md':
          '---\ncode:\n  - other#1/\n---\n# Tech stack\n',
      'project/other#1/.git/HEAD': 'ref\n',
    });
    final project = Directory('${base.path}/project');

    final (status, _) = _run(project);

    expect(status, 0);
    expect(File('${base.path}/project/other#1/AGENTS.md').existsSync(), isTrue);
  });

  for (final (:real, :link) in [
    (real: 'AGENTS.md', link: 'CLAUDE.md'),
    (real: 'CLAUDE.md', link: 'AGENTS.md'),
  ]) {
    test('setup_migration/set_up_new_project/write_agent_files E22: $link '
        'linked to $real takes the inline block and prints one line', () async {
      final root = await writeTree({real: 'Owner\n'});
      try {
        createRelativeLink('${root.path}/$link', real);
      } on FileSystemException {
        markTestSkipped('symbolic links are not available');
        return;
      }

      final (status, lines) = _run(root);

      expect(status, 0);
      expect(
        _read(root, real),
        'Owner\n${inlineBlock(cliVersion: specstoneVersion)}',
      );
      expect(FileSystemEntity.isLinkSync('${root.path}/$link'), isTrue);
      expect(
        lines.where((l) => l.endsWith('CLAUDE.md') || l.endsWith('AGENTS.md')),
        hasLength(1),
      );
    });
  }

  test('f06/us03/fr02/e02, f06/us03/fr02/e03: init writes no .gitignore and '
      'no templates folder', () async {
    final root = await writeTree({'keep.txt': 'x\n'});

    final (status, _) = _run(root);

    expect(status, 0);
    expect(File('${root.path}/.specstone/.gitignore').existsSync(), isFalse);
    expect(
      Directory('${root.path}/.specstone/templates').existsSync(),
      isFalse,
    );
  });

  test('f06/us03/fr02/e05: each draft holds every required field empty and '
      'every required section, nothing else', () async {
    final root = await writeTree({'keep.txt': 'x\n'});
    final set = TemplateResolver().resolveCarried(
      packNames: const ['prd-core', 'software-tech'],
      homeDirectory: testHome(),
    );

    _run(root);

    for (final docType in set.docTypes) {
      final path = 'docs/${docType.path}';
      if (!_draftPaths.contains(path)) continue;
      expect(_read(root, path), skeletonOf(docType, docType.id), reason: path);
    }
  });

  test('f06/us03/fr02/e06: init makes no commit', () async {
    final root = await gitFixture({'keep.txt': 'x\n'});
    final headBefore = git(root, ['rev-parse', 'HEAD']).stdout as String;

    final (status, _) = _run(root);

    expect(status, 0);
    expect(git(root, ['rev-parse', 'HEAD']).stdout as String, headBefore);
    final untracked =
        git(root, ['ls-files', '--others', '--exclude-standard']).stdout
            as String;
    expect(untracked, contains('docs/prds/PROJECT.md'));
  }, skip: hasGit ? null : 'git is not available');

  test('f06/us03/fr01/e01, f06/us03/s5: a configured folder refuses '
      'config_exists and writes nothing', () async {
    for (final legacy in [null, acmeLegacy]) {
      final root = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(),
        ...?legacy,
      });
      final before = _bytesUnder(root);

      expect(
        () => _run(root),
        throwsA(
          isA<MigrateFault>()
              .having((f) => f.code, 'code', MigrateFaultCode.configExists)
              .having((f) => f.exitStatus, 'exitStatus', 64)
              .having((f) => f.file, 'file', '.specstone/config.yaml')
              .having(
                (f) => f.message,
                'message',
                'this folder is already a Specstone project; run specstone '
                    'migrate to upgrade its packs',
              ),
        ),
      );
      expect(_bytesUnder(root), before);
    }
  });

  test('f06/us03/fr01/e02, f06/us03/s4: a legacy folder enters the migrate '
      'run at its git checks', () async {
    final root = await gitFixture(acmeLegacy);

    final (status, lines) = _run(
      root,
      confirmation: OwnerConfirmation.prompt,
      answers: ['y'],
      runGit: runRealGit,
    );

    expect(status, 0);
    final subjects = (git(root, ['log', '--format=%s']).stdout as String)
        .trim()
        .split('\n');
    expect(subjects, hasLength(3));
    expect(lines.first, startsWith('legacy migration: '));
    expect(lines.any((line) => line.contains('apply? [y/N] ')), isTrue);
  }, skip: hasGit ? null : 'git is not available');

  test('setup_migration/migrate_legacy_docs/show_plan_and_apply_on_yes E07: '
      'init on a legacy tree stamps each typed doc it leaves and keeps the '
      'created draft', () async {
    final root = await gitFixture(acmeLegacy);

    final (status, _) = _run(
      root,
      confirmation: OwnerConfirmation.prompt,
      answers: ['y'],
      runGit: runRealGit,
    );

    expect(status, 0);
    expect(
      _read(root, 'docs/prds/features/f01_login/FEATURE.md'),
      startsWith('---\napproved: "'),
    );
    expect(
      _read(root, 'docs/specs/TECH_STACK.md'),
      startsWith('---\ndraft: true'),
    );
  }, skip: hasGit ? null : 'git is not available');

  test('setup_migration/set_up_new_project/write_agent_files E08: init on a '
      'legacy tree writes the agent files in commit 2', () async {
    final root = await gitFixture({...acmeLegacy, 'CLAUDE.md': '# Acme\n'});

    final (status, lines) = _run(
      root,
      confirmation: OwnerConfirmation.prompt,
      answers: ['y'],
      runGit: runRealGit,
    );

    expect(status, 0);
    final names =
        (git(root, ['show', '--name-only', '--format=', 'HEAD']).stdout
                as String)
            .trim()
            .split('\n');
    expect(names, containsAll(['.specstone/AGENT.md', 'CLAUDE.md']));
    expect(
      _read(root, 'CLAUDE.md'),
      contains('<!-- BEGIN specstone v$specstoneVersion -->'),
    );
    expect(lines, contains('  agent files: .specstone/AGENT.md, CLAUDE.md'));
  }, skip: hasGit ? null : 'git is not available');

  test("ms-r11: a legacy folder under --yes with migrate's dry-run plan hash "
      'applies the migrate run with no prompt', () async {
    final root = await gitFixture(acmeLegacy);
    final dryRun = StringBuffer();
    runMigrate(
      MigrateRequest(
        workingDirectory: root,
        homeDirectory: testHome(),
        templates: TemplateResolver(),
        dryRun: true,
        confirmation: OwnerConfirmation.missing,
        readLine: () => null,
        out: dryRun,
      ),
    );
    final dryLines = dryRun.toString().split('\n');
    final hash = dryLines[dryLines.length - 3].substring('plan '.length);

    final (status, lines) = _run(
      root,
      confirmation: OwnerConfirmation.given,
      runGit: runRealGit,
      planHash: hash,
    );

    expect(status, 0);
    final subjects = (git(root, ['log', '--format=%s']).stdout as String)
        .trim()
        .split('\n');
    expect(subjects, hasLength(3));
    expect(lines.first, startsWith('legacy migration: '));
    expect(lines.any((line) => line.contains('apply? [y/N] ')), isFalse);
  }, skip: hasGit ? null : 'git is not available');

  test('ms-r11: a legacy folder under --yes with a stale plan hash refuses '
      'plan_mismatch and writes nothing', () async {
    final root = await gitFixture(acmeLegacy);
    final legacy = _bytesUnder(root);

    expect(
      () => _run(
        root,
        confirmation: OwnerConfirmation.given,
        runGit: runRealGit,
        planHash: '000000000000',
      ),
      throwsA(
        isA<MigrateFault>().having(
          (f) => f.code,
          'code',
          MigrateFaultCode.planMismatch,
        ),
      ),
    );
    expect(_bytesUnder(root), legacy);
  }, skip: hasGit ? null : 'git is not available');

  test('f06/us03/fr01/e02: a legacy folder without a terminal prints the '
      'plan, then refuses owner_terminal_required', () async {
    final root = await gitFixture(acmeLegacy);
    final legacy = _bytesUnder(root);

    final out = StringBuffer();
    expect(
      () => runInit(
        InitRequest(
          workingDirectory: root,
          homeDirectory: testHome(),
          templates: TemplateResolver(),
          confirmation: OwnerConfirmation.missing,
          readLine: () => null,
          out: out,
          runGit: runRealGit,
        ),
      ),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.code, 'code', WriteFaultCode.ownerTerminalRequired)
            .having((f) => f.exitStatus, 'exitStatus', 77)
            .having(
              (f) => f.message,
              'message',
              'migrate applies only at an interactive terminal, or with '
                  "--yes after the Owner's ok in the chat",
            ),
      ),
    );
    expect(out.toString(), startsWith('legacy migration: '));
    expect(_bytesUnder(root), legacy);
  }, skip: hasGit ? null : 'git is not available');

  test('f06/us03/fr01/e02: the legacy entry from the folder holding the docs '
      'link plans code_root as migrate does', () async {
    final tree = await writeTree(
      linkedAcme({
        legacyFrPath: implementingDoc('Validate credentials', ['lib/a.dart']),
        'code/lib/a.dart': 'class A {}\n',
        // Git for Windows may store a link as a file; the plan needs none.
        '.gitignore': 'code/docs\n',
      }),
    );
    if (!linkCodeDocs(tree)) return;
    commitRepo(Directory('${tree.path}/ws'));
    final out = StringBuffer();

    expect(
      () => runInit(
        InitRequest(
          workingDirectory: Directory('${tree.path}/ws/code'),
          homeDirectory: testHome(),
          templates: TemplateResolver(),
          confirmation: OwnerConfirmation.missing,
          readLine: () => null,
          out: out,
          runGit: runRealGit,
        ),
      ),
      throwsA(
        isA<WriteFault>().having(
          (f) => f.code,
          'code',
          WriteFaultCode.ownerTerminalRequired,
        ),
      ),
    );
    expect(
      out.toString(),
      matches(RegExp(r'\n  \.specstone/config\.yaml: .*; code_root code\n')),
    );
  }, skip: hasGit ? null : 'git is not available');

  test('f06/us03/fr01/e02: a refused commit in the legacy entry is git_failed, '
      'exit 75, and the journal stays', () async {
    final root = await gitFixture(acmeLegacy);

    expect(
      () => _run(
        root,
        confirmation: OwnerConfirmation.prompt,
        answers: ['y'],
        runGit: (arguments, {required workingDirectory, environment}) =>
            arguments.first == 'commit'
            ? ProcessResult(0, 1, '', 'error: commit refused\n')
            : runRealGit(arguments, workingDirectory: workingDirectory),
      ),
      throwsA(
        isA<MigrateFault>()
            .having((f) => f.code, 'code', MigrateFaultCode.gitFailed)
            .having((f) => f.exitStatus, 'exitStatus', 75),
      ),
    );
    expect(MoveJournal.pendingMigrate(root), isTrue);
  }, skip: hasGit ? null : 'git is not available');

  test('f06/us03/fr01/e02: git that cannot start in the legacy entry is '
      'git_work_tree_required', () async {
    final root = await writeTree(acmeLegacy);

    expect(
      () => _run(
        root,
        confirmation: OwnerConfirmation.prompt,
        runGit: (arguments, {required workingDirectory, environment}) =>
            throw const ProcessException('git', []),
      ),
      throwsA(
        isA<MigrateFault>().having(
          (f) => f.code,
          'code',
          MigrateFaultCode.gitWorkTreeRequired,
        ),
      ),
    );
  });

  test('f06/us03/fr01, final M6: a folder that refuses writes is '
      'output_not_writable naming the path', () async {
    final root = await writeTree({'keep.txt': 'x\n'});
    expect(Process.runSync('chmod', ['555', root.path]).exitCode, 0);
    addTearDown(() => Process.runSync('chmod', ['755', root.path]));

    expect(
      () => _run(root),
      throwsA(
        isA<RenderFault>()
            .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
            .having(
              (f) => f.message,
              'message',
              startsWith('cannot write docs/prds/PROJECT.md: '),
            ),
      ),
    );
  }, skip: unreadablePathSkipReason());

  test('f06/us03/fr01/e03: a folder inside another project becomes its own '
      'project', () async {
    final outer = await writeTree({
      '.specstone/config.yaml': shippedPinsConfig(),
      'docs/prds/PROJECT.md': '# Outer\n',
      'app/keep.txt': 'x\n',
    });
    final inner = Directory.fromUri(outer.uri.resolve('app'));

    final (status, lines) = _run(inner);

    expect(status, 0);
    expect(lines.last, _configLine());
    expect(
      File.fromUri(outer.uri.resolve('.specstone/config.yaml'))
          .readAsStringSync(),
      shippedPinsConfig(),
    );
    expect(
      File.fromUri(inner.uri.resolve('.specstone/config.yaml')).existsSync(),
      isTrue,
    );
  });

  test('f06/us03/fr01/e04: a docs link puts the config beside the real docs '
      'folder', () async {
    final tree = await writeTree({
      'docsrepo/docs/keep.txt': 'x\n',
      'repo/code/keep.txt': 'x\n',
    });
    try {
      createRelativeLink('${tree.path}/repo/code/docs', '../../docsrepo/docs');
    } on FileSystemException {
      markTestSkipped('symbolic links need privileges on this machine');
      return;
    }
    final code = Directory('${tree.path}/repo/code');

    final (status, lines) = _run(code);

    expect(status, 0);
    expect(lines.last, _configLine());
    expect(
      File('${tree.path}/docsrepo/.specstone/config.yaml').existsSync(),
      isTrue,
    );
    expect(
      Directory('${tree.path}/repo/code/.specstone').existsSync(),
      isFalse,
    );
  });
}
