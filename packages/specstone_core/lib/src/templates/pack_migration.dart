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

/// One step of a [PackMigration], named by its YAML [kind] key.
sealed class MigrationStep {
  const new();

  /// The id of the doc type this step touches.
  String get docType;

  /// The YAML key that names this step's kind.
  String get kind;
}

/// A `rename_section` step: a section id and header move to new values.
final class RenameSection extends MigrationStep {
  const new({
    required this.docType,
    required this.fromId,
    required this.fromHeader,
    required this.toId,
    required this.toHeader,
  });

  @override
  final String docType;

  /// The section id before this step.
  final String fromId;

  /// The section header before this step.
  final String fromHeader;

  /// The section id after this step.
  final String toId;

  /// The section header after this step.
  final String toHeader;

  @override
  String get kind => 'rename_section';
}

/// A `rename_field` step: a field of one doc type moves to a new name.
final class RenameField extends MigrationStep {
  const new({required this.docType, required this.from, required this.to});

  @override
  final String docType;

  /// The field name before this step.
  final String from;

  /// The field name after this step.
  final String to;

  @override
  String get kind => 'rename_field';
}

/// A `move_file` step: a doc file moves to a new path pattern.
final class MoveFile extends MigrationStep {
  const new({required this.docType, required this.from, required this.to});

  @override
  final String docType;

  /// The path pattern before this step, as written.
  final String from;

  /// The path pattern after this step, as written.
  final String to;

  @override
  String get kind => 'move_file';
}

/// Parses a `migrations:` [node] of a `pack.yaml` read from [file].
///
/// A null node gives no entries; entries keep file order. A bad `from:` is
/// `pack_version_invalid`, an unknown step kind is `unknown_value`, a missing
/// key is `missing_key`, and an unknown key is `unknown_key`, keyed
/// `migrations[<i>].from` and `migrations[<i>].steps[<j>].<kind>.<key>` (PD17).
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

/// A `move_file` `to` pattern must hold the `from` placeholders in the same
/// order (PD21): US-02 FR-02 E04 keeps one value per placeholder.
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
