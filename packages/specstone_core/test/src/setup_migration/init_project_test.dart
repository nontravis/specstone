import 'dart:io';

import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/new_doc.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/git_process.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/setup_migration/init_project.dart';
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/git_repo.dart';
import '../../helpers/legacy_fixture.dart';
import '../../helpers/posix_modes.dart';
import '../../helpers/relative_link.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/temp_tree.dart';

const _draftPaths = [
  'docs/prds/PROJECT.md',
  'docs/prds/FEATURES.md',
  'docs/prds/GNFR.md',
  'docs/specs/TECH_STACK.md',
];

/// Runs `init` on [root] and returns its status with the printed lines.
(int, List<String>) _run(
  Directory root, {
  bool interactive = false,
  List<String?> answers = const [],
  RunGit runGit = _noGit,
}) {
  final out = StringBuffer();
  var call = 0;
  final status = runInit(
    InitRequest(
      workingDirectory: root,
      homeDirectory: null,
      templates: TemplateResolver(),
      interactive: interactive,
      readLine: () => call++ < answers.length ? answers[call - 1] : null,
      out: out,
      runGit: runGit,
    ),
  );
  return (status, out.toString().split('\n')..removeLast());
}

/// Fails the test: the scaffold path starts no git process (E06).
ProcessResult _noGit(
  List<String> arguments, {
  required String workingDirectory,
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
      _configLine(),
    ]);
    expect(_read(root, '.specstone/config.yaml'), shippedPinsConfig());
    for (final path in _draftPaths) {
      expect(_read(root, path), startsWith('---\ndraft: true\n'), reason: path);
    }
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
      _configLine(),
    ]);
    expect(_read(root, _draftPaths[0]), project);
    expect(_read(root, _draftPaths[1]), features);
  });

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
      homeDirectory: null,
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
      interactive: true,
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

  test('f06/us03/fr01/e02: a legacy folder without a terminal prints the '
      'plan, then refuses owner_terminal_required', () async {
    final root = await gitFixture(acmeLegacy);
    final legacy = _bytesUnder(root);

    final out = StringBuffer();
    expect(
      () => runInit(
        InitRequest(
          workingDirectory: root,
          homeDirectory: null,
          templates: TemplateResolver(),
          interactive: false,
          readLine: () => null,
          out: out,
          runGit: runRealGit,
        ),
      ),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.code, 'code', WriteFaultCode.ownerTerminalRequired)
            .having((f) => f.exitStatus, 'exitStatus', 77),
      ),
    );
    expect(out.toString(), startsWith('legacy migration: '));
    expect(_bytesUnder(root), legacy);
  }, skip: hasGit ? null : 'git is not available');

  test('f06/us03/fr01/e02: a refused commit in the legacy entry is git_failed, '
      'exit 75, and the journal stays', () async {
    final root = await gitFixture(acmeLegacy);

    expect(
      () => _run(
        root,
        interactive: true,
        answers: ['y'],
        runGit: (arguments, {required workingDirectory}) =>
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
        interactive: true,
        runGit: (arguments, {required workingDirectory}) =>
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
