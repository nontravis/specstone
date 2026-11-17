/// The generated-block kinds a doc type may list under `generators`.
///
/// `TemplateResolver` refuses a listed kind outside the set it is given, which
/// defaults to this one. `journeyGenerators` registers the two journey kinds
/// and `featureCatalogBlocks` the `feature_catalog` kind.
const Set<String> shippedGeneratorKinds = {
  'journey_flow',
  'scenario_copy',
  'feature_catalog',
};
