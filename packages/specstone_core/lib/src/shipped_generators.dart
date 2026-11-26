import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/feature_catalog.dart';
import 'package:specstone_core/src/journeys/journey_generators.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:specstone_core/src/templates/component_catalog.dart';
import 'package:specstone_core/src/templates/generator_kinds.dart'
    show groupFeatureCatalogKind;

/// Returns the generators of the shipped doc types: the journey kinds,
/// `feature_catalog` with its group features docs, `group_feature_catalog`, and
/// `component_catalog`.
GeneratorRegistry<DocIndex> shippedGenerators() {
  final journeys = journeyGenerators();
  return GeneratorRegistry<DocIndex>(
    {
      for (final kind in journeys.kinds) kind: journeys[kind]!,
      featureCatalogKind: featureCatalogBlocks,
      groupFeatureCatalogKind: groupFeatureCatalogBlocks,
      componentCatalogKind: componentCatalogBlocks,
    },
    companions: {featureCatalogKind: featureCatalogCompanions},
  );
}
