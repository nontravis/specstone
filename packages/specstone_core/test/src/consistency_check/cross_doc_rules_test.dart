import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';

const Set<FindingKind> _crossKinds = {
  FindingKind.systemUnresolved,
  FindingKind.operationUnmatched,
  FindingKind.scopeOperationUnresolved,
  FindingKind.scopePathUncovered,
};

const _featuresSystemsTable =
    '# Features\n\n## System interaction diagram\n\n'
    'One system.\n\n## Systems\n\n| System | Description |\n|---|---|\n'
    '| Mobile app | The app people sign in on. |\n';

const _authDoc = 'specs/f01_login/AUTH.md';
const _topicDoc = 'specs/topics/rendering.md';

late Directory _project;

Future<List<Finding>> _found(Map<String, String> edits) async {
  _project = await writeCheckProject(extra: edits);
  return [
    for (final f in checkOf(_project).findings)
      if (_crossKinds.contains(f.kind)) f,
  ];
}

int _lineOf(String docPath, String needle) =>
    File('${_project.path}/docs/$docPath')
        .readAsLinesSync()
        .indexWhere((line) => line.contains(needle)) +
    1;

void main() {
  test('a feature system naming a Systems row has no finding', () async {
    final found = await _found({
      'docs/prds/FEATURES.md': _featuresSystemsTable,
      'docs/$loginFeature': featureWith('system: Mobile app'),
    });
    expect(found, isEmpty);
  });

  test('a feature system naming no Systems row is system_unresolved at the '
      'key', () async {
    final found = await _found({
      'docs/prds/FEATURES.md': _featuresSystemsTable,
      'docs/$loginFeature': featureWith('system: Watch app'),
    });
    expect(found, hasLength(1));
    expect(found.single.kind, FindingKind.systemUnresolved);
    expect(found.single.line, _lineOf(loginFeature, 'system: Watch app'));
    expect(found.single.toJson(), containsPair('system', 'Watch app'));
    expect(found.single.waitsFor, WaitsFor.agent);
  });

  test('an api fr_trace row with no operations block is operation_unmatched at '
      'the row', () async {
    final found = await _found({
      'docs/$loginApi': checkFixtureApiWith(
        operation: '`specstone check --repeats`',
      ),
    });
    expect(found, hasLength(2));
    final byLine = {for (final f in found) f.line: f};
    final row = byLine[_lineOf(loginApi, 'specstone check --repeats')];
    expect(row?.kind, FindingKind.operationUnmatched);
    expect(
      row?.toJson(),
      containsPair('operation', 'specstone check --repeats'),
    );
    final block = byLine[_lineOf(loginApi, '### signIn')];
    expect(block?.kind, FindingKind.operationUnmatched);
    expect(block?.toJson(), containsPair('operation', 'signIn'));
  });

  test('an operations block with no fr_trace row is operation_unmatched at '
      'its heading', () async {
    final found = await _found({
      'docs/$loginApi': checkFixtureApiWith(
        heading:
            '### signIn\n\nSigns the Agent in.\n\n### `signOut`\n\n'
            'Signs the Agent out.',
      ),
    });
    expect(found, hasLength(1));
    expect(found.single.kind, FindingKind.operationUnmatched);
    expect(found.single.line, _lineOf(loginApi, '### `signOut`'));
    expect(found.single.toJson(), containsPair('operation', 'signOut'));
  });

  test('two rows naming one operation and one block give no finding', () async {
    final found = await _found({
      'docs/$loginApi': checkFixtureApiWith(
        trace:
            '| email_login/check_password | `signIn` |\n'
            '| email_login/sign_in_time | `signIn` |',
      ),
    });
    expect(
      found.where((f) => f.kind == FindingKind.operationUnmatched),
      isEmpty,
    );
  });

  test('an auth scope naming no api operation of its feature is '
      'scope_operation_unresolved', () async {
    final found = await _found({
      'docs/$_authDoc': _authDocText(requiredFor: 'deleteAccount'),
    });
    expect(found, hasLength(1));
    expect(found.single.kind, FindingKind.scopeOperationUnresolved);
    expect(found.single.line, _lineOf(_authDoc, 'deleteAccount'));
    expect(found.single.toJson(), containsPair('operation', 'deleteAccount'));
  });

  test(
    'an auth scope naming an api operation of its feature has no finding',
    () async {
      final found = await _found({
        'docs/$_authDoc': _authDocText(requiredFor: 'signIn'),
      });
      expect(found, isEmpty);
    },
  );

  test(
    'a topic scope path no covers prefix reaches is scope_path_uncovered',
    () async {
      final found = await _found({
        'docs/$_topicDoc': _topicDocText(
          covers: '  - lib/src/doc_model/\n',
          scope: 'The topic governs `lib/src/rendering/`.',
        ),
      });
      expect(found, hasLength(1));
      expect(found.single.kind, FindingKind.scopePathUncovered);
      expect(found.single.line, _lineOf(_topicDoc, 'lib/src/rendering/'));
      expect(found.single.toJson(), containsPair('path', 'lib/src/rendering/'));
    },
  );

  test('a topic scope path a covers prefix reaches has no finding', () async {
    final found = await _found({
      'docs/$_topicDoc': _topicDocText(
        covers: '  - lib/src/\n',
        scope: 'The topic governs `lib/src/rendering/`.',
      ),
    });
    expect(found, isEmpty);
  });

  test(
    'a covers entry ending in a code fingerprint still reaches its prefix',
    () async {
      final found = await _found({
        'docs/$_topicDoc': _topicDocText(
          covers: '  - lib/src/ 5d1e0c4b7a92\n',
          scope: 'The topic governs `lib/src/rendering/`.',
        ),
      });
      expect(found, isEmpty);
    },
  );

  test('a merged set that lacks the field a rule reads runs no rule', () async {
    final found = await _found({
      '.specstone/templates/feature.yaml':
          'fields:\n'
          '  - id: system\n'
          '    disabled: true\n',
      'docs/$loginFeature': featureWith('system: Watch app'),
    });
    expect(found, isEmpty);
  });
}

String featureWith(String line) =>
    edit(loginFeature, [('---\n', '---\n$line\n')])['docs/$loginFeature']!;

String checkFixtureApiWith({
  String? trace,
  String? operation,
  String? heading,
}) {
  var api = checkFixtureApi();
  if (trace != null) {
    api = api.replaceFirst('| email_login/check_password | `signIn` |', trace);
  }
  if (operation != null) {
    api = api.replaceFirst(
      '| email_login/check_password | `signIn` |',
      '| email_login/check_password | $operation |',
    );
  }
  if (heading != null) {
    api = api.replaceFirst('### signIn\n\nSigns the Agent in.', heading);
  }
  return api;
}

String checkFixtureApi() =>
    withApprovalHashes(checkProjectFiles())['docs/$loginApi']!;

String _authDocText({required String requiredFor}) =>
    '---\n---\n\n# Login auth\n\n## Roles\n\n| Role | Scope inheritance | '
    'Introduced by | Notes |\n|---|---|---|---|\n| Agent | — | login | The '
    'agent. |\n\n## Scopes\n\n| Scope | Action | Required for |\n|---|---|---|'
    '\n| `account:delete` | delete | $requiredFor |\n\n## Resource matrix\n\n'
    'Default: deny\n\n## Enforcement\n\nThe server layer.\n\n## Audit\n\n| '
    'Event | Triggered by | Logged fields |\n|---|---|---|\n| delete | '
    'account:delete | who, when |\n';

String _topicDocText({required String covers, required String scope}) =>
    '---\ncovers:\n$covers---\n\n# Rendering\n\n## Purpose\n\nOne '
    'paragraph.\n\n## Scope\n\n$scope\n\n## Used by\n\n| Feature | What it '
    'uses |\n|---|---|\n| login | The rules. |\n';
