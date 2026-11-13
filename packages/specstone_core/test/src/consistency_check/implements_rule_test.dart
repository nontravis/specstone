// The expected texts are plan literals kept as written.

import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/implements_rule.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';
import '../../helpers/posix_modes.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/target_fixture.dart';
import '../../helpers/temp_tree.dart';

const _recordLayer =
    'id: implementation\n'
    'description: One feature record per target.\n'
    'path: specs/f{nn}_{slug}/IMPLEMENTATION.md\n'
    'parent: feature\n'
    'per_target: true\n'
    'fields:\n'
    '  - id: statuses\n'
    '    type: record_status\n'
    '    list: true\n'
    '  - id: implements\n'
    '    type: output_ref\n'
    '    list: true\n'
    '    pointer: item_exact\n';

const _recordPath = 'specs/f01_login/IMPLEMENTATION.md';
const _flutterRecord = 'specs/flutter/f01_login/IMPLEMENTATION.md';
const _jasprRecord = 'specs/jaspr/f01_login/IMPLEMENTATION.md';

/// The FR of the login fixture, named relative to its feature.
const _fr = 'email_login/check_password';
const _story = 'email_login';

const _implemented = '$_fr:implemented';

const Set<FindingKind> _kinds = {
  FindingKind.implementsPathUnresolved,
  FindingKind.implementsSymbolUnresolved,
};

/// Returns a record: `statuses` first, then `implements`, one quoted line each.
///
/// The first `statuses` line is file line 3; `implements` follows the last.
String _record({
  List<String> statuses = const [_implemented],
  List<String> code = const [],
}) {
  String list(String key, List<String> lines) => lines.isEmpty
      ? ''
      : "$key:\n${[for (final l in lines) "  - '$l'\n"].join()}";
  return '---\n${list('statuses', statuses)}${list('implements', code)}'
      '---\n\n# Record\n';
}

/// The file line of the [j]th `implements` item after [statusCount] statuses.
int _codeLine(int statusCount, int j) =>
    (statusCount == 0 ? 3 : 4 + statusCount) + j;

/// Returns the fixture files that make [record] the login feature's record.
///
/// The record holds each item's status, so the story and the FR write none.
Map<String, String> _withRecord(
  String record, {
  String path = _recordPath,
  Map<String, String> config = const {},
}) => {'docs/$path': record, ...config};

Future<Directory> _project(
  String record, {
  Map<String, String> extra = const {},
  Set<String> without = const {},
}) => writeCheckProject(
  extra: {..._withRecord(record), ...extra},
  without: without,
  // A stamp would add an `approved:` line and move every line below it.
  unstamped: {'docs/$_recordPath'},
);

CheckReport _run(Directory project, {String? codeTarget}) {
  final session = openSession(project);
  try {
    return runCheck(session, codeTarget: codeTarget);
  } finally {
    session.close();
  }
}

/// Returns `<path>:<line>: <kind>` per implements finding.
List<String> _spots(CheckReport report) => [
  for (final f in report.findings)
    if (_kinds.contains(f.kind)) '${f.path}:${f.line}: ${f.kind.wire}',
];

Iterable<Finding> _found(CheckReport report) =>
    report.findings.where((f) => _kinds.contains(f.kind));

void main() {
  const login = 'app/lib/login.dart';
  const point = '$_fr:$login:checkPassword';
  const entry = '$login:checkPassword';

  test(
    'f04/us02/s1, f04/us02/fr01/e01: every pointer of the fixture resolves',
    () async {
      final report = _run(await _project(_record(code: [point])));

      expect(_found(report), isEmpty);
    },
  );

  test('f04/us02/s2, f04/us02/fr01/e02: a renamed function names the pointer and the symbol', () async {
    final report = _run(
      await _project(
        _record(code: [point]),
        extra: {
          login:
              'class SignInPage {}\n\n'
              'bool checkCredentials(String p) => p.isNotEmpty;\n',
        },
      ),
    );

    final finding = _found(report).single;
    expect(
      finding.textLine,
      '$_recordPath:${_codeLine(1, 0)}: implements_symbol_unresolved: checkPassword occurs nowhere in app/lib/login.dart',
    );
    expect(
      finding.toJson(),
      allOf(
        containsPair('entry', entry),
        containsPair('symbol', 'checkPassword'),
      ),
    );
  });

  test('f04/us02/fr01/e10: a pointer resolves from the code folder, not the project root', () async {
    final report = _run(
      await _project(
        _record(code: [point, '$_fr:app/lib/b.dart']),
        extra: {
          '.specstone/config.yaml': '${shippedPinsConfig()}code_root: code\n',
          'code/$login': checkProjectFiles()[login]!,
        },
        without: {login},
      ),
    );

    expect(_spots(report), [
      '$_recordPath:${_codeLine(1, 1)}: implements_path_unresolved',
    ]);
    expect(
      _found(report).single.toJson(),
      containsPair('entry', 'app/lib/b.dart'),
    );
  });

  test(
    'f04/us02/fr01/e10: a code folder outside the project root holds the code',
    () async {
      final files = withApprovalHashes(checkProjectFiles());
      final workspace = await writeTree({
        for (final MapEntry(:key, :value) in files.entries)
          if (!key.startsWith('app/') && key != '.specstone/config.yaml')
            'project/$key': value,
        ..._withRecord(_record(code: [point]))
            .map((key, value) => MapEntry('project/$key', value)),
        'project/.specstone/config.yaml':
            '${shippedPinsConfig()}code_root: ../outside\n',
        'outside/$login': files[login]!,
      });

      final report = _run(Directory.fromUri(workspace.uri.resolve('project/')));

      expect(_found(report), isEmpty);
    },
  );

  test(
    'f04/us02/fr01/e10: each target resolves its record in its own code root',
    () async {
      String code(String name) =>
          'class SignInPage {}\nclass ${name}SignIn {}\n'
          'bool checkPassword(String p) => p.isNotEmpty;\n';
      final project = await writeTwinProject(
        extra: {
          '.specstone/templates/implementation.yaml': _recordLayer,
          'flutter_ws/app/lib/flutter_only.dart': code('Flutter'),
          'docs/$_flutterRecord': _record(
            code: [
              '$_fr:$login:FlutterSignIn',
              '$_fr:app/lib/flutter_only.dart',
            ],
          ),
          'docs/$_jasprRecord': _record(
            code: [
              '$_fr:$login:FlutterSignIn',
              '$_fr:app/lib/flutter_only.dart',
            ],
          ),
        },
      );

      final report = _run(project);

      expect(_spots(report), [
        '$_jasprRecord:${_codeLine(1, 0)}: implements_symbol_unresolved',
        '$_jasprRecord:${_codeLine(1, 1)}: implements_path_unresolved',
      ]);
    },
  );

  test('f04/us02/fr01/e10: a --target run resolves the records of that target only', () async {
    final project = await writeTwinProject(
      extra: {
        '.specstone/templates/implementation.yaml': _recordLayer,
        'docs/$_flutterRecord': _record(code: ['$_fr:app/lib/gone.dart']),
        'docs/$_jasprRecord': _record(code: ['$_fr:app/lib/gone.dart']),
      },
    );

    expect(_spots(_run(project, codeTarget: 'jaspr')), [
      '$_jasprRecord:${_codeLine(1, 0)}: implements_path_unresolved',
    ]);
    expect(_spots(_run(project)), hasLength(2));
  });

  test('f04/us02/fr01/e11: a code root that does not exist leaves every path unresolved', () async {
    final report = _run(
      await _project(
        _record(code: [point]),
        extra: {
          '.specstone/config.yaml':
              '${shippedPinsConfig()}code_root: nowhere\n',
        },
      ),
    );

    expect(_spots(report), [
      '$_recordPath:${_codeLine(1, 0)}: implements_path_unresolved',
    ]);
  });

  test('f04/us02/fr01/e11: a target with no code folder leaves its paths unresolved beside a target that has one', () async {
    final project = await writeTwinProject(
      without: {'jaspr_ws/app/lib/login.dart'},
      extra: {
        '.specstone/templates/implementation.yaml': _recordLayer,
        'docs/$_flutterRecord': _record(code: ['$_fr:$login:checkPassword']),
        'docs/$_jasprRecord': _record(code: ['$_fr:$login:checkPassword']),
      },
    );

    expect(_spots(_run(project)), [
      '$_jasprRecord:${_codeLine(1, 0)}: implements_path_unresolved',
    ]);
  });

  test(
    'f04/us02/fr01/e03: an empty code path is a path finding that says so',
    () async {
      final report = _run(await _project(_record(code: ['$_fr:'])));

      expect(_found(report).single.message, 'the code path is empty');
    },
  );

  test('f04/us02/fr01/e03, f04/us02/fr01/e10: a pointer with a backslash or a name Windows trims '
      'names no file on any OS, though a POSIX disk holds one', () async {
    for (final pointer in [r'app\lib\login.dart', 'app/lib/login.dart.']) {
      final root = await _project(_record(code: ['$_fr:$pointer']));
      File('${root.path}/$pointer').writeAsStringSync('class SignInPage {}\n');

      expect(_spots(_run(root)), [
        '$_recordPath:${_codeLine(1, 0)}: implements_path_unresolved',
      ], reason: pointer);
    }
  }, skip: Platform.isWindows ? 'Windows cannot hold such a name' : null);

  test('f04/us02/s7, f04/us02/fr01/e03: a pointer to a folder, or to nothing, names no file', () async {
    final folder = _run(await _project(_record(code: ['$_fr:app/lib'])));
    expect(_spots(folder), [
      '$_recordPath:${_codeLine(1, 0)}: implements_path_unresolved',
    ]);
    final gone = _run(
      await _project(_record(code: ['$_fr:app/lib/gone.dart:X'])),
    );
    expect(_spots(gone), [
      '$_recordPath:${_codeLine(1, 0)}: implements_path_unresolved',
    ]);
  });

  test(
    'f04/us02/fr01/e04, cc-s03/inv1: a pointer with no Symbol reads no file',
    () async {
      final session = openSession(
        await _project(_record(code: ['$_fr:$login'])),
      );
      addTearDown(session.close);
      final context = CheckContext(session);

      expect(checkImplements(context, session.index.at(_recordPath)!), isEmpty);
      expect(context.codeFilesRead, 0);
    },
  );

  test(
    'f04/us02/fr01/e05: a dotted Symbol resolves only when each segment does',
    () async {
      final files = {
        'app/lib/auth.dart': 'class AuthService {\n  void signIn() {}\n}\n',
      };
      final both = _run(
        await _project(
          _record(code: ['$_fr:app/lib/auth.dart:AuthService.signIn']),
          extra: files,
        ),
      );
      expect(_spots(both), isEmpty);
      final one = _run(
        await _project(
          _record(code: ['$_fr:app/lib/auth.dart:AuthService.signOut']),
          extra: files,
        ),
      );
      expect(_found(one).single.toJson()['symbol'], 'signOut');
    },
  );

  test('f04/us02/fr01/e06, f04/us02/fr01/e07: a whole word only, found in any text, comments included', () async {
    final part = _run(
      await _project(
        _record(code: [point]),
        extra: {
          login: 'class SignInPage {}\n\nbool checkPasswordNow() => true;\n',
        },
      ),
    );
    expect(_spots(part), [
      '$_recordPath:${_codeLine(1, 0)}: implements_symbol_unresolved',
    ]);
    final comment = _run(
      await _project(
        _record(code: [point]),
        extra: {
          login: 'class SignInPage {}\n// checkPassword moved; see the docs\n',
        },
      ),
    );
    expect(_spots(comment), isEmpty);
  });

  test('f04/us02/fr01/e08: an untyped doc, and a story or FR that still writes implements, get no pointer rule', () async {
    final report = _run(
      await _project(
        _record(code: [point]),
        extra: {
          'docs/prds/notes.md':
              '---\nimplements:\n  - app/lib/gone.dart:X\n---\n\n# Notes\n',
          ...edit(loginStory, [
            (
              '  - PG-01\n---',
              '  - PG-01\nimplements:\n  - app/lib/gone.dart:X\n---',
            ),
          ]),
        },
      ),
    );

    expect(_spots(report), isEmpty);
    expect(spots(report, FindingKind.untypedDoc), [
      'prds/notes.md:1: untyped_doc',
    ]);
  });

  test(
    'f04/us02/fr01/e09: an unreadable code file gives a warning and no finding',
    skip: unreadablePathSkipReason(),
    () async {
      final project = await _project(
        _record(
          code: ['$_fr:$login:SignInPage', '$_fr:app/lib/other.dart:Gone'],
        ),
        extra: {'app/lib/other.dart': 'class Other {}\n'},
      );
      final path = '${project.path}/$login';
      Process.runSync('chmod', ['000', path]);
      addTearDown(() => Process.runSync('chmod', ['644', path]));

      final report = _run(project);

      expect(_spots(report), [
        '$_recordPath:${_codeLine(1, 1)}: implements_symbol_unresolved',
      ]);
      expect(report.warnings, [
        'app/lib/login.dart: cannot read the file; implements Symbols in it are not checked',
      ]);
    },
  );

  test('f04/us02/s16, f04/us02/fr01/e12: a planned entry names a file not written yet, and resolves once implemented', () async {
    const planned = '$_fr:planned';
    const code = '$_fr:app/lib/toast.dart:showToast';
    final before = _run(
      await _project(_record(statuses: [planned], code: [code])),
    );
    expect(_spots(before), isEmpty);

    final after = _run(
      await _project(_record(statuses: [_implemented], code: [code])),
    );
    expect(_spots(after), [
      '$_recordPath:${_codeLine(1, 0)}: implements_path_unresolved',
    ]);
  });

  test('f04/us02/fr01/e13: a planned entry names a symbol not added yet, and its file is not read', () async {
    final session = openSession(
      await _project(
        _record(
          statuses: ['$_fr:planned'],
          code: ['$_fr:$login:resetPassword'],
        ),
      ),
    );
    addTearDown(session.close);
    final context = CheckContext(session);

    expect(checkImplements(context, session.index.at(_recordPath)!), isEmpty);
    expect(context.codeFilesRead, 0);
  });

  test('f04/us02/fr01/e14: an implemented and a deprecated entry both resolve in every run', () async {
    final report = _run(
      await _project(
        _record(
          statuses: ['$_story:implemented', '$_fr:deprecated'],
          code: ['$_story:app/lib/gone.dart', '$_fr:app/lib/gone.dart'],
        ),
      ),
    );

    expect(_spots(report), [
      '$_recordPath:${_codeLine(2, 0)}: implements_path_unresolved',
      '$_recordPath:${_codeLine(2, 1)}: implements_path_unresolved',
    ]);
  });

  test('f04/us02/fr01/e15: an item with no statuses line reads planned, and resolves once a line gives implemented', () async {
    const code = '$_fr:app/lib/toast.dart:showToast';
    final bare = _run(await _project(_record(statuses: [], code: [code])));
    expect(_spots(bare), isEmpty);

    final session = openSession(
      await _project(
        _record(statuses: [], code: ['$_fr:$login:resetPassword']),
      ),
    );
    addTearDown(session.close);
    final context = CheckContext(session);
    expect(checkImplements(context, session.index.at(_recordPath)!), isEmpty);
    expect(context.codeFilesRead, 0);

    final written = _run(
      await _project(_record(statuses: [_implemented], code: [code])),
    );
    expect(_spots(written), hasLength(1));
  });

  test(
    'f04/us03/fr05: a line check_record_entries reports is not resolved here',
    () async {
      final report = _run(
        await _project(
          _record(
            statuses: ['$_story:skipped:no web', '$_fr:implemented'],
            code: [
              '$_story:app/lib/gone.dart',
              '$_fr:app/lib/gone.dart',
              ':app/lib/gone.dart',
              'email_login/nothing:app/lib/gone.dart',
            ],
          ),
        ),
      );

      expect(_spots(report), isEmpty);
      expect(spots(report, FindingKind.skipWithCode), isNotEmpty);
    },
  );
}
