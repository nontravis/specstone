import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart' show withKeyBlock;
import 'package:specstone_core/src/document_writing/key_block_values.dart';
import 'package:specstone_core/src/setup_migration/renumber_doc.dart';
import 'package:specstone_core/src/setup_migration/renumber_index.dart';
import 'package:specstone_core/src/setup_migration/renumber_stamps.dart';

// MARK: - Constants

const _tracedFromKey = 'traced_from';
const _overridesKey = 'overrides';
const _confirmedKey = 'confirmed';
const _visionKey = 'vision';
const _goalsKey = 'goals';

/// The frontmatter keys whose values `check` resolves against item IDs, the
/// one list the pass rewrites (E18, W1); a lettered token in any other value
/// stays byte-equal.
const List<String> renumberedEntryKeys = [
  _tracedFromKey,
  _overridesKey,
  _confirmedKey,
  _visionKey,
  _goalsKey,
];

// MARK: - Entries

/// Returns [lf], the text of [doc] after its body rewrite, with each value of
/// a [renumberedEntryKeys] key naming a renumbered ID set to its new number,
/// and each matched `confirmed` fingerprint of a block the pass rewrote set
/// to the new one ([stamps]).
///
/// Only the frontmatter, which the body rewrite leaves as [doc] holds it, is
/// read.
String withEntriesRenumbered(
  String lf,
  RenumberDoc doc,
  RenumberIndex index,
  Stamps stamps,
) {
  final frontmatter = doc.frontmatterText;
  if (frontmatter.isEmpty) return lf;
  var text = frontmatter;
  for (final key in renumberedEntryKeys) {
    text = _withBlockValues(text, key, _renamerOf(key, doc, index, stamps));
  }
  return text == frontmatter ? lf : text + lf.substring(frontmatter.length);
}

/// The renamer of the values of [key], one of [renumberedEntryKeys].
String? Function(String value) _renamerOf(
  String key,
  RenumberDoc doc,
  RenumberIndex index,
  Stamps stamps,
) => switch (key) {
  _tracedFromKey => (value) => index.tracedFromLabel(value, doc.docPath),
  _overridesKey => index.overridesLabel,
  _confirmedKey => _ConfirmedRenamer((label) {
    final target = index.confirmedTarget(label, doc.docPath);
    if (target == null) return null;
    return (label: target.label, stamp: stamps[target.block]);
  }).call,
  _visionKey || _goalsKey => index.projectIdLabel,
  _ => throw ArgumentError.value(key, 'key', 'is no renumbered entry key'),
};

String _withBlockValues(
  String frontmatter,
  String name,
  String? Function(String value) rename,
) {
  final block = Doc.parse(frontmatter).frontmatter
      ?.where((candidate) => candidate.name == name)
      .firstOrNull;
  if (block == null) return frontmatter;
  final renamed = renameKeyBlockValues(block.text, block.key, rename);
  return renamed == block.text
      ? frontmatter
      : withKeyBlock(frontmatter, name, renamed);
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
