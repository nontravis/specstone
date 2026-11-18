import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/templates/reference_entry.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/marketing.dart';
import '../../helpers/shipped_pins.dart';

const _patternsField =
    'fields:\n  - id: patterns\n    type: string\n    list: true\n';

/// The scope of each shipped campaign pattern, its `description`.
const _scopes = <String, String>{
  'product_launch': 'a launch of a new product or feature to its audience',
  'promotion': 'a time-boxed offer that drives sales',
  'referral': 'a program in which customers bring new customers',
  'retention': 'a program that keeps existing customers buying',
};

/// Each source a pattern may cite, by title.
const _sources = <String, String>{
  'Anthropic marketing plugin, campaign-plan': 'https://raw.githubusercontent.com/anthropics/knowledge-work-plugins/main/marketing/skills/campaign-plan/SKILL.md',
  'marketingskills, product-marketing': 'https://raw.githubusercontent.com/coreyhaines31/marketingskills/main/skills/product-marketing/SKILL.md',
  'HubSpot, GTM strategy': 'https://blog.hubspot.com/sales/gtm-strategy',
  'Amplitude, AARRR pirate metrics':
      'https://amplitude.com/blog/pirate-metrics-framework',
  'Ortto, Marketing funnel explained':
      'https://ortto.com/learn/marketing-funnel-explained/',
  'Extole, Reward brand advocates': 'https://www.extole.com/blog/how-to-reward-brand-advocates-effectively-rewards-tiers-and-community-programs/',
};

const _maxItemChars = 160;
const _minItems = 5;
const _maxItems = 15;

final List<String> _patternIds = _scopes.keys.toList();

YamlMap _fileOf(String id) {
  final bytes = shippedPackFiles['marketing/patterns/$id.yaml'];
  expect(bytes, isNotNull, reason: id);
  return loadYaml(utf8.decode(bytes!)) as YamlMap;
}

void main() {
  test('the pack holds exactly the four pattern files, none with extends', () {
    final files =
        shippedPackFiles.keys
            .where((k) => k.startsWith('marketing/patterns/'))
            .toList()
          ..sort();
    expect(files, [
      for (final id in _patternIds) 'marketing/patterns/$id.yaml',
    ]);
    for (final id in _patternIds) {
      expect(_fileOf(id)['id'], id, reason: id);
      expect(_fileOf(id).containsKey('extends'), isFalse, reason: id);
    }
  });

  group('each pattern', () {
    for (final MapEntry(key: id, value: scope) in _scopes.entries) {
      test('$id carries its scope, 5 to 15 one-sentence items, and sources '
          'from the table', () {
        final file = _fileOf(id);
        expect(file['description'], scope);

        final items = (file['items'] as YamlList).cast<YamlMap>();
        expect(items.length, inInclusiveRange(_minItems, _maxItems));
        for (final item in items) {
          final text = item['text'] as String;
          final reason = '${item['id']}: $text';
          expect(text.length, lessThanOrEqualTo(_maxItemChars), reason: reason);
          expect(text, matches(RegExp(r'^[A-Z][^.!?]*\.$')), reason: reason);
        }

        final reference = (file['reference'] as YamlList).cast<YamlMap>();
        expect(reference, isNotEmpty);
        for (final entry in reference) {
          expect(_sources[entry['title']], entry['url'], reason: '$entry');
        }
      });
    }
  });

  group('merged set', () {
    test('lists the four ids for prd-core and marketing, all fourteen with '
        'software-tech, and none for prd-core alone', () async {
      final marketing = await resolveMarketing();
      expect(marketing.featurePatterns.map((p) => p.id), _patternIds);
      expect(
        marketing.featurePatterns.map((p) => p.pack),
        everyElement('marketing'),
      );

      final both = await resolveMarketing([
        'prd-core',
        'software-tech',
        'marketing',
      ]);
      final ids = both.featurePatterns.map((p) => p.id).toList();
      expect(ids, hasLength(14));
      expect(ids, (List.of(ids)..sort()));
      expect(ids, containsAll(_patternIds));

      final core = await resolveMarketing(['prd-core']);
      expect(
        core.featurePatterns.map((p) => p.id),
        isNot(anyElement(isIn(_patternIds))),
      );
    });

    test(
      'each pattern prints its items, then its Pattern sources lines',
      () async {
        final set = await resolveMarketing();
        for (final id in _patternIds) {
          final pattern = set.featurePattern(id)!;
          final lines = pattern.renderBody().trimRight().split('\n');
          final sources = lines.indexOf('Pattern sources:');
          expect(sources, greaterThan(0), reason: id);
          expect(
            lines.sublist(1, sources),
            everyElement(startsWith('- **')),
            reason: id,
          );
          expect(
            lines.sublist(sources + 1),
            pattern.reference.map(referenceSourceLine),
            reason: id,
          );
        }
      },
    );
  });

  test('a feature that names product_launch resolves only where marketing is '
      'listed', () async {
    Future<List<String>> missing(List<String> packs) async {
      final project = await writeCheckProject(
        extra: {
          '.specstone/config.yaml': shippedPinsConfig(packs),
          '.specstone/templates/feature.yaml': _patternsField,
          ...edit(loginFeature, [
            (
              'goals:\n  - PG-01\n',
              'goals:\n  - PG-01\npatterns:\n  - product_launch\n',
            ),
          ]),
        },
      );
      return spots(await checkOf(project), FindingKind.featurePatternMissing);
    }

    expect(await missing(['prd-core', 'software-tech', 'marketing']), isEmpty);
    expect(await missing(['prd-core', 'software-tech']), isNotEmpty);
  });

  test('a feature that names product_launch resolves in a project of prd-core '
      'and marketing alone', () async {
    final project = await writeCheckProject(
      extra: {
        '.specstone/config.yaml': shippedPinsConfig(['prd-core', 'marketing']),
        '.specstone/templates/feature.yaml': _patternsField,
        ...edit(loginFeature, [
          (
            'goals:\n  - PG-01\n',
            'goals:\n  - PG-01\npatterns:\n  - product_launch\n',
          ),
        ]),
      },
    );
    final report = await checkOf(project);

    expect(
      spots(report, FindingKind.featurePatternMissing),
      isEmpty,
      reason: spots(report).join('\n'),
    );
    expect(
      File('${project.path}/docs/$loginFeature').readAsStringSync(),
      contains('  - product_launch\n'),
    );
  });
}
