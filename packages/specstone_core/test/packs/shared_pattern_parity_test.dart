import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../helpers/package_root.dart';
import '../helpers/temp_tree.dart';

const _goldenPath = 'test/packs/fixtures/merged_pattern_lint.json';
const _updateKey = 'UPDATE_PATTERN_GOLDEN';

/// Returns [entries] as a map keyed by id, so a shared entry that joins a list
/// at another position still compares equal.
Map<String, Object?> _byId(List<PatternEntry>? entries) {
  final byId = <String, Object?>{};
  for (final entry in entries ?? const <PatternEntry>[]) {
    if (byId.containsKey(entry.id)) {
      fail('pattern id ${entry.id} repeats in one list');
    }
    byId[entry.id] = entry.toJson();
  }
  return byId;
}

Map<String, Object?> _lintOf(MergedDocType type) => {
  'doc': {'banned': _byId(type.lint.bannedPatterns)},
  'sections': {
    for (final section in type.sections)
      section.id: {
        'banned': _byId(section.bannedPatterns),
        'required': _byId(section.requiredPatterns),
      },
  },
};

Map<String, Object?> _mergedLint(MergedSet set) => {
  for (final type in set.docTypes) type.id: _lintOf(type),
};

Future<MergedSet> _resolveEveryShippedPack() async {
  final project = await writeTree({});
  final home = await writeTree({});
  return TemplateResolver().resolve(
    workingDirectory: project,
    homeDirectory: home,
  );
}

void main() {
  test(
    'every shipped doc type keeps its merged banned and required patterns',
    () async {
      final actual = _mergedLint(await _resolveEveryShippedPack());
      final golden = File.fromUri(packageRoot().uri.resolve(_goldenPath));
      if (Platform.environment.containsKey(_updateKey)) {
        const encoder = JsonEncoder.withIndent('  ');
        await golden.writeAsString('${encoder.convert(actual)}\n');
        fail('golden updated; unset $_updateKey and rerun');
      }
      final expected = jsonDecode(await golden.readAsString());
      expect(jsonDecode(jsonEncode(actual)), expected);
    },
  );
}
