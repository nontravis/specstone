import 'dart:io';

import 'package:specstone_core/src/canonical_path.dart';
import 'package:specstone_core/src/index_query/folder_prune.dart';
import 'package:specstone_core/src/templates/cleanup_bounds.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../../helpers/forwarding_entities.dart';

const _folders = ['bundles', 'reports'];
// Agent files each folder holds besides plain files; age alone prunes them.
const _agentFiles = {
  'reports': [
    'check.all.txt',
    'get.feature-login.txt',
    'sources/spec.md',
    'sdd-engineer.audit.snapshot.a1b2c3.md',
  ],
};
const _hour = Duration(hours: 1);
const _day = Duration(days: 1);
const _megabyte = 1000000;

void main() {
  late Directory root;
  // Whole seconds: a file system may round a stored time down.
  final now = DateTime.fromMillisecondsSinceEpoch(
    DateTime.now().millisecondsSinceEpoch ~/ 1000 * 1000,
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('folder_prune_');
    for (final name in _folders) {
      Directory('${root.path}/.specstone/$name').createSync(recursive: true);
    }
  });

  tearDown(() {
    // A test may leave a folder read-only.
    _makeWritable(root);
    root.deleteSync(recursive: true);
  });

  Directory folder(String name) => Directory('${root.path}/.specstone/$name');

  /// Makes a file last modified [modified] ago and last read [read] ago, which
  /// defaults to [modified]; a negative span puts a time after `now`.
  File put(
    String name,
    String relative, {
    required Duration modified,
    Duration? read,
    int bytes = 1,
  }) {
    return File('${folder(name).path}/$relative')
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(bytes, 0))
      ..setLastModifiedSync(now.subtract(modified))
      ..setLastAccessedSync(now.subtract(read ?? modified));
  }

  void prune({
    Set<String> keep = const {},
    CleanupBounds bounds = CleanupBounds.defaults,
  }) => pruneSpecstoneFolder(root, keep: keep, bounds: bounds, now: now);

  CleanupBounds boundsOf({
    Duration? bundlesMaxAge,
    int? bundlesMaxBytes,
    Duration? reportsMaxAge,
  }) => CleanupBounds(
    bundlesMaxAge: bundlesMaxAge ?? CleanupBounds.defaults.bundlesMaxAge,
    bundlesMaxBytes: bundlesMaxBytes ?? CleanupBounds.defaults.bundlesMaxBytes,
    reportsMaxAge: reportsMaxAge ?? CleanupBounds.defaults.reportsMaxAge,
  );

  Duration defaultAgeOf(String name) => name == 'bundles'
      ? CleanupBounds.defaults.bundlesMaxAge
      : CleanupBounds.defaults.reportsMaxAge;

  /// Makes a link and returns true; false, with the test skipped, when Windows
  /// refuses it for want of a privilege.
  bool link(String path, String target) {
    try {
      Link(path).createSync(target);
      return true;
    } on FileSystemException {
      if (Platform.isWindows) {
        markTestSkipped('creating a link needs a privilege on Windows');
        return false;
      }
      rethrow;
    }
  }

  for (final name in _folders) {
    group('the age step of $name', () {
      final age = defaultAgeOf(name);

      test('$name deletes a file last used past the age bound', () {
        final old = put(
          name,
          'a.txt',
          modified: age + const Duration(hours: 1),
        );
        final agentFiles = [
          for (final relative in _agentFiles[name] ?? const <String>[])
            put(name, relative, modified: age + const Duration(hours: 1)),
        ];

        prune();

        expect(old.existsSync(), isFalse);
        for (final file in agentFiles) {
          expect(file.existsSync(), isFalse, reason: file.path);
        }
      });

      test('$name keeps a file at the bound and a newer one', () {
        final edge = put(name, 'a.txt', modified: age);
        final fresh = put(name, 'b.txt', modified: _hour);

        prune();

        expect(edge.existsSync(), isTrue);
        expect(fresh.existsSync(), isTrue);
      });

      test(
        '$name keeps a file modified long ago and read within the bound',
        () {
          final read = put(
            name,
            'a.txt',
            modified: age + _day,
            read: const Duration(hours: 2),
          );

          prune();

          expect(read.existsSync(), isTrue);
        },
      );

      test(
        '$name deletes a file whose read and write both lie past the bound',
        () {
          final unread = put(
            name,
            'a.txt',
            modified: age + const Duration(hours: 2),
            read: age + const Duration(hours: 1),
          );

          prune();

          expect(unread.existsSync(), isFalse);
        },
      );

      test('$name keeps the file the run writes and deletes an old other', () {
        final written = put(name, 'a.txt', modified: age + _day);
        final other = put(name, 'b.txt', modified: age + _day);

        prune(keep: {canonicalPath(written.path)});

        expect(written.existsSync(), isTrue);
        expect(other.existsSync(), isFalse);
      });

      test('$name reaches a subfolder and keeps every folder', () {
        final nested = put(name, 'sub/a.txt', modified: age + _day);
        Directory('${folder(name).path}/empty').createSync();

        prune();

        expect(nested.existsSync(), isFalse);
        expect(Directory('${folder(name).path}/sub').existsSync(), isTrue);
        expect(Directory('${folder(name).path}/empty').existsSync(), isTrue);
      });

      test('$name does nothing when its folder is missing', () {
        folder(name).deleteSync(recursive: true);

        expect(prune, returnsNormally);
      });

      test('$name deletes nothing by age for a bound too large for a date', () {
        final old = put(name, 'a.txt', modified: const Duration(days: 4000));
        const huge = Duration(microseconds: 0x7fffffffffffffff);

        expect(
          () => prune(
            bounds: boundsOf(bundlesMaxAge: huge, reportsMaxAge: huge),
          ),
          returnsNormally,
        );

        expect(old.existsSync(), isTrue);
      });

      test('$name keeps a file whose times lie after now', () {
        final future = put(name, 'a.txt', modified: -_day);

        prune();

        expect(future.existsSync(), isTrue);
      });
    });

    group('the links around and inside $name', () {
      final age = defaultAgeOf(name);

      test('$name never follows a link inside it, and keeps the link', () {
        final outside = File('${root.path}/outside.txt')
          ..writeAsStringSync('keep me')
          ..setLastModifiedSync(now.subtract(age + _day))
          ..setLastAccessedSync(now.subtract(age + _day));
        final outsideFolder = Directory('${root.path}/outside')..createSync();
        final inner = File('${outsideFolder.path}/inner.txt')
          ..writeAsStringSync('keep me too')
          ..setLastModifiedSync(now.subtract(age + _day))
          ..setLastAccessedSync(now.subtract(age + _day));
        if (!link('${folder(name).path}/file_link', outside.path)) return;
        if (!link('${folder(name).path}/folder_link', outsideFolder.path)) {
          return;
        }

        prune();

        expect(outside.existsSync(), isTrue);
        expect(inner.existsSync(), isTrue);
        expect(Link('${folder(name).path}/file_link').existsSync(), isTrue);
        expect(Link('${folder(name).path}/folder_link').existsSync(), isTrue);
      });

      test('$name deletes nothing when .specstone is a link', () {
        final elsewhere = Directory('${root.path}/elsewhere')..createSync();
        final old = File('${elsewhere.path}/$name/a.txt')
          ..createSync(recursive: true)
          ..setLastModifiedSync(now.subtract(age + _day))
          ..setLastAccessedSync(now.subtract(age + _day));
        Directory('${root.path}/.specstone').deleteSync(recursive: true);
        if (!link('${root.path}/.specstone', elsewhere.path)) return;

        prune();

        expect(old.existsSync(), isTrue);
      });

      test('$name deletes nothing when it is itself a link', () {
        final elsewhere = Directory('${root.path}/elsewhere')..createSync();
        final old = File('${elsewhere.path}/a.txt')
          ..createSync()
          ..setLastModifiedSync(now.subtract(age + _day))
          ..setLastAccessedSync(now.subtract(age + _day));
        folder(name).deleteSync();
        if (!link(folder(name).path, elsewhere.path)) return;

        prune();

        expect(old.existsSync(), isTrue);
      });
    });

    group('the files $name cannot delete or list', () {
      final age = defaultAgeOf(name);

      test(
        '$name skips a file it cannot delete and goes on',
        () {
          final locked = put(name, 'locked/a.txt', modified: age + _day);
          final other = put(name, 'b.txt', modified: age + _day);
          Process.runSync('chmod', ['555', locked.parent.path]);

          expect(prune, returnsNormally);

          expect(locked.existsSync(), isTrue);
          expect(other.existsSync(), isFalse);
        },
        skip: Platform.isWindows ? 'a read-only folder is a POSIX rule' : null,
      );

      test('$name skips a subfolder it cannot list and goes on', () {
        final hidden = put(name, 'sub/a.txt', modified: age + _day);
        final other = put(name, 'b.txt', modified: age + _day);
        final nested = put(name, 'ok/c.txt', modified: age + _day);
        Process.runSync('chmod', ['000', hidden.parent.path]);

        expect(prune, returnsNormally);

        expect(other.existsSync(), isFalse);
        expect(nested.existsSync(), isFalse);
      }, skip: Platform.isWindows ? 'a mode-000 folder is a POSIX rule' : null);

      test('$name skips a file a handle holds open and goes on', () {
        final held = put(name, 'a.txt', modified: age + _day);
        final other = put(name, 'b.txt', modified: age + _day);
        final handle = held.openSync();
        addTearDown(handle.closeSync);

        expect(prune, returnsNormally);

        expect(held.existsSync(), isTrue);
        expect(other.existsSync(), isFalse);
      }, testOn: 'windows');
    });
  }

  group('the files a folder listing names', () {
    Directory listing(List<FileSystemEntity> entities) =>
        _Listing(folder('bundles'), entities);

    void pruneListed(Directory listed, {int? maxBytes}) => pruneFolderOf(
      listed,
      keep: const {},
      maxAge: _day,
      maxBytes: maxBytes,
      now: now,
    );

    test('a file the age step cannot delete keeps its size in the total', () {
      final stuck = put('bundles', 'a.txt', modified: _day * 9, bytes: 400000);
      final other = put('bundles', 'b.txt', modified: _hour * 3, bytes: 300000);

      pruneListed(listing([_Stuck(stuck), other]), maxBytes: 500000);

      expect(stuck.existsSync(), isTrue);
      expect(other.existsSync(), isFalse);
    });

    test('a file another process deleted keeps its size in the total', () {
      final vanishing = put(
        'bundles',
        'a.txt',
        modified: _day * 9,
        bytes: 400000,
      );
      final other = put('bundles', 'b.txt', modified: _hour * 3, bytes: 300000);

      expect(
        () => pruneListed(
          listing([_Vanishing(vanishing), other]),
          maxBytes: 500000,
        ),
        returnsNormally,
      );

      expect(other.existsSync(), isFalse);
    });

    test('a file gone before its stat is dropped and goes on', () {
      final gone = File('${folder('bundles').path}/gone.txt');
      final other = put('bundles', 'b.txt', modified: _day * 9);

      expect(() => pruneListed(listing([gone, other])), returnsNormally);

      expect(other.existsSync(), isFalse);
    });

    test('a file whose stat fails is dropped, uncounted, and goes on', () {
      final unreadable = put(
        'bundles',
        'a.txt',
        modified: _hour * 2,
        bytes: 400000,
      );
      final other = put('bundles', 'b.txt', modified: _hour * 3, bytes: 400000);

      expect(
        () => pruneListed(
          listing([_Unstatable(unreadable), other]),
          maxBytes: 500000,
        ),
        returnsNormally,
      );

      expect(unreadable.existsSync(), isTrue);
      expect(other.existsSync(), isTrue);
    });
  });

  group('the size step of bundles', () {
    test('bundles delete the least recently used files down to the cap', () {
      final oldest = put('bundles', 'a.txt', modified: _hour * 5, bytes: 100);
      final middle = put('bundles', 'b.txt', modified: _hour * 4, bytes: 100);
      final newest = put('bundles', 'c.txt', modified: _hour * 3, bytes: 100);

      prune(bounds: boundsOf(bundlesMaxBytes: 250));

      expect(oldest.existsSync(), isFalse);
      expect(middle.existsSync(), isTrue);
      expect(newest.existsSync(), isTrue);
    });

    test('bundles keep every file when the total fits the cap', () {
      final first = put('bundles', 'a.txt', modified: _hour * 5, bytes: 100);
      final second = put('bundles', 'b.txt', modified: _hour * 4, bytes: 100);

      prune(bounds: boundsOf(bundlesMaxBytes: 200));

      expect(first.existsSync(), isTrue);
      expect(second.existsSync(), isTrue);
    });

    test(
      'bundles count a file in a subfolder and delete it first when oldest',
      () {
        final nested = put(
          'bundles',
          'sub/a.txt',
          modified: _hour * 5,
          bytes: 100,
        );
        final top = put('bundles', 'b.txt', modified: _hour * 4, bytes: 100);

        prune(bounds: boundsOf(bundlesMaxBytes: 150));

        expect(nested.existsSync(), isFalse);
        expect(top.existsSync(), isTrue);
      },
    );

    test('bundles read a megabyte as 1,000,000 bytes and stop at the cap', () {
      final files = [
        for (var i = 0; i < 6; i++)
          put('bundles', 'f$i.txt', modified: _hour * (6 - i), bytes: 200000),
      ];

      prune(bounds: boundsOf(bundlesMaxBytes: _megabyte));

      expect(files.first.existsSync(), isFalse);
      expect(
        [for (final file in files.skip(1)) file.existsSync()],
        [for (var i = 1; i < 6; i++) true],
      );
    });

    test('bundles delete the first in path order of two equal last uses', () {
      final first = put('bundles', 'a.txt', modified: _hour * 5, bytes: 600000);
      final second = put(
        'bundles',
        'b.txt',
        modified: _hour * 5,
        bytes: 600000,
      );

      prune(bounds: boundsOf(bundlesMaxBytes: 700000));

      expect(first.existsSync(), isFalse);
      expect(second.existsSync(), isTrue);
    });

    test('bundles read the last use as the later of write and read', () {
      final written = put(
        'bundles',
        'a.txt',
        modified: _hour * 9,
        read: _hour * 2,
        bytes: 100,
      );
      final other = put('bundles', 'b.txt', modified: _hour * 5, bytes: 100);

      prune(bounds: boundsOf(bundlesMaxBytes: 150));

      expect(written.existsSync(), isTrue);
      expect(other.existsSync(), isFalse);
    });

    test('bundles keep a file written 5 minutes ago whatever the total', () {
      final fresh = put(
        'bundles',
        'a.txt',
        modified: const Duration(minutes: 5),
        bytes: 400000,
      );
      final older = put('bundles', 'b.txt', modified: _hour * 3, bytes: 400000);

      prune(bounds: boundsOf(bundlesMaxBytes: 100));

      expect(fresh.existsSync(), isTrue);
      expect(older.existsSync(), isFalse);
    });

    test(
      'bundles keep the run files and recent files while the total stays over',
      () {
        final own = put('bundles', 'a.txt', modified: _hour * 5, bytes: 400000);
        final recent = put(
          'bundles',
          'b.txt',
          modified: const Duration(minutes: 30),
          bytes: 400000,
        );
        final older = put(
          'bundles',
          'c.txt',
          modified: _hour * 6,
          bytes: 400000,
        );
        final oldest = put(
          'bundles',
          'd.txt',
          modified: _hour * 7,
          bytes: 400000,
        );

        expect(
          () => prune(
            keep: {canonicalPath(own.path)},
            bounds: boundsOf(bundlesMaxBytes: 100),
          ),
          returnsNormally,
        );

        expect(own.existsSync(), isTrue);
        expect(recent.existsSync(), isTrue);
        expect(older.existsSync(), isFalse);
        expect(oldest.existsSync(), isFalse);
      },
    );

    test('bundles trim a file whose times lie after now last', () {
      final future = put('bundles', 'a.txt', modified: -_day, bytes: 400000);
      final older = put('bundles', 'b.txt', modified: _hour * 3, bytes: 400000);

      prune(bounds: boundsOf(bundlesMaxBytes: 500000));

      expect(older.existsSync(), isFalse);
      expect(future.existsSync(), isTrue);
    });

    test(
      'bundles trim a file whose times lie after now when the cap needs',
      () {
        final future = put('bundles', 'a.txt', modified: -_day, bytes: 400000);
        final older = put(
          'bundles',
          'b.txt',
          modified: _hour * 3,
          bytes: 400000,
        );

        prune(bounds: boundsOf(bundlesMaxBytes: 100));

        expect(older.existsSync(), isFalse);
        expect(future.existsSync(), isFalse);
      },
    );

    test('bundles keep a file dated seconds after now, the cap unmet', () {
      final parallel = put(
        'bundles',
        'a.txt',
        modified: const Duration(seconds: -5),
        bytes: 400000,
      );
      final older = put('bundles', 'b.txt', modified: _hour * 3, bytes: 400000);

      prune(bounds: boundsOf(bundlesMaxBytes: 100));

      expect(older.existsSync(), isFalse);
      expect(parallel.existsSync(), isTrue);
    });

    test('bundles skip a file that is no regular file', () {
      final fifo = File('${folder('bundles').path}/pipe');
      Process.runSync('mkfifo', [fifo.path]);
      Process.runSync('touch', ['-t', '200001010000', fifo.path]);
      final big = put('bundles', 'a.txt', modified: _hour * 3, bytes: 400000);

      expect(
        () => prune(bounds: boundsOf(bundlesMaxBytes: 100)),
        returnsNormally,
      );

      expect(FileSystemEntity.typeSync(fifo.path), FileSystemEntityType.pipe);
      expect(big.existsSync(), isFalse);
    }, skip: Platform.isWindows ? 'a named pipe is a POSIX file' : null);

    test('bundles keep a file at one hour old away from the size step', () {
      final edge = put('bundles', 'a.txt', modified: _hour, bytes: 400000);

      prune(bounds: boundsOf(bundlesMaxBytes: 100));

      expect(edge.existsSync(), isTrue);
    });

    test(
      'bundles skip a file they cannot delete, count it, and try the next',
      () {
        final locked = put(
          'bundles',
          'locked/a.txt',
          modified: _hour * 6,
          bytes: 400000,
        );
        final second = put(
          'bundles',
          'b.txt',
          modified: _hour * 5,
          bytes: 400000,
        );
        final third = put(
          'bundles',
          'c.txt',
          modified: _hour * 4,
          bytes: 400000,
        );
        Process.runSync('chmod', ['555', locked.parent.path]);

        expect(
          () => prune(bounds: boundsOf(bundlesMaxBytes: 700000)),
          returnsNormally,
        );

        expect(locked.existsSync(), isTrue);
        expect(second.existsSync(), isFalse);
        expect(third.existsSync(), isFalse);
      },
      skip: Platform.isWindows ? 'a read-only folder is a POSIX rule' : null,
    );

    test('bundles never count a link toward the total', () {
      final target = File('${root.path}/big.bin')
        ..writeAsBytesSync(List.filled(2 * _megabyte, 0));
      if (!link('${folder('bundles').path}/big_link', target.path)) return;
      final real = put('bundles', 'a.txt', modified: _hour * 5, bytes: 400000);

      prune(bounds: boundsOf(bundlesMaxBytes: 500000));

      expect(real.existsSync(), isTrue);
      expect(target.existsSync(), isTrue);
    });

    test('bundles apply the age step before the size step', () {
      final expired = put(
        'bundles',
        'a.txt',
        modified: _hour * 30,
        bytes: 400000,
      );
      final older = put('bundles', 'b.txt', modified: _hour * 5, bytes: 400000);
      final newer = put('bundles', 'c.txt', modified: _hour * 4, bytes: 400000);

      prune(bounds: boundsOf(bundlesMaxBytes: 900000));

      expect(expired.existsSync(), isFalse);
      expect(older.existsSync(), isTrue);
      expect(newer.existsSync(), isTrue);
    });

    test('reports are never trimmed by size', () {
      final big = put('reports', 'a.txt', modified: _day * 2, bytes: 400000);

      prune(bounds: boundsOf(bundlesMaxBytes: 100));

      expect(big.existsSync(), isTrue);
    });
  });

  group('the bounds read from the config', () {
    CleanupBounds configured(String yaml) =>
        CleanupBounds.fromConfig(loadYaml(yaml) as YamlMap, file: 'config');

    test('bundles take the age and the size bound the config sets', () {
      final kept = put('bundles', 'a.txt', modified: _hour * 30, bytes: 400000);
      final expired = put(
        'bundles',
        'b.txt',
        modified: _hour * 50,
        bytes: 400000,
      );
      final bounds = configured(
        'cleanup:\n  bundles_max_mb: 512\n  bundles_max_age_hours: 48\n',
      );

      prune(bounds: bounds);

      expect(kept.existsSync(), isTrue);
      expect(expired.existsSync(), isFalse);
    });

    test('reports take the age bound the config sets', () {
      final kept = put('reports', 'a.txt', modified: _day * 10);
      final expired = put('reports', 'b.txt', modified: _day * 31);

      prune(bounds: configured('cleanup:\n  reports_max_age_days: 30\n'));

      expect(kept.existsSync(), isTrue);
      expect(expired.existsSync(), isFalse);
    });
  });

  group('isSpecstoneSubfolderOf, a folder right below a project root', () {
    test('a folder below a project root is the own folder', () {
      expect(
        isSpecstoneSubfolderOf(
          '/p',
          '/p/.specstone/bundles',
          'bundles',
          isWindows: false,
        ),
        isTrue,
      );
      expect(
        isSpecstoneSubfolderOf(
          '/p',
          '/p/.specstone/reports',
          'reports',
          isWindows: false,
        ),
        isTrue,
      );
    });
    test('a project at a volume root has one separator before .specstone', () {
      expect(
        isSpecstoneSubfolderOf(
          '/',
          '/.specstone/bundles',
          'bundles',
          isWindows: false,
        ),
        isTrue,
      );
      expect(
        isSpecstoneSubfolderOf(
          r'C:\',
          r'C:\.specstone\bundles',
          'bundles',
          isWindows: true,
        ),
        isTrue,
      );
    });
    test(
      'a folder a link leads elsewhere, deeper, or beside is no own folder',
      () {
        expect(
          isSpecstoneSubfolderOf(
            '/p',
            '/home/me/Documents',
            'bundles',
            isWindows: false,
          ),
          isFalse,
        );
        expect(
          isSpecstoneSubfolderOf(
            '/p',
            '/p/.specstone/bundles/sub',
            'bundles',
            isWindows: false,
          ),
          isFalse,
        );
        expect(
          isSpecstoneSubfolderOf('/p', '/p', 'bundles', isWindows: false),
          isFalse,
        );
        expect(
          isSpecstoneSubfolderOf(
            '/p',
            '/p/.specstone/reports',
            'bundles',
            isWindows: false,
          ),
          isFalse,
        );
      },
    );
  });
}

void _makeWritable(Directory folder) {
  if (Platform.isWindows || !folder.existsSync()) return;
  Process.runSync('chmod', ['-R', 'u+rwx', folder.path]);
}

/// A folder whose listing names [_entities], as a folder does when a file
/// changes between the listing and the read of its time.
final class _Listing extends ForwardingDirectory {
  new(super.inner, this._entities);

  final List<FileSystemEntity> _entities;

  @override
  List<FileSystemEntity> listSync({
    bool recursive = false,
    bool followLinks = true,
  }) => _entities;
}

/// A file another process deletes just before this one does.
final class _Vanishing extends ForwardingFile {
  new(super.inner);

  @override
  void deleteSync({bool recursive = false}) {
    super.deleteSync(recursive: recursive);
    super.deleteSync(recursive: recursive);
  }
}

/// A file no delete removes, as one a handle holds open on Windows.
final class _Stuck extends ForwardingFile {
  new(super.inner);

  @override
  void deleteSync({bool recursive = false}) =>
      throw FileSystemException('delete refused', path);
}

/// A file whose stat fails, as one deleted while it is read does.
final class _Unstatable extends ForwardingFile {
  new(super.inner);

  @override
  FileStat statSync() => throw FileSystemException('stat failed', path);
}
