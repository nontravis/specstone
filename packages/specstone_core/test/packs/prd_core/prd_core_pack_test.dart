import 'dart:convert';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/pack_manifest.dart';
import 'package:specstone_core/src/templates/shared_entry.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/prd_core.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/temp_tree.dart';

/// The shared line ids `prd-core` ships, in file order.
const _sharedLineIds = [
  'present_truth',
  'one_rule_per_item',
  'cite_at_item_end',
  'one_example',
  'condition_first',
  'cite_by_link',
];

/// The doc types the `present_truth` line reaches: those whose lint holds
/// `history` at doc level, which leaves `measurement` out, since its Results
/// section is a log.
const _presentTruthIds = [
  'anti_persona',
  'competitor',
  'feature',
  'features',
  'fr',
  'glossary',
  'gnfr',
  'goal',
  'journey',
  'nf',
  'persona',
  'project',
  'user_story',
];

/// The nine `gnfr` category sections.
const _gnfrCategories = [
  'performance',
  'security',
  'reliability',
  'maintainability',
  'interface',
  'environment',
  'safety',
  'operability',
  'design_standards',
];

/// The `gnfr` sections whose `trace_outside_field` copies read one pattern;
/// `interface` and `design_standards` keep a narrower local one.
const _gnfrFullTraceSections = [
  'performance',
  'security',
  'reliability',
  'maintainability',
  'environment',
  'safety',
  'operability',
];

/// Where one shared pattern reaches.
final class _Reach {
  const new(this.kind, this.forDocTypes, [this.sections]);

  final SharedPatternKind kind;
  final List<String> forDocTypes;

  /// The section ids, or null for the doc-level list.
  final List<String>? sections;
}

/// The shared patterns `prd-core` declares, by id in file order.
const _sharedPatterns = <String, _Reach>{
  'code_identifier': _Reach(SharedPatternKind.banned, [
    'feature',
    'user_story',
  ]),
  'error_code': _Reach(SharedPatternKind.banned, ['feature', 'user_story']),
  'doc_citation': _Reach(SharedPatternKind.banned, [
    'anti_persona',
    'competitor',
    'feature',
    'features',
    'fr',
    'glossary',
    'gnfr',
    'goal',
    'journey',
    'measurement',
    'nf',
    'persona',
    'project',
    'user_story',
  ]),
  'history': _Reach(SharedPatternKind.banned, _presentTruthIds),
  'metric_number': _Reach(
    SharedPatternKind.banned,
    ['goal'],
    ['long_term', 'mid_term', 'short_term'],
  ),
  'second_shall': _Reach(
    SharedPatternKind.banned,
    ['gnfr', 'nf'],
    [..._gnfrCategories, 'statement'],
  ),
  'statement_number': _Reach(
    SharedPatternKind.banned,
    ['gnfr', 'nf'],
    [..._gnfrCategories, 'statement'],
  ),
  'trace_outside_field': _Reach(SharedPatternKind.banned, [
    'gnfr',
  ], _gnfrFullTraceSections),
  'by_line': _Reach(
    SharedPatternKind.required,
    ['goal'],
    ['mid_term', 'short_term'],
  ),
  'level_line': _Reach(
    SharedPatternKind.required,
    ['fr', 'nf'],
    ['verification'],
  ),
};

/// The doc types whose guide holds a banned word list at neither level.
const _noWordListIds = [
  'project',
  'features',
  'persona',
  'anti_persona',
  'reference',
  'feature',
  'user_story',
  'journey',
  'measurement',
  'goal',
  'glossary',
];

/// The doc types that carry no `reference:` entry.
const _noReferenceIds = [
  'project',
  'features',
  'reference',
  'journey',
  'measurement',
  'goal',
  'glossary',
];

void main() {
  group('prd-core manifest', () {
    test('prd-core ships at its current minor with no extends', () {
      final bytes = shippedPackFiles['prd-core/pack.yaml'];
      expect(bytes, isNotNull);
      final manifest = PackManifest.parse(
        utf8.decode(bytes!),
        file: 'packs/prd-core/pack.yaml',
      );
      expect(manifest.name, 'prd-core');
      expect(manifest.version.toString(), '1.31.0');
      expect(manifest.extendsPack, isNull);
    });

    test('prd-core ships no migration entry and no migrations key', () {
      expect(_prdCoreManifest().migrations, isEmpty);
      final text = utf8.decode(shippedPackFiles['prd-core/pack.yaml']!);
      expect(text, isNot(contains('migrations:')));
    });

    test(
      'a prd-core pin one minor below its floor is pack_pin_below_floor',
      () async {
        final project = await writeTree({
          '.specstone/config.yaml': shippedPinsBelowFloor(),
        });
        final home = await writeTree({});

        expect(
          () => TemplateResolver().resolve(
            workingDirectory: project,
            homeDirectory: home,
          ),
          throwsA(
            isA<TemplateFault>().having(
              (f) => f.code,
              'code',
              FaultCode.packPinBelowFloor,
            ),
          ),
        );
      },
    );

    test('prd-core ships its shared lines in order with their reach and no '
        'shared field', () {
      final shared = _prdCoreManifest().shared;
      expect(shared.lines.map((l) => l.id), _sharedLineIds);
      expect(
        {for (final l in shared.lines) l.id: l.forDocTypes},
        {
          for (final id in _sharedLineIds)
            id: id == 'present_truth' ? _presentTruthIds : null,
        },
      );
      expect(shared.fields, isEmpty);
    });

    test('the present_truth entry reaches thirteen doc types, measurement '
        'not among them', () {
      final line = _prdCoreManifest().shared.lines.singleWhere(
        (l) => l.id == 'present_truth',
      );

      expect(line.forDocTypes, hasLength(13));
      expect(line.forDocTypes, isNot(contains('measurement')));
    });

    test('prd-core shares each copied pattern once, where its copies sat', () {
      final patterns = _prdCoreManifest().shared.patterns;
      expect(patterns.map((p) => p.id), _sharedPatterns.keys);
      for (final pattern in patterns) {
        final reach = _sharedPatterns[pattern.id]!;
        expect(pattern.kind, reach.kind, reason: pattern.id);
        expect(pattern.forDocTypes, reach.forDocTypes, reason: pattern.id);
        expect(pattern.sections, reach.sections, reason: pattern.id);
      }
    });

    test('no prd-core doc type file repeats a shared pattern it reaches', () {
      for (final pattern in _prdCoreManifest().shared.patterns) {
        final listKey = switch (pattern.kind) {
          SharedPatternKind.banned => 'banned_patterns',
          SharedPatternKind.required => 'required_patterns',
        };
        for (final docTypeId in pattern.forDocTypes!) {
          final file = loadYaml(
            utf8.decode(shippedPackFiles['prd-core/$docTypeId.yaml']!),
          ) as YamlMap;
          final sections = pattern.sections;
          final lints = sections == null
              ? [file['lint'] as YamlMap?]
              : [
                  for (final node in (file['sections'] as YamlList).nodes)
                    if (sections.contains((node as YamlMap)['id']))
                      node['lint'] as YamlMap?,
                ];
          for (final lint in lints) {
            final entries = (lint?[listKey] as YamlList?) ?? YamlList();
            expect(
              [for (final e in entries) (e as YamlMap)['id']],
              isNot(contains(pattern.id)),
              reason: '$docTypeId ${pattern.id}',
            );
          }
        }
      }
    });

    test('no prd-core shared line names another shared line', () {
      final lines = _prdCoreManifest().shared.lines;
      for (final line in lines) {
        for (final other in lines) {
          if (other.id == line.id) continue;
          expect(line.text, isNot(contains(other.id)), reason: line.id);
          expect(line.text, isNot(contains(other.text)), reason: line.id);
        }
      }
    });

    test('a project pinning the shipped prd-core resolves with '
        'no fault', () async {
      final set = await resolvePrdCore();
      expect(set.docTypes.every((d) => d.pack == 'prd-core'), isTrue);
    });
  });

  group('listedWordsIn', () {
    test('finds whole words and phrases in any case', () {
      expect(listedWordsIn('This is Fast, etc. and/or Light-Weight.'), [
        'fast',
        'light-weight',
        'this',
        'etc.',
        'and/or',
      ]);
      expect(listedWordsIn('When required, but not limited to X'), [
        'when required',
        'but not limited to',
      ]);
    });

    test('a listed word inside a longer word is no hit', () {
      expect(
        listedWordsIn('Safety, usability, smaller, fastest, retcon'),
        isEmpty,
      );
    });
  });

  group('prd-core doc types', () {
    test('every doc type titles with no number, so each sets '
        'lint.title_no_number', () async {
      final set = await resolvePrdCore();

      expect(prdCoreIds, hasLength(15));
      for (final id in prdCoreIds) {
        expect(prdCoreDocType(set, id).lint.titleNoNumber, isTrue, reason: id);
      }
    });

    test('each section the pack file gives a template keeps it, and no '
        'description holds a YAML key', () async {
      final set = await resolvePrdCore();
      final blockKey = RegExp(r'\b[a-z_]+: \|');
      for (final docType in set.docTypes) {
        final file = loadYaml(
          utf8.decode(shippedPackFiles['prd-core/${docType.id}.yaml']!),
        ) as YamlMap;
        final sections = (file['sections'] as YamlList?)?.nodes ?? [];
        for (final node in sections) {
          final raw = node as YamlMap;
          if (!raw.containsKey('template')) continue;
          final id = raw['id'] as String;
          expect(
            sectionOf(docType, id).template,
            isNotNull,
            reason: '${docType.id} $id',
          );
        }
        final texts = [
          docType.description,
          for (final field in docType.fields) field.description,
          for (final section in docType.sections) section.description,
        ];
        for (final text in texts) {
          expect(text ?? '', isNot(contains(blockKey)), reason: docType.id);
        }
      }
    });

    test('only project, glossary, gnfr, and goal set bundle_refs', () async {
      final set = await resolvePrdCore();
      expect(
        {
          for (final d in set.docTypes)
            if (d.bundleRefs == true) d.id,
        },
        {'project', 'glossary', 'gnfr', 'goal'},
      );
    });

    test('a project listing only prd-core '
        'holds exactly the fifteen doc types', () async {
      final set = await resolvePrdCore();
      expect(set.docTypes.map((d) => d.id), prdCoreIds);
      expect(set.docTypes.map((d) => d.pack), everyElement('prd-core'));
    });

    test('only the feature summary field carries a lint', () async {
      final set = await resolvePrdCore();
      expect(
        [
          for (final d in set.docTypes)
            for (final f in d.fields)
              if (f.lint != null) '${d.id}.${f.id}',
        ],
        ['feature.summary'],
      );
    });

    test('no description holds a shared line, and each guide prints the '
        'shared lines that reach it', () async {
      final set = await resolvePrdCore();
      for (final docType in set.docTypes) {
        expect(docType.sharedLines.map((l) => l.id), [
          for (final id in _sharedLineIds)
            if (id != 'present_truth' || _presentTruthIds.contains(docType.id))
              id,
        ], reason: docType.id);
      }
    });

    test('each doc type flags a doc over its own line and character '
        'caps', () async {
      final set = await resolvePrdCore();
      // A draft takes no approval stamp, so the counts stay exact.
      const draft = '---\ndraft: true\n---\n\n# Probe\n\n';
      String pathOf(MergedDocType docType) =>
          docType.path!.replaceAll('{nn}', '07').replaceAll('{slug}', 'probe');
      // One project holds every doc type's probe, so each body checks once.
      Future<Map<String, Set<FindingKind>>> kindsByPath(
        String Function(MergedDocType) bodyOf,
      ) async {
        final paths = {for (final t in set.docTypes) t.id: pathOf(t)};
        final report = await checkOf(
          await writeCheckProject(
            extra: {
              for (final t in set.docTypes)
                'docs/${paths[t.id]}': '$draft${bodyOf(t)}\n',
            },
            unstamped: {for (final p in paths.values) 'docs/$p'},
          ),
        );
        return {
          for (final p in paths.values)
            p: {
              for (final f in report.findings)
                if (f.path == p) f.kind,
            },
        };
      }

      final overLines = await kindsByPath(
        (t) => List.filled(t.lint.maxLines! + 1, 'x').join('\n'),
      );
      final overChars = await kindsByPath((t) => 'x' * (t.lint.maxChars! + 1));
      for (final docType in set.docTypes) {
        expect(
          overLines[pathOf(docType)],
          contains(FindingKind.linesOverLimit),
          reason: '${docType.id} lines',
        );
        expect(
          overChars[pathOf(docType)],
          contains(FindingKind.charsOverLimit),
          reason: '${docType.id} chars',
        );
      }
    });

    test('a project that groups features overrides the '
        'four paths in its layer', () async {
      const story = 'prds/features/{slug}/f{nn}_{slug}/us{nn}_{slug}';
      final set = await resolvePrdCore(
        templates: {
          'feature.yaml':
              'path: prds/features/{slug}/f{nn}_{slug}/FEATURE.md\n',
          'user_story.yaml': 'path: $story/USER_STORY.md\n',
          'fr.yaml': 'path: $story/fr{nn}_{slug}.md\n',
          'nf.yaml': 'path: $story/nf{nn}_{slug}.md\n',
        },
      );
      expect(
        set.lookup('feature')!.path,
        'prds/features/{slug}/f{nn}_{slug}/FEATURE.md',
      );
      expect(set.lookup('user_story')!.path, '$story/USER_STORY.md');
      expect(set.lookup('fr')!.path, '$story/fr{nn}_{slug}.md');
      expect(set.lookup('nf')!.path, '$story/nf{nn}_{slug}.md');
      expect(set.lookup('fr')!.parent, 'user_story');
    });

    test('a project adds Availability to gnfr as a project '
        'section', () async {
      final set = await resolvePrdCore(
        templates: {
          'gnfr.yaml':
              'sections:\n'
              '  - id: availability\n'
              '    header: Availability\n'
              '    prefix_id: NFR-A\n'
              '    required: true\n'
              '    after: reliability\n',
        },
      );
      final gnfr = set.lookup('gnfr')!;
      expect(gnfr.sections.map((s) => s.id).take(5), [
        'performance',
        'security',
        'reliability',
        'availability',
        'maintainability',
      ]);
      expect(sectionOf(gnfr, 'availability').prefixId, 'NFR-A');
    });

    test('a project changes the fr '
        'Statement list with add and remove', () async {
      final set = await resolvePrdCore(
        templates: {
          'fr.yaml':
              'sections:\n  - id: statement\n    lint:\n      banned_words:\n'
              '        add: [simply]\n        remove: [etc.]\n',
        },
      );
      expect(sectionOf(set.lookup('fr')!, 'statement').bannedWords, [
        ...nasaBannedWords.where((w) => w != 'etc.'),
        'simply',
      ]);
      expect(set.lookup('fr')!.lint.bannedWords, isNull);
    });

    test('a plain Statement list over the shipped one is '
        'list_override_needs_add_remove', () async {
      await expectLater(
        resolvePrdCore(
          templates: {
            'fr.yaml':
                'sections:\n  - id: statement\n    lint:\n'
                '      banned_words: [simply]\n',
          },
        ),
        throwsA(
          isA<TemplateFault>().having(
            (f) => f.code,
            'code',
            FaultCode.listOverrideNeedsAddRemove,
          ),
        ),
      );
    });

    test('a project writes its own doc-level list plain', () async {
      final set = await resolvePrdCore(
        templates: {'fr.yaml': 'lint:\n  banned_words: [simply]\n'},
      );
      expect(set.lookup('fr')!.lint.bannedWords, ['simply']);
    });
  });

  group('expectOwnFields', () {
    test('fails when an enum field lists other values', () async {
      final anti = prdCoreDocType(await resolvePrdCore(), 'anti_persona');
      expect(
        () => expectOwnFields(anti, const [
          FieldSpec(
            'anti_type',
            FieldType.enumType,
            required: true,
            enumValues: ['misuser', 'other'],
          ),
          FieldSpec(
            'basis',
            FieldType.enumType,
            required: true,
            enumValues: ['proto', 'qualitative', 'statistical'],
          ),
          FieldSpec('reviewed', FieldType.date),
        ]),
        throwsA(isA<TestFailure>()),
      );
    });

    test('fails when a docRef field names other doc types', () async {
      final feature = prdCoreDocType(await resolvePrdCore(), 'feature');
      expect(
        () => expectOwnFields(feature, const [
          FieldSpec('vision', FieldType.string, list: true),
          FieldSpec('goals', FieldType.string, list: true),
          FieldSpec(
            'persona',
            FieldType.docRef,
            list: true,
            docTypes: ['anti_persona'],
          ),
          FieldSpec('system', FieldType.string),
          FieldSpec(
            'depends_on',
            FieldType.docRef,
            list: true,
            docTypes: ['feature'],
          ),
        ]),
        throwsA(isA<TestFailure>()),
      );
    });
  });

  group('prd-core shared lint and sources', () {
    test('eleven doc types carry no banned word list at either level and '
        'seven carry no reference entry', () async {
      final set = await resolvePrdCore();
      for (final id in _noWordListIds) {
        final docType = prdCoreDocType(set, id);
        expect(docType.lint.bannedWords, isNull, reason: id);
        for (final section in docType.sections) {
          expect(section.bannedWords, isNull, reason: '$id ${section.id}');
        }
      }
      for (final id in _noReferenceIds) {
        expect(prdCoreDocType(set, id).reference ?? [], isEmpty, reason: id);
      }
    });

    test('the built-in reference field of every doc type carries no '
        'doc_types limit', () async {
      final set = await resolvePrdCore();
      for (final docType in set.docTypes) {
        expect(
          fieldOf(docType, 'reference').docTypes,
          isNull,
          reason: docType.id,
        );
      }
    });
  });

  group('prd-core pack contents', () {
    test('a project adds its own project-level doc type and the pack '
        'defines no generic one', () async {
      final set = await resolvePrdCore(
        templates: {
          'runbook.yaml':
              'id: runbook\ndescription: A runbook.\n'
              'path: prds/runbooks/{slug}/RUNBOOK.md\n'
              'sections:\n  - id: steps\n    header: Steps\n',
        },
      );
      expect(set.lookup('runbook'), isNotNull);
      for (final generic in ['document', 'doc', 'note', 'spec']) {
        expect(set.lookup(generic), isNull, reason: generic);
      }
    });

    test('the shipped gnfr categories keep their prefix ids after a project '
        'adds one', () async {
      final shipped = prdCoreDocType(await resolvePrdCore(), 'gnfr');
      final added = prdCoreDocType(
        await resolvePrdCore(
          templates: {
            'gnfr.yaml':
                'sections:\n  - id: availability\n    header: Availability\n'
                '    prefix_id: NFR-A\n    after: reliability\n',
          },
        ),
        'gnfr',
      );
      for (final section in shipped.sections) {
        expect(sectionOf(added, section.id).prefixId, section.prefixId);
      }
    });
  });

  group('prd-core writing guides', () {
    test('project, goal, glossary, features, and gnfr hold their fixed '
        'titles in the title key, and their descriptions state none', () async {
      final set = await resolvePrdCore();
      const titles = {
        'project': 'Project context',
        'goal': 'Project goals',
        'glossary': 'Domain glossary',
        'features': 'Feature map',
        'gnfr': 'Project-wide non-functional requirements',
      };
      for (final MapEntry(key: id, value: title) in titles.entries) {
        final type = prdCoreDocType(set, id);
        expect(type.title, title, reason: id);
      }
    });

    test('persona, anti_persona, reference, feature, user_story, fr, and nf '
        'set no title key', () async {
      final set = await resolvePrdCore();
      for (final id in [
        'persona',
        'anti_persona',
        'reference',
        'feature',
        'user_story',
        'fr',
        'nf',
      ]) {
        expect(prdCoreDocType(set, id).title, isNull, reason: id);
      }
    });

    test('every guide line a shared-lint finding message names is printed in '
        'the guide of the doc type it lints', () async {
      final set = await resolvePrdCore();
      const marker = 'guide line: ';
      final named = <String>[];
      for (final docType in set.docTypes) {
        final guide = docType.renderGuide();
        for (final section in docType.sections) {
          for (final pattern
              in section.bannedPatterns ?? const <PatternEntry>[]) {
            final at = pattern.message.indexOf(marker);
            if (at < 0) continue;
            final line = pattern.message.substring(at + marker.length);
            named.add('${docType.id}.${section.id} ${pattern.id}');
            expect(guide, contains(line), reason: named.last);
          }
        }
      }
      expect(named, contains('fr.statement second_shall'));
      expect(named, contains('fr.verification test_file_named'));
    });
  });
}

PackManifest _prdCoreManifest() => PackManifest.parse(
  utf8.decode(shippedPackFiles['prd-core/pack.yaml']!),
  file: 'packs/prd-core/pack.yaml',
);
