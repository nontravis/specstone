import 'package:specstone_core/src/consistency_check/models/yaml_entry.dart';
import 'package:specstone_core/src/index_query/models/doc_content.dart';
import 'package:specstone_core/src/index_query/models/frontmatter_yaml.dart';
import 'package:specstone_core/src/index_query/models/label_place.dart';
import 'package:specstone_core/src/index_query/models/line_facts.dart';
import 'package:specstone_core/src/index_query/models/link_place.dart';
import 'package:specstone_core/src/index_query/models/prefixed_label_place.dart';
import 'package:specstone_core/src/index_query/models/section_counts.dart';
import 'package:yaml/yaml.dart';

/// The 1-based file lines of a doc's links, sections, and frontmatter items.
///
/// The line facts come from the index. The lines of text and the frontmatter
/// YAML are read on first use, so a rule that needs neither never pays for
/// them.
final class DocLines {
  new from(this._content);

  final DocContent _content;

  LineFacts get _facts => _content.lineFacts;

  /// The LF lines without their `\n`.
  late final List<String> lines = _lfLinesOf(_content.text);

  /// The lines of the text `format` lays out for a typed doc, else of the LF
  /// text.
  int get lineCount => _facts.lineCount;

  /// The code points of the text `format` lays out for a typed doc, else of
  /// the LF text.
  int get charCount => _facts.charCount;

  /// The doc links that resolve to another `.md` doc, in source order.
  List<LinkPlace> get links => _facts.links;

  /// The relative links that are no doc link, in source order.
  List<LinkPlace> get fileLinks => _facts.fileLinks;

  /// The number labels of the body at their file lines, in source order.
  List<LabelPlace> get numberLabels => _facts.numberLabels;

  /// The capital-prefix label runs of the body at their file lines, in source
  /// order, whatever prefixes the config lists.
  List<PrefixedLabelPlace> get prefixedLabels => _facts.prefixedLabels;

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
    return FrontmatterYaml.parse(text.substring(4, closing - 3)).map;
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

  /// The value of [key] as written: a string as itself, any other value, a
  /// list or a map included, as its source text.
  ///
  /// Null when [key] is absent or holds no value.
  String? writtenValueOf(String key) {
    final node = _keyEntry(key)?.value;
    if (node == null || node.value == null) return null;
    return node is YamlScalar && node.value is String
        ? node.value! as String
        : node.span.text.trimRight();
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
          YamlEntry(
            value: item.value,
            line: _lineOf(item),
            text: item.span.text,
          ),
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

/// Returns the lines of [text] with each `\r\n` turned into `\n`, without
/// their `\n` and with no final empty line.
List<String> _lfLinesOf(String text) {
  final lfText = text.contains('\r') ? text.replaceAll('\r\n', '\n') : text;
  final lines = lfText.isEmpty ? <String>[] : lfText.split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  return lines;
}
