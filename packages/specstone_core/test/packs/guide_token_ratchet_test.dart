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
  'agent-skills/agent': 517,
  'agent-skills/skill': 536,
  'marketing/audience': 257,
  'marketing/campaign': 348,
  'marketing/campaign_results': 349,
  'marketing/channel': 309,
  'marketing/competitor': 776,
  'marketing/content_pillars': 243,
  'marketing/lifecycle': 268,
  'marketing/loyalty': 266,
  'marketing/messaging': 326,
  'marketing/positioning': 381,
  'marketing/voice': 264,
  'personal-branding/offer': 240,
  'personal-branding/proof': 294,
  'personal-branding/relationships': 266,
  'personal-branding/story': 264,
  'personal-branding/voice': 293,
  'prd-core/anti_persona': 865,
  'prd-core/competitor': 758,
  'prd-core/feature': 1487,
  'prd-core/features': 559,
  'prd-core/fr': 1816,
  'prd-core/glossary': 302,
  'prd-core/gnfr': 2666,
  'prd-core/goal': 644,
  'prd-core/journey': 593,
  'prd-core/measurement': 668,
  'prd-core/nf': 1061,
  'prd-core/persona': 1400,
  'prd-core/project': 581,
  'prd-core/reference': 458,
  'prd-core/user_story': 857,
  'software-design-system/accessibility': 235,
  'software-design-system/color': 240,
  'software-design-system/component': 623,
  'software-design-system/component_group': 236,
  'software-design-system/content': 230,
  'software-design-system/contributing': 230,
  'software-design-system/discovery': 277,
  'software-design-system/elevation': 243,
  'software-design-system/guidelines': 321,
  'software-design-system/icon': 247,
  'software-design-system/layout': 241,
  'software-design-system/motion': 269,
  'software-design-system/setup': 252,
  'software-design-system/shape': 245,
  'software-design-system/spacing': 243,
  'software-design-system/theme': 251,
  'software-design-system/tokens': 224,
  'software-design-system/typography': 241,
  'software-design-system/ui_pattern': 277,
  'software-tech/api': 1857,
  'software-tech/architecture': 1391,
  'software-tech/decision': 528,
  'software-tech/implementation': 1159,
  'software-tech/integration': 801,
  'software-tech/project_api': 804,
  'software-tech/project_architecture': 1635,
  'software-tech/project_security': 697,
  'software-tech/security': 775,
  'software-tech/tech_stack': 693,
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
