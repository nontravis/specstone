import 'dart:convert';

import 'package:specstone_core/src/setup_migration/agent_files.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const _corePack = 'prd-core';
const _packFileSegments = 2;
const _titleNouns = 'spec|doc|file';
const _wordEdge = '(?<![A-Za-z0-9_])';

/// Doc type ids and titles of the shipped packs outside the core pack.
class _TypeNames {
  new(this.ids, this.titles);

  final List<String> ids;
  final List<String> titles;
}

class _DocType {
  new(this.id, this.title);

  final String id;
  final String? title;
}

/// Reads each shipped doc type file's top-level `id` and `title` by pack.
Map<String, List<_DocType>> _typesByPack() {
  final byPack = <String, List<_DocType>>{};
  for (final entry in shippedPackFiles.entries) {
    final segments = entry.key.split('/');
    final isTypeFile =
        segments.length == _packFileSegments &&
        segments.last.endsWith('.yaml') &&
        segments.last != 'pack.yaml';
    if (!isTypeFile) continue;
    final yaml = loadYaml(utf8.decode(entry.value));
    if (yaml is! YamlMap || yaml['id'] is! String) continue;
    final title = yaml['title'];
    byPack
        .putIfAbsent(segments.first, () => [])
        .add(_DocType(yaml['id'] as String, title is String ? title : null));
  }
  return byPack;
}

_TypeNames _buildForeignTypeNames() {
  final byPack = _typesByPack();
  final core = byPack[_corePack] ?? const [];
  final coreNames = {
    for (final type in core) ...[
      type.id.toLowerCase(),
      ?type.title?.toLowerCase(),
    ],
  };
  final ids = <String>{};
  final titles = <String>{};
  for (final MapEntry(:key, :value) in byPack.entries) {
    if (key == _corePack) continue;
    for (final type in value) {
      final title = type.title;
      if (!coreNames.contains(type.id.toLowerCase())) ids.add(type.id);
      if (title != null && !coreNames.contains(title.toLowerCase())) {
        titles.add(title);
      }
    }
  }
  return _TypeNames(ids.toList()..sort(), titles.toList()..sort());
}

final _TypeNames _foreignTypeNames = _buildForeignTypeNames();

String _alternation(Iterable<String> names, {required bool spaced}) => names
    .map(
      (name) => spaced
          ? name.split(RegExp(r'\s+')).map(RegExp.escape).join(r'\s+')
          : RegExp.escape(name),
    )
    .join('|');

final _codeSpanForm = RegExp(
  '`(?:${_alternation(_foreignTypeNames.ids, spaced: false)})`',
);

final _targetForm = RegExp(
  '$_wordEdge(?:${_alternation(_foreignTypeNames.ids, spaced: false)}):',
);

final String _nounNames = _alternation([
  ..._foreignTypeNames.ids,
  ..._foreignTypeNames.titles,
], spaced: true);

final _nounForm = RegExp(
  '$_wordEdge(?:$_nounNames)'
  r'\s+'
  '(?:$_titleNouns)s?(?![A-Za-z0-9_])',
  caseSensitive: false,
);

/// Each match in [text] naming a doc type of a shipped pack outside the core
/// pack; empty when none.
List<String> _foreignTypeHits(String text) => [
  for (final form in [_codeSpanForm, _targetForm, _nounForm])
    for (final match in form.allMatches(text)) match.group(0)!,
];

String _fixtureId() =>
    _foreignTypeNames.ids.firstOrNull ??
    fail('no shipped pack outside the core pack has a doc type');

String _fixtureTitle() =>
    _foreignTypeNames.titles
        .where((title) => title.split(RegExp(r'\s+')).length == 2)
        .firstOrNull ??
    fail('no shipped pack outside the core pack has a two-word title');

void main() {
  test('the pack-neutrality scan finds each name form', () {
    final id = _fixtureId();
    final title = _fixtureTitle();
    final forms = {
      'code span': 'Read the `$id` first.',
      'target': 'Open $id:name next.',
      'id before spec': 'Write the $id spec.',
      'id before doc': 'Write the $id doc.',
      'id before file': 'Write the $id file.',
      'title before doc': 'Write the $title doc.',
      'upper case title before file': 'Write the ${title.toUpperCase()} FILE.',
    };

    for (final MapEntry(:key, :value) in forms.entries) {
      expect(_foreignTypeHits(value), isNotEmpty, reason: key);
    }
  });

  test('the pack-neutrality scan skips each non-name form', () {
    final id = _fixtureId();
    final title = _fixtureTitle();
    final forms = {
      'bare id': 'Write the $id soon.',
      'bare title': 'Write the $title soon.',
      'id inside a longer word': 'Open user_$id:name or my$id:name.',
      'code span beside other text': 'Run `specstone guide $id` now.',
      'core pack code span': 'Read the `competitor` first.',
      'core pack noun form': 'Write the competitor doc.',
      'core pack name': 'Ask what `$_corePack` ships.',
    };

    for (final MapEntry(:key, :value) in forms.entries) {
      expect(_foreignTypeHits(value), isEmpty, reason: key);
    }
  });

  test('the AGENT.md text passes the pack-neutrality scan', () {
    expect(_foreignTypeHits(agentMdText), isEmpty);
  });
}
