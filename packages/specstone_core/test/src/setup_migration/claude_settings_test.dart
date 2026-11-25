import 'dart:convert';

import 'package:specstone_core/src/setup_migration/claude_settings.dart';
import 'package:test/test.dart';

const Map<String, Object?> _postEditGroup = {
  'matcher': 'Write|Edit',
  'hooks': [
    {
      'type': 'command',
      'command': 'specstone',
      'args': ['hook', 'post-edit'],
    },
  ],
};

const Map<String, Object?> _claudePreShellGroup = {
  'matcher': 'Bash|PowerShell',
  'hooks': [
    {'type': 'command', 'command': 'specstone hook pre-shell'},
  ],
};

const Map<String, Object?> _codexPreShellGroup = {
  'matcher': 'Bash',
  'hooks': [
    {'type': 'command', 'command': 'specstone hook pre-shell'},
  ],
};

const Map<SpecstoneHookFile, Map<String, Map<String, Object?>>> _expected = {
  SpecstoneHookFile.claudeSettings: {
    'PostToolUse': _postEditGroup,
    'PreToolUse': _claudePreShellGroup,
  },
  SpecstoneHookFile.codexHooks: {'PreToolUse': _codexPreShellGroup},
};

const _ownerHandler = {'type': 'command', 'command': 'lint'};

const Map<String, Object?> _ownerGroup = {
  'matcher': 'Bash',
  'hooks': [_ownerHandler],
};

SettingsState _read(
  String text, {
  SpecstoneHookFile file = SpecstoneHookFile.claudeSettings,
}) => settingsStateOf(utf8.encode(text), file: file);

Map<String, Object?> _object(String text) =>
    jsonDecode(text) as Map<String, Object?>;

String _json(Object? value, {String indent = '  '}) =>
    JsonEncoder.withIndent(indent).convert(value);

String _staleText(
  String input, {
  SpecstoneHookFile file = SpecstoneHookFile.claudeSettings,
}) {
  final state = _read(input, file: file);
  expect(state, isA<SettingsStale>(), reason: file.path);
  return (state as SettingsStale).text;
}

/// The hooks object holding each group [file] owns, [replace] swapping the
/// array of some events.
Map<String, Object?> _hooksHolding(
  SpecstoneHookFile file, [
  Map<String, List<Object?>> replace = const {},
]) => {
  for (final MapEntry(:key, :value) in _expected[file]!.entries)
    key: replace[key] ?? [value],
};

Map<String, Object?> _hooksOf(String text) =>
    _object(text)['hooks']! as Map<String, Object?>;

List<Object?> _eventOf(String text, String event) =>
    _hooksOf(text)[event]! as List<Object?>;

Map<String, Object?> _handlerOf(Map<String, Object?> group) =>
    (group['hooks']! as List<Object?>).single! as Map<String, Object?>;

/// [group] with [timeout] added to its handler, which makes it stale.
Map<String, Object?> _withTimeout(Map<String, Object?> group, Object timeout) =>
    {
      ...group,
      'hooks': [
        {..._handlerOf(group), 'timeout': timeout},
      ],
    };

/// [group] with its handler in the other form: shell for exec, exec for shell.
Map<String, Object?> _otherForm(Map<String, Object?> group) {
  final handler = _handlerOf(group);
  final args = handler['args'];
  final other = args is List<Object?>
      ? <String, Object?>{
          'type': 'command',
          'command': ['specstone', ...args].join(' '),
        }
      : <String, Object?>{
          'type': 'command',
          'command': 'specstone',
          'args': (handler['command']! as String).split(' ').skip(1).toList(),
        };
  return {
    ...group,
    'hooks': [other],
  };
}

/// [value] with the key order of every object reversed.
Object? _reversed(Object? value) => switch (value) {
  final Map<String, Object?> map => {
    for (final MapEntry(:key, :value) in map.entries.toList().reversed)
      key: _reversed(value),
  },
  final List<Object?> list => [for (final item in list) _reversed(item)],
  _ => value,
};

String _handLaidEvent(String event, Object? group) =>
    '\t\t${jsonEncode(event)}: [\r\n'
    '\t\t\t${jsonEncode(group)}\r\n'
    '\t\t]';

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
  group('hook files', () {
    test('each file names its path and the groups it owns, by event', () {
      expect(SpecstoneHookFile.claudeSettings.path, '.claude/settings.json');
      expect(SpecstoneHookFile.codexHooks.path, '.codex/hooks.json');
      for (final MapEntry(key: file, value: groups) in _expected.entries) {
        expect(file.groups, groups, reason: file.path);
        expect(file.groups.keys, orderedEquals(groups.keys), reason: file.path);
      }
    });

    test('the file defaults to the Claude Code settings', () {
      final text = (settingsStateOf(null) as SettingsMissing).text;

      expect(
        text,
        (settingsStateOf(
          null,
          file: SpecstoneHookFile.claudeSettings,
        ) as SettingsMissing).text,
      );
      expect(_hooksOf(text).keys, ['PostToolUse', 'PreToolUse']);
    });
  });

  group('missing file', () {
    test('creates a text holding the whole group set of the file alone', () {
      for (final MapEntry(key: file, value: groups) in _expected.entries) {
        final state = settingsStateOf(null, file: file);

        expect(state, isA<SettingsMissing>(), reason: file.path);
        final text = (state as SettingsMissing).text;
        expect(_object(text), {
          'hooks': _hooksHolding(file),
        }, reason: file.path);
        expect(
          _hooksOf(text).keys,
          orderedEquals(groups.keys),
          reason: file.path,
        );
        expect(text.endsWith('}\n'), isTrue, reason: file.path);
        expect(text.endsWith('\n\n'), isFalse, reason: file.path);
        expect(text, startsWith('{\n  "hooks": {\n'), reason: file.path);
      }
    });

    test('the created text reads back as current', () {
      for (final file in SpecstoneHookFile.values) {
        final text =
            (settingsStateOf(null, file: file) as SettingsMissing).text;

        expect(_read(text, file: file), isA<SettingsCurrent>());
      }
    });
  });

  group('current', () {
    test('a file holding exactly the whole group set of the file', () {
      for (final file in SpecstoneHookFile.values) {
        final text = _json({'hooks': _hooksHolding(file)});

        expect(_read(text, file: file), isA<SettingsCurrent>());
      }
    });

    test(
      'a hand-laid-out file already holding the groups is not rewritten',
      () {
        for (final MapEntry(key: file, value: groups) in _expected.entries) {
          final events = [
            for (final MapEntry(:key, :value) in groups.entries)
              _handLaidEvent(key, _reversed(value)),
          ];
          final text =
              '{\r\n'
              '\t"permissions": {"allow": ["Bash"]},\r\n'
              '\t"hooks": {\r\n'
              '${events.join(',\r\n')}\r\n'
              '\t},\r\n'
              '\t"model": "opus"\r\n'
              '}';

          expect(_read(text, file: file), isA<SettingsCurrent>());
        }
      },
    );

    test('each group at any position among the Owner groups', () {
      for (final MapEntry(key: file, value: groups) in _expected.entries) {
        for (final MapEntry(key: event, value: group) in groups.entries) {
          for (final positions in [
            [group, _ownerGroup],
            [_ownerGroup, group],
            [_ownerGroup, group, _ownerGroup],
          ]) {
            final text = _json({
              'model': 'opus',
              'hooks': _hooksHolding(file, {event: positions}),
            });

            expect(
              _read(text, file: file),
              isA<SettingsCurrent>(),
              reason: '${file.path} $event $positions',
            );
          }
        }
      }
    });

    test('each group compared by value, not by key order', () {
      for (final MapEntry(key: file, value: groups) in _expected.entries) {
        final text = _json({
          'hooks': {
            for (final MapEntry(:key, :value) in groups.entries)
              key: [_reversed(value)],
          },
        });

        expect(_read(text, file: file), isA<SettingsCurrent>());
      }
    });
  });

  group('stale', () {
    test('an old matcher gives each group once, appended last', () {
      for (final MapEntry(key: file, value: groups) in _expected.entries) {
        for (final MapEntry(key: event, value: group) in groups.entries) {
          final text = _staleText(
            _json({
              'hooks': _hooksHolding(file, {
                event: [
                  {...group, 'matcher': 'Old'},
                  _ownerGroup,
                ],
              }),
            }),
            file: file,
          );

          final reason = '${file.path} $event';
          expect(_specstoneHandlerCount(text), groups.length, reason: reason);
          final inEvent = _eventOf(text, event);
          expect(inEvent, hasLength(2), reason: reason);
          expect(inEvent.last, group, reason: reason);
          expect(inEvent.first, _ownerGroup, reason: reason);
        }
      }
    });

    test('an added timeout gives each group once', () {
      for (final MapEntry(key: file, value: groups) in _expected.entries) {
        for (final MapEntry(key: event, value: group) in groups.entries) {
          final text = _staleText(
            _json({
              'hooks': _hooksHolding(file, {
                event: [_withTimeout(group, 10)],
              }),
            }),
            file: file,
          );

          final reason = '${file.path} $event';
          expect(_specstoneHandlerCount(text), groups.length, reason: reason);
          expect(_eventOf(text, event), [group], reason: reason);
        }
      }
    });

    test('a handler in the other form is replaced by the form written', () {
      for (final MapEntry(key: file, value: groups) in _expected.entries) {
        for (final MapEntry(key: event, value: group) in groups.entries) {
          final text = _staleText(
            _json({
              'hooks': _hooksHolding(file, {
                event: [_otherForm(group)],
              }),
            }),
            file: file,
          );

          final reason = '${file.path} $event';
          expect(_specstoneHandlerCount(text), groups.length, reason: reason);
          expect(_eventOf(text, event), [group], reason: reason);
        }
      }
    });

    test(
      'a Specstone event the binary does not write gives each group once',
      () {
        for (final MapEntry(key: file, value: groups) in _expected.entries) {
          final text = _staleText(
            _json({
              'hooks': {
                'SessionStart': [
                  {
                    'matcher': 'startup',
                    'hooks': [
                      {
                        'type': 'command',
                        'command': 'specstone',
                        'args': ['hook', 'session-start'],
                      },
                    ],
                  },
                ],
              },
            }),
            file: file,
          );

          expect(
            _specstoneHandlerCount(text),
            groups.length,
            reason: file.path,
          );
          for (final MapEntry(key: event, value: group) in groups.entries) {
            expect(_eventOf(text, event).last, group, reason: file.path);
          }
        }
      },
    );

    test('a file with no hooks gains hooks and each owned event last', () {
      for (final MapEntry(key: file, value: groups) in _expected.entries) {
        final text = _staleText(_json({'model': 'opus'}), file: file);

        expect(_object(text).keys, ['model', 'hooks'], reason: file.path);
        expect(_hooksOf(text), _hooksHolding(file), reason: file.path);
        expect(
          _hooksOf(text).keys,
          orderedEquals(groups.keys),
          reason: file.path,
        );
      }
    });

    test('a file holding only the post-edit group gains the pre-shell one', () {
      final text = _staleText(
        _json({
          'model': 'opus',
          'hooks': {
            'PostToolUse': [_postEditGroup],
          },
        }),
      );

      expect(_object(text).keys, ['model', 'hooks']);
      expect(_hooksOf(text), {
        'PostToolUse': [_postEditGroup],
        'PreToolUse': [_claudePreShellGroup],
      });
      expect(_hooksOf(text).keys, ['PostToolUse', 'PreToolUse']);
    });

    test('hooks without the owned events gains them after its events', () {
      for (final MapEntry(key: file, value: groups) in _expected.entries) {
        final text = _staleText(
          _json({
            'hooks': {
              'Stop': [_ownerGroup],
            },
          }),
          file: file,
        );

        expect(_hooksOf(text).keys, [
          'Stop',
          ...groups.keys,
        ], reason: file.path);
      }
    });

    test('each group stays last after the stale text is read again', () {
      for (final MapEntry(key: file, value: groups) in _expected.entries) {
        for (final MapEntry(key: event, value: group) in groups.entries) {
          final text = _staleText(
            _json({
              'hooks': _hooksHolding(file, {
                event: [_withTimeout(group, 10), _ownerGroup],
              }),
            }),
            file: file,
          );

          expect(
            _read(text, file: file),
            isA<SettingsCurrent>(),
            reason: '${file.path} $event',
          );
        }
      }
    });

    test('two Specstone groups in an event give one', () {
      for (final MapEntry(key: file, value: groups) in _expected.entries) {
        for (final MapEntry(key: event, value: group) in groups.entries) {
          final text = _staleText(
            _json({
              'hooks': _hooksHolding(file, {
                event: [group, group],
              }),
            }),
            file: file,
          );

          final reason = '${file.path} $event';
          expect(_specstoneHandlerCount(text), groups.length, reason: reason);
          expect(_eventOf(text, event), [group], reason: reason);
        }
      }
    });

    test('a group under the other event of the file moves to its own', () {
      final text = _staleText(
        _json({
          'hooks': {
            'PostToolUse': [_claudePreShellGroup],
            'PreToolUse': [_postEditGroup],
          },
        }),
      );

      expect(_hooksOf(text), {
        'PostToolUse': [_postEditGroup],
        'PreToolUse': [_claudePreShellGroup],
      });
    });

    test('an Owner handler in a Specstone group stays in that group', () {
      for (final MapEntry(key: file, value: groups) in _expected.entries) {
        for (final MapEntry(key: event, value: group) in groups.entries) {
          final shared = {
            'matcher': group['matcher'],
            'hooks': [
              _ownerHandler,
              ..._withTimeout(group, 5)['hooks']! as List,
            ],
          };
          final text = _staleText(
            _json({
              'hooks': _hooksHolding(file, {
                event: [shared],
              }),
            }),
            file: file,
          );

          expect(_eventOf(text, event), [
            {
              'matcher': group['matcher'],
              'hooks': [_ownerHandler],
            },
            group,
          ], reason: '${file.path} $event');
        }
      }
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
        {'type': 'command', 'command': 'specstone check'},
        {'type': 'command', 'command': 'specstone hook'},
        {'type': 'command', 'command': 'Specstone hook pre-shell'},
        {'type': 'command', 'command': 'xspecstone hook pre-shell'},
        {'type': 'prompt', 'command': 'specstone hook pre-shell'},
        {
          'type': 'command',
          'command': 'specstone hook pre-shell',
          'args': ['--x'],
        },
      ];
      for (final MapEntry(key: file, value: groups) in _expected.entries) {
        for (final MapEntry(key: event, value: group) in groups.entries) {
          final owner = {'matcher': group['matcher'], 'hooks': lookalikes};
          final text = _staleText(
            _json({
              'hooks': _hooksHolding(file, {
                event: [owner, _withTimeout(group, 1)],
              }),
            }),
            file: file,
          );

          final reason = '${file.path} $event';
          expect(_eventOf(text, event).first, owner, reason: reason);
          expect(_specstoneHandlerCount(text), groups.length, reason: reason);
        }
      }
    });
  });

  group('emptied parts', () {
    test('drops an emptied group, event array, and keeps non-empty ones', () {
      for (final MapEntry(key: file, value: groups) in _expected.entries) {
        final text = _staleText(
          _json({
            'hooks': {
              'SessionStart': [
                {
                  'matcher': 'startup',
                  'hooks': [
                    {
                      'type': 'command',
                      'command': 'specstone',
                      'args': ['hook', 'session-start'],
                    },
                  ],
                },
              ],
              'PreCompact': [
                {
                  'matcher': 'auto',
                  'hooks': [
                    {'type': 'command', 'command': 'specstone hook compact'},
                  ],
                },
              ],
              'Stop': [
                {
                  'matcher': '',
                  'hooks': [
                    {
                      'type': 'command',
                      'command': 'specstone',
                      'args': ['hook', 'stop'],
                    },
                  ],
                },
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
          file: file,
        );

        expect(_hooksOf(text).keys, [
          'Stop',
          'Notification',
          ...groups.keys,
        ], reason: file.path);
        expect(_hooksOf(text)['Stop'], [
          {
            'hooks': [_ownerHandler],
          },
        ]);
      }
    });

    test('keeps the Owner key of a group the removal emptied', () {
      for (final MapEntry(key: file, value: groups) in _expected.entries) {
        for (final MapEntry(key: event, value: group) in groups.entries) {
          final text = _staleText(
            _json({
              'hooks': _hooksHolding(file, {
                event: [
                  {..._withTimeout(group, 1), 'x': 1},
                ],
              }),
            }),
            file: file,
          );

          final reason = '${file.path} $event';
          final inEvent = _eventOf(text, event);
          expect(inEvent, hasLength(2), reason: reason);
          expect((inEvent.first! as Map<String, Object?>)['x'], 1);
          expect(_specstoneHandlerCount(text), groups.length, reason: reason);
        }
      }
    });

    test('keeps a group or event the Owner left empty', () {
      for (final MapEntry(key: file, value: groups) in _expected.entries) {
        for (final MapEntry(key: event, value: group) in groups.entries) {
          final text = _staleText(
            _json({
              'hooks': {
                'Stop': <Object?>[],
                ..._hooksHolding(file, {
                  event: [
                    {'matcher': 'Bash', 'hooks': <Object?>[]},
                    _withTimeout(group, 1),
                  ],
                }),
              },
            }),
            file: file,
          );

          expect(_hooksOf(text)['Stop'], <Object?>[]);
          expect(_eventOf(text, event).first, {
            'matcher': 'Bash',
            'hooks': <Object?>[],
          }, reason: '${file.path} $event');
        }
      }
    });

    test('hooks and each owned event keep their place when refilled', () {
      for (final MapEntry(key: file, value: groups) in _expected.entries) {
        final text = _staleText(
          _json({
            'first': 1,
            'hooks': {
              'Alpha': [_ownerGroup],
              for (final MapEntry(:key, :value) in groups.entries)
                key: [_withTimeout(value, 1)],
              'Omega': [_ownerGroup],
            },
            'last': 2,
          }),
          file: file,
        );

        expect(_object(text).keys, ['first', 'hooks', 'last']);
        expect(_hooksOf(text).keys, [
          'Alpha',
          ...groups.keys,
          'Omega',
        ], reason: file.path);
      }
    });

    test('hooks holding only an old Specstone event keeps its place', () {
      for (final file in SpecstoneHookFile.values) {
        final text = _staleText(
          _json({
            'first': 1,
            'hooks': {
              'SessionStart': [
                {
                  'matcher': 'startup',
                  'hooks': [
                    {
                      'type': 'command',
                      'command': 'specstone',
                      'args': ['hook', 'session-start'],
                    },
                  ],
                },
              ],
            },
            'last': 2,
          }),
          file: file,
        );

        expect(_object(text).keys, ['first', 'hooks', 'last']);
        expect(_hooksOf(text), _hooksHolding(file), reason: file.path);
      }
    });

    test(
      'an event the file does not own is dropped once the removal empties it',
      () {
        final text = _staleText(
          _json({
            'hooks': {
              'PostToolUse': [_postEditGroup],
            },
          }),
          file: SpecstoneHookFile.codexHooks,
        );

        expect(_hooksOf(text), {
          'PreToolUse': [_codexPreShellGroup],
        });
      },
    );
  });

  group('Owner content', () {
    test('keeps enabledPlugins, permissions, and every other key', () {
      for (final MapEntry(key: file, value: groups) in _expected.entries) {
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
            for (final MapEntry(:key, :value) in groups.entries)
              key: [_withTimeout(value, 2)],
          },
        };

        final root = _object(_staleText(_json(input), file: file));

        expect(root.keys, input.keys, reason: file.path);
        for (final key in input.keys.where((k) => k != 'hooks')) {
          expect(root[key], input[key], reason: '${file.path} $key');
        }
      }
    });
  });

  group('layout', () {
    test('a tab-indented CRLF file keeps tabs and CRLF, one final CRLF', () {
      for (final MapEntry(key: file, value: groups) in _expected.entries) {
        final input = _json({
          'model': 'opus',
          'hooks': {
            for (final MapEntry(:key, :value) in groups.entries)
              key: [_withTimeout(value, 3)],
          },
        }, indent: '\t').replaceAll('\n', '\r\n');

        final text = _staleText('$input\r\n', file: file);

        expect(
          text,
          startsWith('{\r\n\t"model": "opus",\r\n\t"hooks": {\r\n'),
          reason: file.path,
        );
        expect(text.endsWith('}\r\n'), isTrue, reason: file.path);
        expect(text.endsWith('\r\n\r\n'), isFalse, reason: file.path);
        expect(
          text.replaceAll('\r\n', ''),
          isNot(contains('\n')),
          reason: file.path,
        );
        expect(text, isNot(contains('  ')), reason: file.path);
      }
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
      expect(text, contains('\n        "PreToolUse": [\n'));
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
      'a PreToolUse value that is an object': utf8.encode(
        '{"hooks": {"PreToolUse": {}}}',
      ),
      'a PreToolUse value that is null': utf8.encode(
        '{"hooks": {"PreToolUse": null}}',
      ),
      'an event value that is a string': utf8.encode(
        '{"hooks": {"Stop": "x"}}',
      ),
      'bytes that are not UTF-8': const [0x7b, 0xff, 0xfe, 0x7d],
    };

    for (final MapEntry(:key, :value) in cases.entries) {
      test(key, () {
        for (final file in SpecstoneHookFile.values) {
          final state = settingsStateOf(value, file: file);

          expect(state, isA<SettingsMalformed>(), reason: file.path);
          expect((state as SettingsMalformed).failure, isNotEmpty);
        }
      });
    }

    test('a malformed file is no stale or current one', () {
      for (final file in SpecstoneHookFile.values) {
        final state = _read('{"hooks": {"PreToolUse": 1}}', file: file);

        expect(state, isNot(isA<SettingsStale>()), reason: file.path);
        expect(state, isNot(isA<SettingsCurrent>()), reason: file.path);
      }
    });
  });

  group('isSpecstoneHandler', () {
    test('accepts an exec-form handler of specstone whose args start hook', () {
      expect(
        isSpecstoneHandler({
          'type': 'command',
          'command': 'specstone',
          'args': ['hook', 'post-edit'],
        }),
        isTrue,
      );
      expect(
        isSpecstoneHandler({
          'type': 'command',
          'command': 'specstone',
          'args': ['hook'],
        }),
        isTrue,
      );
      expect(
        isSpecstoneHandler({
          'type': 'command',
          'command': 'specstone',
          'args': ['hook', 'post-edit'],
          'timeout': 9,
        }),
        isTrue,
      );
    });

    test(
      'accepts a shell-form handler whose command starts specstone hook',
      () {
        expect(
          isSpecstoneHandler({
            'type': 'command',
            'command': 'specstone hook pre-shell',
          }),
          isTrue,
        );
        expect(
          isSpecstoneHandler({
            'type': 'command',
            'command': 'specstone hook post-edit',
            'timeout': 9,
          }),
          isTrue,
        );
      },
    );

    test('rejects every other value', () {
      final rejected = <Object?>[
        null,
        'specstone',
        <Object?>[],
        <String, Object?>{},
        _ownerHandler,
        {
          'type': 'command',
          'command': 'specstone',
          'args': ['check'],
        },
        {'type': 'command', 'command': 'specstone', 'args': <Object?>[]},
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
        {'type': 'command', 'command': 'specstone hook'},
        {'type': 'command', 'command': 'specstone check'},
        {'type': 'command', 'command': 'Specstone hook pre-shell'},
        {'type': 'command', 'command': ' specstone hook pre-shell'},
        {'type': 'command', 'command': 1},
        {'type': 'prompt', 'command': 'specstone hook pre-shell'},
        {
          'type': 'command',
          'command': 'specstone hook pre-shell',
          'args': ['hook'],
        },
        {
          'type': 'command',
          'command': 'specstone hook pre-shell',
          'args': <Object?>[],
        },
      ];
      for (final value in rejected) {
        expect(isSpecstoneHandler(value), isFalse, reason: '$value');
      }
    });
  });
}
