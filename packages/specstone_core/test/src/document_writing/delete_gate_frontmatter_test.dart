import 'dart:io';

import 'package:specstone_core/src/document_writing/delete_doc.dart';
import 'package:specstone_core/src/document_writing/owner_confirmation.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:test/test.dart';

import '../../helpers/git_repo.dart';
import '../../helpers/no_generators.dart';
import '../../helpers/write_fixture.dart';

const _target = 'fr:login/reset_password/expire_reset_link';

String _fr(String front) =>
    '---\n$front'
    'traced_from: US-03\nverify_method: test\n---\n\n# Expire reset link\n';

void _delete(Directory root) => writeIn(
  root,
  (session) => answerDelete(
    session,
    const [_target],
    confirmation: OwnerConfirmation.missing,
    readLine: () => null,
    prompts: StringBuffer(),
    generators: noGenerators,
  ),
);

Directory _initRepo(Directory root) {
  expect(git(root, ['init', '-q']).exitCode, 0);
  commitAll(root, 'first');
  return root;
}

void main() {
  test('a doc that keeps approved in its frontmatter stays guarded when no '
      'commit holds an approved copy', () async {
    final root = await writeWriteProject(
      extra: {'docs/$fr32': _fr('draft: true\n')},
    );
    _initRepo(root);
    docFile(
      root,
      fr32,
    ).writeAsStringSync(_fr('draft: true\napproved: "0123456789ab"\n'));

    expect(
      () => _delete(root),
      throwsA(
        isA<WriteFault>().having(
          (f) => f.code,
          'code',
          WriteFaultCode.ownerTerminalRequired,
        ),
      ),
    );
    expect(hasDoc(root, fr32), isTrue);
  }, skip: hasGit ? null : 'git is not available');

  test('a draft whose history holds an approved copy is not guarded, since '
      'its frontmatter holds no approved value', () async {
    final root = await writeWriteProject(
      extra: {'docs/$fr32': _fr('approved: "0123456789ab"\n')},
    );
    _initRepo(root);
    docFile(root, fr32).writeAsStringSync(_fr('draft: true\n'));
    commitAll(root, 'edited as a draft');

    _delete(root);

    expect(hasDoc(root, fr32), isFalse);
  }, skip: hasGit ? null : 'git is not available');
}
