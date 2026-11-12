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

// WORKAROUND: a name a churning isolate deletes and makes again can answer
// the NTFS deleted-file alias or an empty path on every walk inside the hop
// budget, so the resolve throws when the budget ends; remove when the 1.2.1
// fix of the Windows mid-resolve race lands.
final String? _churnRaceOnWindows = Platform.isWindows
    ? 'the Windows mid-resolve race can outlast the hop budget'
    : null;

/// What Windows answered on CI for a file deleted while it was resolved.
const _deletedAlias = r'C:\$Extend\$Deleted\002200000014DCAD7A7FE315';

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

    for (final (relative, appliedTo) in [
      ('proj/missing/../x.txt', 'proj/x.txt'),
      ('proj/missing/./x.txt', 'proj/missing/x.txt'),
      ('proj/missing/..', 'proj'),
    ]) {
      test('$relative is applied as written, and strict mode throws', () {
        final path = '${base.path}/$relative';
        final applied = withNativeSeparators('${base.path}/$appliedTo');

        expect(canonicalPath(path), applied);
        // Windows collapses a `..` before the disk sees it, so none is left.
        if (Platform.isWindows && relative.contains('..')) {
          expect(canonicalPath(path, strict: true), applied);
          return;
        }
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

      var wrong = 0;
      var rounds = 0;
      Object? firstWrong;
      final watch = Stopwatch()..start();
      try {
        while (watch.elapsed < churnFor) {
          rounds++;
          try {
            final answer = canonicalPath(path, strict: true);
            if (answer == path) continue;
            wrong++;
            firstWrong ??= "the answer '$answer'";
          } on FileSystemException catch (error) {
            wrong++;
            firstWrong ??= error;
          }
        }
      } finally {
        // The churn must stop before the test deletes its folder.
        await churn;
      }

      expect(rounds, greaterThan(0));
      expect(
        wrong,
        0,
        reason:
            '$wrong of $rounds judgments wrong or refused; the first: '
            '$firstWrong',
      );
    }, skip: _churnRaceOnWindows);
  });

  group('$_scope: canonicalPath when the resolve answers for a name deleted '
      'meanwhile', () {
    late String path;

    setUp(() async {
      final base = await writeTree({'side-file': ''});
      path =
          '${base.resolveSymbolicLinksSync()}${Platform.pathSeparator}'
          'side-file';
    });

    test('an NTFS deleted-file answer for a name gone since counts as '
        'missing', () {
      String deleteThenAnswerAlias(String asked) {
        if (asked != path) return realPathOnDisk(asked);
        File(asked).deleteSync();
        return _deletedAlias;
      }

      expect(
        canonicalPath(path, strict: true, resolve: deleteThenAnswerAlias),
        path,
      );
    });

    test('a failure for a name gone since counts as missing, whatever its '
        'code', () {
      String deleteThenFail(String asked) {
        if (asked != path) return realPathOnDisk(asked);
        File(asked).deleteSync();
        throw FileSystemException('', asked, const OSError('denied', 5));
      }

      expect(canonicalPath(path, strict: true, resolve: deleteThenFail), path);
    });

    test('an NTFS deleted-file answer for a name made again since resolves '
        'the name again', () {
      var answered = false;
      String answerAliasOnce(String asked) {
        if (asked != path || answered) return realPathOnDisk(asked);
        answered = true;
        return _deletedAlias;
      }

      expect(canonicalPath(path, strict: true, resolve: answerAliasOnce), path);
    });

    test('an empty answer for a name gone since counts as missing', () {
      String deleteThenAnswerEmpty(String asked) {
        if (asked != path) return realPathOnDisk(asked);
        File(asked).deleteSync();
        return '';
      }

      expect(
        canonicalPath(path, strict: true, resolve: deleteThenAnswerEmpty),
        path,
      );
    });

    test('an empty answer for a name that stays throws', () {
      String answerEmpty(String asked) =>
          asked == path ? '' : realPathOnDisk(asked);

      expect(
        () => canonicalPath(path, resolve: answerEmpty),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('an NTFS deleted-file answer for a name that stays throws', () {
      String answerAlias(String asked) =>
          asked == path ? _deletedAlias : realPathOnDisk(asked);

      expect(
        () => canonicalPath(path, resolve: answerAlias),
        throwsA(isA<FileSystemException>()),
      );
    });

    test(r'an answer elsewhere under $Extend is a real path, since another '
        'file system lets a user make that folder', () {
      const madeByUser = r'C:\$Extend\x';
      String answerMadeByUser(String asked) =>
          asked == path ? madeByUser : realPathOnDisk(asked);

      expect(canonicalPath(path, resolve: answerMadeByUser), madeByUser);
    });
  });

  group('$_scope: canonicalPath when a link changes while it is read', () {
    late String link;

    setUp(() async {
      final base = await writeTree({'keep.txt': ''});
      link = '${base.resolveSymbolicLinksSync()}/x';
      createRelativeLink(link, 'gone');
    });

    test('a link deleted meanwhile counts as missing', () {
      String deleteThenFail(String asked) {
        if (asked != link) return linkTargetOnDisk(asked);
        Link(asked).deleteSync();
        throw FileSystemException('', asked, const OSError('not found', 2));
      }

      expect(canonicalPath(link, strict: true, readLink: deleteThenFail), link);
    }, skip: _linksUnavailable);

    test('a link made a plain file meanwhile resolves as that file, whatever '
        'the code', () {
      String replaceThenFail(String asked) {
        if (asked != link) return linkTargetOnDisk(asked);
        Link(asked).deleteSync();
        File(asked).writeAsStringSync('');
        throw FileSystemException('', asked, const OSError('invalid', 22));
      }

      expect(
        canonicalPath(link, strict: true, readLink: replaceThenFail),
        link,
      );
    }, skip: _linksUnavailable);

    test('a link that stays a link rethrows its read error', () {
      String fail(String asked) =>
          throw FileSystemException('', asked, const OSError('denied', 5));

      expect(
        () => canonicalPath(link, strict: true, readLink: fail),
        throwsA(
          isA<FileSystemException>().having(
            (error) => error.osError?.errorCode,
            'code',
            5,
          ),
        ),
      );
    }, skip: _linksUnavailable);
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
