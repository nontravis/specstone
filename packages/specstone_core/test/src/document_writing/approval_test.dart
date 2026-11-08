import 'dart:io';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../../helpers/git_repo.dart';
import '../../helpers/temp_tree.dart';
import '../../helpers/write_fixture.dart';

const _approvedText = '# Signup\n\nApproved body.\n';

/// Long enough that git still pairs a drafted copy with it as a rename.
final _longApproved =
    '# Recover\n\n${List.filled(8, 'A step of the flow.\n').join()}';
const _draftText = '---\ndraft: true\n---\n# Signup\n\nDraft body.\n';

const _docType = MergedDocType(
  id: 'fr',
  generators: ['scenario_copy'],
  fields: [
    MergedField(id: 'slug', type: FieldType.string, list: true),
    MergedField(id: 'status', type: FieldType.string),
    MergedField(id: 'draft', type: FieldType.boolean),
    MergedField(id: 'approved', type: FieldType.string),
    MergedField(
      id: 'implements',
      type: FieldType.outputRef,
      list: true,
      pointer: PointerKind.exact,
    ),
  ],
  sections: [MergedSection(id: 'statement', header: 'Statement')],
  lint: MergedLint(),
  files: [],
);

/// An index entry whose frontmatter is [lines] as the index stores values.
IndexedDoc _indexed(String lines) {
  final map = loadYaml(lines) as YamlMap;
  return IndexedDoc(
    docPath: 'a.md',
    name: 'a',
    frontmatter: {
      for (final e in map.entries)
        '${e.key}': switch (e.value) {
          double(isInfinite: true) => '.inf',
          final Object? v => v,
        },
    },
    tokens: 1,
  );
}

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

  group('stampsHaveRun', () {
    PackVersion v(String text) => PackVersion.parse(text, file: 'x', key: 'x');
    for (final (pins, expected) in [
      ({'prd-core': '1.6.0', 'software-tech': '1.3.0'}, false),
      ({'prd-core': '1.7.0', 'software-tech': '1.3.0'}, true),
      ({'prd-core': '1.6.0', 'software-tech': '1.4.0'}, true),
      ({'prd-core': '1.6.9'}, false),
      ({'prd-core': '1.8.0'}, true),
      (<String, String>{'acme': '9.0.0'}, false),
    ]) {
      test('dw-s03/approval, walk_drafts E12: pins $pins -> $expected', () {
        expect(
          stampsHaveRun({for (final e in pins.entries) e.key: v(e.value)}),
          expected,
        );
      });
    }
  });

  group('approvalHashOf', () {
    const body =
        '---\nstatus: planned\nimplements:\n  - a.dart:one\n---\n\n'
        '# Doc\n\n## Statement\n\nThe system shall do it.\n\n'
        '| a | b |\n|---|---|\n| x | y |\n';
    String hash(String text) => approvalHashOf(text, _docType);

    test('dw-s03/approvalhash: 12 lowercase hex characters', () {
      expect(hash(body), matches(RegExp(r'^[0-9a-f]{12}$')));
    });

    test('report_stale_approvals E02: padded cells give the same hash', () {
      final padded = body.replaceFirst(
        '| a | b |\n|---|---|\n| x | y |',
        '| a   | b   |\n|-----|-----|\n| x   | y   |',
      );
      expect(padded, isNot(body));
      expect(hash(padded), hash(body));
    });

    test(
      'report_stale_approvals E02: a blank line under a heading is ignored',
      () {
        final spaced = body.replaceFirst('## Statement\n\n', '## Statement\n');
        expect(spaced, isNot(body));
        expect(hash(spaced), hash(body));
      },
    );

    test('CRLF line ends hash as LF once the caller converts', () {
      expect(hash(toLf(body.replaceAll('\n', '\r\n'))), hash(body));
    });

    test('report_stale_approvals E03: a changed implements entry keeps it', () {
      expect(hash(body.replaceFirst('a.dart:one', 'b.dart:two')), hash(body));
    });

    test(
      'mark_doc_approved: the approved and draft key blocks are not hashed',
      () {
        final marked = body.replaceFirst(
          'status: planned\n',
          'draft: true\nstatus: planned\napproved: "0123456789ab"\n',
        );
        expect(hash(marked), hash(body));
      },
    );

    test(
      'report_stale_approvals E03: a refreshed generated block keeps it',
      () {
        String withBlock(String inner) =>
            '$body\n${generatedOpenMarker('scenario_copy')}\n$inner'
            '$generatedEndMarker\n';
        expect(hash(withBlock('first\n')), hash(withBlock('second\n')));
      },
    );

    test('report_stale_approvals E02: one changed sentence differs', () {
      expect(
        hash(body.replaceFirst('shall do it', 'shall not do it')),
        isNot(hash(body)),
      );
    });

    test('an untyped doc hashes its text as written', () {
      expect(approvalHashOf('# A\n', null), baseHashOf('# A\n'));
    });
  });

  group('withApprovalHash', () {
    const draft =
        '---\ndraft: true\nstatus: planned\n---\n\n# Doc\n\n'
        '## Statement\n\nText.\n';

    test('mark_doc_approved E11: the double-quoted hash at the field slot', () {
      final written = withApprovalHash(draft, _docType);
      final hash = approvalHashOf(draft, _docType);
      expect(
        written,
        '---\ndraft: true\nstatus: planned\napproved: "$hash"\n---\n\n'
        '# Doc\n\n## Statement\n\nText.\n',
      );
    });

    test('mark_doc_approved E11: replaces approved: true in place', () {
      const old =
          '---\napproved: true\nstatus: planned\n---\n\n# Doc\n\n'
          '## Statement\n\nText.\n';
      final written = withApprovalHash(old, _docType);
      expect(
        written,
        startsWith(
          '---\napproved: "${approvalHashOf(old, _docType)}"\n'
          'status: planned\n',
        ),
      );
      expect(written, isNot(contains('approved: true')));
    });

    test('a doc carrying its own hash hashes to that hash', () {
      final written = withApprovalHash(draft, _docType);
      expect(
        approvalHashOf(written, _docType),
        approvalHashOf(draft, _docType),
      );
    });
  });

  group('approval rules', () {
    const hash = '5d1e0c4b7a92';
    // (label, frontmatter lines, awaits below pins, awaits at pins,
    // approvalOf below pins, approvalOf at pins, guarded)
    final rows = <(String, String, bool, bool, Approval, Approval, bool)>[
      (
        'draft: true',
        'draft: true',
        true,
        true,
        Approval.neverApproved,
        Approval.neverApproved,
        false,
      ),
      (
        'a matching hash',
        'approved: "$hash"',
        false,
        false,
        Approval.approved,
        Approval.approved,
        true,
      ),
      (
        'a stale hash',
        'approved: "0123456789ab"',
        true,
        true,
        Approval.approved,
        Approval.approved,
        true,
      ),
      (
        'approved: true',
        'approved: true',
        false,
        true,
        Approval.approved,
        Approval.approved,
        true,
      ),
      (
        'neither key',
        'status: planned',
        false,
        true,
        Approval.approved,
        Approval.unmarked,
        true,
      ),
      (
        'an unquoted 12-digit value',
        'approved: 123456789012',
        true,
        true,
        Approval.approved,
        Approval.approved,
        true,
      ),
      (
        'a quoted 12-digit value',
        'approved: "123456789012"',
        true,
        true,
        Approval.approved,
        Approval.approved,
        true,
      ),
      (
        'a float-shaped 12-character value',
        'approved: 123e45678901',
        true,
        true,
        Approval.approved,
        Approval.approved,
        true,
      ),
    ];
    for (final (
          label,
          lines,
          belowAwaits,
          atAwaits,
          belowApproval,
          atApproval,
          guarded,
        )
        in rows) {
      for (final fields in [
        ('Doc', ApprovalFields.of(Doc.parse('---\n$lines\n---\n# A\n'))),
        ('IndexedDoc', ApprovalFields.ofIndexed(_indexed(lines))),
      ]) {
        final (reader, f) = fields;
        test('walk_drafts E11-E14, dw-s03/approval: $label via $reader', () {
          expect(
            awaitsApproval(f, hash, stampsHaveRun: false),
            belowAwaits,
            reason: 'awaits below pins',
          );
          expect(
            awaitsApproval(f, hash, stampsHaveRun: true),
            atAwaits,
            reason: 'awaits at pins',
          );
          expect(approvalOf(f, stampsHaveRun: false), belowApproval);
          expect(approvalOf(f, stampsHaveRun: true), atApproval);
          expect(isGuarded(f), guarded);
        });
      }
    }

    test('a doc with no frontmatter is unmarked at the pins', () {
      final f = ApprovalFields.of(Doc.parse('# A\n'));
      expect(approvalOf(f, stampsHaveRun: true), Approval.unmarked);
      expect(approvalOf(f, stampsHaveRun: false), Approval.approved);
    });

    test('dw-s03/inv5: an approved value that is no YAML holds no value', () {
      final f = ApprovalFields.of(
        Doc.parse('---\ndraft: true\napproved: [\n---\n# A\n'),
      );
      expect(approvalOf(f, stampsHaveRun: false), Approval.neverApproved);
    });

    test('HD4: a quoted "approved" key is read', () {
      final f = ApprovalFields.of(
        Doc.parse('---\ndraft: true\n"approved": true\n---\n# A\n'),
      );
      expect(approvalOf(f, stampsHaveRun: false), Approval.approved);
    });
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
}
