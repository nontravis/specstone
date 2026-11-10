import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/git_process.dart';
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
    expect(inputs.firstChangeIn(runRealGit), isNull);
  }, skip: hasGit ? null : 'git is not available');

  test('f06 INV-4: a read outside collect records nothing', () async {
    final root = await writeTree({'a.md': 'one\n'});
    final inputs = PlanInputs(root);

    readPlanInput(_in(root, 'a.md'));
    recordTrackedListing('a.md\x00');

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

  test('f06 INV-4: the tracked listing joins as one more line', () async {
    final root = await writeTree({'a.md': 'one\n'});
    final inputs = PlanInputs(root)
      ..collect(() {
        readPlanInput(_in(root, 'a.md'));
        recordTrackedListing('a.md\x00');
      });

    expect(
      inputs.lines,
      'a.md ${_hex('one\n')}\ngit ls-files ${_hex('a.md\x00')}\n',
    );
  });

  test('f06 INV-4: firstChangeIn names an edited file', () async {
    final root = await writeTree({'a.md': 'one\n', 'b.md': 'two\n'});
    final inputs = _recorded(root, ['a.md', 'b.md']);
    expect(inputs.firstChangeIn(runRealGit), isNull);

    _in(root, 'b.md').writeAsStringSync('2\n');

    expect(inputs.firstChangeIn(runRealGit), 'b.md');
  });

  test('f06 INV-4: firstChangeIn names a deleted file, never a raw '
      'FileSystemException', () async {
    final root = await writeTree({'a.md': 'one\n', 'b.md': 'two\n'});
    final inputs = _recorded(root, ['a.md', 'b.md']);

    _in(root, 'a.md').deleteSync();

    expect(inputs.firstChangeIn(runRealGit), 'a.md');
  });

  test('f06 INV-4: firstChangeIn names git ls-files once a new file is '
      'tracked', () async {
    final root = await writeTree({'a.md': 'one\n'});
    expect(git(root, ['init', '-q']).exitCode, 0);
    commitAll(root, 'first');
    final inputs = PlanInputs(root)
      ..collect(() {
        readPlanInput(_in(root, 'a.md'));
        final listing = git(root, ['ls-files', '-z']).stdout as String;
        recordTrackedListing(listing);
      });
    expect(inputs.firstChangeIn(runRealGit), isNull);

    _in(root, 'new.md').writeAsStringSync('new\n');
    expect(git(root, ['add', 'new.md']).exitCode, 0);

    expect(inputs.firstChangeIn(runRealGit), 'git ls-files');
  }, skip: hasGit ? null : 'git is not available');

  test(
    'f06 INV-4: a git that cannot list counts as a changed listing',
    () async {
      final root = await writeTree({'a.md': 'one\n'});
      final inputs = PlanInputs(root)
        ..collect(() => recordTrackedListing('a.md\x00'));
      ProcessResult missingGit(
        List<String> arguments, {
        required String workingDirectory,
        Map<String, String>? environment,
      }) => throw const ProcessException('git', []);

      expect(inputs.firstChangeIn(missingGit), 'git ls-files');
    },
  );
}
