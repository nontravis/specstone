/// The generated-block kinds a doc type may list under `generators`.
///
/// `TemplateResolver` refuses a listed kind outside the set it is given, which
/// defaults to this one. `journeyGenerators` registers exactly these kinds.
const Set<String> shippedGeneratorKinds = {'journey_flow', 'scenario_copy'};
