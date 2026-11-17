import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/index_query/cite_candidates.dart';
import 'package:specstone_core/src/index_query/cite_resolution.dart';
import 'package:specstone_core/src/index_query/item_words.dart'
    show itemIdPrefixesOf;
import 'package:specstone_core/src/setup_migration/cite_pass.dart';
import 'package:specstone_core/src/setup_migration/migration_chain.dart';
import 'package:specstone_core/src/setup_migration/project_files.dart'
    show parseOverrides, singularLayoutPathsOf;
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart' show checkOf, writeCheckProject;
import '../../helpers/index_fixture.dart';

const _feature = 'prds/features/f01_login/FEATURE.md';
const _domain = 'specs/f01_login/DOMAIN.md';
const _topic = 'specs/topics/doc_model.md';
const _citing = 'specs/f02_signup/ARCHITECTURE.md';

/// The docs every case resolves against: the login feature, its domain doc
/// holding INV-6 and INV-7, and a topic holding RULE-14 and RULE-19.
const Map<String, String> _baseDocs = {
  _feature: '# Login\n\n## Problem\n\nSlow sign-in.\n',
  _domain:
      '# Login domain\n\n## Invariants\n\n'
      '- **INV-6** An account holds one email.\n'
      '- **INV-7** An email names one account.\n',
  _topic: '# Doc model\n\n## Rules\n\n- **RULE-14** One.\n- **RULE-19** Two.\n',
};

/// A sub-feature `login/sso` whose feature doc and domain doc share its Name;
/// the domain holds INV-6.
const Map<String, String> _subFeatureDocs = {
  'prds/features/f01_login/f01_sso/FEATURE.md': '# Single sign-on\n',
  'specs/f01_login/f01_sso/DOMAIN.md':
      '# SSO domain\n\n## Invariants\n\n- **INV-6** One email.\n',
};

final MergedSet _set = TemplateResolver().resolveCarried(
  packNames: const ['prd-core', 'software-tech'],
  homeDirectory: null,
);

/// The cite pass over [docs], each typed by its shipped doc type.
CitePass _passOf(Map<String, String> docs) => CitePass.plan(
  [
    for (final MapEntry(key: docPath, value: lf) in docs.entries)
      (
        docPath: docPath,
        lf: lf,
        type: switch (DocTypeMatcher(
          _set,
          targetNames: const [],
        ).match(docPath)) {
          MatchedDocType(:final docType) => docType,
          _ => null,
        },
        target: null,
      ),
  ],
  idPrefixes: _idPrefixes,
  layoutPaths: _layoutPaths,
);

/// The layout paths of the singular doc types of [_set].
final Set<String> _layoutPaths = singularLayoutPathsOf(
  _set,
  twinNames: const [],
);

/// The item ID prefixes of [_set].
final Set<String> _idPrefixes = itemIdPrefixesOf(_set.docTypes);

/// The text the pass gives the doc at [_citing] holding [body].
String _converted(String body, {Map<String, String> extra = const {}}) {
  final text = '# Sign-up architecture\n\n## Components\n\n$body';
  final pass = _passOf({..._baseDocs, ...extra, _citing: text});
  return pass
      .apply(_citing, text)
      .substring('# Sign-up architecture\n\n## Components\n\n'.length);
}

PackUpgrade _upgrade(String pack, String pin, String target) => PackUpgrade(
  pack: pack,
  pin: PackVersion.parse(pin, file: 'test', key: pack),
  target: PackVersion.parse(target, file: 'test', key: pack),
  steps: const [],
);

void main() {
  group('the cite pass', () {
    test('a name that names one doc becomes a link to it, the path relative '
        'to the citing doc', () {
      expect(
        _converted('See `domain:login`.\n'),
        'See [domain:login](../f01_login/DOMAIN.md).\n',
      );
    });

    test('an item cite becomes one item link per ID, its text the ID', () {
      expect(
        _converted('`domain:login` INV-6 and INV-7\n'),
        '[INV-6](../f01_login/DOMAIN.md#invariants) and [INV-7](../f01_login/DOMAIN.md#invariants)\n',
      );
    });

    test('a name with an ID farther along the line becomes its doc link and '
        'the ID stays as written', () {
      expect(
        _converted(
          'It is the one (`domain:login`); with two targets it needs it '
          '(INV-6) |\n',
        ),
        'It is the one ([domain:login](../f01_login/DOMAIN.md)); with two '
        'targets it needs it (INV-6) |\n',
      );
    });

    test('a lone name that resolves to one doc becomes its link where it '
        'stood', () {
      expect(
        _converted('Before `domain:login` after.\n'),
        'Before [domain:login](../f01_login/DOMAIN.md) after.\n',
      );
    });

    test('an item cite drops its name only up to its run and links each ID, '
        'a later ID staying as written', () {
      expect(
        _converted('`domain:login`  INV-6 and INV-7, then see INV-7 too\n'),
        '[INV-6](../f01_login/DOMAIN.md#invariants) and '
        '[INV-7](../f01_login/DOMAIN.md#invariants), then see INV-7 too\n',
      );
    });

    test('a lettered ID that opens the run stays as written, with its name '
        'dropped only up to it', () {
      expect(
        _converted('`topic:doc_model` RULE-7a, RULE-14\n'),
        'RULE-7a, [RULE-14](../topics/doc_model.md#rules)\n',
      );
    });

    test('a lone-word span ends the run, so the ID after it is no item of the '
        'cite', () {
      expect(
        _converted('`domain:login` INV-6 and `goal` INV-3.\n'),
        '[INV-6](../f01_login/DOMAIN.md#invariants) and `goal` INV-3.\n',
      );
    });

    test('a token shaped like an ID but of no doc type prefix, such as SHA256 '
        'or UTF-8, leaves a doc cite', () {
      expect(
        _converted('See `domain:login` with SHA256 and UTF-8.\n'),
        'See [domain:login](../f01_login/DOMAIN.md) with SHA256 and UTF-8.\n',
      );
    });

    test('an item range becomes two item links joined by to', () {
      expect(
        _converted('`topic:doc_model#rules` RULE-14 to RULE-19\n'),
        '[RULE-14](../topics/doc_model.md#rules) to [RULE-19](../topics/doc_model.md#rules)\n',
      );
    });

    test('a section cite keeps its type prefix as link text and its key in '
        'the fragment', () {
      expect(
        _converted('See `feature:login#problem` first.\n'),
        'See [feature:login](../../prds/features/f01_login/FEATURE.md#problem) first.\n',
      );
    });

    test('a path mention takes the doc type and Name as its text', () {
      expect(
        _converted(
          'See `../f01_login/DOMAIN.md` and ../topics/doc_model.md.\n',
        ),
        'See [domain:login](../f01_login/DOMAIN.md) and [topic:doc_model](../topics/doc_model.md).\n',
      );
    });

    test('a shared name with no ID, and an ID its one doc lacks, stay and '
        'count as left', () {
      const body =
          'See `login/sso` here.\n'
          'And `domain:login` INV-99.\n'
          'And `domain:login` INV-6.\n';
      const text = '# Sign-up architecture\n\n## Components\n\n$body';
      final pass = _passOf({..._baseDocs, ..._subFeatureDocs, _citing: text});

      expect(
        pass.apply(_citing, text),
        endsWith(
          'See `login/sso` here.\nAnd `domain:login` INV-99.\n'
          'And [INV-6](../f01_login/DOMAIN.md#invariants).\n',
        ),
      );
      expect(pass.planLine, 'cites: 1 rewrites in 1 docs; left: 2');
      expect(pass.paths, [_citing]);
      expect(pass.leftOn(const {}), [
        '$_citing:5 login/sso',
        '$_citing:6 domain:login',
      ]);
    });

    test("a singular type's layout path stays as written; the same doc by a "
        'folder-relative path becomes its link', () {
      const text =
          '# Sign-up architecture\n\n## Components\n\n'
          'See `prds/GOAL.md`, docs/prds/GOAL.md, and `../../GOAL.md`.\n';
      final pass = _passOf({
        ..._baseDocs,
        'prds/GOAL.md': '# Project goals\n',
        'prds/features/f01_login/us01_x/fr01_y.md': text,
      });
      const citing = 'prds/features/f01_login/us01_x/fr01_y.md';

      expect(
        pass.apply(citing, text),
        endsWith(
          'See `prds/GOAL.md`, docs/prds/GOAL.md, and '
          '[goal:goal](../../../GOAL.md).\n',
        ),
      );
      expect(pass.planLine, 'cites: 1 rewrites in 1 docs; left: 0');
    });

    test('a left cite is cited at its line in the text the run writes', () {
      const body = 'See `login/sso` here.\n';
      const text = '# Sign-up architecture\n\n## Components\n\n$body';
      final pass = _passOf({..._baseDocs, ..._subFeatureDocs, _citing: text});
      const written = '---\napproved: "0123456789ab"\n---\n\n$text';

      expect(pass.leftOn({_citing: written}), ['$_citing:9 login/sso']);
    });

    test('a cite form written inside a longer code span is no cite, neither '
        'rewritten nor counted as left', () {
      const body = 'Run `see ../f01_login/DOMAIN.md now`.\n';
      const text = '# Sign-up architecture\n\n## Components\n\n$body';
      final pass = _passOf({..._baseDocs, _citing: text});

      expect(pass.apply(_citing, text), text);
      expect(pass.planLine, isNull);
      expect(pass.leftOn(const {}), isEmpty);
    });

    test('a cite in frontmatter, in fenced code, in a Concerns see target, or '
        'in a link is never rewritten', () {
      const text =
          '---\nowner: "`domain:login`"\n---\n\n# Sign-up architecture\n\n'
          '## Components\n\n```\n`domain:login` INV-6\n```\n\n'
          '[the domain](../f01_login/DOMAIN.md) and [`domain:login`](../f01_login/DOMAIN.md)\n\n'
          '## Concerns\n\n- **Data** — one email; see `../f01_login/DOMAIN.md#invariants`\n';
      final pass = _passOf({..._baseDocs, _citing: text});

      expect(pass.apply(_citing, text), text);
      expect(pass.planLine, isNull);
      expect(pass.leftOn(const {}), isEmpty);
    });

    test('a Concerns header the merged type does not hold is no Concerns '
        'section, for the pass as for check', () async {
      const override = 'sections:\n  - {id: concerns, disabled: true}\n';
      const architecture = 'specs/f03_pay/ARCHITECTURE.md';
      const text =
          '# Pay architecture\n\n## Concerns\n\n'
          '- **Data** — one email; see `domain:login`\n';
      final set = TemplateResolver().resolveCarried(
        packNames: const ['prd-core', 'software-tech'],
        homeDirectory: null,
        projectLayers: parseOverrides({
          '.specstone/templates/architecture.yaml': override,
        }),
      );
      final pass = CitePass.plan(
        [
          for (final MapEntry(key: docPath, value: lf) in {
            ..._baseDocs,
            architecture: text,
          }.entries)
            (
              docPath: docPath,
              lf: lf,
              type: switch (DocTypeMatcher(
                set,
                targetNames: const [],
              ).match(docPath)) {
                MatchedDocType(:final docType) => docType,
                _ => null,
              },
              target: null,
            ),
        ],
        idPrefixes: itemIdPrefixesOf(set.docTypes),
        layoutPaths: singularLayoutPathsOf(set, twinNames: const []),
      );
      final report = await checkOf(
        await writeCheckProject(
          extra: {
            '.specstone/templates/architecture.yaml': override,
            'docs/$_domain': _baseDocs[_domain]!,
            'docs/$architecture': text,
          },
        ),
      );

      expect(
        [
          for (final finding in report.findings)
            if (finding.kind == FindingKind.citeUnlinked) finding.path,
        ],
        [architecture],
      );
      expect(pass.planLine, 'cites: 1 rewrites in 1 docs; left: 0');
    });

    test('the cite pass skips see targets of a type built on architecture', () {
      const built = 'specs/EDGE_ARCHITECTURE_ROOT.md';
      const text =
          '# Edge architecture\n\n## Concerns\n\n'
          '- **Data** — one email; see `domain:login`\n';
      final set = TemplateResolver().resolveCarried(
        packNames: const ['prd-core', 'software-tech'],
        homeDirectory: null,
        projectLayers: parseOverrides({
          '.specstone/templates/edge_architecture_root.yaml':
              'id: edge_architecture_root\nextends: architecture\n'
              'path: $built\nparent:\n',
        }),
      );
      final pass = CitePass.plan(
        [
          for (final MapEntry(key: docPath, value: lf) in {
            ..._baseDocs,
            built: text,
          }.entries)
            (
              docPath: docPath,
              lf: lf,
              type: switch (DocTypeMatcher(
                set,
                targetNames: const [],
              ).match(docPath)) {
                MatchedDocType(:final docType) => docType,
                _ => null,
              },
              target: null,
            ),
        ],
        idPrefixes: itemIdPrefixesOf(set.docTypes),
        layoutPaths: singularLayoutPathsOf(set, twinNames: const []),
      );

      expect(pass.planLine, isNull);
      expect(pass.apply(built, text), text);
    });

    test('a tree with no old cite form has no cites line', () {
      final pass = _passOf({..._baseDocs, _citing: '# A\n\nNo cites here.\n'});

      expect(pass.planLine, isNull);
      expect(pass.paths, isEmpty);
    });

    test('each form counts once however many links it becomes, and only typed '
        'docs are read', () {
      const notes = 'notes/plan.md';
      final pass = _passOf({
        ..._baseDocs,
        _citing: '# A\n\n`domain:login` INV-6 and INV-7, `domain:login`\n',
        notes: '# Notes\n\n`domain:login`\n',
      });

      expect(pass.planLine, 'cites: 2 rewrites in 1 docs; left: 0');
      expect(
        pass.apply(notes, '# Notes\n\n`domain:login`\n'),
        '# Notes\n\n`domain:login`\n',
      );
    });

    test(
      'a shared name an item ID settles gives the link check names',
      () async {
        final docs = {
          for (final MapEntry(:key, :value) in loginProject.entries)
            if (key.startsWith('docs/') && key.endsWith('.md'))
              key.substring('docs/'.length): value,
          ..._subFeatureDocs,
        };
        const citing = 'specs/f02_signup/ARCHITECTURE.md';
        final text =
            '${docs[citing]}\nSee `login/sso` INV-6 and `login/sso`.\n';
        final index = await indexWith({
          for (final MapEntry(:key, :value) in _subFeatureDocs.entries)
            'docs/$key': value,
          'docs/$citing': text,
        });
        final candidates = citeCandidatesOf(text, idPrefixes: _idPrefixes);
        final checked = [
          for (final candidate in candidates)
            resolveCite(IndexCiteTree(index), citing, candidate),
        ];

        final pass = _passOf({...docs, citing: text});

        expect(checked.first, isA<CiteLink>());
        expect(checked.last, isA<CiteAmbiguous>());
        final link = citeLinkMarkdown(citing, checked.first as CiteLink).single;
        expect(link, '[INV-6](../f01_login/f01_sso/DOMAIN.md#invariants)');
        expect(
          pass.apply(citing, text),
          endsWith('\nSee $link and `login/sso`.\n'),
        );
        expect(pass.leftOn(const {}), hasLength(1));
      },
    );
  });

  group('runsCitePass', () {
    test('a prd-core or software-tech pin moved up from below the version '
        'that first ships the cite rule runs the pass', () {
      expect(runsCitePass([_upgrade('prd-core', '1.8.0', '1.9.0')]), isTrue);
      expect(
        runsCitePass([_upgrade('software-tech', '1.6.0', '1.7.0')]),
        isTrue,
      );
      expect(runsCitePass([_upgrade('prd-core', '1.0.0', '1.9.0')]), isTrue);
    });

    test(
      'an upgrade from that version or later, or of another pack, runs no pass',
      () {
        expect(
          runsCitePass([_upgrade('prd-core', '1.9.0', '1.10.0')]),
          isFalse,
        );
        expect(
          runsCitePass([_upgrade('software-tech', '1.7.0', '1.8.0')]),
          isFalse,
        );
        expect(runsCitePass([_upgrade('acme', '1.0.0', '1.2.0')]), isFalse);
        expect(runsCitePass(const []), isFalse);
      },
    );
  });
}
