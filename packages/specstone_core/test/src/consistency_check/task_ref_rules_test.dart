// The file contents are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';

const _domain = 'specs/f01_login/DOMAIN.md';
const _error = 'specs/f01_login/ERROR.md';

String _domainDoc({
  required List<String> tasks,
  String lead = '',
  String invariants = '- **INV-4** An email is unique.',
}) =>
    '---\ntasks:\n${tasks.map((t) => '  - $t\n').join()}---\n\n'
    '# Login domain\n\n$lead## Invariants\n\n$invariants\n';

Future<Directory> _project(
  Map<String, String> docs, {
  Map<String, String> extra = const {},
}) {
  final files = {for (final e in docs.entries) 'docs/${e.key}': e.value};
  return writeCheckProject(
    extra: {...files, ...extra},
    unstamped: files.keys.toSet(),
  );
}

/// The 1-based line of the first line of [path] in [project] holding [text].
int _lineOf(Directory project, String path, String text) =>
    File('${project.path}/docs/$path')
        .readAsLinesSync()
        .indexWhere((line) => line.contains(text)) +
    1;

List<Finding> _missing(Directory project) => [
  for (final finding in checkOf(project).findings)
    if (finding.kind == FindingKind.taskItemMissing) finding,
];

void main() {
  test('an entry naming an item ID the doc holds gives no finding', () async {
    final project = await _project({
      _domain: _domainDoc(tasks: ['INV-4:ENG-42']),
    });

    expect(_missing(project), isEmpty);
  });

  test('an entry whose item is gone is one finding at the entry line with its task and item', () async {
    final project = await _project({
      _domain: _domainDoc(
        tasks: ['INV-4:ENG-42'],
        invariants: '- **INV-5** A name is unique.',
      ),
    });

    final found = _missing(project);

    expect(found, hasLength(1));
    final finding = found.single;
    expect(finding.path, _domain);
    expect(finding.name, 'login');
    expect(finding.line, _lineOf(project, _domain, 'ENG-42'));
    expect(finding.waitsFor, WaitsFor.agent);
    expect(finding.toJson(), containsPair('task', 'ENG-42'));
    expect(finding.toJson(), containsPair('item', 'INV-4'));
  });

  test('an entry names a heading by its text with the code span that encloses the whole text dropped', () async {
    final project = await _project({
      loginApi: checkProjectFiles()['docs/$loginApi']!
          .replaceFirst(
            'confirmed:',
            'tasks:\n  - set --batch:ENG-7\nconfirmed:',
          )
          .replaceFirst('### signIn', '### `set --batch`'),
    });

    expect(_missing(project), isEmpty);
  });

  test('an item written in another case is a finding', () async {
    final project = await _project({
      _domain: _domainDoc(tasks: ['inv-4:ENG-42']),
    });

    final found = _missing(project);

    expect(found, hasLength(1));
    expect(found.single.toJson(), containsPair('item', 'inv-4'));
  });

  test('a whole-doc entry gives no finding on a domain doc, an error doc, and a feature doc', () async {
    final project = await _project(
      {
        _domain: _domainDoc(tasks: ['ENG-42']),
        _error: '---\ntasks:\n  - ENG-43\n---\n\n# Login errors\n\n## Error catalog\n\n| Code | Meaning |\n|---|---|\n| login_failed | Refused |\n',
      },
      extra: {
        '.specstone/templates/feature.yaml':
            'fields:\n  - id: tickets\n    type: task_ref\n    list: true\n',
        ...edit(loginFeature, [
          ('goals:\n  - PG-01\n', 'goals:\n  - PG-01\ntickets:\n  - ENG-44\n'),
        ]),
      },
    );

    expect(_missing(project), isEmpty);
  });

  test('an entry whose item is an item ID of the lead resolves, and one the lead lacks does not', () async {
    final project = await _project({
      _domain: _domainDoc(
        tasks: ['INV-9:ENG-42', 'INV-8:ENG-43'],
        lead: '- **INV-9** A lead rule.\n\n',
      ),
    });

    final found = _missing(project);

    expect(found, hasLength(1));
    expect(found.single.toJson(), containsPair('item', 'INV-8'));
  });

  test('an entry naming an error code of a catalog row with no item ID is a finding', () async {
    final project = await _project({
      _error: '---\ntasks:\n  - login_failed:ENG-43\n---\n\n# Login errors\n\n## Error catalog\n\n| Code | Meaning |\n|---|---|\n| login_failed | Refused |\n',
    });

    final found = _missing(project);

    expect(found, hasLength(1));
    expect(found.single.path, _error);
    expect(found.single.toJson(), containsPair('item', 'login_failed'));
  });

  test('an entry that breaks the entry form is a value mismatch and no finding of this rule', () async {
    final project = await _project({
      _domain: _domainDoc(tasks: [':ENG-42', "'INV-4:'"]),
    });

    final report = checkOf(project);

    expect(_missing(project), isEmpty);
    expect(
      [
        for (final f in report.findings)
          if (f.kind == FindingKind.fieldValueMismatch) f.line,
      ],
      [_lineOf(project, _domain, 'tasks:')],
    );
  });

  test('a task ref field under another id is checked the same way', () async {
    final project = await _project(
      {},
      extra: {
        '.specstone/templates/feature.yaml':
            'fields:\n  - id: tickets\n    type: task_ref\n    list: true\n',
        ...edit(loginFeature, [
          (
            'goals:\n  - PG-01\n',
            'goals:\n  - PG-01\ntickets:\n  - ghost:ENG-44\n',
          ),
        ]),
      },
    );

    final found = _missing(project);

    expect(found, hasLength(1));
    expect(found.single.path, loginFeature);
    expect(found.single.line, _lineOf(project, loginFeature, 'ENG-44'));
    expect(found.single.toJson(), containsPair('item', 'ghost'));
  });

  test('a heading of a code span followed by a word is named by its whole text, never by the span alone', () async {
    final api = checkProjectFiles()['docs/$loginApi']!.replaceFirst(
      '### signIn',
      '### `set --batch` mode',
    );
    final project = await _project({
      loginApi: api.replaceFirst(
        'confirmed:',
        'tasks:\n  - set --batch:ENG-7\n  - "`set --batch` mode:ENG-8"\nconfirmed:',
      ),
    });

    final found = _missing(project);

    expect(found, hasLength(1));
    expect(found.single.toJson(), containsPair('task', 'ENG-7'));
    expect(found.single.toJson(), containsPair('item', 'set --batch'));
  });
}
