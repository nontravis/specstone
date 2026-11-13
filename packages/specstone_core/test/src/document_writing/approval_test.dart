import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/document_writing/approval_view.dart';
import 'package:specstone_core/src/git_process.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/rendering/formatter.dart' show layOutDoc;
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:test/test.dart';

import '../../helpers/git_repo.dart';
import '../../helpers/temp_tree.dart';
import '../../helpers/write_fixture.dart';

const _approvedBody = '# Signup\n\nApproved body.\n';

/// A committed copy that counts as approved: it carries its own hash.
final String _approvedText = withApprovalHash(_approvedBody, _docType);

/// Long enough that git still pairs a drafted copy with it as a rename.
final String _longBody =
    '# Recover\n\n${List.filled(8, 'A step of the flow.\n').join()}';
final String _longApproved = withApprovalHash(_longBody, _docType);
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

/// The index entry the refresh stores for a doc whose frontmatter is [lines].
IndexedDoc _indexed(String lines) => parseIndexedDoc(
  docPath: 'a.md',
  bytes: utf8.encode('---\n$lines\n---\n# A\n'),
  match: const NoDocType(),
).doc;

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

/// The ApprovalHash recipe as it stood before the one-parse rewrite: every
/// key block spliced by its own parse, the empty frontmatter dropped, then
/// the layout; the persisted hash must never drift from it.
String _referenceHashOf(String lfText, MergedDocType? docType) {
  final kinds = docType?.listedGenerators.toSet() ?? const <String>{};
  var covered = lfText;
  if (kinds.isNotEmpty) {
    final lines = covered.split('\n');
    final generated = generatedBlockLines(lines, kinds);
    covered = [
      for (final (i, line) in lines.indexed)
        if (!generated[i]) line,
    ].join('\n');
  }
  for (final key in [
    'approved',
    'draft',
    for (final field in docType?.fields ?? const <MergedField>[])
      if (field.type == FieldType.outputRef) field.id,
  ]) {
    covered = withKeyBlock(covered, key, null);
  }
  final doc = Doc.parse(covered);
  final blocks = doc.frontmatter;
  if (blocks == null || !blocks.any((b) => b.text.trim().isNotEmpty)) {
    covered = (blocks == null ? covered : doc.afterFrontmatter).replaceFirst(
      RegExp(r'^\n+'),
      '',
    );
  }
  return baseHashOf(layOutDoc(covered, docType)).substring(0, 12);
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
      ({'prd-core': '1.7.0', 'software-tech': '1.4.0'}, true),
      ({'prd-core': '1.6.9'}, false),
      ({'prd-core': '1.8.0'}, true),
      (<String, String>{'acme': '9.0.0'}, false),
    ]) {
      test('domain:document_writing Approval: pins $pins -> $expected', () {
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

    test(
      'domain:document_writing ApprovalHash: 12 lowercase hex characters',
      () {
        expect(hash(body), matches(RegExp(r'^[0-9a-f]{12}$')));
      },
    );

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

    test('an untyped doc hashes its text less approved and draft', () {
      expect(approvalHashOf('# A\n', null), baseHashOf('# A\n'));
      expect(
        approvalHashOf(
          '---\ndraft: true\napproved: "0123456789ab"\n---\n# A\n',
          null,
        ),
        baseHashOf('# A\n'),
      );
    });

    test('mark_doc_approved E09: a block a format run inserts keeps it', () {
      final inserted = switch (writeGeneratedBlocks(body, _docType, [
        const GeneratedBlock(
          kind: 'scenario_copy',
          sectionId: 'statement',
          place: SectionTop(),
          text: 'Copied text.\n',
        ),
      ])) {
        BlocksWritten(:final lfText) => lfText,
        OpenBlock() => fail('the body holds no open block'),
      };
      expect(inserted, isNot(body));
      expect(hash(inserted), hash(body));
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

    for (final (label, text) in [
      ('with frontmatter', draft),
      ('without frontmatter', '# Doc\n\n## Statement\n\nText.\n'),
    ]) {
      test('mark_doc_approved E10, E11: a doc $label matches its stamp', () {
        final written = withApprovalHash(text, _docType);
        final stamp = RegExp('approved: "([0-9a-f]{12})"')
            .firstMatch(written)!
            .group(1);
        expect(approvalHashOf(written, _docType), stamp);
      });
    }

    test('a doc carrying its own hash hashes to that hash', () {
      final written = withApprovalHash(draft, _docType);
      expect(
        approvalHashOf(written, _docType),
        approvalHashOf(draft, _docType),
      );
    });
  });

  group('countsAsApprovedCopy', () {
    const base = '# Signup\n\nBody.\n';
    final hashed = withApprovalHash(base, _docType);

    test('document_writing/approve_drafts/show_changes_since_approval E19, E20: its own hash counts; a stale hash, a draft, '
        'or no mark does not', () {
      expect(countsAsApprovedCopy(hashed, _docType), isTrue);
      expect(
        countsAsApprovedCopy(hashed.replaceFirst('Body', 'Edit'), _docType),
        isFalse,
      );
      expect(
        countsAsApprovedCopy('---\ndraft: true\n---\n$base', _docType),
        isFalse,
      );
      expect(countsAsApprovedCopy(base, _docType), isFalse);
    });

    test('document_writing/approve_drafts/show_changes_since_approval E11: a copy holding its own hash counts, and the '
        'approval view compares it without the mark', () {
      expect(hashed, contains('approved: "'));
      expect(countsAsApprovedCopy(hashed, _docType), isTrue);
      expect(withoutApprovalMarks(hashed), isNot(contains('approved')));
    });

    test('document_writing/approve_drafts/show_changes_since_approval E11: `approved: true` counts, even with no doc type', () {
      expect(
        countsAsApprovedCopy('---\napproved: true\n---\n$base', null),
        isTrue,
      );
    });

    test('document_writing/approve_drafts/show_changes_since_approval E21: an unquoted digits hash is no hash', () {
      expect(
        countsAsApprovedCopy('---\napproved: 123456789012\n---\n$base', null),
        isFalse,
      );
    });
  });

  test(
    'domain:document_writing INV-5: the one-parse ApprovalHash equals '
    'the key-by-key recipe on every fixture doc and each frontmatter edge',
    () async {
      final matcher = DocTypeMatcher(
        openProject(await writeWriteProject()).set,
        targetNames: const [],
      );
      final texts = <String, String>{
        for (final MapEntry(:key, :value) in writeProject.entries)
          if (key.startsWith('docs/') && key.endsWith('.md'))
            key.substring(5): toLf(value),
      };
      final edges = [
        '# A\n',
        '\n\n# A\n',
        '---\n---\n\n# A\n',
        '---\napproved: "0123456789ab"\n---\n\n# A\n',
        '---\ndraft: true\napproved: true\nstatus: planned\n---\n# A\n',
        '---\napproved: x\napproved: y\n---\n# A\n',
        '---\n# a comment\napproved: x\n---\n# A\n',
        '---\nstatus: [planned\n---\n# A\n',
      ];
      var compared = 0;
      for (final MapEntry(key: docPath, value: lf) in texts.entries) {
        final type = switch (matcher.match(docPath)) {
          MatchedDocType(:final docType) => docType,
          _ => null,
        };
        for (final text in [lf, ...edges]) {
          expect(
            approvalHashOf(text, type),
            _referenceHashOf(text, type),
            reason: '$docPath: $text',
          );
          compared++;
        }
      }
      expect(compared, greaterThan(100));
    },
  );

  group('approval rules', () {
    const hash = '5d1e0c4b7a92';
    // The digits-only rows hash to their own digits (E14).
    String hashOf(String lines) => lines.contains('123456789012')
        ? '123456789012'
        : lines.contains('123e45678901')
        ? '123e45678901'
        : hash;
    // (label, frontmatter lines, awaits below pins, awaits at pins, guarded)
    final rows = <(String, String, bool, bool, bool)>[
      ('draft: true', 'draft: true', true, true, false),
      ('a matching hash', 'approved: "$hash"', false, false, true),
      ('a stale hash', 'approved: "0123456789ab"', true, true, true),
      ('approved: true', 'approved: true', false, true, true),
      ('neither key', 'status: planned', false, true, true),
      (
        'an unquoted 12-digit value',
        'approved: 123456789012',
        true,
        true,
        true,
      ),
      (
        'a quoted 12-digit value',
        'approved: "123456789012"',
        false,
        false,
        true,
      ),
      (
        'a float-shaped 12-character value',
        'approved: 123e45678901',
        true,
        true,
        true,
      ),
    ];
    for (final (label, lines, belowAwaits, atAwaits, guarded) in rows) {
      for (final fields in [
        ('Doc', ApprovalFields.of(Doc.parse('---\n$lines\n---\n# A\n'))),
        ('IndexedDoc', ApprovalFields.ofIndexed(_indexed(lines))),
      ]) {
        final (reader, f) = fields;
        test('walk_drafts E11-E14, the approval rule: $label via $reader', () {
          expect(
            awaitsApproval(f, hashOf(lines), stampsHaveRun: false),
            belowAwaits,
            reason: 'awaits below pins',
          );
          expect(
            awaitsApproval(f, hashOf(lines), stampsHaveRun: true),
            atAwaits,
            reason: 'awaits at pins',
          );
          expect(isGuarded(f), guarded);
        });
      }
    }

    test('a doc with no frontmatter awaits approval at the pins alone, and '
        'is guarded', () {
      const text = '# A\n';
      final f = ApprovalFields.of(Doc.parse(text));
      final hash = comparedApprovalHash(text, null);
      expect(awaitsApproval(f, hash, stampsHaveRun: true), isTrue);
      expect(awaitsApproval(f, hash, stampsHaveRun: false), isFalse);
      expect(isGuarded(f), isTrue);
    });

    test(
      'domain:document_writing INV-5: a frontmatter that is no YAML holds no '
      'value, never awaits approval, and stays guarded',
      () {
        const text = '---\ndraft: true\napproved: [\n---\n# A\n';
        final f = ApprovalFields.of(Doc.parse(text));
        expect(f.isDraft, isFalse);
        expect(comparedApprovalHash(text, null), isNull);
        for (final ran in [false, true]) {
          expect(
            awaitsApproval(
              f,
              comparedApprovalHash(text, null),
              stampsHaveRun: ran,
            ),
            isFalse,
          );
        }
        expect(isGuarded(f), isTrue);
        expect(
          parseIndexedDoc(
            docPath: 'a.md',
            bytes: utf8.encode(text),
            match: const NoDocType(),
          ).doc.approvalHash,
          isNull,
        );
      },
    );

    test('an invalid YAML key reads as no value through both readers', () {
      const text = '---\nstatus: [\ndraft: true\napproved: true\n---\n# A\n';
      for (final f in [
        ApprovalFields.of(Doc.parse(text)),
        ApprovalFields.ofIndexed(
          parseIndexedDoc(
            docPath: 'a.md',
            bytes: utf8.encode(text),
            match: const NoDocType(),
          ).doc,
        ),
      ]) {
        expect(f.isDraft, isFalse);
        expect(f.approvedValue, isNull);
      }
    });

    test('HD4: a quoted "approved" key is read', () {
      final f = ApprovalFields.of(
        Doc.parse('---\ndraft: true\n"approved": true\n---\n# A\n'),
      );
      expect(f.approvedValue, isTrue);
      expect(isGuarded(f), isTrue);
    });
  });

  test('f02/us03/s2, f02/us03/fr02/e01, dw-s03/inv11: the newest committed copy without draft is found', () async {
    final repo = await _repo({'docs/$signupFeature': _approvedText});
    commitAll(repo, 'approved');
    File('${repo.path}/docs/$signupFeature').writeAsStringSync(_draftText);
    commitAll(repo, 'edited as draft');

    expect(
      ApprovalHistory().lastApproved(
        repo,
        'docs/$signupFeature',
        docType: _docType,
      ),
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
      ApprovalHistory().lastApproved(repo, path, docType: _docType),
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
        .writeAsStringSync('---\ndraft: true\n---\n$_longBody');
    commitAll(repo, 'moved and drafted');

    expect(
      ApprovalHistory().lastApproved(repo, newPath, docType: _docType),
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
      ApprovalHistory().lastApproved(
        Directory('${repo.path}/sub'),
        path,
        docType: _docType,
      ),
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
      ApprovalHistory().lastApproved(
        Directory('${repo.path}/$sub'),
        path,
        docType: _docType,
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
        .writeAsStringSync('---\ndraft: true\n---\n$_longBody');
    commitAll(repo, 'moved and drafted');

    expect(
      ApprovalHistory().lastApproved(
        Directory('${repo.path}/sub'),
        newPath,
        docType: _docType,
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
        .writeAsStringSync('---\ndraft: true\n---\n$_longBody');
    commitAll(repo, 'moved and drafted');

    expect(
      ApprovalHistory().lastApproved(
        Directory('${repo.path}/sub'),
        newPath,
        docType: _docType,
      ),
      isA<ApprovedCopy>()
          .having((c) => c.text, 'text', _longApproved)
          .having((c) => c.path, 'path', oldPath),
    );
  }, skip: skipGit);

  test('f02/us03/fr02/e04: a failing rev-parse is UnknownHistory', () {
    final failing = ApprovalHistory(
      runGit: (arguments, {required workingDirectory, environment}) =>
          arguments.first == 'rev-parse'
          ? ProcessResult(0, 128, '', 'fatal: not a git repository')
          : ProcessResult(0, 0, '', ''),
    );

    expect(
      failing.lastApproved(
        Directory.systemTemp,
        'docs/$story1',
        docType: _docType,
      ),
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
          .writeAsStringSync('---\ndraft: true\n---\n$_longBody');
      commitAll(repo, 'moved and drafted');

      expect(
        ApprovalHistory().lastApproved(repo, newPath, docType: _docType),
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
        .writeAsStringSync('---\ndraft: true\n---\n$_longBody');
    commitAll(repo, 'moved and drafted');

    expect(
      ApprovalHistory().lastApproved(repo, newPath, docType: _docType),
      isA<ApprovedCopy>().having((c) => c.text, 'text', _longApproved),
    );
  }, skip: skipSha256);

  test('document_writing/approve_drafts/show_changes_since_approval E03, domain:document_writing INV-11: a committed copy with neither key is '
      'no approval', () async {
    final repo = await _repo({'docs/$signupFeature': _approvedBody});
    commitAll(repo, 'written by hand');

    expect(
      ApprovalHistory().lastApproved(
        repo,
        'docs/$signupFeature',
        docType: _docType,
      ),
      isA<NoApprovedCopy>(),
    );
  }, skip: skipGit);

  test('document_writing/approve_drafts/show_changes_since_approval E05, domain:document_writing INV-11: an edit before any commit leaves the '
      'committed approved copy the newest', () async {
    final repo = await _repo({'docs/$signupFeature': _approvedText});
    commitAll(repo, 'approved');
    File('${repo.path}/docs/$signupFeature')
        .writeAsStringSync('$_approvedText\nUncommitted edit.\n');

    expect(
      ApprovalHistory().lastApproved(
        repo,
        'docs/$signupFeature',
        docType: _docType,
      ),
      isA<ApprovedCopy>().having((c) => c.text, 'text', _approvedText),
    );
  }, skip: skipGit);

  test('document_writing/approve_drafts/show_changes_since_approval E19, domain:document_writing INV-11: a newer copy with no draft and no '
      '`approved:` value is passed over for an older approved one', () async {
    final repo = await _repo({'docs/$signupFeature': _approvedText});
    commitAll(repo, 'approved');
    File('${repo.path}/docs/$signupFeature')
        .writeAsStringSync('# Signup\n\nA legacy run left this.\n');
    commitAll(repo, 'legacy copy');

    expect(
      ApprovalHistory().lastApproved(
        repo,
        'docs/$signupFeature',
        docType: _docType,
      ),
      isA<ApprovedCopy>().having((c) => c.text, 'text', _approvedText),
    );
  }, skip: skipGit);

  test('document_writing/approve_drafts/show_changes_since_approval E20, domain:document_writing INV-11: an edit committed with its old hash '
      'counts as no approval', () async {
    final repo = await _repo({'docs/$signupFeature': _approvedText});
    commitAll(repo, 'approved');
    File('${repo.path}/docs/$signupFeature')
        .writeAsStringSync(_approvedText.replaceFirst('Approved', 'Edited'));
    commitAll(repo, 'edited in an editor');

    expect(
      ApprovalHistory().lastApproved(
        repo,
        'docs/$signupFeature',
        docType: _docType,
      ),
      isA<ApprovedCopy>().having((c) => c.text, 'text', _approvedText),
    );
  }, skip: skipGit);

  test('document_writing/approve_drafts/show_changes_since_approval E21, domain:document_writing INV-11: an unquoted digits hash is no hash', () async {
    final digits = RegExp(r'"(\d{12})"');
    final text = _approvedBody.replaceFirst(
      '# Signup',
      '---\napproved: 123456789012\n---\n# Signup',
    );
    expect(digits.hasMatch(text), isFalse);
    final repo = await _repo({'docs/$signupFeature': text});
    commitAll(repo, 'unquoted');

    expect(
      ApprovalHistory().lastApproved(
        repo,
        'docs/$signupFeature',
        docType: _docType,
      ),
      isA<NoApprovedCopy>(),
    );
  }, skip: skipGit);

  group('an uncommitted move (document_writing/approve_drafts/show_changes_since_approval E18)', () {
    const oldPath = 'docs/$story3';
    const newPath =
        'docs/prds/features/f01_login/us03_recover_account/USER_STORY.md';

    Future<Directory> movedRepo({required bool staged}) async {
      final repo = await _repo({oldPath: _longApproved});
      commitAll(repo, 'approved');
      File('${repo.path}/$newPath')
        ..createSync(recursive: true)
        ..writeAsStringSync('---\ndraft: true\n---\n${_longBody}An edit.\n');
      File('${repo.path}/$oldPath').deleteSync();
      if (staged) expect(git(repo, ['add', '-A']).exitCode, 0);
      return repo;
    }

    for (final staged in [false, true]) {
      test('${staged ? 'staged' : 'unstaged'} move then edit: the history runs '
          'on the path before it, and the index stays byte-equal', () async {
        final repo = await movedRepo(staged: staged);
        final index = File('${repo.path}/.git/index');
        final before = index.readAsBytesSync();
        final indexFiles = <String>[];
        final history = ApprovalHistory(
          runGit: (arguments, {required workingDirectory, environment}) {
            final file = environment?['GIT_INDEX_FILE'];
            if (file != null) indexFiles.add(file);
            return runRealGit(
              arguments,
              workingDirectory: workingDirectory,
              environment: environment,
            );
          },
        );

        final lookup = history.lastApproved(repo, newPath, docType: _docType);

        expect(
          lookup,
          isA<ApprovedCopy>()
              .having((c) => c.text, 'text', _longApproved)
              .having((c) => c.path, 'path', oldPath),
        );
        expect(indexFiles, isNotEmpty, reason: 'the move branch ran');
        expect(indexFiles, everyElement(isNot(index.path)));
        expect(index.readAsBytesSync(), before);
      }, skip: skipGit);
    }

    test(
      'the approval view prints the renamed from line for the moved doc',
      () async {
        final repo = await movedRepo(staged: false);
        final lookup = ApprovalHistory().lastApproved(
          repo,
          newPath,
          docType: _docType,
        );

        final view = renderApprovalView(
          DraftView(
            name: 'recover_account',
            docType: 'fr',
            mergedType: _docType,
            docPath: newPath,
            projectPath: newPath,
            text: File('${repo.path}/$newPath').readAsStringSync(),
            lookup: lookup,
            sentences: (dropped: <String>[], added: <String>[]),
          ),
          position: 1,
          count: 1,
        );

        expect(view, contains('renamed from `$oldPath`'));
        expect(view, contains('+An edit.'));
        expect(view, isNot(contains('@@ -0,0')));
      },
      skip: skipGit,
    );

    test(
      'three never-committed drafts run the temp-index commands once',
      () async {
        final repo = await movedRepo(staged: false);
        var indexCommands = 0;
        final history = ApprovalHistory(
          runGit: (arguments, {required workingDirectory, environment}) {
            if (environment?['GIT_INDEX_FILE'] != null) indexCommands++;
            return runRealGit(
              arguments,
              workingDirectory: workingDirectory,
              environment: environment,
            );
          },
        );

        for (final path in [newPath, 'docs/$story1', 'docs/$story2']) {
          history.lastApproved(repo, path, docType: _docType);
        }

        // One listing, one `add`, and one `diff` for the whole run.
        expect(indexCommands, 3);
      },
      skip: skipGit,
    );

    test('the temp index stages only the paths a move added or removed, never '
        'a tracked doc', () async {
      final repo = await movedRepo(staged: false);
      final staged = <String>[];
      ApprovalHistory(
        runGit: (arguments, {required workingDirectory, environment}) {
          if (environment?['GIT_INDEX_FILE'] != null &&
              arguments.first == 'add') {
            final file = arguments
                .firstWhere((a) => a.startsWith('--pathspec-from-file='))
                .substring('--pathspec-from-file='.length);
            staged.addAll(File(file).readAsStringSync().split('\x00'));
          }
          return runRealGit(
            arguments,
            workingDirectory: workingDirectory,
            environment: environment,
          );
        },
      ).lastApproved(repo, newPath, docType: _docType);

      expect(staged, isNotEmpty);
      expect(staged, isNot(contains('docs/$story1')));
      expect(staged, contains(newPath));
    }, skip: skipGit);

    test(
      'a temp index that cannot be set up makes the history unknown',
      () async {
        final repo = await movedRepo(staged: false);
        final history = ApprovalHistory(
          runGit: (arguments, {required workingDirectory, environment}) {
            if (arguments.contains('--git-path')) {
              // An index file that cannot be copied: it is read-protected.
              return ProcessResult(0, 0, '${repo.path}/unreadable\n', '');
            }
            return runRealGit(
              arguments,
              workingDirectory: workingDirectory,
              environment: environment,
            );
          },
        );
        final unreadable = File('${repo.path}/unreadable')
          ..writeAsStringSync('x');
        expect(Process.runSync('chmod', ['000', unreadable.path]).exitCode, 0);
        addTearDown(() => Process.runSync('chmod', ['600', unreadable.path]));

        expect(
          history.lastApproved(repo, newPath, docType: _docType),
          isA<UnknownHistory>(),
        );
      },
      skip: skipGit ?? (Platform.isWindows ? 'no chmod' : null),
    );

    test(
      'a doc no move put there, whose path no commit holds, is none',
      () async {
        final repo = await movedRepo(staged: false);
        File('${repo.path}/docs/$story1')
          ..createSync(recursive: true)
          ..writeAsStringSync('---\ndraft: true\n---\n# Other\n');

        expect(
          ApprovalHistory().lastApproved(
            repo,
            'docs/$story1',
            docType: _docType,
          ),
          isA<NoApprovedCopy>(),
        );
      },
      skip: skipGit,
    );
  });

  test('f02/us03/s3, f02/us03/fr02/e03, f02/us03/fr02/e05: no committed copy without draft is NoApprovedCopy', () async {
    final repo = await _repo({'docs/$signupFeature': _draftText});
    commitAll(repo, 'draft');
    File('${repo.path}/docs/$signupFeature')
        .writeAsStringSync('$_draftText\nMore.\n');
    commitAll(repo, 'still draft');

    expect(
      ApprovalHistory().lastApproved(
        repo,
        'docs/$signupFeature',
        docType: _docType,
      ),
      isA<NoApprovedCopy>(),
    );
  }, skip: skipGit);

  test(
    'f02/us03/fr02/e03, dw-s03/inv11: a path with no commit is NoApprovedCopy',
    () async {
      final repo = await _repo({'docs/$signupFeature': _approvedText});
      commitAll(repo, 'approved');

      expect(
        ApprovalHistory().lastApproved(repo, 'docs/$story1', docType: _docType),
        isA<NoApprovedCopy>(),
      );
    },
    skip: skipGit,
  );

  test('f02/us03/fr02/e04, dw-s03/inv11: outside a repo, or with git missing, the history is unknown', () async {
    expect(
      ApprovalHistory().lastApproved(
        await writeWriteProject(),
        'docs/$story1',
        docType: _docType,
      ),
      isA<UnknownHistory>(),
      skip: skipGit,
    );
    final missing = ApprovalHistory(
      runGit: (_, {required workingDirectory, environment}) =>
          throw const ProcessException('git', []),
    );
    expect(
      missing.lastApproved(
        Directory.systemTemp,
        'docs/$story1',
        docType: _docType,
      ),
      isA<UnknownHistory>(),
    );
  });

  test('f02/us03/fr02/e04, dw-s03/inv11, final Important 3: git output that is not UTF-8 makes the history unknown', () {
    final garbled = ApprovalHistory(
      runGit: (_, {required workingDirectory, environment}) =>
          throw const FormatException('Missing extension byte'),
    );
    expect(
      garbled.lastApproved(
        Directory.systemTemp,
        'docs/$story1',
        docType: _docType,
      ),
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
      ApprovalHistory().lastApproved(repo, path, docType: _docType),
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
      ApprovalHistory().lastApproved(repo, path, docType: _docType),
      isA<ApprovedCopy>().having((c) => c.text, 'text', _approvedText),
    );
  }, skip: skipGit);

  test(
    'f02/us03/fr02/e04, dw-s03/inv11: a failing git show is UnknownHistory',
    () {
      final sha = 'a' * 40;
      final failing = ApprovalHistory(
        runGit: (arguments, {required workingDirectory, environment}) =>
            switch (arguments.first) {
              'rev-parse' => ProcessResult(0, 0, '\n', ''),
              'log' => ProcessResult(0, 0, '$sha\x00\ndocs/$story1\x00', ''),
              _ => ProcessResult(0, 128, '', 'fatal: bad object'),
            },
      );
      expect(
        failing.lastApproved(
          Directory.systemTemp,
          'docs/$story1',
          docType: _docType,
        ),
        isA<UnknownHistory>(),
      );
    },
  );

  group('mark_doc_approved: a code target record', () {
    const record = MergedDocType(
      id: 'implementation',
      isPerTarget: true,
      fields: [
        MergedField(id: 'statuses', type: FieldType.recordStatus, list: true),
        MergedField(
          id: 'implements',
          type: FieldType.outputRef,
          list: true,
          pointer: PointerKind.itemExact,
        ),
      ],
      sections: [],
      lint: MergedLint(),
      files: [],
    );
    String text({String status = 'implemented', String path = 'a.dart'}) =>
        '---\nstatuses:\n  - login/check:$status\nimplements:\n'
        '  - login/check:$path\n---\n\n# Record\n';

    test('E09: the code paths of a record stay outside its hash', () {
      expect(
        approvalHashOf(text(path: 'b.dart'), record),
        approvalHashOf(text(), record),
      );
    });

    test('E09: the statuses of a record stay inside its hash', () {
      expect(
        approvalHashOf(text(status: 'skipped'), record),
        isNot(approvalHashOf(text(), record)),
      );
    });
  });
}
