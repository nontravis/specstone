import 'dart:convert';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/readability_rules.dart';
import 'package:specstone_core/src/setup_migration/migration_chain.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/models/migration_step.dart';
import 'package:specstone_core/src/templates/pack_manifest.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/shared_entry.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/prd_core.dart';
import '../../helpers/shared_lines.dart';

/// The shared lines `prd-core` ships, by id, in file order.
const _sharedLines = <String, String>{
  'present_truth': 'State the present truth; git holds history.',
  'one_rule_per_item': _oneRuleLine,
  'cite_at_item_end': citeNoteGuideLine,
  'one_example': _exampleLine,
  'condition_first': _conditionLine,
  'cite_by_link': _citeLine,
};

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

const _citeLine =
    'Link to the item of a rule another doc owns; never restate it.';

const _oneRuleLine =
    'Keep one rule per item; put several conditions in a nested list. '
    "Move a one-sentence, no-ID paragraph's detail to the section of this doc "
    'that owns it, never into a sub-list.';

const _exampleLine =
    'Give a non-obvious rule one in-item example: a `such as` clause or one '
    '"For example," sentence, within the sentence cap.';

const _conditionLine =
    'Put the condition before the rule, one clause chain per sentence; '
    'split a sentence whose clauses nest.';

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

/// The readability bar lines the guide prints, in print order.
final List<String> _barLines = [
  for (final MapEntry(:key, :value) in _sharedLines.entries)
    if (readabilityBarSharedLineIds.contains(key)) value,
];

/// The opening clause of each bar line; a section description must not hold
/// it, even without the rest of its line.
final List<String> _barClauses = [
  for (final line in _barLines) line.split(RegExp('[;:,.]')).first,
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
      final upgrade = _upgradeFrom('1.7.0', manifest);
      expect(upgrade.target.toString(), '1.31.0');
    });

    test('the pack lists a mark_retrim entry for fr edge cases and '
        'verification after the strip entry', () {
      final migrations = _prdCoreManifest().migrations;
      expect(migrations.map((e) => e.from.toString()), ['1.7.0', '1.19.0']);
      expect(migrations.first.steps.single, isA<StripSharedCopies>());
      final mark = migrations[1].steps.single as MarkRetrim;
      expect(mark.docTypes, ['fr']);
      expect(mark.sections, ['edge_cases', 'verification']);
      final upgrade = _upgradeFrom('1.7.0', _prdCoreManifest());
      expect(
        [for (final s in upgrade.steps) (s.from.toString(), s.step.kind)],
        [('1.7.0', 'strip_shared_copies'), ('1.19.0', 'mark_retrim')],
      );
    });

    test('a pin past both entries gets the pin change only', () {
      final upgrade = _upgradeFrom('1.19.1', _prdCoreManifest());
      expect(upgrade.target.toString(), '1.31.0');
      expect(upgrade.steps, isEmpty);
    });

    test('prd-core ships its shared lines in order with their reach and no '
        'shared field', () {
      final shared = _prdCoreManifest().shared;
      expect({for (final l in shared.lines) l.id: l.text}, _sharedLines);
      expect(shared.lines.map((l) => l.id), _sharedLines.keys);
      expect(
        {for (final l in shared.lines) l.id: l.forDocTypes},
        {
          for (final id in _sharedLines.keys)
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

    test(
      'no description states the sentence length a lint key holds',
      () async {
        final set = await resolvePrdCore();
        for (final docType in set.docTypes) {
          expect(
            docType.description,
            isNot(contains('Each sentence holds')),
            reason: docType.id,
          );
        }
      },
    );

    test('no description holds a shared line, and each guide prints the '
        'shared lines that reach it', () async {
      final set = await resolvePrdCore();
      for (final docType in set.docTypes) {
        final texts = [
          docType.description,
          for (final field in docType.fields) field.description,
          for (final section in docType.sections) section.description,
        ];
        for (final line in _sharedLines.values) {
          for (final text in texts) {
            expect(text ?? '', isNot(contains(line)), reason: docType.id);
          }
        }
        expect(docType.sharedLines.map((l) => l.id), [
          for (final id in _sharedLines.keys)
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
      for (final docType in set.docTypes) {
        final path = docType.path!
            .replaceAll('{nn}', '07')
            .replaceAll('{slug}', 'probe');
        Future<Set<FindingKind>> kindsOf(String body) async {
          final report = await checkOf(
            await writeCheckProject(
              extra: {'docs/$path': '$draft$body\n'},
              unstamped: {'docs/$path'},
            ),
          );
          return {
            for (final f in report.findings)
              if (f.path == path) f.kind,
          };
        }

        final lines = List.filled(docType.lint.maxLines! + 1, 'x').join('\n');
        final chars = 'x' * (docType.lint.maxChars! + 1);
        expect(
          await kindsOf(lines),
          contains(FindingKind.linesOverLimit),
          reason: '${docType.id} lines',
        );
        expect(
          await kindsOf(chars),
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

    test('a pin at 1.7.0 or 1.9.0 takes steps that change no goal doc', () {
      final manifest = _prdCoreManifest();
      for (final pin in ['1.7.0', '1.9.0']) {
        expect(
          _upgradeFrom(
            pin,
            manifest,
          ).steps.where((s) => s.step.touches('goal')),
          isEmpty,
          reason: pin,
        );
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
        expect(type.description, isNot(contains('Title it')), reason: id);
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

    test('persona, anti_persona, reference, feature, user_story, fr, and nf '
        'descriptions title the doc by its own name', () async {
      final set = await resolvePrdCore();
      final byName = RegExp('Title it `# <[^>]+>`');
      for (final id in [
        'persona',
        'anti_persona',
        'reference',
        'feature',
        'user_story',
        'fr',
        'nf',
      ]) {
        expect(
          byName.hasMatch(prdCoreDocType(set, id).description!),
          isTrue,
          reason: id,
        );
      }
      expect(prdCoreDocType(set, 'fr').description, contains('`# <Name>`'));
      expect(
        prdCoreDocType(set, 'persona').description,
        contains('`# <archetype title>`'),
      );
    });

    test('gnfr, fr, and nf descriptions name the other -ly and -ize word '
        'classes', () async {
      final set = await resolvePrdCore();
      for (final id in ['gnfr', 'fr', 'nf']) {
        expect(
          prdCoreDocType(set, id).description,
          contains('-ly and -ize words beyond the banned list'),
          reason: id,
        );
      }
    });

    test('every other description states one rule per ID and its guide prints '
        'the readability bar', () async {
      final set = await resolvePrdCore();
      final perId = RegExp(r'one rule per (?:`[\w-]+\*` )?ID');
      for (final docType in set.docTypes) {
        if (docType.id == 'fr' || docType.id == 'glossary') continue;
        expect(
          perId.hasMatch(docType.description!),
          isTrue,
          reason: docType.id,
        );
        for (final fragment in _barLines) {
          expect(docType.renderGuide(), contains(fragment), reason: docType.id);
        }
      }
    });

    test('id-less section types state one rule per item under the '
        'readability bar', () async {
      final set = await resolvePrdCore();
      for (final id in [
        'anti_persona',
        'competitor',
        'feature',
        'features',
        'glossary',
        'journey',
        'persona',
        'reference',
      ]) {
        final guide = prdCoreDocType(set, id).renderGuide();
        final rule = guide.indexOf('one rule per item');
        expect(rule, isNonNegative, reason: id);
        for (final fragment in _barLines) {
          expect(
            guide.indexOf(fragment),
            greaterThan(rule),
            reason: '$id $fragment',
          );
        }
      }
    });

    test('every guide says a rule another doc owns is cited by a link, never '
        'restated', () async {
      final set = await resolvePrdCore();
      for (final docType in set.docTypes) {
        expect(
          docType.renderGuide(),
          contains('Link to the item of a rule another doc owns'),
          reason: docType.id,
        );
      }
    });

    test(
      'user story rules line gives the BR id form and asks no id order',
      () async {
        final set = await resolvePrdCore();
        final rules = sectionOf(prdCoreDocType(set, 'user_story'), 'rules');
        expect(rules.description, contains('`**BR-NN** — <rule>`'));
        expect(rules.description, isNot(matches(RegExp('in order|numbered'))));
      },
    );

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
      for (final docType in set.docTypes) {
        expect(
          docType.renderGuide(),
          contains(citeNoteGuideLine),
          reason: docType.id,
        );
      }
    });

    test('every guide prints the readability bar and no section description '
        'holds it', () async {
      final set = await resolvePrdCore();
      for (final docType in set.docTypes) {
        for (final line in _barLines) {
          expect(docType.renderGuide(), contains(line), reason: docType.id);
        }
        for (final clause in _barClauses) {
          for (final section in docType.sections) {
            expect(
              section.description ?? '',
              isNot(contains(clause)),
              reason: '${docType.id} ${section.id}',
            );
          }
        }
      }
    });
  });
}

PackManifest _prdCoreManifest() => PackManifest.parse(
  utf8.decode(shippedPackFiles['prd-core/pack.yaml']!),
  file: 'packs/prd-core/pack.yaml',
);

/// The one upgrade of a project that pins `prd-core` at [pin].
PackUpgrade _upgradeFrom(String pin, PackManifest manifest) => selectUpgrades(
  {'prd-core': PackVersion.parse(pin, file: 'config', key: 'prd-core')},
  {'prd-core': manifest},
).single;
