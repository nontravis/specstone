import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/code_fingerprint.dart';
import 'package:specstone_core/src/consistency_check/code_link_rules.dart';
import 'package:specstone_core/src/consistency_check/models/file_fingerprint.dart';
import 'package:specstone_core/src/git_process.dart';
import 'package:specstone_core/src/index_query/code_root_files.dart'
    show filesUnderCodeRoot;
import 'package:specstone_core/src/index_query/sync_diff_base.dart';
import 'package:test/test.dart';

import '../../helpers/git_repo.dart';

CodeLink _link(Directory root, String path, String? recorded) => CodeLink(
  field: 'implements',
  line: 1,
  value: path,
  pointer: path,
  path: path,
  recorded: recorded,
  root: root,
  target: null,
);

/// Returns a [RunGit] that runs the real git and adds each `log` call's
/// arguments to [logs].
RunGit _logsInto(List<List<String>> logs) =>
    (arguments, {required workingDirectory, environment}) {
      if (arguments.contains('log')) logs.add(arguments);
      return runRealGitBytes(
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
      );
    };

String _fileFingerprint(String text, String path) =>
    fileCodeFingerprint(utf8.encode(text), path: path);

void main() {
  late Directory repo;

  setUp(() {
    repo = Directory.systemTemp.createTempSync('sync_diff_base_');
    expect(git(repo, ['init', '-q']).exitCode, 0);
  });

  tearDown(() => repo.deleteSync(recursive: true));

  File write(String path, String text) => File('${repo.path}/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync(text);

  String head() => (git(repo, ['rev-parse', 'HEAD']).stdout as String).trim();

  group('diffBaseOf', () {
    test('gives the newest commit whose content is the recorded one', () {
      write('lib/a.dart', 'one\n');
      commitAll(repo, 'first');
      write('lib/a.dart', 'two\n');
      commitAll(repo, 'second');
      final second = head();
      write('lib/a.dart', 'three\n');
      commitAll(repo, 'third');
      write('lib/a.dart', 'four\n');
      commitAll(repo, 'fourth');

      final base = diffBaseOf(
        _link(repo, 'lib/a.dart', _fileFingerprint('two\n', 'lib/a.dart')),
      );

      expect(base?.commit, second);
      expect(
        Directory(base!.repo.path).resolveSymbolicLinksSync(),
        repo.resolveSymbolicLinksSync(),
      );
    });

    test('gives null when no commit gives the recorded fingerprint', () {
      write('lib/a.dart', 'one\n');
      commitAll(repo, 'first');
      write('lib/a.dart', 'two\n');
      commitAll(repo, 'second');

      expect(diffBaseOf(_link(repo, 'lib/a.dart', 'ffffffffffff')), isNull);
    });

    test('gives null for a link that records no fingerprint', () {
      write('lib/a.dart', 'one\n');
      commitAll(repo, 'first');

      expect(diffBaseOf(_link(repo, 'lib/a.dart', null)), isNull);
    });

    test('stops after the walk limit', () {
      write('lib/a.dart', 'one\n');
      commitAll(repo, 'first');
      for (final text in ['two\n', 'three\n', 'four\n']) {
        write('lib/a.dart', text);
        commitAll(repo, text);
      }
      final recorded = _fileFingerprint('one\n', 'lib/a.dart');

      expect(diffBaseOf(_link(repo, 'lib/a.dart', recorded), limit: 3), isNull);
      expect(
        diffBaseOf(_link(repo, 'lib/a.dart', recorded), limit: 4),
        isNotNull,
      );
    });

    test('matches a file that opens with a BOM', () {
      final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode('one\n')];
      File('${repo.path}/a.txt').writeAsBytesSync(bytes);
      commitAll(repo, 'first');
      final first = head();
      write('a.txt', 'two\n');
      commitAll(repo, 'second');

      final base = diffBaseOf(
        _link(repo, 'a.txt', fileCodeFingerprint(bytes, path: 'a.txt')),
      );

      expect(base?.commit, first);
    });

    test('matches a file whose bytes are no UTF-8', () {
      final bytes = [0xFF, 0xFE, 0x00, 0x01];
      File('${repo.path}/a.bin').writeAsBytesSync(bytes);
      commitAll(repo, 'first');
      final first = head();
      write('a.bin', 'text\n');
      commitAll(repo, 'second');

      final base = diffBaseOf(
        _link(repo, 'a.bin', fileCodeFingerprint(bytes, path: 'a.bin')),
      );

      expect(base?.commit, first);
    });

    test('gives the commit whose listed files fingerprint as recorded', () {
      write('lib/a.dart', 'a1\n');
      write('lib/b.dart', 'b1\n');
      write('lib/.hidden/c.dart', 'hidden\n');
      write('lib/nested/n.dart', 'n1\n');
      commitAll(repo, 'first');
      write('lib/b.dart', 'b2\n');
      commitAll(repo, 'second');
      final second = head();
      write('lib/a.dart', 'a2\n');
      write('lib/nested/n.dart', 'n2\n');
      commitAll(repo, 'third');
      final recorded = folderCodeFingerprint([
        FileFingerprint(
          path: 'lib/a.dart',
          fingerprint: _fileFingerprint('a1\n', 'lib/a.dart'),
        ),
        FileFingerprint(
          path: 'lib/b.dart',
          fingerprint: _fileFingerprint('b2\n', 'lib/b.dart'),
        ),
      ]);

      final base = diffBaseOf(
        _link(repo, 'lib', recorded),
        nestedRoots: const ['lib/nested'],
      );

      expect(base?.commit, second);
    });

    test('finds the base in a code repo nested in a docs repo', () {
      final docs = Directory.systemTemp.createTempSync('sync_diff_docs_');
      addTearDown(() => docs.deleteSync(recursive: true));
      expect(git(docs, ['init', '-q']).exitCode, 0);
      // The docs repo holds the same relative path with the recorded content,
      // so a walk run there would name this commit.
      File('${docs.path}/lib/a.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('one\n');
      commitAll(docs, 'docs copy');
      final code = Directory('${docs.path}/code')..createSync();
      expect(git(code, ['init', '-q']).exitCode, 0);
      File('${code.path}/lib/a.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('one\n');
      commitAll(code, 'first');
      final first = (git(code, ['rev-parse', 'HEAD']).stdout as String).trim();
      File('${code.path}/lib/a.dart').writeAsStringSync('two\n');
      commitAll(code, 'second');

      final base = diffBaseOf(
        _link(code, 'lib/a.dart', _fileFingerprint('one\n', 'lib/a.dart')),
      );

      expect(base?.commit, first);
      expect(
        base?.repo.resolveSymbolicLinksSync(),
        code.resolveSymbolicLinksSync(),
      );
    });

    test('finds the base in a nested repo its code root repo ignores', () {
      final docs = Directory.systemTemp.createTempSync('sync_diff_outer_');
      addTearDown(() => docs.deleteSync(recursive: true));
      expect(git(docs, ['init', '-q']).exitCode, 0);
      File('${docs.path}/.gitignore').writeAsStringSync('/code/\n');
      commitAll(docs, 'docs');
      final code = Directory('${docs.path}/code')..createSync();
      expect(git(code, ['init', '-q']).exitCode, 0);
      File('${code.path}/lib/a.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('one\n');
      commitAll(code, 'first');
      final first = (git(code, ['rev-parse', 'HEAD']).stdout as String).trim();
      File('${code.path}/lib/a.dart').writeAsStringSync('two\n');
      commitAll(code, 'second');

      final base = diffBaseOf(
        _link(
          docs,
          'code/lib/a.dart',
          _fileFingerprint('one\n', 'code/lib/a.dart'),
        ),
      );

      expect(base?.commit, first);
      expect(
        base?.repo.resolveSymbolicLinksSync(),
        code.resolveSymbolicLinksSync(),
      );
    });
  });

  group('SyncDiffBases', () {
    test('gives each link its base from one history read of its files', () {
      write('lib/a.dart', 'a1\n');
      write('lib/b.dart', 'b1\n');
      commitAll(repo, 'first');
      final first = head();
      write('lib/a.dart', 'a2\n');
      commitAll(repo, 'second');
      final second = head();
      write('lib/b.dart', 'b2\n');
      commitAll(repo, 'third');
      final third = head();
      final logs = <List<String>>[];

      final a = _link(
        repo,
        'lib/a.dart',
        _fileFingerprint('a2\n', 'lib/a.dart'),
      );
      final b = _link(
        repo,
        'lib/b.dart',
        _fileFingerprint('b1\n', 'lib/b.dart'),
      );
      final folder = _link(
        repo,
        'lib',
        folderCodeFingerprint([
          FileFingerprint(
            path: 'lib/a.dart',
            fingerprint: _fileFingerprint('a2\n', 'lib/a.dart'),
          ),
          FileFingerprint(
            path: 'lib/b.dart',
            fingerprint: _fileFingerprint('b2\n', 'lib/b.dart'),
          ),
        ]),
      );
      final bases = SyncDiffBases([a, b, folder, a], git: _logsInto(logs));

      expect(
        [
          bases.of(a),
          bases.of(b),
          bases.of(folder),
          bases.of(a),
        ].map((base) => base?.commit),
        [second, first, third, second],
      );
      // One history read for both files, one for the folder.
      expect(logs, hasLength(2));
    });

    test('reads a further page of history only for a file that needs it', () {
      write('lib/b.dart', 'b1\n');
      write('lib/a.dart', 'a1\n');
      commitAll(repo, 'first');
      final first = head();
      for (final text in ['a2\n', 'a3\n', 'a4\n', 'a5\n', 'a6\n']) {
        write('lib/a.dart', text);
        commitAll(repo, text);
      }
      final latest = head();
      final logs = <List<String>>[];
      final a = _link(
        repo,
        'lib/a.dart',
        _fileFingerprint('a6\n', 'lib/a.dart'),
      );
      final b = _link(
        repo,
        'lib/b.dart',
        _fileFingerprint('b1\n', 'lib/b.dart'),
      );
      final bases = SyncDiffBases([a, b], git: _logsInto(logs), limit: 2);

      expect(bases.of(a)?.commit, latest);
      expect(logs, hasLength(1));
      expect(bases.of(b)?.commit, first);
      expect(logs, hasLength(2));
    });

    test('gives no base when git cannot start', () {
      write('lib/a.dart', 'one\n');
      final link = _link(
        repo,
        'lib/a.dart',
        _fileFingerprint('one\n', 'lib/a.dart'),
      );
      final bases = SyncDiffBases(
        [link],
        git: (arguments, {required workingDirectory, environment}) =>
            throw ProcessException('git', arguments, 'git is not on PATH'),
      );

      expect(bases.of(link), isNull);
    });
  });

  group('diffSince', () {
    test('shows the change since the base, a working tree edit included', () {
      write('code/lib/a.dart', 'one\n');
      commitAll(repo, 'first');
      write('code/lib/a.dart', 'two\n');
      commitAll(repo, 'second');
      write('code/lib/a.dart', 'three\n');
      final root = Directory('${repo.path}/code');
      final base = diffBaseOf(
        _link(root, 'lib/a.dart', _fileFingerprint('one\n', 'lib/a.dart')),
      )!;

      final diff = diffSince(base);

      expect(diff, contains('-one'));
      expect(diff, contains('+three'));
    });

    test('of a folder leaves out what its listing leaves out', () {
      write('lib/a.dart', 'a1\n');
      write('lib/.hidden/h.dart', 'h1\n');
      write('lib/nested/n.dart', 'n1\n');
      commitAll(repo, 'first');
      write('lib/a.dart', 'a2\n');
      write('lib/.hidden/h.dart', 'h2\n');
      write('lib/nested/n.dart', 'n2\n');
      final recorded = folderCodeFingerprint([
        FileFingerprint(
          path: 'lib/a.dart',
          fingerprint: _fileFingerprint('a1\n', 'lib/a.dart'),
        ),
      ]);
      final base = diffBaseOf(
        _link(repo, 'lib', recorded),
        nestedRoots: const ['lib/nested'],
      )!;

      final diff = diffSince(base);

      expect(diff, contains('+a2'));
      expect(diff, isNot(contains('h2')));
      expect(diff, isNot(contains('n2')));
    });

    // D14
    test('of a folder holding a tracked file .gitignore ignores finds the '
        'base the code root lister fingerprints and leaves the file out', () {
      write('.gitignore', '*.g.dart\n');
      write('lib/a.dart', 'a1\n');
      write('lib/gen/out.g.dart', 'g1\n');
      expect(git(repo, ['add', '-A']).exitCode, 0);
      expect(git(repo, ['add', '-f', 'lib/gen/out.g.dart']).exitCode, 0);
      expect(git(repo, ['commit', '-q', '-m', 'first']).exitCode, 0);
      final tracked = head();
      final recorded = folderCodeFingerprint([
        for (final path in filesUnderCodeRoot(repo, 'lib'))
          FileFingerprint(
            path: path,
            fingerprint: _fileFingerprint(
              File('${repo.path}/$path').readAsStringSync(),
              path,
            ),
          ),
      ]);
      write('lib/a.dart', 'a2\n');
      write('lib/gen/out.g.dart', 'g2\n');

      final base = diffBaseOf(_link(repo, 'lib', recorded));

      expect(base?.commit, tracked);
      final diff = diffSince(base!);
      expect(diff, contains('+a2'));
      expect(diff, isNot(contains('g2')));
    });
  });

  group('diffSince of a base holding the working tree content', () {
    test('is empty when nothing changed', () {
      write('lib/a.dart', 'one\n');
      commitAll(repo, 'first');
      final base = diffBaseOf(
        _link(repo, 'lib/a.dart', _fileFingerprint('one\n', 'lib/a.dart')),
      )!;

      expect(diffSince(base), isEmpty);
    });

    test('still shows a mode change', () {
      write('lib/a.dart', 'one\n');
      commitAll(repo, 'first');
      expect(
        Process.runSync('chmod', ['+x', '${repo.path}/lib/a.dart']).exitCode,
        0,
      );
      final base = diffBaseOf(
        _link(repo, 'lib/a.dart', _fileFingerprint('one\n', 'lib/a.dart')),
      )!;

      expect(diffSince(base), contains('new mode 100755'));
    }, skip: Platform.isWindows ? 'Windows keeps no file mode' : null);
  });

  group('untrackedUnder', () {
    test('lists an untracked file under a folder prefix', () {
      write('code/lib/a.dart', 'one\n');
      commitAll(repo, 'first');
      write('code/lib/new.dart', 'new\n');
      write('code/lib/.hidden/h.dart', 'h\n');
      write('code/other/x.dart', 'x\n');
      final root = Directory('${repo.path}/code');

      expect(untrackedUnder(root, 'lib'), ['lib/new.dart']);
    });

    test('leaves out a nested code root', () {
      write('code/lib/a.dart', 'one\n');
      commitAll(repo, 'first');
      write('code/lib/new.dart', 'new\n');
      write('code/lib/inner/x.dart', 'x\n');
      final root = Directory('${repo.path}/code');

      expect(untrackedUnder(root, 'lib', nestedRoots: const ['lib/inner']), [
        'lib/new.dart',
      ]);
    });

    test('gives none outside a repository and throws on another failure', () {
      ProcessResult failing(int code, String stderr) =>
          ProcessResult(0, code, '', stderr);
      final root = Directory.systemTemp;

      expect(
        untrackedUnder(
          root,
          'lib',
          git: (_, {required workingDirectory, environment}) =>
              failing(128, 'fatal: not a git repository'),
        ),
        isEmpty,
      );
      expect(
        () => untrackedUnder(
          root,
          'lib',
          git: (_, {required workingDirectory, environment}) =>
              failing(1, 'fatal: boom'),
        ),
        throwsA(isA<ProcessException>()),
      );
    });
  });
}
