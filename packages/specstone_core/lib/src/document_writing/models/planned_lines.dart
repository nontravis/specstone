import 'package:specstone_core/src/document_writing/models/text_edit.dart';

/// The `planned` lines one write adds to one record: the record's DocPath, the
/// items they name relative to its feature, and the edit that adds them.
final class PlannedLines {
  const new({required this.docPath, required this.items, required this.edit});

  final String docPath;
  final List<String> items;
  final TextEdit edit;
}
