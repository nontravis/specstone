import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';

/// Returns the `format_drift` finding of [doc] when its text differs from
/// what `specstone format` writes for it.
///
/// An untyped doc and a doc the format command refuses hold no flag, so they
/// raise none.
Iterable<Finding> checkFormatDrift(CheckContext context, IndexedDoc doc) sync* {
  if (doc.formatted != false) return;
  yield context.finding(
    doc,
    FindingKind.formatDrift,
    line: 1,
    message:
        'the file differs from what `specstone format` writes; run '
        '`specstone format $docsFolderName/${doc.docPath}`',
  );
}
