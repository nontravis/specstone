@TestOn('!windows')
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:test/test.dart';

import '../helpers/install_local_repo.dart';

const _fr =
    'install_update/machine_install/install_local_build/'
    'build_and_place_branch';
const _story = 'install_update/machine_install/install_local_build';

void main() {
  late String tool;
  late InstallLocalRepo repo;
  late Map<String, String> before;

  setUpAll(() async => tool = await compileInstallLocal());

  setUp(() async {
    repo = await createInstallLocalRepo();
    repo.sandbox.installFake();
    before = repo.sandbox.snapshot();
  });

  // A refusal changes nothing: the install, the worktree list, and the temp
  // folder are as they were, and no build step ran.
  void expectNothingChanged() {
    expect(repo.sandbox.snapshot(), before);
    expect(repo.worktrees(), hasLength(1));
    expect(repo.sandbox.logOf('dart'), isEmpty);
    expect(repo.tmpIsEmpty, isTrue);
  }

  test(
    '$_fr E01: an unknown ref is refused by name before any worktree exists',
    () async {
      final result = await repo.run(tool, args: ['--branch', 'nope']);

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('nope'));
      expectNothingChanged();
    },
  );

  test('$_fr E01: a dash-led ref is refused before git runs', () async {
    for (final ref in ['-x', '--upload-pack=x']) {
      final result = await repo.run(tool, args: ['--branch', ref]);

      expect(result.exitCode, isNot(0), reason: ref);
      expect(result.stderr, contains(ref), reason: ref);
      expect(repo.sandbox.logOf('git'), isEmpty, reason: ref);
      expectNothingChanged();
    }
  });

  test('$_fr design R6: an argument list the tool does not take exits 1 '
      'before any git call', () async {
    for (final args in [
      ['--force'],
      ['--branch'],
      ['develop'],
      ['--branch', 'develop', 'extra'],
    ]) {
      final result = await repo.run(tool, args: args);

      expect(result.exitCode, 1, reason: '$args');
      expect(repo.sandbox.logOf('git'), isEmpty, reason: '$args');
      expectNothingChanged();
    }
  });

  test(
    '$_fr E01: a git failure other than a missing ref keeps its own error',
    () async {
      final plain = await Directory('${repo.sandbox.root.path}/plain').create();

      final result = await Process.run(
        tool,
        const [],
        workingDirectory: plain.path,
        environment: repo.sandbox.env(),
        includeParentEnvironment: false,
      );

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('not a git repository'));
      expect(result.stderr, isNot(contains('branch not found')));
      expectNothingChanged();
    },
  );

  test('$_story S5: checkoutState() is equal across a refused ref', () async {
    File('${repo.work.path}/marker.txt').writeAsStringSync('changed\n');
    File('${repo.work.path}/untracked.txt').writeAsStringSync('new\n');
    final stateBefore = await repo.checkoutState();

    final result = await repo.run(tool, args: ['--branch', 'nope']);

    expect(result.exitCode, isNot(0));
    expect(await repo.checkoutState(), stateBefore);
  });
}
