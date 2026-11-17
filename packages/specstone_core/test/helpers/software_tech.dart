import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';

import 'shipped_pins.dart';
import 'temp_tree.dart';

/// The `software-tech` doc type ids, in code point order (US-07 FR-01).
const softwareTechIds = <String>[
  'api',
  'architecture',
  'auth',
  'domain',
  'error',
  'implementation',
  'integration',
  'project_api',
  'project_architecture',
  'project_auth',
  'project_domain',
  'project_error',
  'project_integration',
  'tech_stack',
  'topic',
];

/// The project spec doc type ids, each with the doc type it extends.
const projectSpecDocBases = <String, String>{
  'project_api': 'api',
  'project_architecture': 'architecture',
  'project_auth': 'auth',
  'project_domain': 'domain',
  'project_error': 'error',
  'project_integration': 'integration',
};

/// Resolves a temp project that pins the shipped `prd-core` and
/// `software-tech`.
///
/// Calls `writeTree`, so call it from a test or `setUpAll`.
Future<MergedSet> resolveSoftwareTech() async {
  final project = await writeTree({
    '.specstone/config.yaml': shippedPinsConfig(),
  });
  final home = await writeTree({});
  return TemplateResolver().resolve(
    workingDirectory: project,
    homeDirectory: home,
  );
}
