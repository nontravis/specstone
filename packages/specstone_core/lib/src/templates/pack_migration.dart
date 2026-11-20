import 'package:specstone_core/src/templates/models/migration_step.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/yaml_reader.dart';
import 'package:yaml/yaml.dart';

final _placeholderPattern = RegExp(r'\{([^{}]*)\}');

/// One `migrations:` entry of a `pack.yaml`: the version it migrates from and
/// its steps.
final class PackMigration {
  new _({required this.from, required this.steps});

  /// The pack version this migration migrates from.
  final PackVersion from;

  /// The steps of this migration, in file order.
  final List<MigrationStep> steps;
}

/// Parses a `migrations:` [node] of a `pack.yaml` read from [file].
///
/// A null node gives no entries; entries keep file order. A bad `from:` is
/// `pack_version_invalid`, an unknown step kind is `unknown_value`, a missing
/// key is `missing_key`, and an unknown key is `unknown_key`, keyed
/// `migrations[<i>].from` and `migrations[<i>].steps[<j>].<kind>.<key>`.
List<PackMigration> parseMigrations(YamlNode? node, {required String file}) =>
    switch (node) {
      null => const <PackMigration>[],
      final YamlList list => [
        for (var i = 0; i < list.length; i++)
          _parseEntry(list.nodes[i], i, file: file),
      ],
      _ => throw TemplateFault(
        FaultCode.unknownValue,
        'the key migrations must be a list',
        file: file,
        key: 'migrations',
      ),
    };

PackMigration _parseEntry(YamlNode node, int i, {required String file}) {
  final prefix = 'migrations[$i].';
  final map = switch (node) {
    final YamlMap map => map,
    _ => throw TemplateFault(
      FaultCode.unknownValue,
      'the migrations entry must be a mapping',
      file: file,
      key: 'migrations[$i]',
    ),
  };
  checkKeys(
    map,
    const {'from', 'steps'},
    file: file,
    format: 'migrations entry',
    prefix: prefix,
  );
  requireValue<Object>(map, 'from', file: file, prefix: prefix);
  return PackMigration._(
    from: PackVersion.fromYaml(
      map.nodes['from']!,
      file: file,
      key: '${prefix}from',
    ),
    steps: _parseSteps(
      requireValue<YamlList>(map, 'steps', file: file, prefix: prefix),
      i,
      file: file,
    ),
  );
}

List<MigrationStep> _parseSteps(YamlList list, int i, {required String file}) =>
    [
      for (var j = 0; j < list.length; j++)
        _parseStep(list.nodes[j], i, j, file: file),
    ];

MigrationStep _parseStep(YamlNode node, int i, int j, {required String file}) {
  final stepKey = 'migrations[$i].steps[$j]';
  final map = switch (node) {
    final YamlMap map when map.length == 1 => map,
    _ => throw TemplateFault(
      FaultCode.unknownValue,
      'the step must be a mapping of exactly one kind',
      file: file,
      key: stepKey,
    ),
  };
  final kind = map.keys.single;
  if (kind is! String) {
    throw TemplateFault(
      FaultCode.unknownValue,
      'the step kind must be a string',
      file: file,
      key: stepKey,
    );
  }
  return switch (kind) {
    'rename_section' => _parseRenameSection(
      _stepBody(map.nodes[kind]!, kind, i, j, file: file),
      i,
      j,
      file: file,
    ),
    'rename_field' => _parseRenameField(
      _stepBody(map.nodes[kind]!, kind, i, j, file: file),
      i,
      j,
      file: file,
    ),
    'move_file' => _parseMoveFile(
      _stepBody(map.nodes[kind]!, kind, i, j, file: file),
      i,
      j,
      file: file,
    ),
    'move_to_record' => _parseMoveToRecord(
      _stepBody(map.nodes[kind]!, kind, i, j, file: file),
      i,
      j,
      file: file,
    ),
    'stamp_code_fingerprints' => _parseStampCodeFingerprints(
      _stepBody(map.nodes[kind]!, kind, i, j, file: file),
      i,
      j,
      file: file,
    ),
    'restamp_code_fingerprints' => _parseRestampCodeFingerprints(
      _stepBody(map.nodes[kind]!, kind, i, j, file: file),
      i,
      j,
      file: file,
    ),
    'bullet_lines' => _parseBulletLines(
      _stepBody(map.nodes[kind]!, kind, i, j, file: file),
      i,
      j,
      file: file,
    ),
    'drop_default_lines' => _parseDropDefaultLines(
      _stepBody(map.nodes[kind]!, kind, i, j, file: file),
      i,
      j,
      file: file,
    ),
    'strip_shared_copies' => _parseStripSharedCopies(
      _stepBody(map.nodes[kind]!, kind, i, j, file: file),
      i,
      j,
      file: file,
    ),
    'drop_shared_lines' => _parseDropSharedLines(
      _stepBody(map.nodes[kind]!, kind, i, j, file: file),
      i,
      j,
      file: file,
    ),
    'mark_retrim' => _parseMarkRetrim(
      _stepBody(map.nodes[kind]!, kind, i, j, file: file),
      i,
      j,
      file: file,
    ),
    _ => throw TemplateFault(
      FaultCode.unknownValue,
      'the step kind $kind is not defined',
      file: file,
      key: stepKey,
    ),
  };
}

YamlMap _stepBody(
  YamlNode node,
  String kind,
  int i,
  int j, {
  required String file,
}) {
  return switch (node) {
    final YamlMap map => map,
    _ => throw TemplateFault(
      FaultCode.unknownValue,
      'the $kind step must be a mapping',
      file: file,
      key: 'migrations[$i].steps[$j].$kind',
    ),
  };
}

RenameSection _parseRenameSection(
  YamlMap map,
  int i,
  int j, {
  required String file,
}) {
  final prefix = 'migrations[$i].steps[$j].rename_section.';
  checkKeys(
    map,
    const {'doc_type', 'from', 'to'},
    file: file,
    format: 'rename_section step',
    prefix: prefix,
  );
  final from = requireValue<YamlMap>(map, 'from', file: file, prefix: prefix);
  final to = requireValue<YamlMap>(map, 'to', file: file, prefix: prefix);
  return RenameSection(
    docType: requireValue<String>(map, 'doc_type', file: file, prefix: prefix),
    fromId: _sectionEnd(from, 'id', '${prefix}from.', file: file),
    fromHeader: _sectionEnd(from, 'header', '${prefix}from.', file: file),
    toId: _sectionEnd(to, 'id', '${prefix}to.', file: file),
    toHeader: _sectionEnd(to, 'header', '${prefix}to.', file: file),
  );
}

String _sectionEnd(
  YamlMap map,
  String key,
  String prefix, {
  required String file,
}) {
  checkKeys(
    map,
    const {'id', 'header'},
    file: file,
    format: 'section reference',
    prefix: prefix,
  );
  return requireValue<String>(map, key, file: file, prefix: prefix);
}

RenameField _parseRenameField(
  YamlMap map,
  int i,
  int j, {
  required String file,
}) {
  final prefix = 'migrations[$i].steps[$j].rename_field.';
  checkKeys(
    map,
    const {'doc_type', 'from', 'to'},
    file: file,
    format: 'rename_field step',
    prefix: prefix,
  );
  return RenameField(
    docType: requireValue<String>(map, 'doc_type', file: file, prefix: prefix),
    from: requireValue<String>(map, 'from', file: file, prefix: prefix),
    to: requireValue<String>(map, 'to', file: file, prefix: prefix),
  );
}

MoveFile _parseMoveFile(YamlMap map, int i, int j, {required String file}) {
  final prefix = 'migrations[$i].steps[$j].move_file.';
  checkKeys(
    map,
    const {'doc_type', 'from', 'to'},
    file: file,
    format: 'move_file step',
    prefix: prefix,
  );
  final from = requireValue<String>(map, 'from', file: file, prefix: prefix);
  final to = requireValue<String>(map, 'to', file: file, prefix: prefix);
  _checkPlaceholders(from, to, key: '${prefix}to', file: file);
  return MoveFile(
    docType: requireValue<String>(map, 'doc_type', file: file, prefix: prefix),
    from: from,
    to: to,
  );
}

MoveToRecord _parseMoveToRecord(
  YamlMap map,
  int i,
  int j, {
  required String file,
}) {
  final prefix = 'migrations[$i].steps[$j].move_to_record.';
  checkKeys(
    map,
    const {'doc_types', 'fields', 'to'},
    file: file,
    format: 'move_to_record step',
    prefix: prefix,
  );
  List<String> listOf(String key) => stringsOf(
    requireValue<YamlList>(map, key, file: file, prefix: prefix),
    key,
    file: file,
    prefix: prefix,
  );
  return MoveToRecord(
    docTypes: listOf('doc_types'),
    fields: listOf('fields'),
    to: requireValue<String>(map, 'to', file: file, prefix: prefix),
  );
}

StampCodeFingerprints _parseStampCodeFingerprints(
  YamlMap map,
  int i,
  int j, {
  required String file,
}) {
  checkKeys(
    map,
    const <String>{},
    file: file,
    format: 'stamp_code_fingerprints step',
    prefix: 'migrations[$i].steps[$j].stamp_code_fingerprints.',
  );
  return const StampCodeFingerprints();
}

RestampCodeFingerprints _parseRestampCodeFingerprints(
  YamlMap map,
  int i,
  int j, {
  required String file,
}) {
  checkKeys(
    map,
    const <String>{},
    file: file,
    format: 'restamp_code_fingerprints step',
    prefix: 'migrations[$i].steps[$j].restamp_code_fingerprints.',
  );
  return const RestampCodeFingerprints();
}

StripSharedCopies _parseStripSharedCopies(
  YamlMap map,
  int i,
  int j, {
  required String file,
}) {
  checkKeys(
    map,
    const <String>{},
    file: file,
    format: 'strip_shared_copies step',
    prefix: 'migrations[$i].steps[$j].strip_shared_copies.',
  );
  return const StripSharedCopies();
}

BulletLines _parseBulletLines(
  YamlMap map,
  int i,
  int j, {
  required String file,
}) {
  final prefix = 'migrations[$i].steps[$j].bullet_lines.';
  checkKeys(
    map,
    const {'doc_type', 'section', 'prefixes'},
    file: file,
    format: 'bullet_lines step',
    prefix: prefix,
  );
  final prefixes = stringsOf(
    requireValue<YamlList>(map, 'prefixes', file: file, prefix: prefix),
    'prefixes',
    file: file,
    prefix: prefix,
  );
  if (prefixes.isEmpty || prefixes.any((p) => p.isEmpty)) {
    throw TemplateFault(
      FaultCode.unknownValue,
      'the key prefixes must hold at least one non-empty string',
      file: file,
      key: '${prefix}prefixes',
    );
  }
  return BulletLines(
    docType: requireValue<String>(map, 'doc_type', file: file, prefix: prefix),
    section: requireValue<String>(map, 'section', file: file, prefix: prefix),
    prefixes: prefixes,
  );
}

DropDefaultLines _parseDropDefaultLines(
  YamlMap map,
  int i,
  int j, {
  required String file,
}) {
  final prefix = 'migrations[$i].steps[$j].drop_default_lines.';
  checkKeys(
    map,
    const {'doc_types'},
    file: file,
    format: 'drop_default_lines step',
    prefix: prefix,
  );
  return DropDefaultLines(
    docTypes: stringsOf(
      requireValue<YamlList>(map, 'doc_types', file: file, prefix: prefix),
      'doc_types',
      file: file,
      prefix: prefix,
    ),
  );
}

DropSharedLines _parseDropSharedLines(
  YamlMap map,
  int i,
  int j, {
  required String file,
}) {
  final prefix = 'migrations[$i].steps[$j].drop_shared_lines.';
  checkKeys(
    map,
    const {'ids'},
    file: file,
    format: 'drop_shared_lines step',
    prefix: prefix,
  );
  requireValue<Object>(map, 'ids', file: file, prefix: prefix);
  final value = map['ids'];
  final ids = value is YamlList && value.every((id) => id is String)
      ? [for (final id in value) id as String]
      : const <String>[];
  if (ids.isEmpty) {
    throw TemplateFault(
      FaultCode.unknownValue,
      'drop_shared_lines holds no id',
      file: file,
      key: '${prefix}ids',
    );
  }
  return DropSharedLines(ids: ids);
}

MarkRetrim _parseMarkRetrim(YamlMap map, int i, int j, {required String file}) {
  final prefix = 'migrations[$i].steps[$j].mark_retrim.';
  checkKeys(
    map,
    const {'doc_types', 'sections'},
    file: file,
    format: 'mark_retrim step',
    prefix: prefix,
  );
  List<String> listOf(String key) {
    final list = stringsOf(
      requireValue<YamlList>(map, key, file: file, prefix: prefix),
      key,
      file: file,
      prefix: prefix,
    );
    if (list.isEmpty) {
      throw TemplateFault(
        FaultCode.unknownValue,
        'the key $key must hold at least one id',
        file: file,
        key: '$prefix$key',
      );
    }
    return list;
  }

  return MarkRetrim(
    docTypes: listOf('doc_types'),
    sections: listOf('sections'),
  );
}

/// A `move_file` `to` pattern must hold the `from` placeholders in the same
/// order, which keeps one value per placeholder.
void _checkPlaceholders(
  String from,
  String to, {
  required String key,
  required String file,
}) {
  final fromNames = [
    for (final match in _placeholderPattern.allMatches(from)) match[1]!,
  ];
  final toNames = [
    for (final match in _placeholderPattern.allMatches(to)) match[1]!,
  ];
  var same = fromNames.length == toNames.length;
  if (same) {
    for (var k = 0; k < fromNames.length; k++) {
      if (fromNames[k] != toNames[k]) {
        same = false;
        break;
      }
    }
  }
  if (!same) {
    throw TemplateFault(
      FaultCode.unknownValue,
      'the to pattern must hold the from pattern placeholders '
      'in the same order',
      file: file,
      key: key,
    );
  }
}
