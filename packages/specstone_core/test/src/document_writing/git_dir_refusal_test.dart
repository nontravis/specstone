import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/document_writing/approve_drafts.dart';
import 'package:specstone_core/src/document_writing/delete_doc.dart';
import 'package:specstone_core/src/document_writing/owner_confirmation.dart';
import 'package:specstone_core/src/document_writing/root_trust.dart';
import 'package:specstone_core/src/git_process.dart';
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:test/test.dart';

import '../../helpers/git_repo.dart';
import '../../helpers/legacy_fixture.dart' show commitRepo;
import '../../helpers/relative_link.dart';
import '../../helpers/temp_tree.dart';
import '../../helpers/write_fixture.dart';

final String? _skip = !hasGit
    ? 'git is not available'
    : Platform.isWindows
    ? 'a link needs a privilege on Windows'
    : null;

const _draft = 'fr:login/email_login/lock_after_failures';

/// Starts git as a release before 2.38 would: with no `safe.bareRepository`
/// config in the command, and printing 2.37.0 for `--version`; [guardedGit]
/// wraps it as the product does.
final RunGit _olderGit = guardedGit(
  (arguments, {required workingDirectory, environment}) =>
      arguments.first == '--version'
      ? ProcessResult(0, 0, 'git version 2.37.0\n', '')
      : Process.runSync(
          'git',
          arguments,
          workingDirectory: workingDirectory,
          environment: environment,
          stdoutEncoding: utf8,
        ),
);

/// Builds a clone whose `docs` link leads to `evil/docs`, a project whose
/// `evil/` folder is a committed git dir laid out as a work tree's `.git`,
/// with a `core.fsmonitor` that would touch [marker]; the Owner trusted the
/// layout, so the git dir check is what refuses it.
///
/// Holds one draft no commit holds, so `approve` asks git about it.
Future<({Directory clone, Directory evil})> _evilProject(File marker) async {
  final base = await writeTree({
    'clone/keep.txt': '',
    for (final MapEntry(:key, :value) in writeProject.entries)
      'evil/$key': value,
  });
  final clone = Directory('${base.path}/clone');
  final evil = Directory('${base.path}/evil');
  commitRepo(evil);
  final dotGit = Directory('${evil.path}/.git');
  for (final entry in dotGit.listSync()) {
    entry.renameSync(
      '${evil.path}/${entry.uri.pathSegments.where((s) => s.isNotEmpty).last}',
    );
  }
  dotGit.deleteSync(recursive: true);
  for (final (key, value) in [
    ('core.bare', 'false'),
    ('core.worktree', '..'),
    ('core.fsmonitor', 'touch ${marker.path}; false'),
  ]) {
    expect(
      Process.runSync('git', [
        'config',
        '-f',
        '${evil.path}/config',
        key,
        value,
      ]).exitCode,
      0,
    );
  }
  File('${evil.path}/docs/prds/personas/y/PERSONA.md')
    ..createSync(recursive: true)
    ..writeAsStringSync('---\ndraft: true\n---\n\n# Y\n');
  createRelativeLink('${clone.path}/docs', '../evil/docs');
  RootTrust.locate(clone, homeDirectory: testHome()).record();
  return (clone: clone, evil: evil);
}

final Matcher _refusesAsNoWorkTree = throwsA(
  isA<MigrateFault>()
      .having((f) => f.code, 'code', MigrateFaultCode.gitWorkTreeRequired)
      .having((f) => f.exitStatus, 'exit', 78)
      .having(
        (f) => f.message,
        'message',
        'the project is not in a git work tree with a first commit; put the '
            'project under git, git init and a first commit, then run the '
            'command again',
      ),
);

void main() {
  late File marker;
  late Directory clone;
  late Directory evil;
  late Map<String, List<int>> docsBefore;

  setUp(() async {
    final scratch = await writeTree({'keep.txt': ''});
    marker = File('${scratch.path}/PWNED');
    (:clone, :evil) = await _evilProject(marker);
    docsBefore = treeBytes(Directory('${evil.path}/docs'));
  });

  /// Runs [refused], then checks no git command ran and no doc changed.
  void expectRefusedUntouched(void Function() refused) {
    expect(refused, _refusesAsNoWorkTree);
    expect(marker.existsSync(), isFalse, reason: 'a git command ran');
    expect(treeBytes(Directory('${evil.path}/docs')), docsBefore);
  }

  test('approve --dry-run refuses a committed git dir on a git '
      'before 2.38 and runs no command', () {
    expectRefusedUntouched(
      () => writeIn(
        clone,
        (s) => approveDryRun(s, history: ApprovalHistory(runGit: _olderGit)),
      ),
    );
  }, skip: _skip);

  test('approve refuses a committed git dir on a git before '
      '2.38, asks nothing, and runs no command', () {
    final out = StringBuffer();

    expectRefusedUntouched(
      () => writeIn(
        clone,
        (s) => approveDrafts(
          s,
          readLine: () => fail('the Owner was asked'),
          out: out,
          history: ApprovalHistory(runGit: _olderGit),
        ),
      ),
    );

    expect(out.toString(), isEmpty);
  }, skip: _skip);

  test('delete --dry-run refuses a committed git dir on a git '
      'before 2.38 and runs no command', () {
    expectRefusedUntouched(
      () => writeIn(
        clone,
        (s) => answerDeleteDryRun(s, const [_draft], runGit: _olderGit),
      ),
    );
  }, skip: _skip);

  test('delete --yes --plan refuses a committed git dir on a '
      'git before 2.38, before it compares the plan, and deletes nothing', () {
    expectRefusedUntouched(
      () => writeIn(
        clone,
        (s) => answerDelete(
          s,
          const [_draft],
          confirmation: OwnerConfirmation.given,
          readLine: () => null,
          prompts: StringBuffer(),
          planHash: 'not-the-plan',
          runGit: _olderGit,
        ),
      ),
    );
  }, skip: _skip);
}
