import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart' show withKeyBlock;
import 'package:specstone_core/src/document_writing/key_block_values.dart';
import 'package:specstone_core/src/setup_migration/renumber_index.dart';
import 'package:specstone_core/src/setup_migration/renumber_stamps.dart';

// MARK: - Constants

const _tracedFromKey = 'traced_from';
const _overridesKey = 'overrides';
const _confirmedKey = 'confirmed';

// MARK: - Entries

/// Returns [lf], the doc at [docPath], with each `traced_from`, `overrides`,
/// and `confirmed` value naming a renumbered ID set to its new number, and
/// each matched `confirmed` fingerprint of a block the pass rewrote set to
/// the new one ([stamps]).
String withEntriesRenumbered(
  String lf,
  String docPath,
  RenumberIndex index,
  Stamps stamps,
) {
  var text = _withBlockValues(
    lf,
    _tracedFromKey,
    (value) => index.tracedFromLabel(value, docPath),
  );
  text = _withBlockValues(text, _overridesKey, index.overridesLabel);
  final confirmed = _ConfirmedRenamer((label) {
    final target = index.confirmedTarget(label, docPath);
    if (target == null) return null;
    return (label: target.label, stamp: stamps[target.block]);
  });
  return _withBlockValues(text, _confirmedKey, confirmed.call);
}

String _withBlockValues(
  String lf,
  String name,
  String? Function(String value) rename,
) {
  final block = Doc.parse(lf).frontmatter
      ?.where((candidate) => candidate.name == name)
      .firstOrNull;
  if (block == null) return lf;
  final renamed = renameKeyBlockValues(block.text, block.key, rename);
  return renamed == block.text ? lf : withKeyBlock(lf, name, renamed);
}

// MARK: - Confirmed entries

/// Renames the `confirmed` values [renameKeyBlockValues] passes one at a
/// time: a label, then its fingerprint, or both in one quoted value.
final class _ConfirmedRenamer {
  new(this._rename);

  final ({String label, Stamp? stamp})? Function(String label) _rename;

  Stamp? _pending;

  String? call(String value) {
    final pending = _pending;
    _pending = null;
    if (pending != null && value == pending.before) return pending.after;
    final space = value.indexOf(' ');
    if (space >= 0) {
      return _entry(value.substring(0, space), value.substring(space + 1));
    }
    final renamed = _rename(value);
    _pending = renamed?.stamp;
    final label = renamed?.label;
    return label == value ? null : label;
  }

  String? _entry(String label, String fingerprint) {
    final renamed = _rename(label);
    if (renamed == null) return null;
    final stamp = renamed.stamp;
    final matched = stamp != null && fingerprint == stamp.before;
    final entry = '${renamed.label} ${matched ? stamp.after : fingerprint}';
    return entry == '$label $fingerprint' ? null : entry;
  }
}
