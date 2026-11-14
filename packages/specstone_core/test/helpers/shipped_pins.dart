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
TemplateResolver resolverCarrying(Map<String, String> versions) {
  final files = {...shippedPackFiles};
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
