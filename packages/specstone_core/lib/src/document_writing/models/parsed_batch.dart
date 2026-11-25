import 'package:specstone_core/src/document_writing/batch_fault.dart';
import 'package:specstone_core/src/document_writing/models/batch_block.dart';

/// A batch file's blocks, and the refusals of the lines no block owns.
final class ParsedBatch {
  const new({required this.blocks, required this.lineFaults});

  final List<BatchBlock> blocks;
  final List<BatchEntry> lineFaults;
}
