import 'dart:io';
import 'dart:isolate';

import 'package:specstone_core/src/canonical_path.dart';
import 'package:test/test.dart';

import '../helpers/relative_link.dart';
import '../helpers/temp_tree.dart';

const _scope = 'document_writing/delete_doc_subtree/finish_interrupted_move';

final String? _linksUnavailable = Platform.isWindows
    ? 'a link needs a privilege on Windows'
    : null;

void main() {
  group('$_scope: canonicalPath follows a link to a target not made yet', () {
    late Directory base;

    setUp(() async {
      base = Directory(
        (await writeTree({'proj/keep.txt': '', 'outside/keep.txt': ''}))
            .resolveSymbolicLinksSync(),
      );
    });

    String canonical(String relative, {bool strict = false}) =>
        canonicalPath('${base.path}/$relative', strict: strict);

    test('a link to a missing path resolves to where the target would be '
        'made, and the names below it follow', () {
      createRelativeLink('${base.path}/proj/lnk', '../outside/made/here');

      expect(canonical('proj/lnk'), '${base.path}/outside/made/here');
      expect(
        canonical('proj/lnk/x/y.txt'),
        '${base.path}/outside/made/here/x/y.txt',
      );
    }, skip: _linksUnavailable);

    test('a chain of dangling links resolves to the end of the chain', () {
      createRelativeLink('${base.path}/proj/a', 'b');
      createRelativeLink('${base.path}/proj/b', '../outside/gone');

      expect(canonical('proj/a'), '${base.path}/outside/gone');
    }, skip: _linksUnavailable);

    test('an absolute target is followed as it is', () {
      Link('${base.path}/proj/lnk').createSync('${base.path}/outside/gone');

      expect(canonical('proj/lnk'), '${base.path}/outside/gone');
    }, skip: _linksUnavailable);

    test('a link to an existing path resolves as the disk does', () {
      createRelativeLink('${base.path}/proj/lnk', '../outside');

      expect(canonical('proj/lnk/keep.txt'), '${base.path}/outside/keep.txt');
    }, skip: _linksUnavailable);

    test('a link loop stays as named, and strict mode throws on it', () {
      createRelativeLink('${base.path}/proj/a', 'b');
      createRelativeLink('${base.path}/proj/b', 'a');

      expect(canonical('proj/a'), '${base.path}/proj/a');
      expect(canonical('proj/a/x.txt'), '${base.path}/proj/a/x.txt');
      expect(
        () => canonical('proj/a', strict: true),
        throwsA(isA<FileSystemException>()),
      );
    }, skip: _linksUnavailable);

    test('strict mode follows a chain the loop limit does not reach', () {
      createRelativeLink('${base.path}/proj/l0', '../outside/gone');
      for (var i = 1; i < 30; i++) {
        createRelativeLink('${base.path}/proj/l$i', 'l${i - 1}');
      }

      expect(canonical('proj/l29', strict: true), '${base.path}/outside/gone');
    }, skip: _linksUnavailable);

    test('strict mode throws on a dangling chain longer than the limit', () {
      createRelativeLink('${base.path}/proj/l0', '../outside/gone');
      for (var i = 1; i < 60; i++) {
        createRelativeLink('${base.path}/proj/l$i', 'l${i - 1}');
      }

      expect(
        () => canonical('proj/l59', strict: true),
        throwsA(isA<FileSystemException>()),
      );
      expect(canonical('proj/l59'), startsWith('${base.path}/proj/l'));
    }, skip: _linksUnavailable);
  });

  group('$_scope: canonicalPath on a . or .. after a missing name', () {
    late Directory base;

    setUp(() async {
      base = Directory(
        (await writeTree({'proj/keep.txt': ''})).resolveSymbolicLinksSync(),
      );
    });

    for (final (relative, applied) in [
      ('proj/missing/../x.txt', 'proj/x.txt'),
      ('proj/missing/./x.txt', 'proj/missing/x.txt'),
      ('proj/missing/..', 'proj'),
    ]) {
      test('$relative is applied as written, and strict mode throws', () {
        final path = '${base.path}/$relative';

        expect(
          canonicalPath(path),
          withNativeSeparators('${base.path}/$applied'),
        );
        expect(
          () => canonicalPath(path, strict: true),
          throwsA(isA<FileSystemException>()),
        );
      });
    }

    test('a .. after a name that exists is resolved by the disk', () {
      final path = '${base.path}/proj/../proj/new.txt';

      expect(
        canonicalPath(path, strict: true),
        '${base.path}${Platform.pathSeparator}proj${Platform.pathSeparator}'
        'new.txt',
      );
    });
  });

  group('$_scope: canonicalPath on a path that vanishes mid-resolve', () {
    const churnFor = Duration(seconds: 2);

    test('a file another isolate makes and deletes counts as missing, never '
        'as unresolvable', () async {
      final base = await writeTree({'keep.txt': ''});
      final path =
          '${base.resolveSymbolicLinksSync()}${Platform.pathSeparator}'
          'side-file';
      final churn = Isolate.run(() {
        final file = File(path);
        final watch = Stopwatch()..start();
        while (watch.elapsed < churnFor) {
          try {
            file
              ..writeAsBytesSync(const [0])
              ..deleteSync();
          } on FileSystemException {
            // A virus scanner may hold the file on Windows; only the
            // judgments below are counted.
          }
        }
      });

      var refused = 0;
      var rounds = 0;
      final watch = Stopwatch()..start();
      while (watch.elapsed < churnFor) {
        rounds++;
        try {
          expect(canonicalPath(path, strict: true), path);
        } on FileSystemException {
          refused++;
        }
      }
      await churn;

      expect(rounds, greaterThan(0));
      expect(refused, 0, reason: '$refused of $rounds judgments refused');
    });
  });

  group('$_scope: linkTargetPath on POSIX', () {
    test('an absolute target stays as written', () {
      expect(linkTargetPath('/p/proj/lnk', '/x/y', isWindows: false), '/x/y');
    });

    test('a relative target is read from the folder of the link', () {
      expect(
        linkTargetPath('/p/proj/lnk', '../out/y', isWindows: false),
        '/p/proj/../out/y',
      );
      expect(linkTargetPath('/lnk', 'y', isWindows: false), '/y');
    });

    test('a name that looks like a Windows drive is an ordinary relative '
        'name', () {
      expect(
        linkTargetPath('/p/proj/lnk', r'C:\x', isWindows: false),
        r'/p/proj/C:\x',
      );
    });
  });

  group('$_scope: linkTargetPath on Windows', () {
    test('a target that starts with one separator is rooted at the drive of '
        'the link', () {
      expect(
        linkTargetPath(r'C:\proj\lnk', r'\dir\x', isWindows: true),
        r'C:\dir\x',
      );
      expect(
        linkTargetPath(r'D:\a\b\lnk', '/dir/x', isWindows: true),
        r'D:\dir\x',
      );
    });

    test('a rooted target on a network share stays on that share', () {
      expect(
        linkTargetPath(r'\\srv\share\proj\lnk', r'\dir\x', isWindows: true),
        r'\\srv\share\dir\x',
      );
    });

    test(
      'a drive-absolute or UNC target stays as written, with backslashes',
      () {
        expect(
          linkTargetPath(r'C:\proj\lnk', 'D:/x/y', isWindows: true),
          r'D:\x\y',
        );
        expect(
          linkTargetPath(r'C:\proj\lnk', r'\\srv\share\x', isWindows: true),
          r'\\srv\share\x',
        );
      },
    );

    test('a drive-relative target cannot be followed', () {
      for (final target in ['D:name', 'D:', r'z:..\x']) {
        expect(
          () => linkTargetPath(r'C:\proj\lnk', target, isWindows: true),
          throwsA(isA<FileSystemException>()),
          reason: target,
        );
      }
    });

    test('a relative target is read from the folder of the link', () {
      expect(
        linkTargetPath(r'C:\proj\.specstone\lnk', r'..\out\x', isWindows: true),
        r'C:\proj\.specstone\..\out\x',
      );
      expect(linkTargetPath(r'C:\lnk', 'x', isWindows: true), r'C:\x');
    });
  });
}
