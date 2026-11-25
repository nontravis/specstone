import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/record_doc.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/models/matrix_line.dart';
import 'package:specstone_core/src/index_query/record_entries.dart';

/// Whether [row] of [record] is a well-formed row of the form the config's
/// mode does not read, naming an FR of the record's feature.
///
/// Every rule that judges a matrix row asks this first, so one answer decides
/// which rows get the form finding alone and no other check, record entry
/// finding, or link state.
bool isRefusedFormRow(CheckContext context, IndexedDoc record, MatrixRow row) {
  if (row.form == context.matrixMode.readsForm) return false;
  final read = recordDocOf(context, record);
  if (read == null) return false;
  final item = recordItemsOf(read.feature, context.index.childrenOf)[row.item];
  return item?.docTypeId == frType;
}
