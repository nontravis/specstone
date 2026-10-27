import 'dart:io';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:test/test.dart';

import '../../helpers/temp_tree.dart';
import '../../helpers/write_fixture.dart';

ProcessResult git(Directory dir, List<String> args) => Process.runSync('git', [
  '-c',
  'user.name=t',
  '-c',
  'user.email=t@t',
  ...args,
], workingDirectory: dir.path);

final bool _hasGit = () {
  try {
    return Process.runSync('git', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}();

const _approvedText = '# Signup\n\nApproved body.\n';

/// Long enough that git still pairs a drafted copy with it as a rename.
final _longApproved =
    '# Recover\n\n${List.filled(8, 'A step of the flow.\n').join()}';
const _draftText = '---\ndraft: true\n---\n# Signup\n\nDraft body.\n';

/// Starts a repo in a new temp folder holding [files].
Future<Directory> _repo(Map<String, String> files) async {
  final root = await writeTree(files);
  expect(git(root, ['init', '-q']).exitCode, 0);
  return root;
}

void _commit(Directory root, String message) {
  expect(git(root, ['add', '-A']).exitCode, 0);
  expect(git(root, ['commit', '-q', '-m', message]).exitCode, 0);
}

void main() {
  final skipGit = _hasGit ? null : 'git is not available';

  test('dw-s03/inv5, f02/us04/fr02/e04, f02/us04/fr02/e05: approval reads the frontmatter only', () {
    expect(
      approvalOf(Doc.parse('---\ndraft: true\n---\n# A\n')),
      Approval.neverApproved,
    );
    expect(
      approvalOf(Doc.parse('---\ndraft: true\napproved: true\n---\n# A\n')),
      Approval.approved,
    );
    expect(approvalOf(Doc.parse('# A\n')), Approval.approved);
  });

  test('dw-s03/inv5, f02/us04/fr02/e04: holdsApproved is true exactly when approved holds YAML true', () {
    expect(
      holdsApproved(Doc.parse('---\ndraft: true\napproved: true\n---\n# A\n')),
      isTrue,
    );
    expect(holdsApproved(Doc.parse('---\napproved: true\n---\n# A\n')), isTrue);
    expect(
      holdsApproved(Doc.parse('---\ndraft: true\napproved: false\n---\n# A\n')),
      isFalse,
    );
    expect(
      holdsApproved(Doc.parse('---\napproved: "true"\n---\n# A\n')),
      isFalse,
    );
    expect(holdsApproved(Doc.parse('---\ndraft: true\n---\n# A\n')), isFalse);
    expect(holdsApproved(Doc.parse('# A\n')), isFalse);
  });

  test('f02/us03/s2, f02/us03/fr02/e01, dw-s03/inv11: the newest committed copy without draft is found', () async {
    final repo = await _repo({'docs/$signupFeature': _approvedText});
    _commit(repo, 'approved');
    File('${repo.path}/docs/$signupFeature').writeAsStringSync(_draftText);
    _commit(repo, 'edited as draft');

    expect(
      const ApprovalHistory().lastApproved(repo, 'docs/$signupFeature'),
      isA<ApprovedCopy>().having((c) => c.text, 'text', _approvedText),
    );
  }, skip: skipGit);

  test(
    'f02/us03/fr02/e02: --follow reaches the approved copy under its old path',
    () async {
      const oldPath = 'docs/$story3';
      const newPath =
          'docs/prds/features/f01_login/us03_recover_account/USER_STORY.md';
      final repo = await _repo({oldPath: _longApproved});
      _commit(repo, 'approved');
      Directory(File('${repo.path}/$newPath').parent.path)
          .createSync(recursive: true);
      expect(git(repo, ['mv', oldPath, newPath]).exitCode, 0);
      File('${repo.path}/$newPath')
          .writeAsStringSync('---\ndraft: true\n---\n$_longApproved');
      _commit(repo, 'moved and drafted');

      expect(
        const ApprovalHistory().lastApproved(repo, newPath),
        isA<ApprovedCopy>().having((c) => c.text, 'text', _longApproved),
      );
    },
    skip: skipGit,
  );

  test('f02/us03/s3, f02/us03/fr02/e03, f02/us03/fr02/e05: no committed copy without draft is NoApprovedCopy', () async {
    final repo = await _repo({'docs/$signupFeature': _draftText});
    _commit(repo, 'draft');
    File('${repo.path}/docs/$signupFeature')
        .writeAsStringSync('$_draftText\nMore.\n');
    _commit(repo, 'still draft');

    expect(
      const ApprovalHistory().lastApproved(repo, 'docs/$signupFeature'),
      isA<NoApprovedCopy>(),
    );
  }, skip: skipGit);

  test(
    'f02/us03/fr02/e03, dw-s03/inv11: a path with no commit is NoApprovedCopy',
    () async {
      final repo = await _repo({'docs/$signupFeature': _approvedText});
      _commit(repo, 'approved');

      expect(
        const ApprovalHistory().lastApproved(repo, 'docs/$story1'),
        isA<NoApprovedCopy>(),
      );
    },
    skip: skipGit,
  );

  test('f02/us03/fr02/e04, dw-s03/inv11: outside a repo, or with git missing, the history is unknown', () async {
    expect(
      const ApprovalHistory().lastApproved(
        await writeWriteProject(),
        'docs/$story1',
      ),
      isA<UnknownHistory>(),
      skip: skipGit,
    );
    final missing = ApprovalHistory(
      runGit: (_, {required workingDirectory}) =>
          throw const ProcessException('git', []),
    );
    expect(
      missing.lastApproved(Directory.systemTemp, 'docs/$story1'),
      isA<UnknownHistory>(),
    );
  });

  test('f02/us03/fr02, dw-s03/inv11: changed hunks name the lines that differ and carry no context', () {
    expect(changedHunks('a\nb\nc\n', 'a\nB\nc\n'), '@@ -2 +2 @@\n-b\n+B\n');
    expect(changedHunks('a\nc\n', 'a\nb\nc\n'), '@@ -1,0 +2 @@\n+b\n');
    expect(changedHunks('a\nb\nc\n', 'a\nc\n'), '@@ -2 +1,0 @@\n-b\n');
    expect(changedHunks('a\n', 'a\n'), '');
  });

  test('f02/us03/fr02, dw-s03/inv11: changed hunks join separate changes and read CRLF as LF', () {
    expect(
      changedHunks('a\nb\nc\nd\ne\n', 'A\nb\nc\nd\nE\nF\n'),
      '@@ -1 +1 @@\n-a\n+A\n@@ -5 +5,2 @@\n-e\n+E\n+F\n',
    );
    expect(changedHunks('a\r\nb\r\n', 'a\nb\n'), '');
    expect(changedHunks('', 'a\n'), '@@ -0,0 +1 @@\n+a\n');
  });
}
