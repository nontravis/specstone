import 'dart:convert';

const _hookEvent = 'PostToolUse';
const _hooksKey = 'hooks';
const Set<String> _groupKeys = {'matcher', _hooksKey};

/// What `.claude/settings.json` holds against the Specstone hook group.
sealed class SettingsState {
  const new();
}

/// No file: [text] is the file a run creates, holding the group alone.
final class SettingsMissing extends SettingsState {
  const new(this.text);

  final String text;
}

/// The Specstone handlers are exactly the one group; nothing to write.
final class SettingsCurrent extends SettingsState {
  const new();
}

/// Any other set of Specstone handlers; [text] is the merged file.
final class SettingsStale extends SettingsState {
  const new(this.text);

  final String text;
}

/// A file that is not one JSON object a run can merge into.
final class SettingsMalformed extends SettingsState {
  const new(this.failure);

  /// Why the file does not parse, for the refusal that names it.
  final String failure;
}

/// Reads [bytes] of `.claude/settings.json` (null: no file) as a state.
///
/// Decodes UTF-8 strictly and parses plain JSON, so bytes that are not UTF-8
/// and comments read as [SettingsMalformed]. [SettingsStale] and
/// [SettingsMissing] hold the whole file text, ending in one line ending.
SettingsState settingsStateOf(List<int>? bytes) {
  if (bytes == null) {
    return SettingsMissing(
      _render(_withGroup(<String, Object?>{}), '  ', '\n'),
    );
  }
  final String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    return const SettingsMalformed('the file is not valid UTF-8');
  }
  final Object? root;
  try {
    root = jsonDecode(text);
  } on FormatException catch (e) {
    return SettingsMalformed(_describe(e));
  }
  if (root is! Map<String, Object?>) {
    return const SettingsMalformed('the top level is not a JSON object');
  }
  final failure = _shapeFailure(root);
  if (failure != null) return SettingsMalformed(failure);
  if (_isCurrent(root)) return const SettingsCurrent();
  return SettingsStale(
    _render(_withGroup(root), _indentUnitOf(text), _lineEndingOf(text)),
  );
}

/// The Specstone matcher group as compact JSON.
String specstoneSettingsGroupJson() => jsonEncode(_group());

/// Whether [handler] is one the CLI owns in `.claude/settings.json`.
///
/// A `command` handler of this CLI whose `args` start with `hook`.
bool isSpecstoneHandler(Object? handler) {
  if (handler is! Map<String, Object?>) return false;
  final args = handler['args'];
  return handler['type'] == 'command' &&
      handler['command'] == 'specstone' &&
      args is List<Object?> &&
      args.isNotEmpty &&
      args.first == 'hook';
}

Map<String, Object?> _group() => <String, Object?>{
  'matcher': 'Write|Edit',
  _hooksKey: <Object?>[
    <String, Object?>{
      'type': 'command',
      'command': 'specstone',
      'args': <Object?>['hook', 'post-edit'],
    },
  ],
};

String _describe(FormatException error) {
  final offset = error.offset;
  return offset == null ? error.message : '${error.message} at offset $offset';
}

/// Why [root] cannot take a merge, or null when its hook shape is mergeable.
String? _shapeFailure(Map<String, Object?> root) {
  if (!root.containsKey(_hooksKey)) return null;
  final hooks = root[_hooksKey];
  if (hooks is! Map<String, Object?>) {
    return '"$_hooksKey" is not a JSON object';
  }
  for (final MapEntry(:key, :value) in hooks.entries) {
    if (value is! List<Object?>) return '"$_hooksKey.$key" is not an array';
  }
  return null;
}

/// Each matcher group holding a Specstone handler, with its event.
List<({String event, Map<String, Object?> group})> _specstoneGroups(
  Map<String, Object?> root,
) {
  final hooks = root[_hooksKey];
  if (hooks is! Map<String, Object?>) return const [];
  return [
    for (final MapEntry(:key, :value) in hooks.entries)
      for (final group in value! as List<Object?>)
        if (_handlersOf(group).any(isSpecstoneHandler))
          (event: key, group: group! as Map<String, Object?>),
  ];
}

List<Object?> _handlersOf(Object? group) {
  if (group is! Map<String, Object?>) return const [];
  final handlers = group[_hooksKey];
  return handlers is List<Object?> ? handlers : const [];
}

bool _isCurrent(Map<String, Object?> root) {
  final owned = _specstoneGroups(root);
  return owned.length == 1 &&
      owned.single.event == _hookEvent &&
      _sameJson(owned.single.group, _group());
}

bool _sameJson(Object? a, Object? b) {
  if (a is Map<String, Object?> && b is Map<String, Object?>) {
    return a.length == b.length &&
        a.entries.every(
          (e) => b.containsKey(e.key) && _sameJson(e.value, b[e.key]),
        );
  }
  if (a is List<Object?> && b is List<Object?>) {
    return a.length == b.length &&
        Iterable<int>.generate(a.length).every((i) => _sameJson(a[i], b[i]));
  }
  return a == b;
}

/// Removes every Specstone handler from [root], then appends the group last
/// in `hooks.PostToolUse`, and returns [root].
///
/// A matcher group or an event array the removal emptied is dropped, except
/// `PostToolUse`, which the append refills in its place.
Map<String, Object?> _withGroup(Map<String, Object?> root) {
  final hooks =
      root.putIfAbsent(_hooksKey, () => <String, Object?>{})!
          as Map<String, Object?>;
  for (final event in hooks.keys.toList()) {
    final groups = hooks[event]! as List<Object?>;
    final before = groups.length;
    groups.removeWhere(_emptiedByRemoval);
    if (groups.length < before && groups.isEmpty && event != _hookEvent) {
      hooks.remove(event);
    }
  }
  (hooks.putIfAbsent(_hookEvent, () => <Object?>[])! as List<Object?>).add(
    _group(),
  );
  return root;
}

/// Strips Specstone handlers from [group]; true when that left it empty.
bool _emptiedByRemoval(Object? group) {
  final handlers = _handlersOf(group);
  if (!handlers.any(isSpecstoneHandler)) return false;
  handlers.removeWhere(isSpecstoneHandler);
  return handlers.isEmpty &&
      (group! as Map<String, Object?>).keys.every(_groupKeys.contains);
}

/// The leading whitespace of the first indented line, else two spaces.
String _indentUnitOf(String text) {
  for (final line in text.split('\n')) {
    final indent = RegExp(r'^[ \t]+(?=\S)').stringMatch(line);
    if (indent != null) return indent;
  }
  return '  ';
}

String _lineEndingOf(String text) => text.contains('\r\n') ? '\r\n' : '\n';

String _render(Object? value, String unit, String lineEnding) {
  final out = StringBuffer();
  _writeValue(out, value, unit, lineEnding, 0);
  return (out..write(lineEnding)).toString();
}

void _writeValue(
  StringBuffer out,
  Object? value,
  String unit,
  String lineEnding,
  int depth,
) {
  switch (value) {
    case final Map<String, Object?> map when map.isNotEmpty:
      _writeContainer(out, '{', '}', unit, lineEnding, depth, [
        for (final MapEntry(:key, :value) in map.entries)
          (label: '${jsonEncode(key)}: ', value: value),
      ]);
    case final List<Object?> list when list.isNotEmpty:
      _writeContainer(out, '[', ']', unit, lineEnding, depth, [
        for (final item in list) (label: '', value: item),
      ]);
    default:
      out.write(jsonEncode(value));
  }
}

void _writeContainer(
  StringBuffer out,
  String open,
  String close,
  String unit,
  String lineEnding,
  int depth,
  List<({String label, Object? value})> members,
) {
  out
    ..write(open)
    ..write(lineEnding);
  for (var i = 0; i < members.length; i++) {
    out
      ..write(unit * (depth + 1))
      ..write(members[i].label);
    _writeValue(out, members[i].value, unit, lineEnding, depth + 1);
    out.write(i < members.length - 1 ? ',$lineEnding' : lineEnding);
  }
  out
    ..write(unit * depth)
    ..write(close);
}
