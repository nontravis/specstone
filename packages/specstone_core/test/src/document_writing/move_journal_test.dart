import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/document_writing/delete_doc.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/git_process.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:test/test.dart';

import '../../helpers/git_repo.dart';
import '../../helpers/posix_modes.dart';
import '../../helpers/temp_tree.dart';
import '../../helpers/write_fixture.dart';

const _login = 'prds/features/f01_login';
const _trashDocs = '.specstone/trash/files/docs';

/// Returns a folder on another volume than the temp folder, else null.
///
/// Reads `SPECSTONE_OTHER_VOLUME`; on Linux falls back to `/dev/shm` when its
/// device id differs from the temp folder's.
Directory? _otherVolume() {
  final given = Platform.environment['SPECSTONE_OTHER_VOLUME'];
  if (given != null && given.isNotEmpty) return Directory(given);
  if (!Platform.isLinux || !Directory('/dev/shm').existsSync()) return null;
  String deviceOf(String path) =>
      Process.runSync('stat', ['-c', '%d', path]).stdout.toString().trim();
  return deviceOf('/dev/shm') == deviceOf(Directory.systemTemp.path)
      ? null
      : Directory('/dev/shm');
}

/// A `Directory` whose probe folders refuse to be removed, as a disk that
/// turns read-only mid-run does.
final class _StuckProbeDirectory implements Directory {
  const new(this._inner);

  final Directory _inner;

  static Directory _wrap(Directory inner) => _StuckProbeDirectory(inner);

  @override
  void deleteSync({bool recursive = false}) {
    if (path.split(RegExp(r'[/\\]')).last.startsWith('.specstone-probe-')) {
      throw FileSystemException('Permission denied', path);
    }
    _inner.deleteSync(recursive: recursive);
  }

  @override
  Directory renameSync(String newPath) => _wrap(_inner.renameSync(newPath));

  @override
  Directory createTempSync([String? prefix]) =>
      _wrap(_inner.createTempSync(prefix));

  @override
  String get path => _inner.path;

  @override
  Uri get uri => _inner.uri;

  @override
  bool existsSync() => _inner.existsSync();

  @override
  void createSync({bool recursive = false}) =>
      _inner.createSync(recursive: recursive);

  @override
  Directory get absolute => _wrap(_inner.absolute);

  @override
  Directory get parent => _wrap(_inner.parent);

  @override
  bool get isAbsolute => _inner.isAbsolute;

  @override
  Future<Directory> create({bool recursive = false}) =>
      _inner.create(recursive: recursive);

  @override
  Future<Directory> createTemp([String? prefix]) => _inner.createTemp(prefix);

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      _inner.delete(recursive: recursive);

  @override
  // ignore: avoid_slow_async_io, forwards the Directory interface
  Future<bool> exists() => _inner.exists();

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) => _inner.list(recursive: recursive, followLinks: followLinks);

  @override
  List<FileSystemEntity> listSync({
    bool recursive = false,
    bool followLinks = true,
  }) => _inner.listSync(recursive: recursive, followLinks: followLinks);

  @override
  Future<Directory> rename(String newPath) => _inner.rename(newPath);

  @override
  Future<String> resolveSymbolicLinks() => _inner.resolveSymbolicLinks();

  @override
  String resolveSymbolicLinksSync() => _inner.resolveSymbolicLinksSync();

  @override
  // ignore: avoid_slow_async_io, forwards the Directory interface
  Future<FileStat> stat() => _inner.stat();

  @override
  FileStat statSync() => _inner.statSync();

  @override
  Stream<FileSystemEvent> watch({
    int events = FileSystemEvent.all,
    bool recursive = false,
  }) => _inner.watch(events: events, recursive: recursive);
}

/// Makes every `Directory` the code under test opens a [_StuckProbeDirectory].
final class _StuckProbeHook extends IOOverrides {
  @override
  Directory createDirectory(String path) =>
      _StuckProbeDirectory(super.createDirectory(path));
}

JournalTarget _target(Directory root) => JournalTarget(
  projectRoot: root,
  docsRoot: Directory('${root.path}${Platform.pathSeparator}docs'),
);

/// Writes [files] as a git work tree with one commit.
Future<Directory> _gitTree(Map<String, String> files) async {
  final root = await writeTree(files);
  expect(
    Process.runSync('git', [
      'init',
      '-q',
    ], workingDirectory: root.path).exitCode,
    0,
  );
  for (final setting in [
    ['user.name', 't'],
    ['user.email', 't@t'],
    ['core.autocrlf', 'false'],
  ]) {
    expect(git(root, ['config', ...setting]).exitCode, 0);
  }
  commitAll(root, 'initial');
  return root;
}

String _head(Directory root) =>
    (git(root, ['rev-parse', 'HEAD']).stdout as String).trim();

List<String> _log(Directory root) =>
    (git(root, ['log', '--format=%s']).stdout as String)
        .split('\n')
        .where((line) => line.isNotEmpty)
        .toList();

void main() {
  late Directory root;

  setUp(() async {
    root = await writeWriteProject();
  });

  bool dirExists(String relative) =>
      Directory('${root.path}/$relative').existsSync();
  bool journalExists() =>
      File('${root.path}/${MoveJournal.journalPath}').existsSync();

  /// Drops the one link into [story3], so a delete of its unit is not refused.
  void dropLinkIntoStory3() {
    final file = docFile(root, fr12);
    file.writeAsStringSync(
      file.readAsStringSync().replaceFirst(
        ' See [reset](../us03_reset_password/USER_STORY.md#use-case).',
        '',
      ),
    );
  }

  /// Moves `docs/<path>` to the trash, as a stopped run would have.
  void moveToTrash(String path) {
    final target = File('${root.path}/$_trashDocs/$path');
    target.parent.createSync(recursive: true);
    docFile(root, path).renameSync(target.path);
  }

  test('f02/us04/fr03, dw-s03/inv9, f02/us04/fr03/e06: run moves to the trash, prunes, then clears journal and trash', () {
    const MoveJournal([
      MoveStep('docs/$fr31', '$_trashDocs/$fr31'),
      MoveStep('docs/$fr32', '$_trashDocs/$fr32'),
      MoveStep('docs/$story3', '$_trashDocs/$story3'),
      PruneStep('docs/$_login/us03_reset_password'),
    ]).run(JournalTarget.of(openProject(root)));
    expect(dirExists('docs/$_login/us03_reset_password'), isFalse);
    expect(dirExists(MoveJournal.trashPath), isFalse);
    expect(hasDoc(root, story1), isTrue);
    expect(
      File('${root.path}/.specstone/.gitignore').readAsStringSync(),
      contains('trash/\n'),
    );
  });

  test('f02/us04/s4, f02/us04/fr03/e01, nfr-di01: a delete stopped after two of five moves is finished by the replay', () {
    final files = [story3, fr31, fr32, signupFeature, signupArch];
    writeJournal(root, [
      for (final path in files) MoveStep('docs/$path', '$_trashDocs/$path'),
      const PruneStep('docs/$_login/us03_reset_password'),
      const PruneStep('docs/prds/features/f02_signup'),
      const PruneStep('docs/specs/f02_signup'),
    ]);
    moveToTrash(story3);
    moveToTrash(fr31);
    MoveJournal.replay(JournalTarget.of(openProject(root)));
    for (final path in files) {
      expect(hasDoc(root, path), isFalse, reason: path);
    }
    expect(dirExists('docs/$_login/us03_reset_password'), isFalse);
    expect(dirExists('docs/prds/features/f02_signup'), isFalse);
    expect(dirExists('docs/specs/f02_signup'), isFalse);
    expect(hasDoc(root, loginFeature), isTrue);
    expect(journalExists(), isFalse);
    expect(dirExists(MoveJournal.trashPath), isFalse);
  });

  test('f02/us04/fr03/e02: a rename stopped before its link rewrite writes the listed text on replay', () {
    const renamed = 'prds/features/f01_login/us03_forgot_password';
    final rewritten = readDoc(
      root,
      fr12,
    ).replaceAll('us03_reset_password', 'us03_forgot_password');
    writeJournal(root, [
      const MoveStep('docs/$_login/us03_reset_password', 'docs/$renamed'),
      WriteStep('docs/$fr12', rewritten),
    ]);
    Directory('${root.path}/docs/$_login/us03_reset_password')
        .renameSync('${root.path}/docs/$renamed');
    expect(readDoc(root, fr12), contains('us03_reset_password'));

    MoveJournal.replay(JournalTarget.of(openProject(root)));

    expect(readDoc(root, fr12), rewritten);
    expect(hasDoc(root, '$renamed/USER_STORY.md'), isTrue);
    expect(dirExists('docs/$_login/us03_reset_password'), isFalse);
    expect(journalExists(), isFalse);
  });

  test('f02/us04/fr03/e03: a reorder stopped mid-renumbering finishes, so no two siblings share a number', () {
    const stage = '.specstone/trash/stage';
    const us01 = 'docs/$_login/us01_email_login';
    const us03 = 'docs/$_login/us03_reset_password';
    writeJournal(root, [
      const MoveStep(us01, '$stage/0'),
      const MoveStep(us03, '$stage/1'),
      const MoveStep('$stage/0', 'docs/$_login/us03_email_login'),
      const MoveStep('$stage/1', 'docs/$_login/us01_reset_password'),
    ]);
    Directory('${root.path}/$stage').createSync(recursive: true);
    Directory('${root.path}/$us01').renameSync('${root.path}/$stage/0');
    Directory('${root.path}/$us03').renameSync('${root.path}/$stage/1');
    Directory('${root.path}/$stage/0')
        .renameSync('${root.path}/docs/$_login/us03_email_login');

    MoveJournal.replay(JournalTarget.of(openProject(root)));

    expect(hasDoc(root, '$_login/us03_email_login/USER_STORY.md'), isTrue);
    expect(hasDoc(root, '$_login/us01_reset_password/USER_STORY.md'), isTrue);
    expect(dirExists('docs/$_login/us01_email_login'), isFalse);
    expect(dirExists('docs/$_login/us03_reset_password'), isFalse);
    expect(dirExists(MoveJournal.trashPath), isFalse);
  });

  test('f02/us04/fr03/e04, nfr-di01: a replay that stops partway keeps the journal, and the next replay finishes', () {
    final locked = Directory('${root.path}/docs/$_login/us03_reset_password');
    writeJournal(root, [
      const MoveStep(
        'docs/$_login/us03_reset_password',
        '$_trashDocs/$_login/us03_reset_password',
      ),
      const PruneStep('docs/$_login/us03_reset_password'),
    ]);
    Process.runSync('chmod', ['555', locked.path]);
    addTearDown(() => Process.runSync('chmod', ['755', locked.path]));

    expect(
      () => MoveJournal.replay(JournalTarget.of(openProject(root))),
      throwsA(
        isA<RenderFault>()
            .having((e) => e.code, 'code', RenderFaultCode.outputNotWritable)
            .having(
              (e) => e.message,
              'message',
              startsWith('cannot move $_login/us03_reset_password: '),
            ),
      ),
    );
    expect(journalExists(), isTrue);
    expect(locked.existsSync(), isTrue);

    Process.runSync('chmod', ['755', locked.path]);
    MoveJournal.replay(JournalTarget.of(openProject(root)));

    expect(journalExists(), isFalse);
    expect(locked.existsSync(), isFalse);
    expect(dirExists(MoveJournal.trashPath), isFalse);
  }, skip: unreadablePathSkipReason() ?? false);

  test('f02/us04/fr03/e05: with no trash folder nothing is pending and replay does nothing', () {
    final before = readDoc(root, story1);
    expect(MoveJournal.pending(root), isFalse);

    MoveJournal.replay(JournalTarget.of(openProject(root)));

    expect(readDoc(root, story1), before);
    expect(dirExists(MoveJournal.trashPath), isFalse);
    Directory('${root.path}/${MoveJournal.trashPath}')
        .createSync(recursive: true);
    expect(MoveJournal.pending(root), isTrue);
  });

  Matcher notReplayable(String reason) => throwsA(
    isA<RenderFault>()
        .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
        .having(
          (f) => f.message,
          'message',
          'cannot replay .specstone/trash/journal.json: $reason; '
              'fix or remove it',
        ),
  );

  test('final Minor 2, f02/us04/fr03, dw-s03/inv9: a journal that does not parse is refused and the trash stays', () {
    final journal = File('${root.path}/${MoveJournal.journalPath}')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{"steps": [');
    final leftover = File('${root.path}/$_trashDocs/leftover.md')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('x');
    final before = readDoc(root, story1);

    expect(
      () => MoveJournal.replay(JournalTarget.of(openProject(root))),
      throwsA(
        isA<RenderFault>()
            .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
            .having(
              (f) => f.message,
              'message',
              allOf(
                startsWith('cannot replay .specstone/trash/journal.json: '),
                endsWith('; fix or remove it'),
              ),
            ),
      ),
    );

    expect(journal.existsSync(), isTrue);
    expect(leftover.existsSync(), isTrue);
    expect(readDoc(root, story1), before);
  });

  test('final Minor 2, f02/us04/fr03: a journal with an unknown step is refused like an unparsable one', () {
    final journal = File('${root.path}/${MoveJournal.journalPath}')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'steps': [
            {'bogus': <String, Object>{}},
          ],
        }),
      );

    expect(
      () => MoveJournal.replay(JournalTarget.of(openProject(root))),
      notReplayable('not a journal step'),
    );

    expect(journal.existsSync(), isTrue);
    expect(dirExists(MoveJournal.trashPath), isTrue);
  });

  test('f02/us04/fr03/e03, final Minor 3: a replay skips a stage move whose slot is taken', () {
    const stage = MoveJournal.stagePath;
    const us01 = 'docs/$_login/us01_email_login';
    File('${root.path}/$stage/0/kept.md')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('staged');
    writeJournal(root, const [MoveStep(us01, '$stage/0')]);

    MoveJournal.replay(JournalTarget.of(openProject(root)));

    expect(hasDoc(root, story1), isTrue);
    expect(journalExists(), isFalse);
    expect(dirExists(MoveJournal.trashPath), isFalse);
  });

  test('f02/us04/fr03, dw-s03/inv9: a PruneStep keeps a folder that holds a file and stops at the docs root', () async {
    final bare = await writeTree({
      '.specstone/config.yaml': writeProject['.specstone/config.yaml']!,
      'docs/keep/file.md': 'x',
    });
    Directory('${bare.path}/docs/a/b').createSync(recursive: true);
    Directory('${bare.path}/docs/keep/inner').createSync();
    final project = JournalTarget.of(openProject(bare));

    const PruneStep('docs/keep/inner').apply(project);
    const PruneStep('docs/a/b').apply(project);

    expect(Directory('${bare.path}/docs/keep').existsSync(), isTrue);
    expect(Directory('${bare.path}/docs/keep/inner').existsSync(), isFalse);
    expect(Directory('${bare.path}/docs/a').existsSync(), isFalse);
    expect(Directory('${bare.path}/docs').existsSync(), isTrue);
  });

  test('f02/us04/fr03: a WriteStep writes only a file that exists and differs, and a MoveStep skips a missing source', () {
    final project = JournalTarget.of(openProject(root));
    final before = readDoc(root, story1);

    const WriteStep('docs/prds/missing.md', 'x').apply(project);
    const MoveStep('docs/prds/missing.md', 'docs/prds/other.md').apply(project);
    WriteStep('docs/$story1', before).apply(project);
    const WriteStep('docs/$story1', 'changed\n').apply(project);

    expect(hasDoc(root, 'prds/missing.md'), isFalse);
    expect(hasDoc(root, 'prds/other.md'), isFalse);
    expect(readDoc(root, story1), 'changed\n');
  });

  test('f02/us04/fr03: run reports a gitignore it cannot write as index_not_writable and moves nothing', () {
    final ignore = File('${root.path}/.specstone/.gitignore')
      ..writeAsStringSync('mine\n');
    Process.runSync('chmod', ['444', ignore.path]);
    addTearDown(() => Process.runSync('chmod', ['644', ignore.path]));

    expect(
      () =>
          const MoveJournal([MoveStep('docs/$story3', '$_trashDocs/$story3')])
              .run(JournalTarget.of(openProject(root))),
      throwsA(
        isA<IndexFault>().having(
          (e) => e.code,
          'code',
          IndexFaultCode.indexNotWritable,
        ),
      ),
    );
    expect(hasDoc(root, story3), isTrue);
    expect(journalExists(), isFalse);
  }, skip: unreadablePathSkipReason() ?? false);

  test('f02/us04/fr03/e04: a WriteStep on a file that is not UTF-8 text fails as output_not_writable', () {
    docFile(root, story1).writeAsBytesSync([0xff, 0xfe, 0x41]);

    expect(
      () => const WriteStep(
        'docs/$story1',
        'x',
      ).apply(JournalTarget.of(openProject(root))),
      throwsA(
        isA<RenderFault>()
            .having((e) => e.code, 'code', RenderFaultCode.outputNotWritable)
            .having(
              (e) => e.message,
              'message',
              startsWith('cannot write $story1: '),
            ),
      ),
    );
  });

  test('f02/us04/fr03/e04: a replay whose journal cannot be read fails as output_not_writable', () {
    writeJournal(root, const []);
    final journal = File('${root.path}/${MoveJournal.journalPath}');
    Process.runSync('chmod', ['000', journal.path]);
    addTearDown(() => Process.runSync('chmod', ['644', journal.path]));

    expect(
      () => MoveJournal.replay(JournalTarget.of(openProject(root))),
      throwsA(
        isA<RenderFault>()
            .having((e) => e.code, 'code', RenderFaultCode.outputNotWritable)
            .having(
              (e) => e.message,
              'message',
              startsWith('cannot read ${MoveJournal.journalPath}: '),
            ),
      ),
    );
    expect(journal.existsSync(), isTrue);
  }, skip: unreadablePathSkipReason() ?? false);

  test(
    'f02/us04/fr03, dw-s03/inv9, HD1: a docs root on another volume refuses before the journal',
    () async {
      final volume = _otherVolume()!;
      final outside = volume.createTempSync('specstone_docs_');
      addTearDown(() => outside.deleteSync(recursive: true));
      final unlinked = writeProject['docs/$fr12']!.replaceFirst(
        ' See [reset](../us03_reset_password/USER_STORY.md#use-case).',
        '',
      );
      for (final MapEntry(:key, :value) in {
        ...writeProject,
        'docs/$fr12': unlinked,
      }.entries) {
        if (!key.startsWith('docs/')) continue;
        File('${outside.path}/${key.substring(5)}')
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(value);
      }
      final linked = await writeWriteProject(
        without: {
          for (final k in writeProject.keys)
            if (k.startsWith('docs/')) k,
        },
      );
      Link('${linked.path}/docs').createSync(outside.path);

      expect(
        () => writeIn(
          linked,
          (s) => answerDelete(
            s,
            'user_story:login/reset_password',
            interactive: false,
            readLine: () => null,
            prompts: StringBuffer(),
          ),
        ),
        throwsA(
          isA<RenderFault>()
              .having((e) => e.code, 'code', RenderFaultCode.outputNotWritable)
              .having(
                (e) => e.message,
                'message',
                startsWith('cannot move docs into .specstone/trash: '),
              ),
        ),
      );
      expect(
        Directory('${linked.path}/.specstone/trash').existsSync(),
        isFalse,
      );
      expect(File('${outside.path}/$story3').existsSync(), isTrue);
      expect(
        outside.listSync().map((e) => e.path.split('/').last),
        isNot(contains(startsWith('.specstone-probe-'))),
      );
      writeIn(linked, (_) {});
    },
    skip: Platform.isWindows
        ? 'links need privileges on Windows'
        : _otherVolume() == null
        ? 'no second volume: set SPECSTONE_OTHER_VOLUME'
        : false,
  );

  test('f02/us04/fr03, dw-s03/inv9, HD1: a docs root without write permission still deletes a unit whose folder is writable', () async {
    final docs = '${root.path}/docs';
    addTearDown(() => Process.runSync('chmod', ['755', docs]));
    dropLinkIntoStory3();
    Process.runSync('chmod', ['555', docs]);

    writeIn(
      root,
      (s) => answerDelete(
        s,
        'user_story:login/reset_password',
        interactive: false,
        readLine: () => null,
        prompts: StringBuffer(),
      ),
    );

    expect(hasDoc(root, story3), isFalse);
    expect(dirExists(MoveJournal.trashPath), isFalse);
  }, skip: unreadablePathSkipReason() ?? false);

  test(
    'f02/us04/fr03, dw-s03/inv9, HD1: a folder linked to another volume refuses before the journal',
    () {
      final outside = _otherVolume()!.createTempSync('specstone_folder_');
      addTearDown(() => outside.deleteSync(recursive: true));
      File('${outside.path}/note.md').writeAsStringSync('note\n');
      Link('${root.path}/docs/prds/elsewhere').createSync(outside.path);

      expect(
        () => const MoveJournal([
          MoveStep(
            'docs/prds/elsewhere/note.md',
            '$_trashDocs/prds/elsewhere/note.md',
          ),
        ]).run(JournalTarget.of(openProject(root))),
        throwsA(
          isA<RenderFault>()
              .having((e) => e.code, 'code', RenderFaultCode.outputNotWritable)
              .having(
                (e) => e.message,
                'message',
                startsWith('cannot move docs into .specstone/trash: '),
              ),
        ),
      );
      expect(dirExists(MoveJournal.trashPath), isFalse);
      expect(File('${outside.path}/note.md').existsSync(), isTrue);
      expect(
        outside.listSync().map((e) => e.uri.pathSegments.last),
        isNot(contains(startsWith('.specstone-probe-'))),
      );
      writeIn(root, (_) {});
    },
    skip: Platform.isWindows
        ? 'links need privileges on Windows'
        : _otherVolume() == null
        ? 'no second volume: set SPECSTONE_OTHER_VOLUME'
        : false,
  );

  test('f02/us04/fr03, dw-s03/inv9, HD1: a probe folder that cannot be removed does not hide the move', () {
    IOOverrides.runWithIOOverrides(
      () =>
          const MoveJournal([MoveStep('docs/$story3', '$_trashDocs/$story3')])
              .run(JournalTarget.of(openProject(root))),
      _StuckProbeHook(),
    );

    expect(hasDoc(root, story3), isFalse);
    expect(dirExists(MoveJournal.trashPath), isFalse);
  });

  test('f02/us04/fr03, dw-s03/inv9, HD1: a refused probe whose folder cannot be removed still comes back as the refusal', () {
    Directory('${root.path}/.specstone').createSync();
    File('${root.path}/${MoveJournal.trashPath}').writeAsStringSync('');

    expect(
      () => IOOverrides.runWithIOOverrides(
        () =>
            const MoveJournal([MoveStep('docs/$story3', '$_trashDocs/$story3')])
                .run(JournalTarget.of(openProject(root))),
        _StuckProbeHook(),
      ),
      throwsA(
        isA<RenderFault>()
            .having((e) => e.code, 'code', RenderFaultCode.outputNotWritable)
            .having(
              (e) => e.message,
              'message',
              startsWith('cannot move docs into .specstone/trash: '),
            ),
      ),
    );
    expect(hasDoc(root, story3), isTrue);
  });

  test('dw-s03/inv9, H09: a move step moves a symlink as itself', () {
    final outside = Directory.systemTemp.createTempSync('specstone_link_');
    addTearDown(() => outside.deleteSync(recursive: true));
    File('${outside.path}/keep.md').writeAsStringSync('keep\n');
    final link = Link('${root.path}/docs/prds/shortcut')
      ..createSync(outside.path);

    const MoveStep(
      'docs/prds/shortcut',
      '$_trashDocs/prds/shortcut',
    ).apply(JournalTarget.of(openProject(root)));

    final landed = Link('${root.path}/$_trashDocs/prds/shortcut');
    expect(landed.existsSync(), isTrue);
    expect(landed.targetSync(), outside.path);
    expect(link.existsSync(), isFalse);
    expect(File('${outside.path}/keep.md').readAsStringSync(), 'keep\n');
  }, skip: Platform.isWindows ? 'links need privileges on Windows' : false);

  group('f06/us01/fr07: create and commit steps', () {
    final skipGit = hasGit ? null : 'git is not available';

    test('f06/us01/fr07: a create step writes an absent file and never overwrites one', () async {
      final root = await writeTree({'docs/prds/PROJECT.md': 'old\n'});
      final target = _target(root);
      const CreateStep('docs/specs/TECH_STACK.md', 'draft\n').apply(target);
      const CreateStep('docs/prds/PROJECT.md', 'new\n').apply(target);
      expect(
        File('${root.path}/docs/specs/TECH_STACK.md').readAsStringSync(),
        'draft\n',
      );
      expect(
        File('${root.path}/docs/prds/PROJECT.md').readAsStringSync(),
        'old\n',
      );
    });

    test('f06/us01/fr07: a journal of moves, commit 1, writes, commit 2 makes two commits, the first pure renames', () async {
      final root = await _gitTree({
        'docs/prds/d01_context.md': '# D-01 — Project context\n',
      });
      final base = _head(root);
      MoveJournal([
        const MoveStep('docs/prds/d01_context.md', 'docs/prds/PROJECT.md'),
        CommitStep(
          message: 'move',
          paths: ['docs/prds/d01_context.md', 'docs/prds/PROJECT.md'],
          base: base,
        ),
        const WriteStep('docs/prds/PROJECT.md', '# Project context\n'),
        const CreateStep('.specstone/config.yaml', 'packs:\n'),
        CommitStep(
          message: 'rewrite',
          paths: [
            'docs/prds/PROJECT.md',
            '.specstone/config.yaml',
            '.specstone/.gitignore',
          ],
          base: base,
        ),
      ]).run(_target(root));
      expect(_log(root), ['rewrite', 'move', 'initial']);
      expect(
        git(root, [
          'show',
          '--name-status',
          '-M',
          '--format=',
          'HEAD~1',
        ]).stdout,
        'R100\tdocs/prds/d01_context.md\tdocs/prds/PROJECT.md\n',
      );
      expect(git(root, ['status', '--porcelain']).stdout, '');
      expect(MoveJournal.pending(root), isFalse);
    }, skip: skipGit);

    test('f06/us01/fr07: a replay after commit 1 skips the done steps and makes commit 2 only', () async {
      final root = await _gitTree({
        'docs/prds/d01_context.md': '# D-01 — Project context\n',
      });
      final base = _head(root);
      final steps = [
        const MoveStep('docs/prds/d01_context.md', 'docs/prds/PROJECT.md'),
        CommitStep(
          message: 'move',
          paths: ['docs/prds/d01_context.md', 'docs/prds/PROJECT.md'],
          base: base,
        ),
        const WriteStep('docs/prds/PROJECT.md', '# Project context\n'),
        const CreateStep('.specstone/config.yaml', 'packs:\n'),
        CommitStep(
          message: 'rewrite',
          paths: [
            'docs/prds/PROJECT.md',
            '.specstone/config.yaml',
            '.specstone/.gitignore',
          ],
          base: base,
        ),
      ];
      final specstone = Directory('${root.path}/.specstone')
        ..createSync(recursive: true);
      ensureSpecstoneGitignore(specstone);
      File('${root.path}/${MoveJournal.journalPath}')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(jsonEncode(MoveJournal(steps).toJson()));
      steps[0].apply(_target(root));
      steps[1].apply(_target(root));
      expect(_log(root), ['move', 'initial']);

      MoveJournal.replay(_target(root));

      expect(_log(root), ['rewrite', 'move', 'initial']);
      expect(
        File('${root.path}/docs/prds/PROJECT.md').readAsStringSync(),
        '# Project context\n',
      );
      expect(MoveJournal.pending(root), isFalse);
    }, skip: skipGit);

    test('f06/us01/fr07: remaining lists the steps not done, and describe prints each', () async {
      final root = await _gitTree({
        'docs/prds/d01_context.md': '# D-01 — Project context\n',
      });
      final base = _head(root);
      final steps = [
        const MoveStep('docs/prds/d01_context.md', 'docs/prds/PROJECT.md'),
        CommitStep(
          message: 'move',
          paths: ['docs/prds/d01_context.md', 'docs/prds/PROJECT.md'],
          base: base,
        ),
        const WriteStep('docs/prds/PROJECT.md', '# Project context\n'),
        const CreateStep('.specstone/config.yaml', 'packs:\n'),
        CommitStep(
          message: 'rewrite',
          paths: ['docs/prds/PROJECT.md'],
          base: base,
        ),
      ];
      expect(MoveJournal.remaining(_target(root)), isEmpty);
      File('${root.path}/${MoveJournal.journalPath}')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(jsonEncode(MoveJournal(steps).toJson()));
      expect(steps.map((s) => s.describe()), [
        'move docs/prds/d01_context.md -> docs/prds/PROJECT.md',
        'commit "move"',
        'write docs/prds/PROJECT.md',
        'create .specstone/config.yaml',
        'commit "rewrite"',
      ]);
      steps[0].apply(_target(root));
      steps[1].apply(_target(root));

      expect(MoveJournal.remaining(_target(root)).map((s) => s.describe()), [
        'write docs/prds/PROJECT.md',
        'create .specstone/config.yaml',
        'commit "rewrite"',
      ]);
    }, skip: skipGit);

    test('f06/us01/fr07/e03: a commit-msg hook that prefixes the subject does '
        'not make a resume commit twice', () async {
      final root = await _gitTree({'docs/prds/d01_context.md': 'x\n'});
      final hook = File('${root.path}/.git/hooks/commit-msg')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          '#!/bin/sh\n'
          r'printf "[X] " | cat - "$1" > "$1.tmp" && mv "$1.tmp" "$1"'
          '\n',
        );
      expect(Process.runSync('chmod', ['755', hook.path]).exitCode, 0);
      final base = _head(root);
      final steps = [
        const MoveStep('docs/prds/d01_context.md', 'docs/prds/PROJECT.md'),
        CommitStep(
          message: 'move',
          paths: ['docs/prds/d01_context.md', 'docs/prds/PROJECT.md'],
          base: base,
        ),
        const WriteStep('docs/prds/PROJECT.md', 'y\n'),
        CommitStep(
          message: 'rewrite',
          paths: ['docs/prds/PROJECT.md'],
          base: base,
        ),
      ];
      File('${root.path}/${MoveJournal.journalPath}')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(jsonEncode(MoveJournal(steps).toJson()));
      steps[0].apply(_target(root));
      steps[1].apply(_target(root));
      expect(_log(root), ['[X] move', 'initial']);
      expect(steps[1].isDone(_target(root)), isTrue);

      MoveJournal.replay(_target(root));

      expect(_log(root), ['[X] rewrite', '[X] move', 'initial']);
      expect(MoveJournal.pending(root), isFalse);
    }, skip: Platform.isWindows ? 'the hook is a sh script' : skipGit);

    test('f06/us01/fr07/e03: a commit whose paths stage nothing is done and '
        'makes no empty commit', () async {
      final root = await _gitTree({'docs/prds/PROJECT.md': 'x\n'});
      final base = _head(root);

      CommitStep(
        message: 'rewrite',
        paths: ['docs/prds/PROJECT.md'],
        base: base,
      ).apply(_target(root));

      expect(_log(root), ['initial']);
    }, skip: skipGit);

    test('f06/us01/fr07/e03: read returns the pending steps, null when none or '
        'unparsable', () async {
      final root = await writeTree({'docs/prds/PROJECT.md': 'x\n'});
      expect(MoveJournal.read(root), isNull);
      final journal = File('${root.path}/${MoveJournal.journalPath}')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode(
            const MoveJournal([WriteStep('docs/prds/PROJECT.md', 'y\n')])
                .toJson(),
          ),
        );
      expect(MoveJournal.read(root)!.map((s) => s.describe()), [
        'write docs/prds/PROJECT.md',
      ]);
      journal.writeAsStringSync('{not json');
      expect(MoveJournal.read(root), isNull);
    });

    test(
      'f06/us01/fr07/e09: a commit git refuses leaves the journal pending',
      () async {
        final root = await _gitTree({'docs/prds/d01_context.md': 'x\n'});
        final hook = File('${root.path}/.git/hooks/pre-commit')
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('#!/bin/sh\necho "lint failed" >&2\nexit 1\n');
        Process.runSync('chmod', ['755', hook.path]);

        expect(
          () => MoveJournal([
            const MoveStep('docs/prds/d01_context.md', 'docs/prds/PROJECT.md'),
            CommitStep(
              message: 'move',
              paths: ['docs/prds/d01_context.md', 'docs/prds/PROJECT.md'],
              base: _head(root),
            ),
          ]).run(_target(root)),
          throwsA(
            isA<GitCommandFailed>()
                .having((e) => e.verb, 'verb', 'commit')
                .having((e) => e.line, 'line', 'lint failed'),
          ),
        );
        expect(MoveJournal.pending(root), isTrue);
      },
      skip: Platform.isWindows ? 'hooks need a shell script' : skipGit,
    );

    test('f06/us01/fr07/e09: the decisive line is the first fatal or error line, else the last line', () async {
      final root = await writeTree({'x': ''});
      ProcessResult failing(String stderr, String stdout) =>
          ProcessResult(0, 1, stdout, stderr);
      void commitWith(String stderr, {String stdout = ''}) =>
          const CommitStep(message: 'm', paths: ['x'], base: 'b').apply(
            JournalTarget(
              projectRoot: root,
              docsRoot: root,
              runGit: (arguments, {required workingDirectory}) =>
                  arguments.first == 'log'
                  ? ProcessResult(0, 0, '', '')
                  : failing(stderr, stdout),
            ),
          );

      expect(
        () => commitWith('hint: x\nfatal: bad thing\nerror: later\n'),
        throwsA(
          isA<GitCommandFailed>()
              .having((e) => e.line, 'line', 'fatal: bad thing')
              .having((e) => e.verb, 'verb', 'add'),
        ),
      );
      expect(
        () => commitWith('one\n\nlast words\n\n'),
        throwsA(
          isA<GitCommandFailed>().having((e) => e.line, 'line', 'last words'),
        ),
      );
    });

    test('f06/us01/fr07/e09: a failure with no stderr reports the last stdout line', () async {
      final root = await writeTree({'x': ''});
      JournalTarget target() => JournalTarget(
        projectRoot: root,
        docsRoot: root,
        runGit: (arguments, {required workingDirectory}) =>
            arguments.first == 'log'
            ? ProcessResult(0, 0, '', '')
            : ProcessResult(0, 1, 'On branch x\nnothing to commit\n\n', ''),
      );

      expect(
        () => const CommitStep(
          message: 'm',
          paths: ['x'],
          base: 'b',
        ).apply(target()),
        throwsA(
          isA<GitCommandFailed>().having(
            (e) => e.line,
            'line',
            'nothing to commit',
          ),
        ),
      );
    });

    test('f06/us01/fr07: fromJson refuses a commit step whose path is not a string', () {
      expect(
        () => JournalStep.fromJson({
          'commit': {
            'message': 'm',
            'paths': ['a', 1],
            'base': 'b',
          },
        }),
        throwsFormatException,
      );
    });

    test(
      'f06/us01/fr07: a prune step is done when its folder is gone',
      () async {
        final root = await writeTree({'docs/keep.md': 'x'});
        Directory('${root.path}/docs/a').createSync();

        expect(const PruneStep('docs/a').isDone(_target(root)), isFalse);
        const PruneStep('docs/a').apply(_target(root));
        expect(const PruneStep('docs/a').isDone(_target(root)), isTrue);
      },
    );

    test('f06/us01/fr07: a write step is done when the file already holds its text', () async {
      final root = await writeTree({'docs/prds/PROJECT.md': 'same\n'});

      expect(
        const WriteStep('docs/prds/PROJECT.md', 'same\n').isDone(_target(root)),
        isTrue,
      );
      expect(
        const WriteStep(
          'docs/prds/PROJECT.md',
          'other\n',
        ).isDone(_target(root)),
        isFalse,
      );
    });
  });
}
