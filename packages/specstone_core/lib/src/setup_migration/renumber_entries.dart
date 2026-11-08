import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart' show withKeyBlock;
import 'package:specstone_core/src/document_writing/key_block_values.dart';
import 'package:specstone_core/src/setup_migration/renumber_doc.dart';
import 'package:specstone_core/src/setup_migration/renumber_index.dart';

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
/// a [renumberedEntryKeys] key naming a renumbered ID set to its new number.
///
/// A `confirmed` fingerprint stays as written; the upgrade's stamp pass sets
/// it once, after every step.
///
/// Only the frontmatter, which the body rewrite leaves as [doc] holds it, is
/// read.
String withEntriesRenumbered(String lf, RenumberDoc doc, RenumberIndex index) {
  final frontmatter = doc.frontmatterText;
  if (frontmatter.isEmpty) return lf;
  var text = frontmatter;
  for (final key in renumberedEntryKeys) {
    text = withBlockValues(text, key, _renamerOf(key, doc, index));
  }
  return text == frontmatter ? lf : text + lf.substring(frontmatter.length);
}

/// The renamer of the values of [key], one of [renumberedEntryKeys].
String? Function(String value) _renamerOf(
  String key,
  RenumberDoc doc,
  RenumberIndex index,
) => switch (key) {
  _tracedFromKey => (value) => index.tracedFromLabel(value, doc.docPath),
  _overridesKey => index.overridesLabel,
  _confirmedKey => (value) => _confirmedLabel(value, doc, index),
  _visionKey || _goalsKey => index.projectIdLabel,
  _ => throw ArgumentError.value(key, 'key', 'is no renumbered entry key'),
};

/// Returns [text] with each value of the frontmatter key [name] set to what
/// [rename] returns for it, or kept when it returns null.
String withBlockValues(
  String text,
  String name,
  String? Function(String value) rename,
) {
  final block = Doc.parse(text).frontmatter
      ?.where((candidate) => candidate.name == name)
      .firstOrNull;
  if (block == null) return text;
  final renamed = renameKeyBlockValues(block.text, block.key, rename);
  return renamed == block.text ? text : withKeyBlock(text, name, renamed);
}

// MARK: - Confirmed entries

/// Renames the label of a `confirmed` [value] [renameKeyBlockValues] passes:
/// a label, a fingerprint, or both in one quoted value.
String? _confirmedLabel(String value, RenumberDoc doc, RenumberIndex index) {
  final space = value.indexOf(' ');
  final label = space < 0 ? value : value.substring(0, space);
  final renamed = index.confirmedTarget(label, doc.docPath)?.label;
  if (renamed == null || renamed == label) return null;
  return space < 0 ? renamed : '$renamed${value.substring(space)}';
}
