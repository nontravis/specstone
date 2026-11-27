import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart';

/// A registry of no generator: a write given it refreshes no generated block.
final GeneratorRegistry<DocIndex> noGenerators = GeneratorRegistry<DocIndex>(
  {},
);
