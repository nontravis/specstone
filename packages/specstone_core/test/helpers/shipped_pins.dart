import 'package:specstone_core/src/templates/shipped_pack_files.dart';

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
