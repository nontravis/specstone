// The expected texts are plan literals kept as written.

import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/test_pointer_rule.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';
import '../../helpers/posix_modes.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/target_fixture.dart';

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
    '    pointer: item_exact\n'
    '  - id: tests\n'
    '    type: output_ref\n'
    '    list: true\n'
    '    pointer: item_test\n';

const _recordPath = 'specs/f01_login/IMPLEMENTATION.md';
const _flutterRecord = 'specs/flutter/f01_login/IMPLEMENTATION.md';
const _jasprRecord = 'specs/jaspr/f01_login/IMPLEMENTATION.md';

const _fr = 'email_login/check_password';
const _implemented = '$_fr:implemented';
const _testFile = 'app/test/login_test.dart';
const _testBody =
    "void main() {\n  test('shows a toast: then hides it today', () {});\n}\n";

/// Returns a record: `statuses`, then `tests`, one quoted line each.
String _record({
  List<String> statuses = const [_implemented],
  List<String> tests = const [],
}) {
  String list(String key, List<String> lines) => lines.isEmpty
      ? ''
      : "$key:\n${[for (final l in lines) "  - '$l'\n"].join()}";
  return '---\n${list('statuses', statuses)}${list('tests', tests)}'
      '---\n\n# Record\n';
}

/// The file line of the [j]th `tests` item after [statusCount] statuses.
int _testLine(int statusCount, int j) =>
    (statusCount == 0 ? 3 : 4 + statusCount) + j;

Future<Directory> _project(
  String record, {
  Map<String, String> extra = const {},
}) => writeCheckProject(
  extra: {
    '.specstone/templates/implementation.yaml': _recordLayer,
    'docs/$_recordPath': record,
    _testFile: _testBody,
    ...extra,
  },
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

List<String> _spots(CheckReport report) => [
  for (final f in report.findings)
    if (f.kind == FindingKind.testsUnresolved)
      '${f.path}:${f.line}: ${f.kind.wire}',
];

Finding _only(CheckReport report) =>
    report.findings.singleWhere((f) => f.kind == FindingKind.testsUnresolved);

void main() {
  test('a test field not named tests resolves its lines', () async {
    final report = _run(
      await writeCheckProject(
        extra: {
          '.specstone/templates/implementation.yaml':
              '$_recordLayer'
              '  - id: tests\n'
              '    disabled: true\n'
              '  - id: proofs\n'
              '    type: output_ref\n'
              '    list: true\n'
              '    pointer: item_test\n',
          'docs/$_recordPath':
              "---\nstatuses:\n  - '$_implemented'\nproofs:\n"
              "  - '$_fr:$_testFile:shows a toast'\n"
              "  - '$_fr:app/test/gone_test.dart'\n---\n\n# Record\n",
          _testFile: _testBody,
        },
        unstamped: {'docs/$_recordPath'},
      ),
    );

    expect(_spots(report), [
      '$_recordPath:${_testLine(1, 1)}: tests_unresolved',
    ]);
  });

  test('a line naming a present file and no test gives no finding', () async {
    final report = _run(await _project(_record(tests: ['$_fr:$_testFile'])));

    expect(_spots(report), isEmpty);
    expect(report.warnings, isEmpty);
  });

  test('a test file another rule read is read from that read', () async {
    final project = await _project(
      _record(tests: ['$_fr:$_testFile:shows a toast']),
    );
    final session = openSession(project);
    addTearDown(session.close);
    final context = CheckContext(session);
    context.readCodeBytes(context.targets.single, _testFile);
    File('${project.path}/$_testFile').writeAsStringSync('void main() {}\n');

    final findings = checkTestPointers(
      context,
      session.index.at(_recordPath)!,
    ).toList();

    expect(findings, isEmpty);
    expect(context.codeFilesRead, 1);
  });

  test('a line naming no test reads no file', () async {
    final project = await _project(_record(tests: ['$_fr:$_testFile']));
    final path = '${project.path}/$_testFile';
    Process.runSync('chmod', ['000', path]);
    addTearDown(() => Process.runSync('chmod', ['644', path]));

    final report = _run(project);

    expect(_spots(report), isEmpty);
    expect(report.warnings, isEmpty);
  }, skip: unreadablePathSkipReason());

  test('a test name matches as written inside a longer name, colons and '
      'spaces included', () async {
    final report = _run(
      await _project(
        _record(tests: ['$_fr:$_testFile:shows a toast: then hides it']),
      ),
    );

    expect(_spots(report), isEmpty);
  });

  test(
    'a name the file does not hold is tests_unresolved with its name',
    () async {
      final report = _run(
        await _project(_record(tests: ['$_fr:$_testFile:hides the toast'])),
      );

      expect(_spots(report), [
        '$_recordPath:${_testLine(1, 0)}: tests_unresolved',
      ]);
      final finding = _only(report);
      expect(finding.message, 'hides the toast occurs nowhere in $_testFile');
      expect(
        finding.toJson(),
        allOf(
          containsPair('entry', '$_testFile:hides the toast'),
          containsPair('name', 'hides the toast'),
          containsPair('waitsFor', 'agent'),
        ),
      );
    },
  );

  test('a folder, or a file not present, is tests_unresolved with no name '
      'key', () async {
    final report = _run(
      await _project(
        _record(
          tests: [
            '$_fr:app/test',
            '$_fr:app/test/gone_test.dart:shows a toast',
            '$_fr:',
          ],
        ),
      ),
    );

    expect(_spots(report), [
      '$_recordPath:${_testLine(1, 0)}: tests_unresolved',
      '$_recordPath:${_testLine(1, 1)}: tests_unresolved',
      '$_recordPath:${_testLine(1, 2)}: tests_unresolved',
    ]);
    final findings = report.findings
        .where((f) => f.kind == FindingKind.testsUnresolved)
        .toList();
    expect(
      findings.map((f) => f.keys.containsKey('name')),
      everyElement(false),
    );
    expect(findings.first.keys, {'entry': 'app/test'});
    expect(findings.last.message, 'the test path is empty');
  });

  test('a planned entry names a test file not written yet and gives no '
      'finding', () async {
    final report = _run(
      await _project(
        _record(
          statuses: ['$_fr:planned'],
          tests: ['$_fr:app/test/later_test.dart:shows a toast'],
        ),
      ),
    );

    expect(_spots(report), isEmpty);
  });

  test(
    'a skipped entry and an item with no entry give no finding here',
    () async {
      final report = _run(
        await _project(
          _record(
            statuses: ['$_fr:skipped:not in this client'],
            tests: ['$_fr:app/test/gone_test.dart', 'email_login:app/test/x'],
          ),
        ),
      );

      expect(_spots(report), isEmpty);
    },
  );

  test('a line naming no item of the feature gives no finding here', () async {
    final report = _run(
      await _project(
        _record(tests: ['email_login/pin:app/test/gone_test.dart', 'no colon']),
      ),
    );

    expect(_spots(report), isEmpty);
  });

  test('a deprecated entry resolves its lines', () async {
    final report = _run(
      await _project(
        _record(
          statuses: ['$_fr:deprecated'],
          tests: ['$_fr:app/test/gone_test.dart'],
        ),
      ),
    );

    expect(_spots(report), [
      '$_recordPath:${_testLine(1, 0)}: tests_unresolved',
    ]);
  });

  test('an unreadable test file gives one warning for every line naming it '
      'and no finding', () async {
    final project = await _project(
      _record(
        tests: [
          '$_fr:$_testFile:shows a toast',
          '$_fr:$_testFile:hides the toast',
        ],
      ),
    );
    final path = '${project.path}/$_testFile';
    Process.runSync('chmod', ['000', path]);
    addTearDown(() => Process.runSync('chmod', ['644', path]));

    final report = _run(project);

    expect(_spots(report), isEmpty);
    expect(report.warnings, [
      '$_testFile: cannot read the file; tests names in it are not checked',
    ]);
  }, skip: unreadablePathSkipReason());

  test(
    'one file holds two names: each missing name is its own finding',
    () async {
      final report = _run(
        await _project(
          _record(
            tests: [
              '$_fr:$_testFile:shows a toast',
              '$_fr:$_testFile:gone one',
              '$_fr:$_testFile:gone two',
            ],
          ),
        ),
      );

      expect(_spots(report), [
        '$_recordPath:${_testLine(1, 1)}: tests_unresolved',
        '$_recordPath:${_testLine(1, 2)}: tests_unresolved',
      ]);
    },
  );

  test('each target resolves its record in its own code root', () async {
    final project = await writeTwinProject(
      extra: {
        '.specstone/templates/implementation.yaml': _recordLayer,
        'flutter_ws/$_testFile': _testBody,
        'docs/$_flutterRecord': _record(
          tests: ['$_fr:$_testFile:shows a toast'],
        ),
        'docs/$_jasprRecord': _record(tests: ['$_fr:$_testFile:shows a toast']),
      },
    );

    expect(_spots(_run(project)), [
      '$_jasprRecord:${_testLine(1, 0)}: tests_unresolved',
    ]);
    expect(_spots(_run(project, codeTarget: 'flutter')), isEmpty);
  });

  test('a project with no tests field runs no test rule', () async {
    final report = _run(
      await writeCheckProject(
        extra: {
          '.specstone/config.yaml': shippedPinsConfig(['prd-core']),
        },
      ),
    );

    expect(_spots(report), isEmpty);
  });
}
