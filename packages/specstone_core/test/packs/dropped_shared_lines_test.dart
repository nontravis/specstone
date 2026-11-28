@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/templates/layer_source.dart';
import 'package:specstone_core/src/templates/models/migration_step.dart';
import 'package:specstone_core/src/templates/pack_manifest.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// Runs `git` with [args] in the package directory and returns its stdout.
///
/// Fails the test with [whenFailed] and git's stderr when git exits non-zero
/// or is missing.
String _git(List<String> args, {required String whenFailed}) {
  final ProcessResult result;
  try {
    result = Process.runSync(
      'git',
      args,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
  } on ProcessException catch (error) {
    fail('$whenFailed: git is not available ($error)');
  }
  if (result.exitCode != 0) fail('$whenFailed: ${result.stderr}'.trim());
  return result.stdout as String;
}

/// The newest `v*` release tag reachable from HEAD.
String _latestReleaseTag() => _git(
  ['describe', '--tags', '--abbrev=0', '--match', 'v[0-9]*'],
  whenFailed:
      'no release tag found; fetch the v* tags and their history '
      '(CI: actions/checkout with fetch-depth: 0)',
).trim();

/// The shared line ids each pack declared at [tag], keyed by pack name.
///
/// Reads only `shared_lines[].id`, since an old manifest may not parse with
/// today's [PackManifest]. A pack absent at [tag] has no entry.
Map<String, Set<String>> _releasedSharedLineIds(String tag) {
  final files = _git(
    ['ls-tree', '-r', '--name-only', tag, '--', 'packs'],
    whenFailed: 'cannot list the packs at $tag',
  ).split('\n').where((path) => path.endsWith('/$packManifestName'));
  return {
    for (final path in files)
      path.split('/')[1]: _sharedLineIds(
        _git(['show', '$tag:./$path'], whenFailed: 'cannot read $path at $tag'),
      ),
  };
}

Set<String> _sharedLineIds(String manifestYaml) {
  final root = loadYaml(manifestYaml);
  final lines = root is YamlMap ? root['shared_lines'] : null;
  return {
    if (lines is YamlList)
      for (final line in lines)
        if (line is YamlMap && line['id'] is String) line['id'] as String,
  };
}

/// Parses the `pack.yaml` of each shipped pack, keyed by pack name.
Map<String, PackManifest> _shippedManifests() => {
  for (final key in shippedPackFiles.keys)
    if (key.split('/') case [final pack, packManifestName])
      pack: PackManifest.parse(utf8.decode(shippedPackFiles[key]!), file: key),
};

/// Lists `<pack> <id>` for each [released] id its pack in [shipped] neither
/// declares nor drops, in pack then id order.
List<String> _missingDrops(
  Map<String, Set<String>> released,
  Map<String, PackManifest> shipped,
) {
  final missing = <String>[];
  for (final pack in shipped.keys.toList()..sort()) {
    final manifest = shipped[pack]!;
    final accounted = {
      for (final line in manifest.shared.lines) line.id,
      for (final migration in manifest.migrations)
        for (final step in migration.steps)
          if (step is DropSharedLines) ...step.ids,
    };
    for (final id in [...?released[pack]]..sort()) {
      if (!accounted.contains(id)) missing.add('$pack $id');
    }
  }
  return missing;
}

void main() {
  test('each released shared line id stays or is dropped', () {
    final released = _releasedSharedLineIds(_latestReleaseTag());
    expect(_missingDrops(released, _shippedManifests()), isEmpty);
  });

  test('a released id gone with no drop step names pack and id', () {
    final shipped = {
      'acme': PackManifest.parse('''
name: acme
version: 1.1.0
shared_lines:
  - id: kept
    text: Keep it short.
''', file: 'acme/pack.yaml'),
      'beta': PackManifest.parse('''
name: beta
version: 1.1.0
migrations:
  - from: 1.0.0
    steps:
      - drop_shared_lines: {ids: [gone]}
''', file: 'beta/pack.yaml'),
    };
    const released = {
      'acme': {'old_tone', 'kept'},
      'beta': {'gone'},
    };
    expect(_missingDrops(released, shipped), ['acme old_tone']);
  });
}
