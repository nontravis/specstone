/// What a link cites: the whole doc, one `##` section,
/// one item of a section, the block of a `###` heading, or nothing the doc
/// holds.
sealed class LinkCite {
  const new();
}

/// A doc link: no fragment, or an empty one.
final class DocCite extends LinkCite {
  const new();
}

/// A section link: the anchor names a `##` section and the link's text is
/// no item ID of that section.
final class SectionCite extends LinkCite {
  const new({required this.sectionKey});

  final String sectionKey;
}

/// An item link: the anchor names the `##` section and the whole text an
/// item ID of it, or `S<N>` on an `acceptance_criteria` section.
final class ItemCite extends LinkCite {
  const new({required this.sectionKey, required this.itemId});

  final String sectionKey;

  /// The key `check` holds the item by: the ID as written, or
  /// `Scenario <n>` for an `S<N>` link.
  final String itemId;
}

/// A fragment that names a `###` heading: the cite is that
/// heading's whole block, which `headingBlockExtentOf` bounds.
final class HeadingBlockCite extends LinkCite {
  const new({required this.headingLine});

  /// The file line of the `###` heading.
  final int headingLine;
}

/// A link whose fragment matches no anchor of its target's known anchor set:
/// a broken pointer. `check` reports it (`link_anchor_missing`);
/// a follow skips it and never prints the doc.
final class UnresolvedCite extends LinkCite {
  const new();
}

/// A link whose fragment is an anchor of its target but names no `##`
/// section and no `###` block the doc can place: an html id, the title, a
/// heading below `###`, or a heading whose line the scan cannot pair, or an
/// anchor set that is unknown. The anchor cannot be judged as a section or a
/// block, so a reader skips it: `check` reports no finding for it
/// and a follow never prints the doc.
final class OtherAnchorCite extends LinkCite {
  const new();
}
