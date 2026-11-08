import 'dart:io';

import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/git_process.dart';
import 'package:specstone_core/src/plan_hash.dart';
import 'package:test/test.dart';

import '../helpers/git_repo.dart';
import '../helpers/temp_tree.dart';

const _plan = 'a.md\nb.md\n';

void main() {
  test('ms-r11: outside a git work tree the plan hash covers the plan text '
      'only', () async {
    final root = await writeTree({'keep.txt': 'x\n'});
    expect(planHashOf(_plan, root, runRealGit), baseHashOf(_plan));
  });

  test('ms-r11: a git that cannot start leaves the plan text only', () async {
    final root = await writeTree({'keep.txt': 'x\n'});
    ProcessResult missingGit(
      List<String> arguments, {
      required String workingDirectory,
      Map<String, String>? environment,
    }) => throw const ProcessException('git', []);
    expect(planHashOf(_plan, root, missingGit), baseHashOf(_plan));
  });

  test('ms-r11: inside a git work tree the plan hash covers HEAD, so a new '
      'commit changes it', () async {
    final root = await writeTree({'keep.txt': 'x\n'});
    expect(git(root, ['init', '-q']).exitCode, 0);
    expect(
      planHashOf(_plan, root, runRealGit),
      baseHashOf(_plan),
      reason: 'a repository with no commit has no HEAD yet',
    );
    commitAll(root, 'first');
    final first = planHashOf(_plan, root, runRealGit);
    expect(first, isNot(baseHashOf(_plan)));
    expect(planHashOf(_plan, root, runRealGit), first);

    File('${root.path}/keep.txt').writeAsStringSync('y\n');
    commitAll(root, 'second');
    expect(planHashOf(_plan, root, runRealGit), isNot(first));
  }, skip: hasGit ? null : 'git is not available');
}
