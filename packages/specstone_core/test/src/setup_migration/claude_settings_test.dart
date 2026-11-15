import 'dart:convert';

import 'package:specstone_core/src/setup_migration/claude_settings.dart';
import 'package:test/test.dart';

const Map<String, Object?> _group = {
  'matcher': 'Write|Edit',
  'hooks': [
    {
      'type': 'command',
      'command': 'specstone',
      'args': ['hook', 'post-edit'],
    },
  ],
};

SettingsState _read(String text) => settingsStateOf(utf8.encode(text));

Map<String, Object?> _object(String text) =>
    jsonDecode(text) as Map<String, Object?>;

String _json(Object? value, {String indent = '  '}) =>
    JsonEncoder.withIndent(indent).convert(value);

Map<String, Object?> _handler(List<String> args, {Object? timeout}) => {
  'type': 'command',
  'command': 'specstone',
  'args': args,
  'timeout': ?timeout,
};

Map<String, Object?> _specstoneGroup(
  List<String> args, {
  String matcher = 'Write|Edit',
  Object? timeout,
}) => {
  'matcher': matcher,
  'hooks': [_handler(args, timeout: timeout)],
};

const _ownerHandler = {'type': 'command', 'command': 'lint'};

String _staleText(String input) {
  final state = _read(input);
  expect(state, isA<SettingsStale>());
  return (state as SettingsStale).text;
}

List<Object?> _postToolUse(String text) =>
    (_object(text)['hooks']! as Map<String, Object?>)['PostToolUse']!
        as List<Object?>;

int _specstoneHandlerCount(String text) {
  final hooks =
      (_object(text)['hooks'] ?? <String, Object?>{}) as Map<String, Object?>;
  var count = 0;
  for (final groups in hooks.values) {
    for (final group in groups! as List<Object?>) {
      final handlers =
          (group! as Map<String, Object?>)['hooks']! as List<Object?>;
      count += handlers.where(isSpecstoneHandler).length;
    }
  }
  return count;
}

void main() {
  group('missing file', () {
    test('creates a text holding the group alone', () {
      final state = settingsStateOf(null);

      expect(state, isA<SettingsMissing>());
      final text = (state as SettingsMissing).text;
      expect(_object(text), {
        'hooks': {
          'PostToolUse': [_group],
        },
      });
      expect(text.endsWith('}\n'), isTrue);
      expect(text.endsWith('\n\n'), isFalse);
      expect(text, startsWith('{\n  "hooks": {\n'));
    });

    test('the created text reads back as current', () {
      final text = (settingsStateOf(null) as SettingsMissing).text;

      expect(_read(text), isA<SettingsCurrent>());
    });
  });

  group('current', () {
    test('a file holding exactly the group', () {
      final text = _json({
        'hooks': {
          'PostToolUse': [_group],
        },
      });

      expect(_read(text), isA<SettingsCurrent>());
    });

    test('a hand-laid-out file already holding the group is not rewritten', () {
      const text =
          '{\r\n'
          '\t"permissions": {"allow": ["Bash"]},\r\n'
          '\t"hooks": {\r\n'
          '\t\t"PostToolUse": [\r\n'
          '\t\t\t{"hooks": [{"args": ["hook", "post-edit"], '
          '"command": "specstone", "type": "command"}], '
          '"matcher": "Write|Edit"}\r\n'
          '\t\t]\r\n'
          '\t},\r\n'
          '\t"model": "opus"\r\n'
          '}';

      expect(_read(text), isA<SettingsCurrent>());
    });

    test('the group at any position among the Owner groups', () {
      final owner = {
        'matcher': 'Bash',
        'hooks': [_ownerHandler],
      };
      for (final groups in [
        [_group, owner],
        [owner, _group],
        [owner, _group, owner],
      ]) {
        final text = _json({
          'model': 'opus',
          'hooks': {'PostToolUse': groups},
        });

        expect(_read(text), isA<SettingsCurrent>(), reason: '$groups');
      }
    });

    test('the group compared by value, not by key order', () {
      final reordered = {
        'hooks': [
          {
            'args': ['hook', 'post-edit'],
            'command': 'specstone',
            'type': 'command',
          },
        ],
        'matcher': 'Write|Edit',
      };
      final text = _json({
        'hooks': {
          'PostToolUse': [reordered],
        },
      });

      expect(_read(text), isA<SettingsCurrent>());
    });
  });

  group('stale', () {
    test('an old matcher gives the group once, appended last', () {
      final text = _staleText(
        _json({
          'hooks': {
            'PostToolUse': [
              _specstoneGroup(['hook', 'post-edit'], matcher: 'Write'),
              {
                'matcher': 'Bash',
                'hooks': [_ownerHandler],
              },
            ],
          },
        }),
      );

      expect(_specstoneHandlerCount(text), 1);
      final groups = _postToolUse(text);
      expect(groups, hasLength(2));
      expect(groups.last, _group);
      expect((groups.first! as Map<String, Object?>)['matcher'], 'Bash');
    });

    test('an added timeout gives the group once, appended last', () {
      final text = _staleText(
        _json({
          'hooks': {
            'PostToolUse': [
              _specstoneGroup(['hook', 'post-edit'], timeout: 10),
            ],
          },
        }),
      );

      expect(_specstoneHandlerCount(text), 1);
      expect(_postToolUse(text), [_group]);
    });

    test('an args the binary does not write gives the group once', () {
      final text = _staleText(
        _json({
          'hooks': {
            'SessionStart': [
              _specstoneGroup(['hook', 'session-start'], matcher: 'startup'),
            ],
          },
        }),
      );

      expect(_specstoneHandlerCount(text), 1);
      expect(_postToolUse(text).last, _group);
    });

    test('a file with no hooks gains hooks and PostToolUse last', () {
      final text = _staleText(_json({'model': 'opus'}));

      final root = _object(text);
      expect(root.keys, ['model', 'hooks']);
      expect(_postToolUse(text), [_group]);
    });

    test('hooks without PostToolUse gains PostToolUse after its events', () {
      final text = _staleText(
        _json({
          'hooks': {
            'Stop': [
              {
                'hooks': [_ownerHandler],
              },
            ],
          },
        }),
      );

      final hooks = _object(text)['hooks']! as Map<String, Object?>;
      expect(hooks.keys, ['Stop', 'PostToolUse']);
    });

    test('the group stays last after the stale text is read again', () {
      final text = _staleText(
        _json({
          'hooks': {
            'PostToolUse': [
              _specstoneGroup(['hook', 'post-edit'], timeout: 10),
              {
                'matcher': 'Bash',
                'hooks': [_ownerHandler],
              },
            ],
          },
        }),
      );

      expect(_read(text), isA<SettingsCurrent>());
    });

    test('two Specstone groups give one', () {
      final text = _staleText(
        _json({
          'hooks': {
            'PostToolUse': [_group, _group],
          },
        }),
      );

      expect(_specstoneHandlerCount(text), 1);
      expect(_postToolUse(text), [_group]);
    });

    test('an Owner handler in a Specstone group stays in that group', () {
      final shared = {
        'matcher': 'Write|Edit',
        'hooks': [
          _ownerHandler,
          _handler(['hook', 'post-edit'], timeout: 5),
        ],
      };
      final text = _staleText(
        _json({
          'hooks': {
            'PostToolUse': [shared],
          },
        }),
      );

      final groups = _postToolUse(text);
      expect(groups, [
        {
          'matcher': 'Write|Edit',
          'hooks': [_ownerHandler],
        },
        _group,
      ]);
    });

    test("a handler that only looks like Specstone is the Owner's", () {
      final lookalikes = [
        {
          'type': 'command',
          'command': 'specstone',
          'args': ['check'],
        },
        {'type': 'command', 'command': 'specstone'},
        {
          'type': 'command',
          'command': 'other',
          'args': ['hook'],
        },
        {
          'type': 'prompt',
          'command': 'specstone',
          'args': ['hook'],
        },
      ];
      final text = _staleText(
        _json({
          'hooks': {
            'PostToolUse': [
              {'matcher': 'Write|Edit', 'hooks': lookalikes},
            ],
          },
        }),
      );

      expect(_postToolUse(text).first, {
        'matcher': 'Write|Edit',
        'hooks': lookalikes,
      });
      expect(_specstoneHandlerCount(text), 1);
    });
  });

  group('emptied parts', () {
    test('drops an emptied group, event array, and keeps non-empty ones', () {
      final text = _staleText(
        _json({
          'hooks': {
            'SessionStart': [
              _specstoneGroup(['hook', 'session-start'], matcher: 'startup'),
            ],
            'Stop': [
              _specstoneGroup(['hook', 'stop'], matcher: ''),
              {
                'hooks': [_ownerHandler],
              },
            ],
            'Notification': [
              {
                'hooks': [_ownerHandler],
              },
            ],
          },
        }),
      );

      final hooks = _object(text)['hooks']! as Map<String, Object?>;
      expect(hooks.keys, ['Stop', 'Notification', 'PostToolUse']);
      expect(hooks['Stop'], [
        {
          'hooks': [_ownerHandler],
        },
      ]);
    });

    test('keeps the Owner key of a group the removal emptied', () {
      final text = _staleText(
        _json({
          'hooks': {
            'PostToolUse': [
              {
                'matcher': 'Write|Edit',
                'hooks': [
                  _handler(['hook', 'post-edit']),
                ],
                'x': 1,
              },
            ],
          },
        }),
      );

      final groups = _postToolUse(text);
      expect(groups, hasLength(2));
      expect((groups.first! as Map<String, Object?>)['x'], 1);
      expect(_specstoneHandlerCount(text), 1);
    });

    test('keeps a group or event the Owner left empty', () {
      final text = _staleText(
        _json({
          'hooks': {
            'Stop': <Object?>[],
            'PostToolUse': [
              {'matcher': 'Bash', 'hooks': <Object?>[]},
            ],
          },
        }),
      );

      final hooks = _object(text)['hooks']! as Map<String, Object?>;
      expect(hooks['Stop'], <Object?>[]);
      expect(_postToolUse(text).first, {
        'matcher': 'Bash',
        'hooks': <Object?>[],
      });
    });

    test('hooks and PostToolUse keep their place when refilled', () {
      final text = _staleText(
        _json({
          'first': 1,
          'hooks': {
            'Alpha': [
              {
                'hooks': [_ownerHandler],
              },
            ],
            'PostToolUse': [
              _specstoneGroup(['hook', 'post-edit'], timeout: 1),
            ],
            'Omega': [
              {
                'hooks': [_ownerHandler],
              },
            ],
          },
          'last': 2,
        }),
      );

      final root = _object(text);
      expect(root.keys, ['first', 'hooks', 'last']);
      expect((root['hooks']! as Map<String, Object?>).keys, [
        'Alpha',
        'PostToolUse',
        'Omega',
      ]);
    });

    test('hooks holding only an old Specstone event keeps its place', () {
      final text = _staleText(
        _json({
          'first': 1,
          'hooks': {
            'SessionStart': [
              _specstoneGroup(['hook', 'session-start'], matcher: 'startup'),
            ],
          },
          'last': 2,
        }),
      );

      final root = _object(text);
      expect(root.keys, ['first', 'hooks', 'last']);
      expect(root['hooks'], {
        'PostToolUse': [_group],
      });
    });
  });

  group('Owner content', () {
    test('keeps enabledPlugins, permissions, and every other key', () {
      final input = {
        'enabledPlugins': {'a@b': true, 'specstone@specstone': false},
        'permissions': {
          'allow': ['Bash(dart test:*)'],
          'deny': <Object?>[],
        },
        'env': {'X': 'y'},
        'count': 3,
        'ratio': 1.5,
        'flag': null,
        'name': 'café "quoted" \\ \t',
        'hooks': {
          'PostToolUse': [
            _specstoneGroup(['hook', 'post-edit'], timeout: 2),
          ],
        },
      };

      final root = _object(_staleText(_json(input)));

      expect(root.keys, input.keys);
      for (final key in input.keys.where((k) => k != 'hooks')) {
        expect(root[key], input[key], reason: key);
      }
    });
  });

  group('layout', () {
    test('a tab-indented CRLF file keeps tabs and CRLF, one final CRLF', () {
      final input = _json({
        'model': 'opus',
        'hooks': {
          'PostToolUse': [
            _specstoneGroup(['hook', 'post-edit'], timeout: 3),
          ],
        },
      }, indent: '\t').replaceAll('\n', '\r\n');

      final text = _staleText('$input\r\n');

      expect(text, startsWith('{\r\n\t"model": "opus",\r\n\t"hooks": {\r\n'));
      expect(text.endsWith('}\r\n'), isTrue);
      expect(text.endsWith('\r\n\r\n'), isFalse);
      expect(text.replaceAll('\r\n', ''), isNot(contains('\n')));
      expect(text, isNot(contains('  ')));
    });

    test('a file with no final line ending ends in one', () {
      final text = _staleText(_json({'model': 'opus'}));

      expect(text.endsWith('}\n'), isTrue);
      expect(text.endsWith('\n\n'), isFalse);
    });

    test('a file with extra final line endings ends in one', () {
      final text = _staleText('${_json({'model': 'opus'})}\n\n\n');

      expect(text.endsWith('}\n'), isTrue);
      expect(text.endsWith('\n\n'), isFalse);
    });

    test('the indent unit of the first indented line is kept', () {
      final text = _staleText(_json({'model': 'opus'}, indent: '    '));

      expect(text, startsWith('{\n    "model": "opus",\n    "hooks": {\n'));
      expect(text, contains('\n        "PostToolUse": [\n'));
    });

    test('a compact file takes two spaces and LF', () {
      final text = _staleText('{"model":"opus"}');

      expect(text, startsWith('{\n  "model": "opus",\n  "hooks": {\n'));
      expect(text, isNot(contains('\r')));
    });

    test('empty containers stay on one line', () {
      final text = _staleText('{"env": {}, "list": []}');

      expect(text, contains('"env": {},'));
      expect(text, contains('"list": [],'));
    });
  });

  group('malformed', () {
    final cases = <String, List<int>>{
      'invalid JSON': utf8.encode('{"hooks": '),
      'a line comment': utf8.encode('{\n  // note\n  "model": "opus"\n}\n'),
      'a block comment': utf8.encode('{ /* note */ "model": "opus" }'),
      'a trailing comma': utf8.encode('{"model": "opus",}'),
      'an empty file': const <int>[],
      'a top-level array': utf8.encode('[]'),
      'a top-level string': utf8.encode('"hooks"'),
      'a top-level null': utf8.encode('null'),
      'hooks that is an array': utf8.encode('{"hooks": []}'),
      'hooks that is null': utf8.encode('{"hooks": null}'),
      'an event value that is an object': utf8.encode(
        '{"hooks": {"PostToolUse": {}}}',
      ),
      'an event value that is a string': utf8.encode(
        '{"hooks": {"Stop": "x"}}',
      ),
      'bytes that are not UTF-8': const [0x7b, 0xff, 0xfe, 0x7d],
    };

    for (final MapEntry(:key, :value) in cases.entries) {
      test(key, () {
        final state = settingsStateOf(value);

        expect(state, isA<SettingsMalformed>());
        expect((state as SettingsMalformed).failure, isNotEmpty);
      });
    }

    test('a malformed file is no stale or current one', () {
      final state = _read('{"hooks": {"PostToolUse": 1}}');

      expect(state, isNot(isA<SettingsStale>()));
      expect(state, isNot(isA<SettingsCurrent>()));
    });
  });

  group('isSpecstoneHandler', () {
    test('accepts a command handler of specstone whose args start hook', () {
      expect(isSpecstoneHandler(_handler(['hook', 'post-edit'])), isTrue);
      expect(isSpecstoneHandler(_handler(['hook'])), isTrue);
      expect(
        isSpecstoneHandler(_handler(['hook', 'post-edit'], timeout: 9)),
        isTrue,
      );
    });

    test('rejects every other value', () {
      final rejected = <Object?>[
        null,
        'specstone',
        <Object?>[],
        <String, Object?>{},
        _ownerHandler,
        _handler(['check']),
        _handler([]),
        {'type': 'command', 'command': 'specstone', 'args': 'hook'},
        {'type': 'command', 'command': 'specstone'},
        {
          'type': 'prompt',
          'command': 'specstone',
          'args': ['hook'],
        },
        {
          'type': 'command',
          'command': 'Specstone',
          'args': ['hook'],
        },
      ];
      for (final value in rejected) {
        expect(isSpecstoneHandler(value), isFalse, reason: '$value');
      }
    });
  });

  test('specstoneSettingsGroupJson is the one group', () {
    expect(jsonDecode(specstoneSettingsGroupJson()), _group);
  });
}
