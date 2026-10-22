import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/layer.dart';
import 'package:specstone_core/src/templates/layer_source.dart';
import 'package:specstone_core/src/templates/template_fault.dart';

/// Orders [packs] by their `extends` chains (INV-4, INV-18).
///
/// Shipped packs come first by name, then personal packs so each sits above
/// every pack its chain reaches; personal packs outside one chain keep name
/// order (INV-22). Every `extends` must name a loaded pack
/// (`extends_target_unknown`), no chain may return to its start
/// (`extends_cycle`), and no two personal packs may extend one pack
/// (`personal_pack_conflict`, [configFile], key `packs`). Chains run over
/// loaded packs only.
List<LoadedPack> orderPacks(
  List<LoadedPack> packs, {
  required String configFile,
}) {
  final extendsOf = {
    for (final pack in packs) pack.manifest.name: pack.manifest.extendsPack,
  };
  _checkTargets(packs, extendsOf);
  _checkCycles(packs, extendsOf);
  _checkPersonalConflicts(packs, configFile);
  final shipped = [...packs.where((pack) => pack.kind == LayerKind.shipped)]
    ..sort((a, b) => compareCodePoints(a.manifest.name, b.manifest.name));
  final personal = _chainOrdered(
    packs.where((pack) => pack.kind == LayerKind.personal),
    extendsOf,
  );
  return [...shipped, ...personal];
}

/// Whether [upper]'s `extends` chain reaches [lower] (INV-5).
///
/// [extendsOf] maps every loaded pack's name to its `extends` target; false
/// when [upper] is [lower] itself or a target is no loaded pack.
bool reaches(
  LoadedPack upper,
  LoadedPack lower, {
  required Map<String, String?> extendsOf,
}) {
  var target = upper.manifest.extendsPack;
  while (target != null) {
    if (target == lower.manifest.name) return true;
    if (!extendsOf.containsKey(target)) return false;
    target = extendsOf[target];
  }
  return false;
}

/// Throws `extends_target_unknown` for any `extends` naming no loaded pack.
void _checkTargets(List<LoadedPack> packs, Map<String, String?> extendsOf) {
  for (final pack in packs) {
    final target = pack.manifest.extendsPack;
    if (target != null && !extendsOf.containsKey(target)) {
      throw TemplateFault(
        FaultCode.extendsTargetUnknown,
        'the key extends names no loaded pack: $target',
        file: pack.manifest.file,
        key: 'extends',
      );
    }
  }
}

/// Throws `extends_cycle` for a chain that returns to its start.
///
/// `file` holds the later-loaded `pack.yaml` of the cycle in name order
/// (INV-22); `relatedFiles` holds the other cycle files in that order.
void _checkCycles(List<LoadedPack> packs, Map<String, String?> extendsOf) {
  final byName = {for (final pack in packs) pack.manifest.name: pack};
  final sorted = [...packs]
    ..sort((a, b) => compareCodePoints(a.manifest.name, b.manifest.name));
  for (final pack in sorted) {
    final walked = <String>[pack.manifest.name];
    var target = pack.manifest.extendsPack;
    while (target != null && extendsOf.containsKey(target)) {
      final index = walked.indexOf(target);
      if (index != -1) {
        final cycle = walked.sublist(index);
        _throwCycle(cycle, byName);
      }
      walked.add(target);
      target = extendsOf[target];
    }
  }
}

/// Throws the `extends_cycle` fault for [cycle], walked in chain order.
Never _throwCycle(List<String> cycle, Map<String, LoadedPack> byName) {
  final members = [...cycle]..sort(compareCodePoints);
  final later = byName[members.last]!;
  throw TemplateFault(
    FaultCode.extendsCycle,
    'extends chain returns to its start: ${[...cycle, cycle.first].join(', ')}',
    file: later.manifest.file,
    relatedFiles: [
      for (final name in members.where((name) => name != members.last))
        byName[name]!.manifest.file,
    ],
  );
}

/// Throws `personal_pack_conflict` for two personal packs with one target.
void _checkPersonalConflicts(List<LoadedPack> packs, String configFile) {
  final ownerOf = <String, String>{};
  final sorted = [...packs.where((pack) => pack.kind == LayerKind.personal)]
    ..sort((a, b) => compareCodePoints(a.manifest.name, b.manifest.name));
  for (final pack in sorted) {
    final target = pack.manifest.extendsPack;
    if (target == null) continue;
    final owner = ownerOf[target];
    if (owner != null) {
      throw TemplateFault(
        FaultCode.personalPackConflict,
        'two listed personal packs extend one pack: $owner and '
        '${pack.manifest.name} both extend $target',
        file: configFile,
        key: 'packs',
      );
    }
    ownerOf[target] = pack.manifest.name;
  }
}

/// Sorts [personal] so each pack sits above every pack its chain reaches.
///
/// Packs wait until every pack they reach is placed; among unblocked packs
/// the name-first (INV-22) is placed first. Cycles cannot reach here:
/// `_checkCycles` ran first.
List<LoadedPack> _chainOrdered(
  Iterable<LoadedPack> personal,
  Map<String, String?> extendsOf,
) {
  final pending = [...personal]
    ..sort((a, b) => compareCodePoints(a.manifest.name, b.manifest.name));
  final ordered = <LoadedPack>[];
  while (pending.isNotEmpty) {
    final pack = pending.firstWhereOrNull(
      (pack) => !pending.any(
        (other) => other != pack && reaches(pack, other, extendsOf: extendsOf),
      ),
    );
    if (pack == null) throw StateError('pack chain ordering stalled');
    ordered.add(pack);
    pending.remove(pack);
  }
  return ordered;
}

extension<T> on List<T> {
  /// The first element matching [test], or null (firstOrNull without
  /// package:collection).
  T? firstWhereOrNull(bool Function(T) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
