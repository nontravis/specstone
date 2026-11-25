import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/sync_work.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/git_repo.dart';
import '../../helpers/index_fixture.dart';

const _cartFeature = 'prds/features/f02_cart/FEATURE.md';
const _cartArchitecture = 'specs/f02_cart/ARCHITECTURE.md';
const _topic = 'specs/topics/shared.md';
const _login = 'app/lib/login.dart';
const _shared = 'app/lib/shared.dart';
const _other = 'app/lib/other.dart';
const _otherText = 'class Other {}\n';

/// The fixture with a second feature, and a topic covering its own file.
Map<String, String> _extras() => {
  'docs/$_cartFeature': checkProjectFiles()['docs/$loginFeature']!.replaceFirst(
    '# Login',
    '# Cart',
  ),
  'docs/$_cartArchitecture': checkProjectFiles()['docs/$loginArchitecture']!
      .replaceFirst('app/lib/', 'app/lib/cart/'),
  'docs/$_topic':
      '---\ncovers:\n  - $_shared\n---\n\n# Shared\n\n## Purpose\n\nShares.\n',
  _shared: 'class Shared {}\n',
  _other: _otherText,
};

Finding _finding(
  FindingKind kind,
  String path, {
  WaitsFor? waitsFor,
  Map<String, Object> keys = const {},
}) => Finding(
  kind: kind,
  path: path,
  line: 1,
  message: 'm',
  waitsFor: waitsFor,
  keys: keys,
);

void _append(String project, String file, int lines) {
  File('$project/$file').writeAsStringSync(
    [for (var i = 0; i < lines; i++) 'int v$i = $i;\n'].join(),
    mode: FileMode.append,
  );
}

/// Returns the groups of the check of [project] plus the [extra] findings.
Future<List<SyncGroup>> _groupsOf(
  Directory project, {
  String? feature,
  List<Finding> extra = const [],
}) async {
  final session = openSession(project);
  addTearDown(session.close);
  final report = await runCheck(session);
  return syncGroupsOf(
    CheckContext(session),
    CheckReport(findings: [...report.findings, ...extra]),
    feature: feature,
  );
}

/// Writes the fixture as a git repository with its first commit made.
Future<Directory> _committedProject({
  Set<String> unfingerprinted = const {},
  Map<String, String> extra = const {},
}) async {
  final project = await writeCheckProject(
    extra: {..._extras(), ...extra},
    unfingerprinted: unfingerprinted,
  );
  expect(git(project, ['init', '-q']).exitCode, 0);
  commitAll(project, 'first');
  return project;
}

void main() {
  group('the work list', () {
    test('two features and a topic give three groups', () async {
      final project = await writeCheckProject(extra: _extras());
      for (final file in [_login, _shared]) {
        _append(project.path, file, 1);
      }

      final groups = await _groupsOf(
        project,
        extra: [_finding(FindingKind.codeSuspect, _cartArchitecture)],
      );

      expect(
        [for (final group in groups) group.scope],
        ['charter:shared', 'feature:cart', 'feature:login'],
      );
    });

    test(
      'a tests_missing and a covers_entry_empty finding join no group',
      () async {
        final project = await writeCheckProject();

        final groups = await _groupsOf(
          project,
          extra: [
            _finding(FindingKind.testsMissing, loginRecord),
            _finding(FindingKind.coversEntryEmpty, loginArchitecture),
          ],
        );

        expect(groups, isEmpty);
      },
    );

    test(
      'a matrix row finding that waits for the Owner joins no group',
      () async {
        final project = await writeCheckProject();

        final groups = await _groupsOf(
          project,
          extra: [
            _finding(
              FindingKind.suspect,
              loginRecord,
              waitsFor: WaitsFor.owner,
            ),
          ],
        );

        expect(groups, isEmpty);
      },
    );

    test('an agent-waiting matrix row finding joins its group', () async {
      final project = await writeCheckProject();

      final groups = await _groupsOf(
        project,
        extra: [_finding(FindingKind.suspect, loginRecord)],
      );

      expect([for (final group in groups) group.scope], ['feature:login']);
      expect(groups.single.route, SyncRoute.engineer);
    });

    test(
      'a suspect finding on a doc that is no record joins no group',
      () async {
        final project = await writeCheckProject();

        final groups = await _groupsOf(
          project,
          extra: [_finding(FindingKind.suspect, loginFr)],
        );

        expect(groups, isEmpty);
      },
    );

    test('an unparsable matrix row joins no group', () async {
      final project = await writeCheckProject();

      final groups = await _groupsOf(
        project,
        extra: [
          _finding(
            FindingKind.matrixRowMalformed,
            loginRecord,
            keys: {'row': '- nonsense'},
          ),
        ],
      );

      expect(groups, isEmpty);
    });

    test('a refused-form matrix row joins its group', () async {
      final project = await writeCheckProject();

      final groups = await _groupsOf(
        project,
        extra: [
          _finding(
            FindingKind.matrixRowMalformed,
            loginRecord,
            keys: {'row': '- email_login/check_password: `a test`'},
          ),
        ],
      );

      expect([for (final group in groups) group.scope], ['feature:login']);
    });

    test('a tests_unresolved finding joins the group of its doc', () async {
      final project = await writeCheckProject();

      final groups = await _groupsOf(
        project,
        extra: [_finding(FindingKind.testsUnresolved, loginRecord)],
      );

      final [group] = groups;
      expect(group.scope, 'feature:login');
      expect(
        [for (final f in group.findings) f.kind],
        [FindingKind.testsUnresolved],
      );
      expect(group.links, isEmpty);
    });

    test('a project architecture covers entry gives a group of its own '
        'with the doc as its covering doc', () async {
      const architecture = 'specs/ARCHITECTURE.md';
      const tool = 'tool/build.dart';
      final project = await _committedProject(
        extra: {
          'docs/$architecture':
              '---\ncovers:\n  - $tool 0123456789ab\n---\n\n'
              '# Login demo architecture\n',
          tool: 'void main() {}\n',
        },
      );

      final groups = await _groupsOf(project);

      final group = groups.singleWhere(
        (group) => group.scope.startsWith('project_architecture:'),
      );
      final [finding] = group.findings;
      expect(finding.kind, FindingKind.codeSuspect);
      expect(finding.path, architecture);
      final [work] = group.links;
      expect(work.link.path, tool);
      final [covering] = work.coveringDocs;
      expect(covering.docPath, architecture);
      expect(group.scope, 'project_architecture:${covering.name}');
    });

    test(
      'a feature target gives every code link, clean ones included',
      () async {
        final project = await writeCheckProject();

        final groups = await _groupsOf(project, feature: 'login');

        final [group] = groups;
        expect(group.scope, 'feature:login');
        expect(group.findings, isEmpty);
        expect(group.route, SyncRoute.engineer);
        expect([
          for (final work in group.links) work.link.path,
        ], unorderedEquals([_login, _login, 'app/lib/']));
      },
    );
  });

  group('the routes', () {
    test('a group of 40 changed lines on covers entries is small', () async {
      final project = await _committedProject();
      _append(project.path, _other, 40);

      final [group] = await _groupsOf(project);

      expect(group.route, SyncRoute.small);
    });

    test('a group of 41 changed lines on covers entries is engineer', () async {
      final project = await _committedProject();
      _append(project.path, _other, 41);

      final [group] = await _groupsOf(project);

      expect(group.route, SyncRoute.engineer);
    });

    test('a group holding an implements entry is never small', () async {
      final project = await _committedProject();
      _append(project.path, _login, 1);

      final [group] = await _groupsOf(project);

      expect(group.route, SyncRoute.engineer);
    });

    test(
      'a group with an untracked file under a folder entry is engineer',
      () async {
        final project = await _committedProject();
        _append(project.path, _other, 1);
        File('${project.path}/app/lib/new.dart')
            .writeAsStringSync('class N {}\n');

        final [group] = await _groupsOf(project);

        expect(group.route, SyncRoute.engineer);
      },
    );

    test(
      'a code_unconfirmed link has no diff base, so its group is engineer',
      () async {
        final project = await _committedProject(unfingerprinted: {loginRecord});

        final [group] = await _groupsOf(project);

        expect(
          {for (final f in group.findings) f.kind},
          {FindingKind.codeUnconfirmed},
        );
        expect(group.route, SyncRoute.engineer);
      },
    );

    test(
      'a covering doc that is a pending draft makes the group engineer',
      () async {
        final project = await _committedProject(
          extra: doc(loginRecord, 'statuses:', 'draft: true\nstatuses:'),
        );
        _append(project.path, _other, 1);

        final [group] = await _groupsOf(project);

        expect(group.route, SyncRoute.engineer);
      },
    );

    test('a code_suspect finding with no code link is never small', () async {
      final project = await writeCheckProject();

      final [group] = await _groupsOf(
        project,
        extra: [_finding(FindingKind.codeSuspect, loginArchitecture)],
      );

      expect(group.links, isEmpty);
      expect(group.route, SyncRoute.engineer);
    });

    test('a file two entries cover counts its changed lines once', () async {
      final project = await _committedProject(
        extra: doc(loginRecord, '  - app/lib/\n', '  - $_other\n  - $_other\n'),
      );
      _append(project.path, _other, 25);

      final groups = await _groupsOf(project);

      final group = groups.firstWhere((g) => g.scope == 'feature:login');
      expect(group.links, hasLength(2));
      expect(group.route, SyncRoute.small);
    });

    test('a code_uncovered finding is the last group', () async {
      final project = await writeCheckProject(extra: _extras());
      _append(project.path, _shared, 1);

      final groups = await _groupsOf(
        project,
        extra: [
          _finding(FindingKind.codeSuspect, _cartArchitecture),
          _finding(
            FindingKind.codeUncovered,
            techStack,
            keys: {'codePath': 'app/lib/x.dart'},
          ),
        ],
      );

      expect(
        [for (final group in groups) group.scope],
        ['charter:shared', 'feature:cart', 'feature:login', 'uncovered'],
      );
      expect(groups.last.route, SyncRoute.last);
    });
  });
}
