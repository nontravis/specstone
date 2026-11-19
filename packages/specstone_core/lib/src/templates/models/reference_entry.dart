/// One `reference:` entry of a doc type, as one layer writes it.
final class ReferenceEntry {
  new({required this.title, this.url, this.file, this.doc, this.locator});

  /// The source's name; a title-only entry is a book or standard.
  final String title;

  /// The link address, shown as written and never fetched.
  final String? url;

  /// The cited file, normalized to its layer-relative path.
  final String? file;

  /// The cited project doc identity; only the project layer may write it.
  final String? doc;

  /// The chapter, page, or appendix of the cited source.
  final String? locator;

  /// Returns the JSON object of this entry with only the keys set.
  Map<String, Object> toJson() => {
    'title': title,
    'url': ?url,
    'file': ?file,
    'doc': ?doc,
    'locator': ?locator,
  };
}
