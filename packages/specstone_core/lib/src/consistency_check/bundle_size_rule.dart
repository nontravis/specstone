import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/bundle_file.dart'
    show readRangeTokenLimit;
import 'package:specstone_core/src/index_query/bundle_render.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';

/// Returns `bundle_over_limit` for the nesting-type doc [feature] when its
/// design read-first file, or one of its stories', holds more than
/// [readRangeTokenLimit] est. tokens; no finding for any other doc.
///
/// A file is sized as `context --out` writes it, from the Index alone: the
/// feature's with its children in summary, a story's whole; each file also
/// holds the ancestor spec pieces its docs link. The finding names the largest
/// file.
Iterable<Finding> checkBundleSize(
  CheckContext context,
  IndexedDoc feature,
) sync* {
  final index = context.index;
  final nesting = index.set.nestingType;
  if (nesting == null || feature.docTypeId != nesting.id) return;
  final children = index.childrenOf(feature);
  var largest = (
    doc: feature,
    size: _designSizeOf(index, feature, summary: children.isNotEmpty),
  );
  for (final story in children) {
    if (!index.isChainDoc(story) || story.docTypeId == nesting.id) continue;
    final size = _designSizeOf(index, story, summary: false);
    if (size > largest.size) largest = (doc: story, size: size);
  }
  if (largest.size <= readRangeTokenLimit) return;
  final address = index.addressOf(largest.doc);
  yield context.finding(
    feature,
    FindingKind.bundleOverLimit,
    line: 1,
    message:
        'the design read-first file of $address holds '
        '${largest.size} est. tokens; the limit is $readRangeTokenLimit',
    keys: {
      'doc': address,
      'limit': readRangeTokenLimit,
      'actual': largest.size,
    },
  );
}

/// Returns the est. tokens of [doc]'s design read-first file when they pass
/// [readRangeTokenLimit], else 0.
int _designSizeOf(DocIndex index, IndexedDoc doc, {required bool summary}) =>
    readFirstOverLimitOf(
      index,
      pickBundle(
        index,
        [doc.docPath],
        BundleMode.design,
        noProject: false,
        summary: summary,
      ),
    ) ??
    0;
