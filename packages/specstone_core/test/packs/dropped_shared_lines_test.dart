import 'dart:convert';

import 'package:specstone_core/src/templates/layer_source.dart';
import 'package:specstone_core/src/templates/models/migration_step.dart';
import 'package:specstone_core/src/templates/pack_manifest.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:test/test.dart';

/// The shared line ids each shipped pack declared in `v1.2.0-beta.1`, keyed by
/// pack name.
///
/// Recorded by hand: refresh it before a release that changes a shipped pack's
/// `shared_lines`. A later pack version must keep each id or drop it with a
/// `drop_shared_lines` step.
const _releasedSharedLineIds = <String, Set<String>>{
  'agent-skills': {},
  'marketing': {},
  'personal-branding': {},
  'prd-core': {},
  'software-design-system': {},
  'software-tech': {},
};

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
    final shipped = _shippedManifests();
    expect(
      _releasedSharedLineIds.keys,
      containsAll(shipped.keys),
      reason: 'add a row for each new shipped pack',
    );
    expect(_missingDrops(_releasedSharedLineIds, shipped), isEmpty);
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
