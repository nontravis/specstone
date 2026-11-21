import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/layer_source.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

/// The est. tokens each shipped guide may print, keyed `<pack>/<doc type>`.
///
/// Recorded by hand, so a guide's growth shows as a row change in the diff.
const _guideTokenRows = <String, int>{
  'agent-skills/agent': 552,
  'agent-skills/skill': 568,
  'marketing/audience': 324,
  'marketing/campaign': 415,
  'marketing/campaign_results': 419,
  'marketing/channel': 376,
  'marketing/competitor': 354,
  'marketing/content_pillars': 309,
  'marketing/lifecycle': 337,
  'marketing/loyalty': 335,
  'marketing/messaging': 386,
  'marketing/positioning': 451,
  'marketing/voice': 323,
  'personal-branding/offer': 295,
  'personal-branding/proof': 386,
  'personal-branding/relationships': 330,
  'personal-branding/story': 341,
  'personal-branding/voice': 355,
  'prd-core/anti_persona': 997,
  'prd-core/feature': 1738,
  'prd-core/features': 468,
  'prd-core/fr': 1868,
  'prd-core/glossary': 342,
  'prd-core/gnfr': 2799,
  'prd-core/goal': 693,
  'prd-core/journey': 638,
  'prd-core/measurement': 687,
  'prd-core/nf': 1162,
  'prd-core/persona': 1654,
  'prd-core/project': 668,
  'prd-core/reference': 496,
  'prd-core/user_story': 1015,
  'software-design-system/accessibility': 263,
  'software-design-system/color': 267,
  'software-design-system/component': 659,
  'software-design-system/component_group': 257,
  'software-design-system/content': 258,
  'software-design-system/contributing': 267,
  'software-design-system/discovery': 306,
  'software-design-system/elevation': 270,
  'software-design-system/guidelines': 351,
  'software-design-system/icon': 279,
  'software-design-system/layout': 271,
  'software-design-system/motion': 299,
  'software-design-system/setup': 280,
  'software-design-system/shape': 272,
  'software-design-system/spacing': 270,
  'software-design-system/theme': 280,
  'software-design-system/tokens': 251,
  'software-design-system/typography': 268,
  'software-design-system/ui_pattern': 303,
  'software-tech/api': 1134,
  'software-tech/architecture': 1468,
  'software-tech/auth': 1176,
  'software-tech/domain': 1282,
  'software-tech/error': 1020,
  'software-tech/implementation': 1160,
  'software-tech/integration': 992,
  'software-tech/project_api': 714,
  'software-tech/project_architecture': 1249,
  'software-tech/project_auth': 1077,
  'software-tech/project_domain': 1212,
  'software-tech/project_error': 928,
  'software-tech/project_integration': 918,
  'software-tech/tech_stack': 848,
  'software-tech/topic': 1050,
};

const _yamlExtension = '.yaml';

/// Maps each shipped pack to the ids of the doc types its own files carry.
Map<String, List<String>> _shippedTypeIds() {
  final ids = <String, List<String>>{};
  for (final key in shippedPackFiles.keys) {
    if (key.split('/') case [final pack, final file]
        when file != packManifestName && file.endsWith(_yamlExtension)) {
      ids
          .putIfAbsent(pack, () => [])
          .add(file.substring(0, file.length - _yamlExtension.length));
    }
  }
  return ids;
}

/// Returns [pack] and every pack it extends, nearest first.
List<String> _chainOf(TemplateResolver resolver, String pack) {
  final chain = <String>[];
  String? next = pack;
  while (next != null) {
    chain.add(next);
    next = resolver.availableManifests([
      next,
    ], homeDirectory: null)[next]!.extendsPack;
  }
  return chain;
}

/// Maps each shipped `<pack>/<doc type>` to the est. tokens of its guide.
///
/// Each guide renders under its pack and that pack's `extends` chain alone.
Map<String, int> _guideTokenCounts(TemplateResolver resolver) {
  final ids = _shippedTypeIds();
  final counts = <String, int>{};
  for (final pack in ids.keys.toList()..sort()) {
    final set = resolver.resolveCarried(
      packNames: _chainOf(resolver, pack),
      homeDirectory: null,
    );
    for (final id in [...?ids[pack]]..sort()) {
      final type = set.lookup(id);
      if (type == null) fail('$pack/$id resolves to no doc type');
      counts['$pack/$id'] = tokenSizeOf(type.renderGuide());
    }
  }
  return counts;
}

void main() {
  late final Map<String, int> counts;

  setUpAll(() => counts = _guideTokenCounts(TemplateResolver()));

  test('no shipped guide is above its recorded token count', () {
    final grown = [
      for (final MapEntry(:key, :value) in counts.entries)
        if (_guideTokenRows[key] case final row? when value > row)
          "'$key': $value, // row $row",
    ];
    expect(grown, isEmpty, reason: grown.join('\n'));
  });

  test('every shipped doc type has a recorded token count', () {
    expect(counts, isNotEmpty);
    final unrecorded = [
      for (final MapEntry(:key, :value) in counts.entries)
        if (!_guideTokenRows.containsKey(key)) "'$key': $value,",
    ];
    expect(unrecorded, isEmpty, reason: unrecorded.join('\n'));
  });
}
