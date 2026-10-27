// The expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/posix_modes.dart';
import '../../helpers/temp_tree.dart';

void main() {
  /// Sets the fixture architecture's one `covers` entry.
  Map<String, String> narrow(String covers) =>
      doc(loginArchitecture, 'app/lib/', covers);

  test('f04/us02/s3, f04/us02/fr03/e01: a file under the code root no covers entry reaches is code_uncovered', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          ...narrow('app/lib/src/'),
          'app/lib/src/a.dart': '',
          'app/lib/main.dart': '',
        },
      ),
    );
    expect(spots(report), [
      '$techStack:3: code_uncovered',
      '$techStack:3: code_uncovered',
    ]);
    expect(
      report.findings.last.message,
      'app/lib/main.dart is under the code root app/lib/ and no covers entry reaches it',
    );
    expect(
      [for (final f in report.findings) f.toJson()['path']],
      ['app/lib/login.dart', 'app/lib/main.dart'],
    );
  });

  test(
    'f04/us02/s4, f04/us02/fr03/e02: with no code field the check does not run',
    () async {
      final report = checkOf(
        await writeCheckProject(
          extra: {
            ...narrow('app/lib/src/'),
            ...doc(techStack, '---\ncode:\n  - app/lib/\n---\n\n', ''),
          },
        ),
      );
      expect(spots(report, FindingKind.codeUncovered), isEmpty);
    },
  );

  test(
    'f04/us02/fr03/e03, f04/us02/fr03/e04: dot names and links are skipped; generated files have no exclude',
    skip: Platform.isWindows
        ? 'a symbolic link needs a privilege on Windows'
        : null,
    () async {
      final outside = await writeTree({'x.dart': ''});
      final project = await writeCheckProject(
        extra: {...narrow('app/lib/login.dart'), 'app/lib/.DS_Store': ''},
      );
      Link('${project.path}/app/lib/linked').createSync(outside.path);
      expect(spots(checkOf(project), FindingKind.codeUncovered), isEmpty);
      final generated = checkOf(
        await writeCheckProject(extra: {'app/lib/login.g.dart': ''}),
      );
      expect(spots(generated, FindingKind.codeUncovered), isEmpty);
    },
  );

  test('f04/us02/fr03/e05: a folder entry reaches only the files inside it, by path segment', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {...narrow('app/lib/src'), 'app/lib/srcx/a.dart': ''},
      ),
    );
    expect([
      for (final f in report.findings) f.toJson()['path'],
    ], contains('app/lib/srcx/a.dart'));
  });

  test('f04/us02/s6, f04/us02/fr03/e06: a check on one feature leaves uncovered code out', () async {
    final project = await writeCheckProject(
      extra: {...narrow('app/lib/src/'), 'app/lib/main.dart': ''},
    );
    expect(
      spots(checkOf(project, target: 'login'), FindingKind.codeUncovered),
      isEmpty,
    );
  });

  test('f04/us02/fr02/e04, f04/us02/fr03/e07: a missing root is code_root_missing; the other root is still listed', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          ...doc(techStack, '  - app/lib/\n', '  - app/lib/\n  - api/lib/\n'),
          ...narrow('app/lib/src/'),
          'app/lib/src/a.dart': '',
        },
      ),
    );
    expect(spots(report), [
      '$techStack:3: code_uncovered',
      '$techStack:4: code_root_missing',
    ]);
  });

  test('f04/us02/s8, f04/us02/fr02/e01, f04/us02/fr02/e02, f04/us02/fr02/e03, f04/us02/fr02/e05: a covers entry '
      'names a file or a folder, with or without a final slash; one that moved names nothing', () async {
    for (final entry in ['app/lib/login.dart', 'app/lib']) {
      expect(
        spots(
          checkOf(await writeCheckProject(extra: narrow(entry))),
          FindingKind.coversPathMissing,
        ),
        isEmpty,
      );
    }
    final moved = checkOf(
      await writeCheckProject(extra: narrow('app/lib/login/')),
    );
    expect(spots(moved, FindingKind.coversPathMissing), [
      '$loginArchitecture:3: covers_path_missing',
    ]);
    expect(
      moved.findings
          .firstWhere((f) => f.kind == FindingKind.coversPathMissing)
          .textLine,
      '$loginArchitecture:3: covers_path_missing: app/lib/login/ names nothing on disk',
    );
  });

  test('cc-INV-10: a file under two roots is reported once, under the first root that lists it', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          ...doc(techStack, '  - app/lib/\n', '  - app/lib/\n  - app/\n'),
          ...narrow('app/lib/login.dart'),
          'app/lib/main.dart': '',
        },
      ),
    );
    expect(spots(report, FindingKind.codeUncovered), [
      '$techStack:3: code_uncovered',
    ]);
  });

  test(
    'f04/us02/fr03/e08: a code root that cannot be listed gives a warning and no finding',
    skip: unreadablePathSkipReason(),
    () async {
      final project = await writeCheckProject(
        extra: {
          ...narrow('app/lib/src/'),
          'app/lib/src/b.dart': '',
          'app/lib/sealed/a.dart': '',
        },
      );
      final path = '${project.path}/app/lib/sealed';
      Process.runSync('chmod', ['000', path]);
      addTearDown(() => Process.runSync('chmod', ['755', path]));
      final report = checkOf(project);
      expect(spots(report, FindingKind.codeUncovered), [
        '$techStack:3: code_uncovered',
      ]);
      expect(report.warnings, [
        'app/lib/sealed: cannot list the folder; files under it are not checked for covers',
      ]);
    },
  );
}
