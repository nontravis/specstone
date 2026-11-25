import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/rulebook_fixture.dart';
import '../../helpers/shipped_pins.dart';

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

/// A project layer that types [_authDoc] with a `scopes` section, which no
/// shipped type holds.
const Map<String, String> _accessLayer = {
  '.specstone/templates/access.yaml':
      "id: access\ndescription: |-\n  One feature's access rules.\n"
      'path: specs/f{nn}_{slug}/AUTH.md\nparent: feature\nper_target: true\n'
      'sections:\n  - id: scopes\n    header: Scopes\n    description: |-\n'
      '      Write a table of Scope, Action, Required for.\n',
};

late Directory _project;

Future<List<Finding>> _found(
  Map<String, String> edits, {
  Set<String> without = const {},
}) async {
  _project = await writeCheckProject(extra: edits, without: without);
  return [
    for (final f in (await checkOf(_project)).findings)
      if (_crossKinds.contains(f.kind)) f,
  ];
}

/// The `covers` field block of [charterLayer].
const _charterCovers =
    '  - id: covers\n    type: output_ref\n    list: true\n'
    '    required: true\n    pointer: prefix\n    description: |-\n'
    '      Lists the code folders or files the charter covers.\n';

/// The `scope` section block of [charterLayer].
const _charterScope =
    '  - id: scope\n    header: Scope\n    required: true\n'
    '    description: |-\n      Write what it covers.\n';

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
    expect(
      found.single.line,
      lineOfFirst(_project, loginFeature, 'system: Watch app'),
    );
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
    final row =
        byLine[lineOfFirst(_project, loginApi, 'specstone check --repeats')];
    expect(row?.kind, FindingKind.operationUnmatched);
    expect(
      row?.toJson(),
      containsPair('operation', 'specstone check --repeats'),
    );
    final block = byLine[lineOfFirst(_project, loginApi, '### signIn')];
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
    expect(found.single.line, lineOfFirst(_project, loginApi, '### `signOut`'));
    expect(found.single.toJson(), containsPair('operation', 'signOut'));
  });

  test('a quoted operations heading is an operations block', () async {
    final found = await _found({
      'docs/$loginApi': checkFixtureApiWith(
        heading:
            '### signIn\n\nSigns the Agent in.\n\n> ### `signOut`\n>\n'
            '> Signs the Agent out.',
      ),
    });
    expect(found, hasLength(1));
    expect(found.single.kind, FindingKind.operationUnmatched);
    expect(
      found.single.line,
      lineOfFirst(_project, loginApi, '> ### `signOut`'),
    );
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
      ..._accessLayer,
      'docs/$_authDoc': _authDocText(requiredFor: 'deleteAccount'),
    });
    expect(found, hasLength(1));
    expect(found.single.kind, FindingKind.scopeOperationUnresolved);
    expect(found.single.line, lineOfFirst(_project, _authDoc, 'deleteAccount'));
    expect(found.single.toJson(), containsPair('operation', 'deleteAccount'));
  });

  test(
    'an auth scope naming an api operation of its feature has no finding',
    () async {
      final found = await _found({
        ..._accessLayer,
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
      expect(
        found.single.line,
        lineOfFirst(_project, _topicDoc, 'lib/src/rendering/'),
      );
      expect(
        found.single.toJson(),
        containsPair('codePath', 'lib/src/rendering/'),
      );
      expect(found.single.toJson()['path'], isNot('lib/src/rendering/'));
    },
  );

  test('an empty covers entry reaches no topic scope path', () async {
    for (final form in ["''", '.', './', '/', 'lib/..', './ 5d1e0c4b7a92']) {
      final found = await _found({
        'docs/$_topicDoc': _topicDocText(
          covers: '  - $form\n',
          scope: 'The topic governs `lib/src/rendering/`.',
        ),
      });
      expect(found.map((f) => f.kind), [
        FindingKind.scopePathUncovered,
      ], reason: form);
    }
  });

  test('a topic scope path a covers prefix reaches has no finding', () async {
    final found = await _found({
      'docs/$_topicDoc': _topicDocText(
        covers: '  - lib/src/\n',
        scope: 'The topic governs `lib/src/rendering/`.',
      ),
    });
    expect(found, isEmpty);
  });

  test('a covers entry ending in a fingerprint reaches its own scope path and '
      'leaves an unreached one scope_path_uncovered', () async {
    final found = await _found({
      'docs/$_topicDoc': _topicDocText(
        covers: '  - lib/src/doc_model/ 5d1e0c4b7a92\n',
        scope:
            'The topic governs `lib/src/doc_model/` and '
            '`lib/src/rendering/`.',
      ),
    });

    expect(found, hasLength(1));
    expect(found.single.kind, FindingKind.scopePathUncovered);
    expect(
      found.single.toJson(),
      containsPair('codePath', 'lib/src/rendering/'),
    );

    final reached = await _found({
      'docs/$_topicDoc': _topicDocText(
        covers: '  - lib/src/ 5d1e0c4b7a92\n',
        scope: 'The topic governs `lib/src/rendering/`.',
      ),
    });
    expect(reached, isEmpty);
  });

  test('an upper-case token stays part of the covers prefix', () async {
    final found = await _found({
      'docs/$_topicDoc': _topicDocText(
        covers: '  - lib/src/ 5D1E0C4B7A92\n',
        scope: 'The topic governs `lib/src/rendering/`.',
      ),
    });

    expect(found.single.kind, FindingKind.scopePathUncovered);
  });

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

  test('a merged set whose topic lacks the covers field or the scope section '
      'runs no scope rule', () async {
    const uncovered =
        '---\ncovers:\n  - lib/src/\n---\n\n# Rendering\n\n'
        '## Purpose\n\nOne paragraph.\n\n## Scope\n\n'
        'Governs `lib/other/`.\n\n## Used by\n\n| Feature | What it uses |\n'
        '|---|---|\n| login | The rules. |\n';
    final fires = await _found({'docs/$_topicDoc': uncovered});
    expect(fires.map((f) => f.kind), [FindingKind.scopePathUncovered]);

    for (final layer in [
      charterLayer.replaceFirst(_charterCovers, ''),
      charterLayer.replaceFirst(_charterScope, ''),
    ]) {
      final found = await _found({
        charterLayerFile: layer,
        'docs/$_topicDoc': uncovered,
      });
      expect(found, isEmpty, reason: layer);
    }
  });

  test('a merged set lacking the api, auth, and topic doc types runs none of '
      'their rules and still runs the system rule', () async {
    final found = await _found(
      {
        '.specstone/config.yaml': shippedPinsConfig(['prd-core']),
        'docs/prds/FEATURES.md': _featuresSystemsTable,
        'docs/$loginFeature': featureWith('system: Watch app'),
        'docs/$_authDoc': _authDocText(requiredFor: 'deleteAccount'),
        'docs/$_topicDoc': _topicDocText(
          covers: '  - lib/src/\n',
          scope: 'Governs `lib/other/`.',
        ),
      },
      without: {charterLayerFile},
    );

    expect(found.map((f) => f.kind), [FindingKind.systemUnresolved]);
  });

  test('a doc type holding the ids under other names still fires', () async {
    final found = await _found({
      '.specstone/templates/sysmap.yaml':
          'id: sysmap\n'
          'description: Map.\npath: ops/map.md\n'
          'sections:\n  - id: systems\n    header: Systems\n',
      '.specstone/templates/unit.yaml':
          'id: unit\n'
          'description: Unit.\npath: ops/units/{slug}.md\n'
          'fields:\n  - id: system\n    type: string\n',
      '.specstone/templates/ruleset.yaml':
          'id: ruleset\n'
          'description: Rules.\npath: ops/sets/{slug}.md\n'
          'fields:\n  - id: covers\n    type: output_ref\n'
          '    list: true\n    pointer: prefix\n'
          'sections:\n  - id: scope\n    header: Scope\n',
      'docs/ops/map.md': _featuresSystemsTable,
      'docs/ops/units/a.md': '---\nsystem: Watch app\n---\n\n# A\n',
      'docs/ops/sets/b.md':
          '---\ncovers:\n  - lib/a/\n---\n\n# B\n\n'
          '## Scope\n\nGoverns `lib/b/`.\n',
    });
    expect(
      found.map((f) => f.kind),
      unorderedEquals([
        FindingKind.systemUnresolved,
        FindingKind.scopePathUncovered,
      ]),
    );
  });

  test('a scope code span that is no path is not read as one', () async {
    final found = await _found({
      'docs/$_topicDoc': _topicDocText(
        covers: '  - lib/src/\n',
        scope: 'The `Renderer` class governs `lib/src/rendering/`.',
      ),
    });
    expect(found, isEmpty);
  });

  test(
    'an api without its operations section leaves auth scopes unchecked',
    () async {
      final found = await _found({
        '.specstone/templates/api.yaml':
            'sections:\n  - id: operations\n    disabled: true\n',
        ..._accessLayer,
        'docs/$_authDoc': _authDocText(requiredFor: 'deleteAccount'),
      });
      expect(
        found.where((f) => f.kind == FindingKind.scopeOperationUnresolved),
        isEmpty,
      );
    },
  );
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
