import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/doc_model/number_label.dart'
    show numberLabelLinesInMarkdown;
import 'package:specstone_core/src/doc_model/path_pattern.dart';
import 'package:specstone_core/src/doc_model/tbr_marker.dart';
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/index_query/banned_matches.dart';
import 'package:specstone_core/src/index_query/item_facts.dart';
import 'package:specstone_core/src/index_query/line_facts.dart';
import 'package:specstone_core/src/index_query/section_counts.dart';
import 'package:specstone_core/src/rendering/formatter.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:yaml/yaml.dart';

/// The id of the `feature` doc type.
const featureType = 'feature';

/// The id of the `user_story` doc type.
const storyType = 'user_story';

/// The id of the `fr` doc type.
const frType = 'fr';

/// Returns the SHA-256 of [bytes] as lowercase hex.
String contentHashOf(List<int> bytes) => sha256.convert(bytes).toString();

/// Returns the size of [text] in tokens: its code points divided by 4, rounded
/// down.
int tokenSizeOf(String text) => text.runes.length ~/ 4;

final _outsideKey = RegExp(r'[^\p{L}\p{M}\p{N} _-]', unicode: true);
final _keySeparators = RegExp('[ _-]+');
final _keyEdges = RegExp(r'^_+|_+$');

/// The key of the lead: the text before a doc's first `##` header.
///
/// Reserved: no template section id and no derived key may start with `_`.
const leadKey = '_lead';

/// Returns the section key a header without a template id takes.
///
/// The header lowercases, loses every character that is not a letter, mark,
/// digit, space, `-`, or `_`, turns each run of spaces, `-`, and `_` into one
/// `_`, and loses `_` at both ends. Empty when no word remains.
String sectionKeyOf(String headerText) => headerText
    .toLowerCase()
    .replaceAll(_outsideKey, '')
    .replaceAll(_keySeparators, '_')
    .replaceAll(_keyEdges, '');

/// Returns the name a doc answers to in a query.
///
/// The `{slug}` values of the doc type path that matches joined with `/`; the
/// doc type id when that path has none; [docPath] when [docType] is null. A
/// doc matched through [target]'s pattern set is read with that set's
/// patterns, as the matcher expands them, so its target folder names no slug
/// and twins of two targets share the name (RULE-21).
String docNameOf(String docPath, MergedDocType? docType, {String? target}) {
  if (docType == null) return docPath;
  for (final path in docType.paths) {
    final pattern = target == null
        ? PathPattern(path)
        : PathPattern(path).forTarget(target);
    final slugs = pattern.slugValues(docPath);
    if (slugs != null) return slugs.isEmpty ? docType.id : slugs.join('/');
  }
  return docType.id;
}

/// Returns [n] as the word a message uses: `two` for 2, else the digits.
String countWord(int n) => n == 2 ? 'two' : '$n';

/// One `##` section of an indexed doc.
final class IndexedSection {
  const new({required this.key, required this.headerLine, required this.body});

  /// The template section id, else the [sectionKeyOf] key of the header.
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
    this.target,
    this.parentPath,
    this.title,
    required this.frontmatter,
    required this.tokens,
    this.formatted,
    this.approvalHash,
    this.order = 0,
    this.warnings = const [],
  });

  /// The path of the doc relative to the docs root.
  final String docPath;

  /// The id of the doc type that matches [docPath]; null when untyped.
  final String? docTypeId;

  /// The name the doc answers to in a query.
  final String name;

  /// The code target a per-target doc belongs to: the one whose pattern set
  /// matched with two or more targets, else the single target when named.
  ///
  /// Null for a shared doc, a doc of a doc type that is not per-target, and
  /// an untyped doc (INV-26).
  final String? target;

  /// Whether the doc shows under [codeTarget]: always with none, else only
  /// when the doc is shared or belongs to that target (INV-26).
  bool inTarget(String? codeTarget) =>
      codeTarget == null || target == null || target == codeTarget;

  /// The docPath of the doc this one nests under; null for a root doc.
  final String? parentPath;

  /// The text after `# ` in the doc head; null without a title line.
  final String? title;

  /// The frontmatter as plain Dart values; empty without valid frontmatter.
  final Map<String, Object?> frontmatter;

  /// The size of the whole file in tokens.
  final int tokens;

  /// Whether the LF text equals the text the format command lays out.
  ///
  /// Null for an untyped doc, a doc whose bytes are not UTF-8, and a doc the
  /// format command refuses: the docs whose counts cover their text as
  /// decoded.
  final bool? formatted;

  /// The [comparedApprovalHash] of the doc; null for an untyped doc or one
  /// whose frontmatter is not valid YAML.
  final String? approvalHash;

  /// The position of the doc in tree order.
  final int order;

  /// What went wrong while reading the doc, one sentence each.
  final List<String> warnings;

  /// Whether exactly one doc type matches [docPath].
  bool get isTyped => docTypeId != null;

  /// The `status` the doc writes, or null when it writes none.
  ///
  /// A story or FR takes its status from its record entry instead
  /// (`DocIndex.statusOf`); this is the raw written value.
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
  /// Takes [text], [bannedMatches], and [itemFacts] through [readText],
  /// [readBannedMatches], and [readItemFacts], each called on the first read
  /// of its field.
  new({
    required String Function() readText,
    this.frontmatterText,
    required this.head,
    required this.sections,
    required this.links,
    required this.lineFacts,
    required List<BannedMatch> Function() readBannedMatches,
    required ItemFacts Function() readItemFacts,
  }) : _readText = readText,
       _readBannedMatches = readBannedMatches,
       _readItemFacts = readItemFacts;

  /// The whole file as decoded, in its own line endings.
  late final String text = _readText();

  final String Function() _readText;

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

  /// The banned-pattern matches of the file under its doc type, stored by the
  /// refresh that parsed it.
  late final List<BannedMatch> bannedMatches = _readBannedMatches();

  final List<BannedMatch> Function() _readBannedMatches;

  /// The items of the doc and its lead's counts, stored by the refresh that
  /// parsed it; a read command that never reads them never decodes them.
  late final ItemFacts itemFacts = _readItemFacts();

  final ItemFacts Function() _readItemFacts;
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
/// [codeTarget] names the project's one target when it has exactly one and it
/// is named, so a per-target doc stores it (E24); null leaves a per-target
/// doc's target unset, as a project with one unnamed target or no code root
/// stores no name. Invalid UTF-8 decodes with replacement characters, and
/// invalid frontmatter YAML leaves no values; each adds a warning instead of
/// failing. A doc that is not UTF-8, which format skips, is not laid out and
/// has no `formatted` value.
ParsedDoc parseIndexedDoc({
  required String docPath,
  required List<int> bytes,
  required DocTypeMatch match,
  String? codeTarget,
}) {
  final warnings = <String>[];
  final (:text, :isUtf8) = _decode(bytes, docPath, warnings);
  final lfText = toLf(text);
  final doc = Doc.parse(lfText);
  final (:docType, :target) = switch (match) {
    MatchedDocType(:final docType, :final target) => (
      docType: docType,
      target: target,
    ),
    _ => (docType: null, target: null),
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
  final templates = _templatesByKey(docType);
  final sections = [
    for (final section in doc.sections) _sectionOf(section, templates),
  ];
  final laid = docType == null || !isUtf8 ? null : formatDoc(doc, docType);
  final laidText = switch (laid) {
    Formatted(:final text) => text,
    _ => lfText,
  };
  final lineFacts = LineFacts.of(
    lfText: lfText,
    countedText: laidText,
    docPath: docPath,
    doc: doc,
    sectionCounts: _countsOf(sections, laid, templates),
    frontmatterErrorLine: yaml?.errorLine,
    bodyNumberLabels: numberLabelLinesInMarkdown(doc.afterFrontmatter),
    bodyTbrMarkers: tbrMarkerLinesIn(doc.afterFrontmatter),
    warnings: warnings,
  );
  final itemFacts = itemFactsOf(
    doc: doc,
    lfText: lfText,
    lineFacts: lineFacts,
    laid: laid is Formatted ? laid : null,
    type: docType,
  );
  final content = DocContent(
    readText: () => text,
    frontmatterText: doc.frontmatter == null
        ? null
        : lfText.substring(0, lfText.length - doc.afterFrontmatter.length),
    head: doc.head,
    sections: sections,
    links: {for (final place in lineFacts.links) place.target}.toList(),
    lineFacts: lineFacts,
    readBannedMatches: () => bannedMatchesOf(sections, lineFacts, docType),
    readItemFacts: () => itemFacts,
  );
  final indexed = IndexedDoc(
    docPath: docPath,
    docTypeId: docType?.id,
    name: docNameOf(docPath, docType, target: target),
    target: docType != null && docType.isPerTarget
        ? (target ?? codeTarget)
        : null,
    title: doc.title,
    frontmatter: frontmatter,
    tokens: tokenSizeOf(text),
    formatted: laid is Formatted ? laid.text == lfText : null,
    approvalHash: docType == null
        ? null
        : comparedApprovalHash(lfText, docType),
    warnings: warnings,
  );
  return ParsedDoc(indexed, content, contentHashOf(bytes));
}

/// Returns the content of [lfText], a doc of [docType], as far as a reader of
/// its item IDs and blocks reads it: its sections, keyed as
/// [parseIndexedDoc] keys them, and their section and fenced lines.
///
/// No markdown parse, layout, or YAML read runs, so the content holds no
/// links, banned matches, or section counts (see [LineFacts.structureOf]). Its
/// item facts count [lfText] as it is, with no layout.
DocContent docStructureOf(String lfText, MergedDocType? docType) {
  final doc = Doc.parse(lfText);
  final lineFacts = LineFacts.structureOf(lfText: lfText, doc: doc);
  return DocContent(
    readText: () => lfText,
    frontmatterText: doc.frontmatter == null
        ? null
        : lfText.substring(0, lfText.length - doc.afterFrontmatter.length),
    head: doc.head,
    sections: indexedSectionsOf(doc, docType),
    links: const [],
    lineFacts: lineFacts,
    readBannedMatches: () => const [],
    readItemFacts: () => itemFactsOf(
      doc: doc,
      lfText: lfText,
      lineFacts: lineFacts,
      laid: null,
      type: docType,
    ),
  );
}

({String text, bool isUtf8}) _decode(
  List<int> bytes,
  String docPath,
  List<String> warnings,
) {
  try {
    return (text: utf8.decode(bytes), isUtf8: true);
  } on FormatException {
    warnings.add(
      '$docPath: not UTF-8 text; indexed with replacement characters',
    );
    return (text: utf8.decode(bytes, allowMalformed: true), isUtf8: false);
  }
}

/// Returns the counts of each of [sections], in its order.
///
/// A section takes the counts of its laid-out twin; without a layout the
/// counts are those of the text on disk.
List<SectionCounts> _countsOf(
  List<IndexedSection> sections,
  FormatOutcome? laid,
  Map<String, MergedSection> templates,
) {
  if (laid is! Formatted) return [for (final s in sections) sectionCountsOf(s)];
  return [
    for (final twin in laid.twinOf)
      sectionCountsOf(_sectionOf(laid.sections[twin], templates)),
  ];
}

/// Returns the sections of [doc], keyed as [parseIndexedDoc] keys them under
/// [docType].
List<IndexedSection> indexedSectionsOf(Doc doc, MergedDocType? docType) {
  final templates = _templatesByKey(docType);
  return [for (final section in doc.sections) _sectionOf(section, templates)];
}

/// Returns the sections of [docType] by the [headerKey] of their header.
Map<String, MergedSection> _templatesByKey(MergedDocType? docType) => {
  for (final section in docType?.sections ?? const <MergedSection>[])
    headerKey(section.header): section,
};

/// Keys [section] by the template section its header names (rendering INV-5).
IndexedSection _sectionOf(
  Section section,
  Map<String, MergedSection> templates,
) {
  final headerText = section.headerText;
  final template = templates[headerKey(headerText)];
  return IndexedSection(
    key: template?.id ?? sectionKeyOf(headerText),
    headerLine: section.headerLine,
    body: section.body,
  );
}

/// Returns the frontmatter values of [doc] as the index stores them.
///
/// Empty when the frontmatter is absent or is not valid YAML.
Map<String, Object?> frontmatterValuesOf(Doc doc) {
  final blocks = doc.frontmatter;
  final yaml = blocks == null
      ? null
      : parseFrontmatterYaml(blocks.map((b) => b.text).join());
  return _frontmatterValues(yaml, '', []);
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
