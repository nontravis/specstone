import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// The keys whose list holds pattern entries, in a lint, a section, or a pack.
const _patternListKeys = {
  'banned_patterns',
  'required_patterns',
  'shared_banned_patterns',
  'shared_required_patterns',
};

/// Adds each `pattern:` value under [node] to [places], keyed by regex text.
///
/// A place reads `<file> <path>`; a list under a `merge` map's `add` counts as
/// the list itself.
void _collect(
  Object? node,
  String path,
  String file,
  Map<String, List<String>> places,
) {
  if (node is YamlMap) {
    for (final MapEntry(:key, :value) in node.entries) {
      final here = '$path.$key';
      if (_patternListKeys.contains(key)) {
        _collectList(value, here, file, places);
      }
      _collect(value, here, file, places);
    }
  } else if (node is YamlList) {
    for (var i = 0; i < node.length; i++) {
      _collect(node[i], '$path[$i]', file, places);
    }
  }
}

void _collectList(
  Object? list,
  String path,
  String file,
  Map<String, List<String>> places,
) {
  final entries = list is YamlMap ? list['add'] : list;
  if (entries is! YamlList) return;
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    if (entry is! YamlMap || entry['pattern'] is! String) continue;
    final id = entry['id'];
    places
        .putIfAbsent(entry['pattern'] as String, () => [])
        .add('$file $path[$i] (id: $id)');
  }
}

void main() {
  // D16, D12.
  test('no shipped pack holds one regex text in two places', () {
    final repeated = <String>[];
    final packs = Directory('packs').listSync().whereType<Directory>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final pack in packs) {
      final files =
          pack
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.yaml'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      final places = <String, List<String>>{};
      for (final file in files) {
        _collect(loadYaml(file.readAsStringSync()), '', file.path, places);
      }
      for (final MapEntry(:key, :value) in places.entries) {
        if (value.length > 1) {
          repeated.add('${pack.path}: $key\n  ${value.join('\n  ')}');
        }
      }
    }
    expect(repeated, isEmpty, reason: repeated.join('\n'));
  });
}
