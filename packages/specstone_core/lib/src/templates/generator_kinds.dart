/// The generator kind of the one doc type that writes the group features docs.
const groupFeatureCatalogKind = 'group_feature_catalog';

/// The generated-block kinds a doc type may list under `generators`.
///
/// `TemplateResolver` refuses a listed kind outside the set it is given, which
/// defaults to this one. `journeyGenerators` registers the two journey kinds,
/// `featureCatalogBlocks` the `feature_catalog` kind,
/// `groupFeatureCatalogBlocks` the `group_feature_catalog` kind, and
/// `componentCatalogBlocks` the `component_catalog` kind.
const Set<String> shippedGeneratorKinds = {
  'journey_flow',
  'scenario_copy',
  'feature_catalog',
  groupFeatureCatalogKind,
  'component_catalog',
};
