import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';

/// The `config.yaml` text pinning [packs] to the shipped versions.
///
/// Fixtures call it so a pack version bump changes no fixture.
String shippedPinsConfig([
  List<String> packs = const ['prd-core', 'software-tech'],
]) {
  final versions = shippedPackVersions();
  final pins = [for (final pack in packs) '  $pack: ${versions[pack]}\n'];
  return 'packs:\n${pins.join()}';
}

/// The `config.yaml` text of [shippedPinsConfig] with [pack] pinned one minor
/// below its shipped version.
///
/// The pin is `MAJOR.MINOR-1.0`, so it stays one minor older after a bump.
String shippedPinsOneMinorBelow(String pack) {
  final shipped = PackVersion.parse(
    shippedPackVersions()[pack]!,
    file: 'shipped',
    key: pack,
  );
  if (shipped.minor == 0) {
    throw StateError('$pack ships at $shipped, with no minor below it');
  }
  final below = '${shipped.major}.${shipped.minor - 1}.0';
  final pinned = '  $pack: $shipped\n';
  final config = shippedPinsConfig();
  if (!config.contains(pinned)) {
    throw StateError('shippedPinsConfig does not pin $pack at $shipped');
  }
  return config.replaceFirst(pinned, '  $pack: $below\n');
}

/// Whether a project on the shipped pins keeps a record's statuses outside
/// the approval hash, the rule every shipped-pin fixture hashes by.
final bool shippedStatusesOutside = statusesOutsideApproval({
  for (final MapEntry(:key, :value) in shippedPackVersions().entries)
    key: PackVersion.parse(value, file: 'shipped', key: key),
});

/// The `software-tech` version just below the pin that keeps a record's
/// statuses outside the approval hash.
const statusesBelowVersion = '1.6.0';

/// Returns a resolver whose shipped packs carry [versions] in place of their
/// own, so a project may pin them below the shipped versions.
///
/// Each key of [without] names a shipped file, such as
/// `prd-core/glossary.yaml`, that the carried pack leaves out.
TemplateResolver resolverCarrying(
  Map<String, String> versions, {
  Set<String> without = const {},
}) {
  final files = {...shippedPackFiles};
  without.forEach(files.remove);
  for (final MapEntry(:key, :value) in versions.entries) {
    final manifest = utf8.decode(files['$key/pack.yaml']!);
    files['$key/pack.yaml'] = Uint8List.fromList(
      utf8.encode(
        manifest.replaceFirst(
          RegExp(r'^version: .*$', multiLine: true),
          'version: $value',
        ),
      ),
    );
  }
  return TemplateResolver(shippedFiles: files);
}

/// The resolver of a project whose config [pinStatusesBelow] rewrote.
final TemplateResolver statusesBelowResolver = resolverCarrying({
  'software-tech': statusesBelowVersion,
});

/// Pins `software-tech` in the config of [root] at [statusesBelowVersion],
/// in place of its shipped version; open it with [statusesBelowResolver].
void pinStatusesBelow(Directory root) {
  final config = File('${root.path}/.specstone/config.yaml');
  final shipped = 'software-tech: ${shippedPackVersions()['software-tech']}';
  final text = config.readAsStringSync();
  if (!text.contains(shipped)) {
    throw StateError('${config.path} does not pin $shipped');
  }
  config.writeAsStringSync(
    text.replaceFirst(shipped, 'software-tech: $statusesBelowVersion'),
  );
}
