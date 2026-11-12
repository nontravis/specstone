// The expected texts are plan literals kept as written.

import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/implements_rule.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';
import '../../helpers/posix_modes.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/temp_tree.dart';

void main() {
  const entry = 'app/lib/login.dart:checkPassword';

  test(
    'f04/us02/s1, f04/us02/fr01/e01: every pointer of the fixture resolves',
    () async {
      expect(checkOf(await writeCheckProject()).findings, isEmpty);
    },
  );

  test('f04/us02/s2, f04/us02/fr01/e02: a renamed function names the pointer and the symbol', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          'app/lib/login.dart': 'class SignInPage {}\n\nbool checkCredentials(String p) => p.isNotEmpty;\n',
        },
      ),
    );
    final finding = report.findings.single;
    expect(
      finding.textLine,
      '$loginFr:10: implements_symbol_unresolved: checkPassword occurs nowhere in app/lib/login.dart',
    );
    expect(
      finding.toJson(),
      allOf(
        containsPair('entry', entry),
        containsPair('symbol', 'checkPassword'),
      ),
    );
  });

  test(
    'code_root: pointers resolve from the code folder, not the project root',
    () async {
      final report = checkOf(
        await writeCheckProject(
          extra: {
            '.specstone/config.yaml': '${shippedPinsConfig()}code_root: code\n',
            'code/app/lib/login.dart':
                checkProjectFiles()['app/lib/login.dart']!,
            ...fr(entry, 'app/lib/b.dart'),
          },
          without: {'app/lib/login.dart'},
        ),
      );
      expect(spots(report), ['$loginFr:10: implements_path_unresolved']);
      expect(
        report.findings.single.toJson(),
        containsPair('entry', 'app/lib/b.dart'),
      );
    },
  );

  test('code_root: a folder outside the project root holds the code', () async {
    final files = withApprovalHashes(checkProjectFiles());
    final config = '${shippedPinsConfig()}code_root: ../outside\n';
    final workspace = await writeTree({
      for (final MapEntry(:key, :value) in files.entries)
        if (!key.startsWith('app/') && key != '.specstone/config.yaml')
          'project/$key': value,
      'project/.specstone/config.yaml': config,
      'outside/app/lib/login.dart': files['app/lib/login.dart']!,
    });

    final report = checkOf(
      Directory.fromUri(workspace.uri.resolve('project/')),
    );

    expect(report.findings, isEmpty);
  });

  test('f04/us02/fr01/e03: a pointer with a backslash or a name Windows trims '
      'names no file on any OS, though a POSIX disk holds one', () async {
    for (final pointer in [r'app\lib\login.dart', 'app/lib/login.dart.']) {
      final root = await writeCheckProject(extra: fr(entry, pointer));
      File('${root.path}/$pointer').writeAsStringSync('class SignInPage {}\n');

      expect(spots(checkOf(root)), [
        '$loginFr:10: implements_path_unresolved',
      ], reason: pointer);
    }
  }, skip: Platform.isWindows ? 'Windows cannot hold such a name' : null);

  test('f04/us02/s7, f04/us02/fr01/e03: a pointer to a folder, or to nothing, names no file', () async {
    final folder = checkOf(
      await writeCheckProject(extra: fr(entry, 'app/lib')),
    );
    expect(spots(folder), ['$loginFr:10: implements_path_unresolved']);
    final gone = checkOf(
      await writeCheckProject(extra: fr(entry, 'app/lib/gone.dart:X')),
    );
    expect(spots(gone), ['$loginFr:10: implements_path_unresolved']);
  });

  test(
    'f04/us02/fr01/e04, cc-s03/inv1: a pointer with no Symbol reads no file',
    () async {
      final session = openSession(
        await writeCheckProject(extra: fr(entry, 'app/lib/login.dart')),
      );
      addTearDown(session.close);
      final context = CheckContext(session);
      expect(checkImplements(context, session.index.at(loginFr)!), isEmpty);
      expect(context.codeFilesRead, 0);
    },
  );

  test(
    'f04/us02/fr01/e05: a dotted Symbol resolves only when each segment does',
    () async {
      final files = {
        'app/lib/auth.dart': 'class AuthService {\n  void signIn() {}\n}\n',
      };
      final both = checkOf(
        await writeCheckProject(
          extra: {
            ...files,
            ...fr(entry, 'app/lib/auth.dart:AuthService.signIn'),
          },
        ),
      );
      expect(spots(both), isEmpty);
      final one = checkOf(
        await writeCheckProject(
          extra: {
            ...files,
            ...fr(entry, 'app/lib/auth.dart:AuthService.signOut'),
          },
        ),
      );
      expect(one.findings.single.toJson()['symbol'], 'signOut');
    },
  );

  test('f04/us02/fr01/e06, f04/us02/fr01/e07: a whole word only, found in any text, comments included', () async {
    final part = checkOf(
      await writeCheckProject(
        extra: {
          'app/lib/login.dart':
              'class SignInPage {}\n\nbool checkPasswordNow() => true;\n',
        },
      ),
    );
    expect(spots(part), ['$loginFr:10: implements_symbol_unresolved']);
    final comment = checkOf(
      await writeCheckProject(
        extra: {
          'app/lib/login.dart':
              'class SignInPage {}\n// checkPassword moved; see the docs\n',
        },
      ),
    );
    expect(spots(comment), isEmpty);
  });

  test('f04/us02/fr01/e08: an untyped doc gets no pointer rule', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          'docs/prds/notes.md':
              '---\nimplements:\n  - app/lib/gone.dart:X\n---\n\n# Notes\n',
        },
      ),
    );
    expect(spots(report), ['prds/notes.md:1: untyped_doc']);
  });

  test(
    'f04/us02/fr01/e09: an unreadable code file gives a warning and no finding',
    skip: unreadablePathSkipReason(),
    () async {
      final project = await writeCheckProject(
        extra: {
          'app/lib/other.dart': 'class Other {}\n',
          ...doc(
            loginStory,
            'app/lib/login.dart:SignInPage',
            'app/lib/other.dart:Gone',
          ),
        },
      );
      final path = '${project.path}/app/lib/login.dart';
      Process.runSync('chmod', ['000', path]);
      addTearDown(() => Process.runSync('chmod', ['644', path]));
      final report = checkOf(project);
      expect(spots(report), ['$loginStory:7: implements_symbol_unresolved']);
      expect(report.warnings, [
        'app/lib/login.dart: cannot read the file; implements Symbols in it are not checked',
      ]);
    },
  );
}
