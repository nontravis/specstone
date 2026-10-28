import 'dart:convert';

import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/line_facts.dart';
import 'package:specstone_core/src/index_query/link_places.dart';
import 'package:specstone_core/src/index_query/section_counts.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:yaml/yaml.dart';

/// One frontmatter list item or scalar with its source line.
///
/// `text` is the item's source text, its span.
typedef YamlEntry = ({Object? value, int line, String text});

/// The 1-based file lines of a doc's links, sections, and frontmatter items.
///
/// The line facts come from the index. The lines of text and the frontmatter
/// YAML are read on first use, so a rule that needs neither never pays for
/// them.
final class DocLines {
  new from(this._content);

  /// Reads [text], a file's decoded text with any line ends, the way a
  /// refresh stores it.
  ///
  /// The empty docPath resolves no link relative to a folder, so [links] are
  /// those of a doc at the docs root. Only tests call this.
  factory of(String text) => DocLines.from(
    parseIndexedDoc(
      docPath: '',
      bytes: utf8.encode(text),
      match: const NoDocType(),
    ).content,
  );

  final DocContent _content;

  LineFacts get _facts => _content.lineFacts;

  /// The LF lines without their `\n`.
  late final List<String> lines = lfLinesOf(toLf(_content.text));

  /// The number of LF lines.
  int get lineCount => _facts.lineCount;

  /// The code points of the LF text.
  int get charCount => _facts.charCount;

  /// The doc links that resolve to another `.md` doc, in source order.
  List<LinkPlace> get links => _facts.links;

  /// The header line of each section, in the order of `Doc.sections`.
  List<int> get sectionLines => _facts.sectionLines;

  /// The line and code point counts of each section, in the order of
  /// [sectionLines].
  List<SectionCounts> get sectionCounts => _facts.sectionCounts;

  /// The line the YAML parser names, 1 when the frontmatter is no mapping.
  ///
  /// Null when the frontmatter is valid or absent.
  int? get frontmatterErrorLine => _facts.frontmatterErrorLine;

  late final YamlMap? _frontmatter = _parseFrontmatter();

  YamlMap? _parseFrontmatter() {
    final text = _content.frontmatterText;
    if (text == null) return null;
    // Drop the opening `---` line and the closing one.
    final closing = text.endsWith('\n') ? text.length - 1 : text.length;
    return parseFrontmatterYaml(text.substring(4, closing - 3)).map;
  }

  /// Whether file [line] (1-based) is fenced code content or a fence line.
  ///
  /// False for a line the file does not have.
  bool isFenced(int line) => _facts.isFenced(line);

  /// The line of frontmatter [key], or null when it is absent.
  int? keyLine(String key) {
    final entry = _keyEntry(key);
    return entry == null ? null : _lineOf(entry.key);
  }

  /// Each item of the list value of [key], or its one scalar, with lines.
  ///
  /// Empty when [key] is absent. A null value, or a null item, is absent too.
  List<YamlEntry> entriesOf(String key) {
    final value = _keyEntry(key)?.value;
    if (value == null) return const [];
    final items = value is YamlList ? value.nodes : [value];
    return [
      for (final item in items)
        if (item.value != null)
          (value: item.value, line: _lineOf(item), text: item.span.text),
    ];
  }

  MapEntry<YamlNode, YamlNode>? _keyEntry(String key) {
    final frontmatter = _frontmatter;
    if (frontmatter == null) return null;
    for (final entry in frontmatter.nodes.entries) {
      final name = entry.key;
      if (name is YamlNode && name.value == key) {
        return MapEntry(name, entry.value);
      }
    }
    return null;
  }
}

// The frontmatter text starts on file line 2, and YAML lines start at 0.
int _lineOf(YamlNode node) => node.span.start.line + 2;
