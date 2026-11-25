import 'package:specstone_core/src/document_writing/item_landing.dart'
    show itemSpanOf, nestedIdsOf;
import 'package:specstone_core/src/document_writing/move_item.dart'
    show ItemLanding, ItemTarget, Renumbering, ownOverrideOf;
import 'package:specstone_core/src/index_query/doc_index.dart';

/// The lines of one moved item in its source doc.
final class MovedSpan {
  const new({required this.first, required this.last, required this.landing});

  final int first;
  final int last;
  final ItemLanding landing;
}

/// Where each moved item sits and lands, and the new ID of each item a call
/// renumbers in place, as every rewrite reads them.
final class ItemMoves {
  new(this.index, this.landings, {List<Renumbering> renumberings = const []}) {
    for (final Renumbering(:docPath, :oldToNew) in renumberings) {
      if (oldToNew.isNotEmpty) renumbered[docPath] = oldToNew;
    }
    for (final landing in landings) {
      final docPath = landing.from.doc.docPath;
      final span = itemSpanOf(index, landing);
      byKey[_keyOf(docPath, landing.from.id)] = landing;
      for (final id in nestedIdsOf(index, span.located)) {
        byKey[_keyOf(docPath, id)] = _nestedLanding(landing, id);
      }
      (spans[docPath] ??= []).add(
        MovedSpan(first: span.first, last: span.last, landing: landing),
      );
      prefixes.add(span.located.prefix);
      if (ownOverrideOf(index, span.located) case final own?) {
        (ownLines[docPath] ??= {}).add(own.cite.line);
      }
    }
  }

  final DocIndex index;
  final List<ItemLanding> landings;

  /// Each landing by its source doc's DocPath and the ID it moves; an item
  /// nested in a moved item lands with it under its own ID.
  final byKey = <String, ItemLanding>{};
  final spans = <String, List<MovedSpan>>{};
  final ownLines = <String, Set<int>>{};
  final prefixes = <String>{};

  /// The new ID of each item renumbered in place, by DocPath then old ID.
  final renumbered = <String, Map<String, String>>{};

  static String _keyOf(String docPath, String id) => '$docPath#$id';

  /// Returns the landing of the item [id] nested in the item [holder] moves.
  static ItemLanding _nestedLanding(ItemLanding holder, String id) =>
      ItemLanding(
        from: ItemTarget(doc: holder.from.doc, id: id),
        to: holder.to,
        sectionKey: holder.sectionKey,
        newId: id,
        created: holder.created,
      );

  /// Whether the call moves or renumbers any item.
  bool get isEmpty => landings.isEmpty && renumbered.isEmpty;

  /// Returns the ID the item [id] of [docPath] takes in place, or null when
  /// the call keeps its number.
  String? renumberedId(String docPath, String id) => renumbered[docPath]?[id];

  ItemLanding? landingOf(String docPath, String id, {String? sectionKey}) {
    final landing = byKey[_keyOf(docPath, id)];
    if (landing == null) return null;
    return sectionKey == null || landing.sectionKey == sectionKey
        ? landing
        : null;
  }

  /// The span of a moved item that holds file [line] of [docPath].
  MovedSpan? spanAt(String docPath, int line) {
    for (final span in spans[docPath] ?? const <MovedSpan>[]) {
      if (span.first <= line && line <= span.last) return span;
    }
    return null;
  }

  /// The DocPath of the doc the text of [docPath]'s file [line] sits in once
  /// the items have moved.
  String placeOf(String docPath, int line) =>
      spanAt(docPath, line)?.landing.to.docPath ?? docPath;

  /// Whether file [line] of [docPath] is the `Overrides:` line of a moved
  /// item, which lands with its link rebased.
  bool isOwnLine(String docPath, int line) =>
      ownLines[docPath]?.contains(line) ?? false;
}
