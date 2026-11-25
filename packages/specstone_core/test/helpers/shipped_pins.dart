import 'dart:convert';
import 'dart:typed_data';

import 'package:specstone_core/src/templates/pack_floors.dart';
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
/// below its floor, then the `<pack>: <version>` line [extra] when given.
///
/// The pin derives from the floor, so a version bump moves no fixture.
String shippedPinsBelowFloor({String pack = 'prd-core', String? extra}) {
  final floor = PackFloors.shipped.byPack[pack]!;
  final pinned = '  $pack: ${shippedPackVersions()[pack]}\n';
  final config = shippedPinsConfig();
  if (!config.contains(pinned)) {
    throw StateError('shippedPinsConfig does not pin $pack as expected');
  }
  final below = config.replaceFirst(
    pinned,
    '  $pack: ${floor.major}.${floor.minor - 1}.0\n',
  );
  return extra == null ? below : '$below  $extra\n';
}

/// The shipped pack files less each key of [without], such as
/// `prd-core/glossary.yaml`.
///
/// A dropped doc type also leaves the `for_doc_types` of its pack's shared
/// entries, and an entry left with none is dropped, as a pack that never
/// shipped the type would write them.
Map<String, Uint8List> shippedFilesWithout(Set<String> without) {
  final files = {...shippedPackFiles};
  without.forEach(files.remove);
  final droppedTypes = <String, Set<String>>{};
  for (final key in without) {
    final [pack, file] = key.split('/');
    if (file == 'pack.yaml') continue;
    droppedTypes.putIfAbsent(pack, () => {}).add(file.replaceAll('.yaml', ''));
  }
  for (final MapEntry(:key, :value) in droppedTypes.entries) {
    final manifest = utf8.decode(files['$key/pack.yaml']!);
    files['$key/pack.yaml'] = Uint8List.fromList(
      utf8.encode(_manifestWithoutTypes(manifest, value)),
    );
  }
  return files;
}

/// Returns [manifest] with each of [dropped] out of every `for_doc_types`
/// list, and every list entry whose list empties removed whole.
String _manifestWithoutTypes(String manifest, Set<String> dropped) {
  final listPattern = RegExp(r'^(\s*for_doc_types: )\[(.*)\]$');
  final kept = <String>[];
  for (final entry in _manifestEntries(manifest)) {
    var emptied = false;
    for (final (at, line) in entry.indexed) {
      final match = listPattern.firstMatch(line);
      if (match == null) continue;
      final ids = match[2]!.split(', ').where((id) => !dropped.contains(id));
      emptied = ids.isEmpty;
      entry[at] = '${match[1]}[${ids.join(', ')}]';
    }
    if (!emptied) kept.addAll(entry);
  }
  return kept.join('\n');
}

/// Splits [manifest] into blocks of lines: each `  - ` list entry and each
/// line that starts at column 0 begins one.
List<List<String>> _manifestEntries(String manifest) {
  final entries = <List<String>>[];
  for (final line in manifest.split('\n')) {
    if (RegExp(r'^(  - |\S)').hasMatch(line) || entries.isEmpty) {
      entries.add([]);
    }
    entries.last.add(line);
  }
  return entries;
}

/// Returns a resolver whose shipped packs carry [versions] in place of their
/// own, so a project may pin them below the shipped versions.
///
/// Each key of [without] names a shipped file, such as
/// `prd-core/glossary.yaml`, that the carried pack leaves out.
TemplateResolver resolverCarrying(
  Map<String, String> versions, {
  Set<String> without = const {},
}) {
  final files = shippedFilesWithout(without);
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
