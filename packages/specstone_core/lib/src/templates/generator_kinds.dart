/// The generated-block kinds a doc type may list under `generators`.
///
/// Empty until a kind ships; `TemplateResolver` refuses a listed kind outside
/// the set it is given, which defaults to this one.
const Set<String> shippedGeneratorKinds = {};
