import 'dart:convert';

import 'package:specstone_core/src/doc_model/doc.dart' show KeyBlock;
import 'package:yaml/yaml.dart';

// MARK: - Public

/// Returns the entries [block] holds: a list's items, one scalar as one
/// entry, none for an empty value; null when its YAML is invalid.
List<Object?>? listEntriesOf(KeyBlock block) {
  try {
    return switch (loadYaml(block.indentedValueText)) {
      null => const <Object?>[],
      final YamlList list => [...list],
      final other => [other],
    };
  } on YamlException {
    return null;
  }
}

/// Returns the key block text of [fieldId] listing [entries] in order, written
/// over [onDisk], its key spelling kept.
///
/// Each entry equal by YAML value to one on disk keeps that entry's lines,
/// comments above it included; a new or changed one takes the indent and
/// quote style of the first kept entry, or of the first entry on disk when
/// none is kept. A block that is not a plain list of one-line items, or an
/// absent one, is written as a fresh block list: indent two spaces, each
/// entry plain, or single-quoted when plain text would read back as another
/// value. An empty [entries] writes an empty YAML list.
String listBlockOf(String fieldId, List<Object?> entries, {KeyBlock? onDisk}) {
  final key = onDisk?.key ?? fieldId;
  if (entries.isEmpty) return '$key: []\n';
  final held = onDisk == null ? null : _HeldList.read(onDisk);
  if (held == null) {
    return '$key:\n${[for (final e in entries) _Style.fresh.lineOf(e)].join()}';
  }
  final matched = held.match(entries);
  final style = held.styleOf(matched);
  final buffer = StringBuffer(held.header);
  for (final (at, entry) in entries.indexed) {
    final item = matched[at];
    buffer.write(item == null ? style.lineOf(entry) : held.items[item].lines);
  }
  buffer.write(held.trailer);
  return buffer.toString();
}

// MARK: - Held list

/// A block that is a plain list of one-line items, split into its parts.
final class _HeldList {
  const new(this.header, this.items, this.trailer);

  /// Reads [block]; null when it is not a `key:` line followed by one-line
  /// `- value` items, comments and blank lines between them.
  static _HeldList? read(KeyBlock block) {
    final lines = const LineSplitter().convert(block.text);
    final keyAt = lines.indexWhere((line) => !_isTrivia(line));
    if (keyAt < 0) return null;
    final afterKey = lines[keyAt].substring(block.key.length).trim();
    if (!afterKey.startsWith(':') || !_isTrivia(afterKey.substring(1))) {
      return null;
    }
    final items = <_HeldItem>[];
    var pending = '';
    for (final line in lines.skip(keyAt + 1)) {
      if (_isTrivia(line)) {
        pending += '$line\n';
        continue;
      }
      final item = _HeldItem.read(line, pending);
      if (item == null) return null;
      items.add(item);
      pending = '';
    }
    return _HeldList('${lines.take(keyAt + 1).join('\n')}\n', items, pending);
  }

  /// The lines up to and with the key line.
  final String header;
  final List<_HeldItem> items;

  /// The comments and blank lines after the last item.
  final String trailer;

  /// Returns, per entry, the index of the item it equals, each item once;
  /// null for an entry no item equals.
  List<int?> match(List<Object?> entries) {
    final taken = <int>{};
    int? itemEqualTo(Object? entry) {
      for (final (at, item) in items.indexed) {
        if (taken.contains(at) || !item.equals(entry)) continue;
        taken.add(at);
        return at;
      }
      return null;
    }

    return [for (final entry in entries) itemEqualTo(entry)];
  }

  /// Returns the style the new entries take: that of the first kept item,
  /// else of the first item on disk, else the fresh one.
  _Style styleOf(List<int?> matched) {
    final first = matched.nonNulls.firstOrNull;
    final item = first == null ? items.firstOrNull : items[first];
    return item?.style ?? _Style.fresh;
  }
}

/// One item of a list on disk: its lines and the value they read as.
final class _HeldItem {
  const new(this.lines, this.value, this.style);

  /// Reads [line], an item line after the [above] comment lines; null when it
  /// is no `- value` line or its value is not valid YAML.
  static _HeldItem? read(String line, String above) {
    final dash = _itemLine.firstMatch(line);
    if (dash == null) return null;
    final text = line.substring(dash.end);
    final Object? value;
    try {
      value = loadYaml(text);
    } on YamlException {
      return null;
    }
    final quote = text.startsWith("'") || text.startsWith('"') ? text[0] : null;
    return _HeldItem('$above$line\n', _plain(value), _Style(dash[1]!, quote));
  }

  /// The comment lines above the item, then its own line.
  final String lines;
  final Object? value;
  final _Style style;

  bool equals(Object? entry) => jsonEncode(value) == jsonEncode(_plain(entry));
}

/// The indent before `- ` and the quote character of an entry, null for plain.
final class _Style {
  const new(this.indent, this.quote);

  static const fresh = _Style('  ', null);

  final String indent;
  final String? quote;

  String lineOf(Object? entry) => '$indent- ${_scalarOf(entry)}\n';

  String _scalarOf(Object? entry) {
    if (entry is! String) return jsonEncode(_plain(entry));
    if (entry.contains('\n') || quote == '"') return jsonEncode(entry);
    if (quote == null && _isPlain(entry)) return entry;
    return "'${entry.replaceAll("'", "''")}'";
  }
}

// MARK: - Reading

/// Matches the start of an item line up to its value: indent, dash, space.
final _itemLine = RegExp(r'^(\s*)-(\s+|$)');

/// Whether [line] is blank or a comment.
bool _isTrivia(String line) {
  final text = line.trim();
  return text.isEmpty || text.startsWith('#');
}

/// Whether plain [text] reads back as the same string.
bool _isPlain(String text) {
  try {
    return loadYaml(text) == text;
  } on YamlException {
    return false;
  }
}

Object? _plain(Object? yaml) => switch (yaml) {
  YamlMap() => {for (final e in yaml.entries) '${e.key}': _plain(e.value)},
  YamlList() => [for (final e in yaml) _plain(e)],
  _ => yaml,
};
