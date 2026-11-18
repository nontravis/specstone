// The file contents are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/nested_fixture.dart';
import '../../helpers/target_fixture.dart';

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

Future<List<Finding>> _missing(Directory project) async => [
  for (final finding in (await checkOf(project)).findings)
    if (finding.kind == FindingKind.taskItemMissing) finding,
];

Future<List<Finding>> _leftover(Directory project) async => [
  for (final finding in (await checkOf(project)).findings)
    if (finding.kind == FindingKind.taskRefLeftover) finding,
];

void main() {
  test('an entry naming an item ID the doc holds gives no finding', () async {
    final project = await _project({
      _domain: _domainDoc(tasks: ['INV-4:ENG-42']),
    });

    expect(await _missing(project), isEmpty);
  });

  test('an entry whose item is gone is one finding at the entry line with its task and item', () async {
    final project = await _project({
      _domain: _domainDoc(
        tasks: ['INV-4:ENG-42'],
        invariants: '- **INV-5** A name is unique.',
      ),
    });

    final found = await _missing(project);

    expect(found, hasLength(1));
    final finding = found.single;
    expect(finding.path, _domain);
    expect(finding.name, 'login');
    expect(finding.line, lineOfFirst(project, _domain, 'ENG-42'));
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

    expect(await _missing(project), isEmpty);
  });

  test('an item written in another case is a finding', () async {
    final project = await _project({
      _domain: _domainDoc(tasks: ['inv-4:ENG-42']),
    });

    final found = await _missing(project);

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

    expect(await _missing(project), isEmpty);
  });

  test('an entry whose item is an item ID of the lead resolves, and one the lead lacks does not', () async {
    final project = await _project({
      _domain: _domainDoc(
        tasks: ['INV-9:ENG-42', 'INV-8:ENG-43'],
        lead: '- **INV-9** A lead rule.\n\n',
      ),
    });

    final found = await _missing(project);

    expect(found, hasLength(1));
    expect(found.single.toJson(), containsPair('item', 'INV-8'));
    expect(found.single.line, lineOfFirst(project, _domain, 'ENG-43'));
  });

  test('an entry naming a heading of the lead resolves by its text', () async {
    final project = await _project({
      _domain: _domainDoc(tasks: ['Notes:ENG-42'], lead: '### Notes\n\n'),
    });

    expect(await _missing(project), isEmpty);
  });

  group('an item ID inside a closed generated block of the lead', () {
    final doc = _domainDoc(
      tasks: ['INV-9:ENG-42'],
      lead:
          '<!-- specstone:generated scenario_copy (do not edit) -->\n'
          '- **INV-9** Copied.\n'
          '<!-- specstone:generated end -->\n\n',
    );
    const layer = '.specstone/templates/domain.yaml';

    test('is no item when the doc type lists the generator', () async {
      final project = await _project(
        {_domain: doc},
        extra: {layer: 'generators: [scenario_copy]\n'},
      );

      final found = await _missing(project);

      expect(found, hasLength(1));
      expect(found.single.toJson(), containsPair('item', 'INV-9'));
    });

    test('is an item when the doc type lists no generator', () async {
      final project = await _project({_domain: doc});

      expect(await _missing(project), isEmpty);
    });
  });

  test('an entry naming an error code of a catalog row with no item ID is a finding', () async {
    final project = await _project({
      _error: '---\ntasks:\n  - login_failed:ENG-43\n---\n\n# Login errors\n\n## Error catalog\n\n| Code | Meaning |\n|---|---|\n| login_failed | Refused |\n',
    });

    final found = await _missing(project);

    expect(found, hasLength(1));
    expect(found.single.path, _error);
    expect(found.single.toJson(), containsPair('item', 'login_failed'));
  });

  test('an entry that breaks the entry form is a value mismatch and no finding of this rule', () async {
    final project = await _project({
      _domain: _domainDoc(tasks: [':ENG-42', "'INV-4:'"]),
    });

    final report = await checkOf(project);

    expect(await _missing(project), isEmpty);
    expect(
      [
        for (final f in report.findings)
          if (f.kind == FindingKind.fieldValueMismatch) f.line,
      ],
      [lineOfFirst(project, _domain, 'tasks:')],
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

    final found = await _missing(project);

    expect(found, hasLength(1));
    expect(found.single.path, loginFeature);
    expect(found.single.line, lineOfFirst(project, loginFeature, 'ENG-44'));
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

    final found = await _missing(project);

    expect(found, hasLength(1));
    expect(found.single.toJson(), containsPair('task', 'ENG-7'));
    expect(found.single.toJson(), containsPair('item', 'set --batch'));
  });

  test('a heading enclosed whole by a double-backtick span is named by the text inside it', () async {
    final api = checkProjectFiles()['docs/$loginApi']!.replaceFirst(
      '### signIn',
      '### ``a`b``',
    );
    final project = await _project({
      loginApi: api.replaceFirst(
        'confirmed:',
        'tasks:\n  - a`b:ENG-7\nconfirmed:',
      ),
    });

    expect(await _missing(project), isEmpty);
  });

  group('a task ref left on a done feature', () {
    const record = loginRecord;
    const sso = 'prds/features/f01_login/us02_sso/USER_STORY.md';
    const story = 'email_login';
    const frName = 'email_login/check_password';

    String recordOf(List<String> statuses) =>
        '---\n${statuses.isEmpty ? '' : "statuses:\n${statuses.map((s) => "  - '$s'\n").join()}"}'
        "implements:\n  - 'email_login:app/lib/login.dart:SignInPage'\n"
        "  - 'email_login/check_password:app/lib/login.dart:checkPassword'\n"
        '---\n\n# Login implementation\n';

    Future<Directory> projectWith(
      List<String> statuses, {
      List<String> tasks = const ['INV-4:ENG-42'],
      Map<String, String> extra = const {},
    }) => _project(
      {_domain: _domainDoc(tasks: tasks)},
      extra: {record: recordOf(statuses), ...extra},
    );

    Map<String, String> secondStory() => {
      'docs/$sso': checkProjectFiles()['docs/$loginStory']!.replaceFirst(
        '# Agent signs in with email',
        '# Agent signs in with a provider',
      ),
    };

    test('is one finding at the entry line with its task, item, feature, and the fix', () async {
      final project = await projectWith([
        '$story:implemented',
        '$frName:implemented',
      ]);

      final found = await _leftover(project);

      expect(found, hasLength(1));
      final finding = found.single;
      expect(finding.path, _domain);
      expect(finding.line, lineOfFirst(project, _domain, 'ENG-42'));
      expect(finding.waitsFor, WaitsFor.agent);
      expect(finding.toJson(), containsPair('task', 'ENG-42'));
      expect(finding.toJson(), containsPair('item', 'INV-4'));
      expect(finding.toJson(), containsPair('feature', 'login'));
      expect(
        finding.message,
        'task ENG-42 is left on the done feature login; '
        'drop the entry with specstone set domain:login --field tasks '
        '--base <bases.fields.tasks of get --json>, '
        'the list less the entry on stdin',
      );
    });

    test('is none while one FR is planned or has no statuses line', () async {
      final planned = await projectWith([
        '$story:implemented',
        '$frName:planned',
      ]);
      final noLine = await projectWith(['$story:implemented']);
      final bare = await projectWith([]);

      expect(await _leftover(planned), isEmpty);
      expect(await _leftover(noLine), isEmpty);
      expect(await _leftover(bare), isEmpty);
    });

    test(
      'leaves out a skipped story with its FRs, and a deprecated FR',
      () async {
        final skipped = await projectWith([
          '$story:skipped:no web',
          'sso:implemented',
        ], extra: secondStory());
        final deprecated = await projectWith([
          '$story:implemented',
          '$frName:deprecated',
        ]);

        expect(await _leftover(skipped), hasLength(1));
        expect(await _leftover(deprecated), hasLength(1));
      },
    );

    test('is none when every entry is skipped or deprecated and none is implemented', () async {
      final deprecated = await projectWith([
        '$story:deprecated',
        '$frName:deprecated',
      ]);
      final mixed = await projectWith([
        '$story:deprecated',
        '$frName:skipped:no web',
      ]);

      expect(await _leftover(deprecated), isEmpty);
      expect(await _leftover(mixed), isEmpty);
    });

    test('is none when the feature is skipped by its own entry', () async {
      final project = await projectWith([
        ':skipped:no web',
        '$story:implemented',
        '$frName:implemented',
      ]);

      expect(await _leftover(project), isEmpty);
    });

    group('with nested features', () {
      const cartDoc = 'docs/$cartDomain';
      const shopRecord = '.specstone/records/f02_shop/IMPLEMENTATION.md';

      Future<Directory> nested(
        String refund, {
        String doc = cartDoc,
        Map<String, String> extra = const {},
      }) => writeNestedProject(
        extra: {
          ...nestedRecords(refund: refund),
          doc:
              '---\ntasks:\n  - ENG-42\n---\n\n# Domain\n\n## Entities\n| Entity | Kind | Identity | Owns | Notes |\n'
              '|--------|------|----------|------|-------|\n| Order | Aggregate root | id | lines | — |\n\n'
              '## Invariants\n- **INV-1** An order holds at least one line.\n',
          ...extra,
        },
      );

      test('waits for every story and FR of the nested features', () async {
        const shopDoc = 'docs/$shopDomain';

        expect(await _leftover(await nested('planned', doc: shopDoc)), isEmpty);
        expect(
          await _leftover(await nested('implemented', doc: shopDoc)),
          hasLength(1),
        );
      });

      test('is none under a skip of a feature above', () async {
        final project = await nested(
          'implemented',
          extra: {
            shopRecord: "---\nstatuses:\n  - ':skipped:no shop'\n---\n\n# Shop implementation\n",
          },
        );

        expect(await _leftover(project), isEmpty);
      });
    });

    test('is none on a doc whose doc type has no feature parent', () async {
      final project = await _project(
        {},
        extra: {
          '.specstone/templates/tech_stack.yaml':
              'fields:\n  - id: tickets\n    type: task_ref\n    list: true\n',
          '.specstone/templates/feature.yaml':
              'fields:\n  - id: tickets\n    type: task_ref\n    list: true\n',
          '.specstone/templates/topic.yaml':
              'fields:\n  - id: tickets\n    type: task_ref\n    list: true\n',
          'docs/specs/topics/rules.md': '---\ncovers:\n  - app/lib/\ntickets:\n  - ENG-46\n---\n\n# Rules\n\n## Rules\n\n- **R-1** A rule.\n',
          ...edit(techStack, [
            (
              'code:\n  - app/lib/\n',
              'code:\n  - app/lib/\ntickets:\n  - ENG-45\n',
            ),
          ]),
          ...edit(loginFeature, [
            (
              'goals:\n  - PG-01\n',
              'goals:\n  - PG-01\ntickets:\n  - ENG-44\n',
            ),
          ]),
        },
      );

      expect(await _leftover(project), isEmpty);
    });

    test('is one finding for a whole-doc entry with an empty item', () async {
      final project = await projectWith(
        ['$story:implemented', '$frName:implemented'],
        tasks: ['ENG-42'],
      );

      final found = await _leftover(project);

      expect(found, hasLength(1));
      expect(found.single.toJson(), containsPair('item', ''));
    });

    test('names the field the entry sits in', () async {
      final project = await _project(
        {},
        extra: {
          '.specstone/templates/domain.yaml':
              'fields:\n  - id: tickets\n    type: task_ref\n    list: true\n',
          'docs/$_domain': '---\ntickets:\n  - ENG-42\n---\n\n# Login domain\n\n## Invariants\n\n- **INV-4** An email is unique.\n',
        },
      );

      expect(
        (await _leftover(project)).single.message,
        contains('--field tickets --base <bases.fields.tickets of get --json>'),
      );
    });

    group('on a doc shared across code targets', () {
      const flutterRecord =
          '.specstone/records/flutter/f01_login/IMPLEMENTATION.md';
      const jasprRecord =
          '.specstone/records/jaspr/f01_login/IMPLEMENTATION.md';

      Future<Directory> twins(List<String> flutter, List<String> jaspr) {
        String twin(List<String> statuses) =>
            "---\nstatuses:\n${statuses.map((s) => "  - '$s'\n").join()}---\n\n# Login implementation\n";
        return writeTwinProject(
          extra: {
            ...edit(loginApi, [
              ('confirmed:', 'tasks:\n  - ENG-42\nconfirmed:'),
            ]),
            flutterRecord: twin(flutter),
            jasprRecord: twin(jaspr),
          },
        );
      }

      const done = ['$story:implemented', '$frName:implemented'];
      const skipped = [':skipped:no jaspr'];
      const planned = ['$story:implemented', '$frName:planned'];

      Future<List<Finding>> leftoverOn(Directory project) async => [
        for (final f in await _leftover(project))
          if (f.path == loginApi) f,
      ];

      test(
        'is one finding once done in every target that does not skip it',
        () async {
          expect(await leftoverOn(await twins(done, done)), hasLength(1));
          expect(await leftoverOn(await twins(done, skipped)), hasLength(1));
        },
      );

      test(
        'is none while one target that does not skip it is not done',
        () async {
          expect(await leftoverOn(await twins(done, planned)), isEmpty);
        },
      );

      test('is none when every target skips the feature', () async {
        expect(await leftoverOn(await twins(skipped, skipped)), isEmpty);
      });

      test('names the target on both the get and the set of the fix', () async {
        final project = await twins(done, done);
        final twin = File('${project.path}/docs/$flutterArchitecture');
        twin.writeAsStringSync(
          twin.readAsStringSync().replaceFirst(
            'covers:',
            'tasks:\n  - ENG-42\ncovers:',
          ),
        );

        final fix = (await _leftover(project))
            .singleWhere((f) => f.path == flutterArchitecture)
            .message;

        expect(fix, contains('--field tasks --target flutter --base '));
        expect(fix, contains('of get --json --target flutter>'));
      });
    });

    test('is read from a record that sits outside specs', () async {
      final project = await writeCheckProject(
        without: {record},
        unstamped: {'docs/$_domain'},
        extra: {
          'docs/$_domain': _domainDoc(tasks: ['INV-4:ENG-42']),
          '.specstone/templates/implementation.yaml': 'id: implementation\npath: records/f{nn}_{slug}/IMPLEMENTATION.md\n',
          'docs/records/f01_login/IMPLEMENTATION.md': recordOf([
            '$story:implemented',
            '$frName:implemented',
          ]),
        },
      );

      expect(await _leftover(project), hasLength(1));
    });

    test('comes with the missing-item finding when the entry names an item the doc lacks', () async {
      final project = await projectWith(
        ['$story:implemented', '$frName:implemented'],
        tasks: ['INV-9:ENG-42'],
      );

      expect(await _missing(project), hasLength(1));
      expect(await _leftover(project), hasLength(1));
    });
  });
}
