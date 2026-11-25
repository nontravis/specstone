/// A `##` section a cite can name: its key, its heading's anchor, and the
/// key of each item it holds, as `itemKeyOfHead` reads it.
final class CiteSection {
  const new({required this.key, required this.anchor, required this.itemKeys});

  final String key;
  final String anchor;
  final Set<String> itemKeys;
}
