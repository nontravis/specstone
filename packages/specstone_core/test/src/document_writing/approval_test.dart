import 'dart:io';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:test/test.dart';

import '../../helpers/git_repo.dart';
import '../../helpers/temp_tree.dart';
import '../../helpers/write_fixture.dart';

const _approvedText = '# Signup\n\nApproved body.\n';

/// Long enough that git still pairs a drafted copy with it as a rename.
final _longApproved =
    '# Recover\n\n${List.filled(8, 'A step of the flow.\n').join()}';
const _draftText = '---\ndraft: true\n---\n# Signup\n\nDraft body.\n';

/// Whether this machine's `git` can make a SHA-256 repository.
final bool hasSha256Git = () {
  if (!hasGit) return false;
  final probe = Directory.systemTemp.createTempSync('specstone_sha256_');
  try {
    return git(probe, ['init', '-q', '--object-format=sha256']).exitCode == 0;
  } finally {
    probe.deleteSync(recursive: true);
  }
}();

/// Starts a repo in a new temp folder holding [files].
///
/// [sha256] inits with git's SHA-256 object format instead of SHA-1.
Future<Directory> _repo(
  Map<String, String> files, {
  bool sha256 = false,
}) async {
  final root = await writeTree(files);
  expect(
    git(root, ['init', '-q', if (sha256) '--object-format=sha256']).exitCode,
    0,
  );
  expect(git(root, ['config', 'user.name', 't']).exitCode, 0);
  expect(git(root, ['config', 'user.email', 't@t']).exitCode, 0);
  expect(git(root, ['config', 'core.autocrlf', 'false']).exitCode, 0);
  return root;
}

void main() {
  final skipGit = hasGit ? null : 'git is not available';
  final skipSha256 = !hasGit
      ? 'git is not available'
      : hasSha256Git
      ? null
      : 'git cannot make a SHA-256 repository';

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

  test('dw-s03/inv5, HD4: a quoted "approved": true holds approved', () {
    expect(
      holdsApproved(
        Doc.parse('---\ndraft: true\n"approved": true\n---\n# A\n'),
      ),
      isTrue,
    );
    expect(
      approvalOf(Doc.parse("---\ndraft: true\n'approved': true\n---\n# A\n")),
      Approval.approved,
    );
  });

  test('f02/us03/s2, f02/us03/fr02/e01, dw-s03/inv11: the newest committed copy without draft is found', () async {
    final repo = await _repo({'docs/$signupFeature': _approvedText});
    commitAll(repo, 'approved');
    File('${repo.path}/docs/$signupFeature').writeAsStringSync(_draftText);
    commitAll(repo, 'edited as draft');

    expect(
      const ApprovalHistory().lastApproved(repo, 'docs/$signupFeature'),
      isA<ApprovedCopy>().having((c) => c.text, 'text', _approvedText),
    );
  }, skip: skipGit);

  test('f02/us03/fr02/e01, dw-s03/inv11: the approved copy names its commit and path', () async {
    const path = 'docs/$signupFeature';
    final repo = await _repo({path: _approvedText});
    commitAll(repo, 'approved');
    final approvingCommit = (git(repo, ['rev-parse', 'HEAD']).stdout as String)
        .trim();
    File('${repo.path}/$path').writeAsStringSync(_draftText);
    commitAll(repo, 'edited as draft');

    expect(
      const ApprovalHistory().lastApproved(repo, path),
      isA<ApprovedCopy>()
          .having((c) => c.commit, 'commit', approvingCommit)
          .having((c) => c.path, 'path', path),
    );
  }, skip: skipGit);

  test("f02/us03/fr02/e02, dw-s03/inv11: a renamed doc's approved copy names its old path", () async {
    const oldPath = 'docs/$story3';
    const newPath =
        'docs/prds/features/f01_login/us03_recover_account/USER_STORY.md';
    final repo = await _repo({oldPath: _longApproved});
    commitAll(repo, 'approved');
    Directory(File('${repo.path}/$newPath').parent.path)
        .createSync(recursive: true);
    expect(git(repo, ['mv', oldPath, newPath]).exitCode, 0);
    File('${repo.path}/$newPath')
        .writeAsStringSync('---\ndraft: true\n---\n$_longApproved');
    commitAll(repo, 'moved and drafted');

    expect(
      const ApprovalHistory().lastApproved(repo, newPath),
      isA<ApprovedCopy>().having((c) => c.path, 'path', oldPath),
    );
  }, skip: skipGit);

  test('f02/us03/fr02/e01, e15: a project below the repository top-level names '
      'its copy by project path', () async {
    const path = 'docs/$signupFeature';
    final repo = await _repo({'sub/$path': _approvedText});
    commitAll(repo, 'approved');
    File('${repo.path}/sub/$path').writeAsStringSync(_draftText);
    commitAll(repo, 'edited as draft');

    expect(
      const ApprovalHistory().lastApproved(Directory('${repo.path}/sub'), path),
      isA<ApprovedCopy>()
          .having((c) => c.text, 'text', _approvedText)
          .having((c) => c.path, 'path', path),
    );
  }, skip: skipGit);

  test('f02/us03/fr02/e15, H29: a non-ASCII folder above the project strips '
      'from the path', () async {
    const sub = 'my ล็อก';
    const path = 'docs/$signupFeature';
    final repo = await _repo({'$sub/$path': _approvedText});
    // A user's global core.quotepath=false must not hide the quoting.
    expect(git(repo, ['config', 'core.quotepath', 'true']).exitCode, 0);
    commitAll(repo, 'approved');
    File('${repo.path}/$sub/$path').writeAsStringSync(_draftText);
    commitAll(repo, 'edited as draft');

    expect(
      const ApprovalHistory().lastApproved(
        Directory('${repo.path}/$sub'),
        path,
      ),
      isA<ApprovedCopy>().having((c) => c.path, 'path', path),
    );
  }, skip: skipGit);

  test('f02/us03/fr02/e02, e15: a rename inside a project below the '
      'top-level names the old project path', () async {
    const oldPath = 'docs/$story3';
    const newPath =
        'docs/prds/features/f01_login/us03_recover_account/USER_STORY.md';
    final repo = await _repo({'sub/$oldPath': _longApproved});
    commitAll(repo, 'approved');
    Directory(File('${repo.path}/sub/$newPath').parent.path)
        .createSync(recursive: true);
    expect(git(repo, ['mv', 'sub/$oldPath', 'sub/$newPath']).exitCode, 0);
    File('${repo.path}/sub/$newPath')
        .writeAsStringSync('---\ndraft: true\n---\n$_longApproved');
    commitAll(repo, 'moved and drafted');

    expect(
      const ApprovalHistory().lastApproved(
        Directory('${repo.path}/sub'),
        newPath,
      ),
      isA<ApprovedCopy>()
          .having((c) => c.text, 'text', _longApproved)
          .having((c) => c.path, 'path', oldPath),
    );
  }, skip: skipGit);

  test('f02/us03/fr02/e02, e15: a doc renamed in from outside the project '
      'keeps its top-level path', () async {
    const oldPath = 'elsewhere/$story3';
    const newPath = 'docs/$story3';
    final repo = await _repo({oldPath: _longApproved});
    commitAll(repo, 'approved');
    Directory(File('${repo.path}/sub/$newPath').parent.path)
        .createSync(recursive: true);
    expect(git(repo, ['mv', oldPath, 'sub/$newPath']).exitCode, 0);
    File('${repo.path}/sub/$newPath')
        .writeAsStringSync('---\ndraft: true\n---\n$_longApproved');
    commitAll(repo, 'moved and drafted');

    expect(
      const ApprovalHistory().lastApproved(
        Directory('${repo.path}/sub'),
        newPath,
      ),
      isA<ApprovedCopy>()
          .having((c) => c.text, 'text', _longApproved)
          .having((c) => c.path, 'path', oldPath),
    );
  }, skip: skipGit);

  test('f02/us03/fr02/e04: a failing rev-parse is UnknownHistory', () {
    final failing = ApprovalHistory(
      runGit: (arguments, {required workingDirectory}) =>
          arguments.first == 'rev-parse'
          ? ProcessResult(0, 128, '', 'fatal: not a git repository')
          : ProcessResult(0, 0, '', ''),
    );

    expect(
      failing.lastApproved(Directory.systemTemp, 'docs/$story1'),
      isA<UnknownHistory>(),
    );
  });

  test(
    'f02/us03/fr02/e02: --follow reaches the approved copy under its old path',
    () async {
      const oldPath = 'docs/$story3';
      const newPath =
          'docs/prds/features/f01_login/us03_recover_account/USER_STORY.md';
      final repo = await _repo({oldPath: _longApproved});
      commitAll(repo, 'approved');
      Directory(File('${repo.path}/$newPath').parent.path)
          .createSync(recursive: true);
      expect(git(repo, ['mv', oldPath, newPath]).exitCode, 0);
      File('${repo.path}/$newPath')
          .writeAsStringSync('---\ndraft: true\n---\n$_longApproved');
      commitAll(repo, 'moved and drafted');

      expect(
        const ApprovalHistory().lastApproved(repo, newPath),
        isA<ApprovedCopy>().having((c) => c.text, 'text', _longApproved),
      );
    },
    skip: skipGit,
  );

  test('f02/us03/fr02/e02, dw-s03/inv11, FM1: a SHA-256 repository reaches the '
      'approved copy under its old path', () async {
    const oldPath = 'docs/$story3';
    const newPath =
        'docs/prds/features/f01_login/us03_recover_account/USER_STORY.md';
    final repo = await _repo({oldPath: _longApproved}, sha256: true);
    commitAll(repo, 'approved');
    Directory(File('${repo.path}/$newPath').parent.path)
        .createSync(recursive: true);
    expect(git(repo, ['mv', oldPath, newPath]).exitCode, 0);
    File('${repo.path}/$newPath')
        .writeAsStringSync('---\ndraft: true\n---\n$_longApproved');
    commitAll(repo, 'moved and drafted');

    expect(
      const ApprovalHistory().lastApproved(repo, newPath),
      isA<ApprovedCopy>().having((c) => c.text, 'text', _longApproved),
    );
  }, skip: skipSha256);

  test('f02/us03/s3, f02/us03/fr02/e03, f02/us03/fr02/e05: no committed copy without draft is NoApprovedCopy', () async {
    final repo = await _repo({'docs/$signupFeature': _draftText});
    commitAll(repo, 'draft');
    File('${repo.path}/docs/$signupFeature')
        .writeAsStringSync('$_draftText\nMore.\n');
    commitAll(repo, 'still draft');

    expect(
      const ApprovalHistory().lastApproved(repo, 'docs/$signupFeature'),
      isA<NoApprovedCopy>(),
    );
  }, skip: skipGit);

  test(
    'f02/us03/fr02/e03, dw-s03/inv11: a path with no commit is NoApprovedCopy',
    () async {
      final repo = await _repo({'docs/$signupFeature': _approvedText});
      commitAll(repo, 'approved');

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

  test('f02/us03/fr02/e04, dw-s03/inv11, final Important 3: git output that is not UTF-8 makes the history unknown', () {
    final garbled = ApprovalHistory(
      runGit: (_, {required workingDirectory}) =>
          throw const FormatException('Missing extension byte'),
    );
    expect(
      garbled.lastApproved(Directory.systemTemp, 'docs/$story1'),
      isA<UnknownHistory>(),
    );
  });

  test('f02/us03/fr02/e01, dw-s03/inv11, H28: a file deleted and added again finds its older approved copy', () async {
    const path = 'docs/$signupFeature';
    final repo = await _repo({path: _approvedText});
    commitAll(repo, 'approved');
    expect(git(repo, ['rm', '-q', path]).exitCode, 0);
    commitAll(repo, 'deleted');
    File('${repo.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(_draftText);
    commitAll(repo, 'added again as draft');

    expect(
      const ApprovalHistory().lastApproved(repo, path),
      isA<ApprovedCopy>().having((c) => c.text, 'text', _approvedText),
    );
  }, skip: skipGit);

  test('f02/us03/fr02/e01, dw-s03/inv11, H29: a non-ASCII path finds its approved copy', () async {
    const path =
        'docs/prds/features/f01_login/us01_\u0e25\u0e47\u0e2d\u0e01/USER_STORY.md';
    final repo = await _repo({path: _approvedText});
    // A user's global core.quotepath=false must not hide the quoting.
    expect(git(repo, ['config', 'core.quotepath', 'true']).exitCode, 0);
    commitAll(repo, 'approved');
    File('${repo.path}/$path').writeAsStringSync(_draftText);
    commitAll(repo, 'edited as draft');

    expect(
      const ApprovalHistory().lastApproved(repo, path),
      isA<ApprovedCopy>().having((c) => c.text, 'text', _approvedText),
    );
  }, skip: skipGit);

  test(
    'f02/us03/fr02/e04, dw-s03/inv11: a failing git show is UnknownHistory',
    () {
      final sha = 'a' * 40;
      final failing = ApprovalHistory(
        runGit: (arguments, {required workingDirectory}) =>
            switch (arguments.first) {
              'rev-parse' => ProcessResult(0, 0, '\n', ''),
              'log' => ProcessResult(0, 0, '$sha\x00\ndocs/$story1\x00', ''),
              _ => ProcessResult(0, 128, '', 'fatal: bad object'),
            },
      );
      expect(
        failing.lastApproved(Directory.systemTemp, 'docs/$story1'),
        isA<UnknownHistory>(),
      );
    },
  );

  test('dw-s03/inv5: an approved value that is no YAML holds no approval', () {
    final doc = Doc.parse('---\ndraft: true\napproved: [\n---\n# A\n');
    expect(holdsApproved(doc), isFalse);
    expect(approvalOf(doc), Approval.neverApproved);
  });
}
