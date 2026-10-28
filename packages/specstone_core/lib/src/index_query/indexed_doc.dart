import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:markdown/markdown.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/doc_model/path_pattern.dart';
import 'package:specstone_core/src/index_query/line_facts.dart';
import 'package:specstone_core/src/index_query/section_counts.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:yaml/yaml.dart';

/// Returns the SHA-256 of [bytes] as lowercase hex.
String contentHashOf(List<int> bytes) => sha256.convert(bytes).toString();

/// Returns the size of [text] in tokens: its code points divided by 4, rounded
/// down.
int tokenSizeOf(String text) => text.runes.length ~/ 4;

final _outsideSlug = RegExp(r'[^\p{L}\p{M}\p{N} _-]', unicode: true);

/// Returns the section key a header without a template id takes.
///
/// The header lowercases, loses every character that is not a letter, mark,
/// digit, space, `-`, or `_`, and turns each space into `-`.
String headingSlug(String headerText) =>
    headerText.toLowerCase().replaceAll(_outsideSlug, '').replaceAll(' ', '-');

/// Returns the name a doc answers to in a query.
///
/// The `{slug}` values of the doc type path joined with `/`; the doc type id
/// when the path has none; [docPath] when [docType] is null.
String docNameOf(String docPath, MergedDocType? docType) {
  if (docType == null) return docPath;
  final path = docType.path;
  final slugs = path == null
      ? const <String>[]
      : PathPattern(path).slugValues(docPath) ?? const <String>[];
  return slugs.isEmpty ? docType.id : slugs.join('/');
}

/// Returns [n] as the word a message uses: `two` for 2, else the digits.
String countWord(int n) => n == 2 ? 'two' : '$n';

/// One `##` section of an indexed doc.
final class IndexedSection {
  const new({required this.key, required this.headerLine, required this.body});

  /// The template section id, else the heading slug.
  final String key;

  /// The `##` line as written, without its line ending.
  final String headerLine;

  /// Every line after the header line up to the next section header.
  final String body;

  /// The header line and the body, without the final line break.
  String get text {
    final whole = '$headerLine\n$body';
    return whole.endsWith('\n') ? whole.substring(0, whole.length - 1) : whole;
  }

  /// The size of [text] in tokens.
  int get tokens => tokenSizeOf(text);
}

/// What the index keeps about one doc, apart from its text.
final class IndexedDoc {
  const new({
    required this.docPath,
    this.docTypeId,
    required this.name,
    this.parentPath,
    this.title,
    required this.frontmatter,
    required this.tokens,
    this.order = 0,
    this.warnings = const [],
  });

  /// The path of the doc relative to the docs root.
  final String docPath;

  /// The id of the doc type that matches [docPath]; null when untyped.
  final String? docTypeId;

  /// The name the doc answers to in a query.
  final String name;

  /// The docPath of the doc this one nests under; null for a root doc.
  final String? parentPath;

  /// The text after `# ` in the doc head; null without a title line.
  final String? title;

  /// The frontmatter as plain Dart values; empty without valid frontmatter.
  final Map<String, Object?> frontmatter;

  /// The size of the whole file in tokens.
  final int tokens;

  /// The position of the doc in tree order.
  final int order;

  /// What went wrong while reading the doc, one sentence each.
  final List<String> warnings;

  /// Whether exactly one doc type matches [docPath].
  bool get isTyped => docTypeId != null;

  /// The `status` the doc writes, or null when it writes none.
  String? get writtenStatus => switch (frontmatter['status']) {
    final String status => status,
    _ => null,
  };

  /// Whether the `draft` key holds the YAML boolean `true`.
  bool get isDraft => frontmatter['draft'] == true;

  /// Returns the values of [key]: a scalar as one string, each scalar item of
  /// a list, else none.
  List<String> valuesOf(String key) => switch (frontmatter[key]) {
    final List<Object?> items => [
      for (final item in items)
        if (_isScalar(item)) '$item',
    ],
    final Object? value when _isScalar(value) => ['$value'],
    _ => const [],
  };
}

bool _isScalar(Object? value) =>
    value is String || value is num || value is bool;

/// The text and structure of one doc, as `get` and `context` print it.
final class DocContent {
  const new({
    required this.text,
    this.frontmatterText,
    required this.head,
    required this.sections,
    required this.links,
    required this.lineFacts,
  });

  /// The whole file as decoded, in its own line endings.
  final String text;

  /// The frontmatter lines, delimiters included, in LF; null without any.
  final String? frontmatterText;

  /// The text between the frontmatter and the first section, in LF.
  final String head;

  /// The sections in file order.
  final List<IndexedSection> sections;

  /// The docPaths of the other docs this one links to, each once in order.
  final List<String> links;

  /// The line facts of the file, stored by the refresh that parsed it.
  final LineFacts lineFacts;
}

/// One parsed file: its index entry, its content, and its content hash.
final class ParsedDoc {
  const new(this.doc, this.content, this.contentHash);

  /// The index entry.
  final IndexedDoc doc;

  /// The text and structure.
  final DocContent content;

  /// The SHA-256 of the file bytes as hex.
  final String contentHash;
}

/// Parses the file [bytes] at [docPath] into its index entry and content.
///
/// Invalid UTF-8 decodes with replacement characters, and invalid frontmatter
/// YAML leaves no values; each adds a warning instead of failing.
ParsedDoc parseIndexedDoc({
  required String docPath,
  required List<int> bytes,
  required DocTypeMatch match,
}) {
  final warnings = <String>[];
  final text = _decode(bytes, docPath, warnings);
  final lfText = toLf(text);
  final doc = Doc.parse(lfText);
  final docType = switch (match) {
    MatchedDocType(:final docType) => docType,
    _ => null,
  };
  if (match case AmbiguousDocType(:final docTypeIds)) {
    warnings.add(
      '$docPath matches ${countWord(docTypeIds.length)} doc types: '
      '${docTypeIds.join(', ')}',
    );
  }
  final yaml = switch (doc.frontmatter) {
    final blocks? => parseFrontmatterYaml(blocks.map((b) => b.text).join()),
    null => null,
  };
  final frontmatter = _frontmatterValues(yaml, docPath, warnings);
  final sections = [
    for (final section in doc.sections) _sectionOf(section, docType),
  ];
  final content = DocContent(
    text: text,
    frontmatterText: doc.frontmatter == null
        ? null
        : lfText.substring(0, lfText.length - doc.afterFrontmatter.length),
    head: doc.head,
    sections: sections,
    links: _linksOf(doc.afterFrontmatter, docPath),
    lineFacts: LineFacts.of(
      lfText: lfText,
      doc: doc,
      sectionCounts: [for (final section in sections) sectionCountsOf(section)],
      frontmatterErrorLine: yaml?.errorLine,
    ),
  );
  final indexed = IndexedDoc(
    docPath: docPath,
    docTypeId: docType?.id,
    name: docNameOf(docPath, docType),
    title: doc.title,
    frontmatter: frontmatter,
    tokens: tokenSizeOf(text),
    warnings: warnings,
  );
  return ParsedDoc(indexed, content, contentHashOf(bytes));
}

String _decode(List<int> bytes, String docPath, List<String> warnings) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    warnings.add(
      '$docPath: not UTF-8 text; indexed with replacement characters',
    );
    return utf8.decode(bytes, allowMalformed: true);
  }
}

IndexedSection _sectionOf(Section section, MergedDocType? docType) {
  final headerText = section.headerText;
  final template = docType?.sections
      .where((s) => s.header == headerText)
      .firstOrNull;
  return IndexedSection(
    key: template?.id ?? headingSlug(headerText),
    headerLine: section.headerLine,
    body: section.body,
  );
}

Map<String, Object?> _frontmatterValues(
  FrontmatterYaml? yaml,
  String docPath,
  List<String> warnings,
) {
  if (yaml == null) return const {};
  // An empty frontmatter has no mapping and no error: valid YAML with no
  // values.
  if (yaml.errorLine != null) return _notIndexed(docPath, warnings);
  final map = yaml.map;
  if (map == null) return const {};
  return {for (final entry in map.entries) '${entry.key}': _plain(entry.value)};
}

Map<String, Object?> _notIndexed(String docPath, List<String> warnings) {
  warnings.add(
    '$docPath: frontmatter is not valid YAML; its values are not indexed',
  );
  return const {};
}

/// Returns [value] as plain maps, lists, and scalars that `jsonEncode` takes.
///
/// A non-finite number has no JSON form, so it stays as its YAML text.
Object? _plain(Object? value) => switch (value) {
  YamlMap() => {for (final e in value.entries) '${e.key}': _plain(e.value)},
  YamlList() => [for (final item in value) _plain(item)],
  double(isNaN: true) => '.nan',
  double(isInfinite: true, isNegative: true) => '-.inf',
  double(isInfinite: true) => '.inf',
  _ => value,
};

List<String> _linksOf(String lfBody, String docPath) {
  // Exact: a doc link is inline (`](`) or has a `]:` definition; an autolink
  // is absolute, so it never resolves to a doc.
  if (!lfBody.contains('](') && !lfBody.contains(']:')) return const [];
  final links = <String>{};
  void visit(List<Node> nodes) {
    for (final node in nodes) {
      if (node is! Element) continue;
      if (node.tag == 'a') {
        final target = resolveDocLink(node.attributes['href'] ?? '', docPath);
        if (target is DocTarget &&
            target.docPath.endsWith('.md') &&
            target.docPath != docPath) {
          links.add(target.docPath);
        }
      }
      final children = node.children;
      if (children != null) visit(children);
    }
  }

  visit(Document(extensionSet: ExtensionSet.gitHubFlavored).parse(lfBody));
  return links.toList();
}
