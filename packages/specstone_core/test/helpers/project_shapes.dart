import 'dart:io';

import 'check_fixture.dart';
import 'grouped_fixture.dart';
import 'nested_fixture.dart';
import 'shipped_pins.dart';
import 'target_fixture.dart';
import 'write_fixture.dart';

const _configPath = '.specstone/config.yaml';

/// One project shape the CLI supports: its docs and its `config.yaml` text.
final class ProjectShape {
  const new({required this.name, required this.files, required this.config});

  /// The test label.
  final String name;

  /// Every file but the config, keyed by path from the project root.
  final Map<String, String> files;

  /// The text of `.specstone/config.yaml`.
  final String config;

  /// Every file of the shape, the config included.
  Map<String, String> get allFiles => {...files, _configPath: config};
}

/// Returns every shape of the catalog but the baseline tree, which
/// `writeBaselineTree` writes.
///
/// Call it inside a test: the two-target shape is written to a temp tree and
/// read back, so its files stay the ones `writeTwinProject` writes.
// D8: one catalog of project shapes for the shape-by-command matrix.
Future<List<ProjectShape>> projectShapes() async {
  // The shared fixture's persona holds a `## Profile` section the persona type
  // does not declare, so `format` refuses it; the catalog declares `Snapshot`.
  final flat = {
    ...writeProject,
    'docs/prds/personas/buyer/PERSONA.md':
        '---\ndraft: true\nreference:\n  - login/email_login\n---\n\n'
        '# Buyer\n\n## Snapshot\nBuys things.\n',
  };
  final nested = withApprovalHashes(
    withCodeFingerprints({
      ...checkProjectFiles(),
      ...nestedFiles(),
      ...nestedRecords(),
    }),
  );
  final twin = await writeTwinProject();
  final twinFiles = _readTree(twin);
  return [
    _shapeOf('flat', flat),
    _shapeOf('nested', nested),
    ProjectShape(
      name: 'grouped',
      files: _withoutConfig(groupedFiles()),
      config: groupedFiles()[_configPath]!,
    ),
    ProjectShape(
      name: 'feature_grouped',
      files: _withoutConfig(featureGroupedFiles()),
      config: featureGroupedFiles()[_configPath]!,
    ),
    _shapeOf('two_targets', twinFiles),
    ProjectShape(
      name: 'plugin_era',
      files: _withoutConfig(flat),
      config:
          '${shippedPinsConfig(shippedPinsDefaultPacks, const [])}'
          'agent_files_version: 1.0.0\n',
    ),
    ProjectShape(
      name: 'floor_pins',
      files: _withoutConfig(flat),
      config: shippedPinsAtFloor(),
    ),
  ];
}

ProjectShape _shapeOf(String name, Map<String, String> all) => ProjectShape(
  name: name,
  files: _withoutConfig(all),
  config: all[_configPath]!,
);

Map<String, String> _withoutConfig(Map<String, String> all) => {
  for (final MapEntry(:key, :value) in all.entries)
    if (key != _configPath) key: value,
};

Map<String, String> _readTree(Directory root) {
  final prefix = '${root.path}${Platform.pathSeparator}';
  return {
    for (final entity in root.listSync(recursive: true, followLinks: false))
      if (entity is File)
        entity.path
            .substring(prefix.length)
            .replaceAll(Platform.pathSeparator, '/'): entity
            .readAsStringSync(),
  };
}
