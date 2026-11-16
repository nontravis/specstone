import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/bundle_render.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';

/// The most est. tokens a design read-first file may hold.
///
/// Est. tokens are characters / 4; about 3.2 characters make one real token in
/// markdown with paths and code, so 20,000 est. tokens is about one
/// 25,000-token file read.
const bundleTokenLimit = 20000;

/// Returns `bundle_over_limit` for the nesting-type doc [feature] when its
/// design read-first file, or one of its stories', holds more than
/// [bundleTokenLimit] est. tokens; no finding for any other doc.
///
/// A file is sized as `context --out` writes it, from the Index alone: the
/// feature's with its children in summary, a story's whole. The finding names
/// the largest file.
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
  if (largest.size <= bundleTokenLimit) return;
  yield context.finding(
    feature,
    FindingKind.bundleOverLimit,
    line: 1,
    message:
        'the design read-first file of ${largest.doc.name} holds '
        '${largest.size} est. tokens; the limit is $bundleTokenLimit',
    keys: {
      'doc': largest.doc.name,
      'limit': bundleTokenLimit,
      'actual': largest.size,
    },
  );
}

int _designSizeOf(DocIndex index, IndexedDoc doc, {required bool summary}) =>
    readFirstTokensOf(
      index,
      pickBundle(
        index,
        doc.name,
        BundleMode.design,
        noProject: false,
        summary: summary,
      ),
    );
