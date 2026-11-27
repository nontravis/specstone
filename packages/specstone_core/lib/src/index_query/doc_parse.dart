import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/markdown_body.dart'
    show MarkdownTree, parseMarkdownTreeByBlock;
import 'package:specstone_core/src/doc_model/models/block_scan.dart';
import 'package:specstone_core/src/doc_model/text_scan.dart';
import 'package:specstone_core/src/index_query/line_facts.dart'
    show linesBeforeBodyOf;
import 'package:specstone_core/src/index_query/link_blocks.dart'
    show leafTextOf;
import 'package:specstone_core/src/index_query/link_scan.dart'
    show linkSourcesOfLeaf;
import 'package:specstone_core/src/index_query/models/leaf_text.dart';
import 'package:specstone_core/src/index_query/models/link_source.dart';

/// The frontmatter keys whose blocks mark a doc's approval state.
const _approvalKeys = ['draft', 'approved'];

/// One doc text's parse, each part computed once on first read.
///
/// The body is the text after the frontmatter; its first line is file line
/// [bodyFirstLine].
final class DocParse {
  factory of(String lfText) => DocParse._(lfText, null);

  /// Takes [doc], the [Doc.parse] of [lfText] a caller already holds.
  factory parsed(String lfText, Doc doc) => DocParse._(lfText, doc);

  new _(this.lfText, this._given);

  final String lfText;
  final Doc? _given;

  late final Doc doc = _given ?? Doc.parse(lfText);

  late final int bodyFirstLine = linesBeforeBodyOf(doc, lfText) + 1;

  /// Null when the markdown parser fails on the body.
  late final MarkdownTree? tree = parseMarkdownTreeByBlock(
    doc.afterFrontmatter,
  );

  late final LeafText leafText = leafTextOf(doc.afterFrontmatter);

  late final List<LinkSource> linkSources = linkSourcesOfLeaf(
    doc.afterFrontmatter,
    leafText,
    firstLine: bodyFirstLine,
  );

  /// The [blockScan] of the body's lines, split at each `\n`.
  late final BlockScan lineBlocks = blockScan(doc.afterFrontmatter.split('\n'));

  /// The code points of the first `draft` and the first `approved` key block,
  /// comment lines and line breaks included; 0 with neither.
  late final int approvalMarkChars = _approvalMarkChars();

  /// Counts 0 when the text never writes either key name, so a bare or plainly
  /// quoted key always counts, and a key spelled by YAML escapes counts only
  /// when its name also appears elsewhere in the text.
  int _approvalMarkChars() {
    final blocks = doc.frontmatter;
    if (blocks == null || !_approvalKeys.any(lfText.contains)) return 0;
    var chars = 0;
    for (final key in _approvalKeys) {
      for (final block in blocks) {
        if (block.name != key) continue;
        chars += block.text.length - scanText(block.text).pairs;
        break;
      }
    }
    return chars;
  }
}
