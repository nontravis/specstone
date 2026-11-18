import 'package:specstone_core/src/templates/merged_set.dart';

import 'marketing.dart';

/// The `personal-branding` doc type ids, in code point order.
const personalBrandingIds = <String>[
  'offer',
  'proof',
  'relationships',
  'story',
];

/// The packs of a project that writes personal-brand docs.
const personalBrandingPacks = <String>[
  'prd-core',
  'marketing',
  'personal-branding',
];

/// Resolves a temp project that pins the shipped [packs].
///
/// Calls `writeTree`, so call it from a test or `setUpAll`.
Future<MergedSet> resolvePersonalBranding([
  List<String> packs = personalBrandingPacks,
]) => resolveMarketing(packs);
