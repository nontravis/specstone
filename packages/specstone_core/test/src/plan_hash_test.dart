import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/plan_hash.dart';
import 'package:test/test.dart';

import '../helpers/git_repo.dart';
import '../helpers/temp_tree.dart';

const _plan = 'a.md\nb.md\n';

String _hex(String text) => sha256.convert(utf8.encode(text)).toString();

File _in(Directory root, String path) => File('${root.path}/$path');

/// Records every file of [paths] under [root] the way a planner read does.
PlanInputs _recorded(Directory root, List<String> paths) {
  final inputs = PlanInputs(root)
    ..collect(() {
      for (final path in paths) {
        readPlanInput(_in(root, path));
      }
    });
  return inputs;
}

void main() {
  test('f06 INV-4: the hash is the baseHashOf of the plan text followed by one '
      'line per recorded file', () async {
    final root = await writeTree({'b/two.md': 'two\n', 'a/one.md': 'one\n'});
    final inputs = _recorded(root, ['b/two.md', 'a/one.md']);

    final lines = 'a/one.md ${_hex('one\n')}\nb/two.md ${_hex('two\n')}\n';

    expect(inputs.lines, lines);
    expect(planHashOf(_plan, inputs), baseHashOf('$_plan$lines'));
  });

  test('f06 INV-4: one changed byte changes the hash', () async {
    final root = await writeTree({'a.md': 'one\n'});
    final inputs = _recorded(root, ['a.md']);
    final before = planHashOf(_plan, inputs);

    _in(root, 'a.md').writeAsStringSync('One\n');

    expect(planHashOf(_plan, _recorded(root, ['a.md'])), isNot(before));
    expect(planHashOf('$_plan.', inputs), isNot(before));
  });

  test('f06 INV-4: a plan that read no file hashes its text alone', () async {
    final root = await writeTree({'keep.txt': 'x\n'});

    expect(planHashOf(_plan, PlanInputs(root)), baseHashOf(_plan));
  });

  test('f06 INV-4: a commit that touches no input leaves the hash', () async {
    final root = await writeTree({'keep.txt': 'x\n', 'other.txt': 'y\n'});
    expect(git(root, ['init', '-q']).exitCode, 0);
    commitAll(root, 'first');
    final inputs = _recorded(root, ['keep.txt']);
    final before = planHashOf(_plan, inputs);

    _in(root, 'other.txt').writeAsStringSync('z\n');
    commitAll(root, 'second');

    expect(planHashOf(_plan, inputs), before);
    expect(planHashOf(_plan, _recorded(root, ['keep.txt'])), before);
  }, skip: hasGit ? null : 'git is not available');

  test('f06 INV-4: a read outside collect records nothing', () async {
    final root = await writeTree({'a.md': 'one\n'});
    final inputs = PlanInputs(root);

    readPlanInput(_in(root, 'a.md'));
    recordTrackedAnswer('a.md', isTracked: true);

    expect(inputs.lines, isEmpty);
  });

  test('f06 INV-4: a path read twice keeps one line, its first hash', () async {
    final root = await writeTree({'a.md': 'one\n'});
    final inputs = PlanInputs(root)
      ..collect(() {
        readPlanInput(_in(root, 'a.md'));
        _in(root, 'a.md').writeAsStringSync('two\n');
        readPlanInput(_in(root, 'a.md'));
      });

    expect(inputs.lines, 'a.md ${_hex('one\n')}\n');
  });

  test('f06 INV-4: paths sort by code point, so a path past U+FFFF comes '
      'after U+FFFD', () async {
    final root = await writeTree({
      'a/\u{1F600}.md': 'astral\n',
      'a/\u{FFFD}.md': 'bmp\n',
    });
    final inputs = _recorded(root, ['a/\u{1F600}.md', 'a/\u{FFFD}.md']);

    expect(
      inputs.lines,
      'a/\u{FFFD}.md ${_hex('bmp\n')}\n'
      'a/\u{1F600}.md ${_hex('astral\n')}\n',
    );
  });

  test(
    r'f06 INV-4: a backslash in a name is no separator on POSIX, so a\b.md and '
    'a/b.md keep two lines',
    () async {
      final root = await writeTree({r'a\b.md': 'one\n', 'a/b.md': 'two\n'});
      final inputs = _recorded(root, [r'a\b.md', 'a/b.md']);

      expect(
        inputs.lines,
        'a/b.md ${_hex('two\n')}\n${r'a\b.md'} ${_hex('one\n')}\n',
      );
    },
    skip: Platform.isWindows ? 'a backslash separates paths on Windows' : null,
  );

  test('f06 INV-4: a file outside the project root enters by its absolute '
      'path', () async {
    final root = await writeTree({'a.md': 'one\n'});
    final home = await writeTree({'pack.yaml': 'name: x\n'});
    final inputs = PlanInputs(root)
      ..collect(() => readPlanInput(_in(home, 'pack.yaml')));

    expect(
      inputs.lines,
      '${_in(home, 'pack.yaml').absolute.path} ${_hex('name: x\n')}\n',
    );
  });

  test('f06 INV-4: a read that fails keeps its path, relative as a successful '
      'read is keyed, and the failure still throws', () async {
    final root = await writeTree({'a.md': 'one\n'});
    final inputs = PlanInputs(root);

    expect(
      () => inputs.collect(() {
        readPlanInput(_in(root, 'a.md'));
        readPlanInput(_in(root, 'sub/gone.md'));
      }),
      throwsA(isA<FileSystemException>()),
    );

    expect(inputs.firstUnreadable, 'sub/gone.md');
    expect(inputs.lines, 'a.md ${_hex('one\n')}\n');
  });

  test('f06 INV-4: the first failed read is the one kept', () async {
    final root = await writeTree({'a.md': 'one\n'});
    final inputs = PlanInputs(root)
      ..collect(() {
        for (final path in ['first.md', 'second.md']) {
          try {
            readPlanInput(_in(root, path));
          } on FileSystemException {
            // The recorder keeps the first failure; the plan goes on.
          }
        }
      });

    expect(inputs.firstUnreadable, 'first.md');
  });

  test('f06 INV-4: no read failed, no path is kept', () async {
    final root = await writeTree({'a.md': 'one\n'});

    expect(_recorded(root, ['a.md']).firstUnreadable, isNull);
  });

  test('f06 INV-4: a failed read inside a plan that collects for itself is '
      'kept by the recorder around it too', () async {
    final root = await writeTree({'a.md': 'one\n'});
    final outer = PlanInputs(root);
    final inner = PlanInputs(root);

    expect(
      () => outer.collect(
        () => inner.collect(() => readPlanInput(_in(root, 'gone.md'))),
      ),
      throwsA(isA<FileSystemException>()),
    );

    expect(inner.firstUnreadable, 'gone.md');
    expect(outer.firstUnreadable, 'gone.md');
  });

  test('f06 INV-4: a failed read outside collect records nothing', () async {
    final root = await writeTree({'a.md': 'one\n'});
    final inputs = PlanInputs(root);

    expect(
      () => readPlanInput(_in(root, 'gone.md')),
      throwsA(isA<FileSystemException>()),
    );

    expect(inputs.firstUnreadable, isNull);
  });

  test('f06 INV-4: a tracked answer joins as one line per path, after the '
      'file lines, in code point order', () async {
    final root = await writeTree({'a.md': 'one\n'});
    final inputs = PlanInputs(root)
      ..collect(() {
        readPlanInput(_in(root, 'a.md'));
        recordTrackedAnswer('lib/z.dart', isTracked: false);
        recordTrackedAnswer('lib/b.dart', isTracked: true);
        recordTrackedAnswer('lib/b.dart', isTracked: false);
      });

    expect(
      inputs.lines,
      'a.md ${_hex('one\n')}\nlib/b.dart tracked\nlib/z.dart untracked\n',
    );
  });

  test('f06 INV-4: a tracked answer outside collect records nothing', () {
    final inputs = PlanInputs(Directory.systemTemp);

    recordTrackedAnswer('lib/a.dart', isTracked: true);

    expect(inputs.lines, isEmpty);
  });

  group('firstDifferenceFrom', () {
    Future<PlanInputs> plan(
      Directory root,
      List<String> files, {
      Map<String, bool> tracked = const {},
    }) async {
      return PlanInputs(root)..collect(() {
        for (final path in files) {
          readPlanInput(_in(root, path));
        }
        for (final MapEntry(:key, :value) in tracked.entries) {
          recordTrackedAnswer(key, isTracked: value);
        }
      });
    }

    test('f06 INV-4: equal lines differ nowhere', () async {
      final root = await writeTree({'a.md': 'one\n'});

      expect(
        (await plan(root, [
          'a.md',
        ])).firstDifferenceFrom(await plan(root, ['a.md'])),
        isNull,
      );
    });

    test('f06 INV-4: an edited file is named', () async {
      final root = await writeTree({'a.md': 'one\n', 'b.md': 'two\n'});
      final before = await plan(root, ['a.md', 'b.md']);

      _in(root, 'b.md').writeAsStringSync('2\n');

      expect(
        before.firstDifferenceFrom(await plan(root, ['a.md', 'b.md'])),
        'b.md',
      );
    });

    test('f06 INV-4: a file one plan read and the other did not is named, '
        'whichever side lacks it', () async {
      final root = await writeTree({'a.md': 'one\n', 'b.md': 'two\n'});
      final fewer = await plan(root, ['a.md']);
      final more = await plan(root, ['a.md', 'b.md']);

      expect(fewer.firstDifferenceFrom(more), 'b.md');
      expect(more.firstDifferenceFrom(fewer), 'b.md');
    });

    test('f06 INV-4: the first differing path in code point order is named, '
        'not the first found', () async {
      final root = await writeTree({
        'a.md': 'one\n',
        'b.md': 'two\n',
        'c.md': 'three\n',
      });
      final before = await plan(root, ['a.md', 'b.md', 'c.md']);

      _in(root, 'c.md').writeAsStringSync('3\n');
      _in(root, 'b.md').writeAsStringSync('2\n');

      expect(
        before.firstDifferenceFrom(await plan(root, ['c.md', 'b.md', 'a.md'])),
        'b.md',
      );
    });

    test('f06 INV-4: a changed tracked answer names its path', () async {
      final root = await writeTree({'a.md': 'one\n'});
      final before = await plan(root, ['a.md'], tracked: {'lib/a.dart': true});
      final after = await plan(root, ['a.md'], tracked: {'lib/a.dart': false});

      expect(before.firstDifferenceFrom(after), 'lib/a.dart');
    });

    test('f06 INV-4: a commit that adds an unasked file differs nowhere, as '
        'the plan never asked git about it', () async {
      final root = await writeTree({'keep.txt': 'x\n'});
      expect(git(root, ['init', '-q']).exitCode, 0);
      commitAll(root, 'first');
      final before = await plan(root, ['keep.txt']);

      _in(root, 'other.txt').writeAsStringSync('z\n');
      commitAll(root, 'second');

      expect(
        before.firstDifferenceFrom(await plan(root, ['keep.txt'])),
        isNull,
      );
    }, skip: hasGit ? null : 'git is not available');
  });

  group('pathFromRoots', () {
    test('f06 INV-4: on Windows a path that mixes `/` into a native root '
        'still reads from that root', () {
      expect(
        pathFromRoots(r'C:\work\project/a/one.md', [
          r'C:\work\project\',
        ], isWindows: true),
        'a/one.md',
      );
    });

    test('f06 INV-4: on Windows a root without a trailing separator holds '
        'its children, and a backslash in the key becomes `/`', () {
      expect(
        pathFromRoots(r'C:\work\project\a\one.md', [
          'C:/work/project',
        ], isWindows: true),
        'a/one.md',
      );
    });

    test('f06 INV-4: a path outside every root stays as given', () {
      expect(
        pathFromRoots(r'C:\home\.specstone/packs/acme/pack.yaml', [
          r'C:\work\project\',
        ], isWindows: true),
        r'C:\home\.specstone/packs/acme/pack.yaml',
      );
    });

    test('f06 INV-4: a sibling folder that shares a prefix is outside', () {
      expect(
        pathFromRoots('/work/project-two/a.md', [
          '/work/project',
        ], isWindows: false),
        '/work/project-two/a.md',
      );
    });

    test('f06 INV-4: on POSIX a backslash is part of a file name', () {
      expect(
        pathFromRoots(r'/work/project/a\b.md', [
          '/work/project',
        ], isWindows: false),
        r'a\b.md',
      );
    });
  });
}
