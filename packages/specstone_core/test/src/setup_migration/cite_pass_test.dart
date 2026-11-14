import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/index_query/cite_candidates.dart';
import 'package:specstone_core/src/index_query/cite_resolution.dart';
import 'package:specstone_core/src/setup_migration/cite_pass.dart';
import 'package:specstone_core/src/setup_migration/migration_chain.dart';
import 'package:specstone_core/src/setup_migration/project_files.dart'
    show parseOverrides;
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

final MergedSet _set = TemplateResolver().resolveCarried(
  packNames: const ['prd-core', 'software-tech'],
  homeDirectory: null,
);

/// The cite pass over [docs], each typed by its shipped doc type.
CitePass _passOf(Map<String, String> docs) => CitePass.plan([
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
]);

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
    test('f06/us02/fr02/e78: a name that names one doc becomes a link to it, the path relative to the citing doc', () {
      expect(
        _converted('See `domain:login`.\n'),
        'See [domain:login](../f01_login/DOMAIN.md).\n',
      );
    });

    test('f06/us02/fr02/e79: an item cite becomes one item link per ID, its text the ID', () {
      expect(
        _converted('`domain:login` INV-6 and INV-7\n'),
        '[INV-6](../f01_login/DOMAIN.md#invariants) and [INV-7](../f01_login/DOMAIN.md#invariants)\n',
      );
    });

    test(
      'f06/us02/fr02/e80: an item range becomes two item links joined by to',
      () {
        expect(
          _converted('`topic:doc_model#rules` RULE-14 to RULE-19\n'),
          '[RULE-14](../topics/doc_model.md#rules) to [RULE-19](../topics/doc_model.md#rules)\n',
        );
      },
    );

    test('f06/us02/fr02/e81: a section cite keeps its type prefix as link text and its key in the fragment', () {
      expect(
        _converted('See `feature:login#problem` first.\n'),
        'See [feature:login](../../prds/features/f01_login/FEATURE.md#problem) first.\n',
      );
    });

    test('f06/us02/fr02/e81: a path mention takes the doc type and Name as its text', () {
      expect(
        _converted(
          'See `../f01_login/DOMAIN.md` and ../topics/doc_model.md.\n',
        ),
        'See [domain:login](../f01_login/DOMAIN.md) and [topic:doc_model](../topics/doc_model.md).\n',
      );
    });

    test('f06/us02/fr02/e82: a shared name with no ID, and an ID its one doc lacks, stay and count as left', () {
      const body =
          'See `login` here.\n'
          'And `domain:login` INV-99.\n'
          'And `domain:login` INV-6.\n';
      const text = '# Sign-up architecture\n\n## Components\n\n$body';
      final pass = _passOf({..._baseDocs, _citing: text});

      expect(
        pass.apply(_citing, text),
        endsWith(
          'See `login` here.\nAnd `domain:login` INV-99.\n'
          'And [INV-6](../f01_login/DOMAIN.md#invariants).\n',
        ),
      );
      expect(pass.planLine, 'cites: 1 rewrites in 1 docs; left: 2');
      expect(pass.paths, [_citing]);
      expect(pass.leftOn(const {}), [
        '$_citing:5 login',
        '$_citing:6 domain:login',
      ]);
    });

    test('f06/us02/fr02/e82: a left cite is cited at its line in the text the run writes', () {
      const body = 'See `login` here.\n';
      const text = '# Sign-up architecture\n\n## Components\n\n$body';
      final pass = _passOf({..._baseDocs, _citing: text});
      const written = '---\napproved: "0123456789ab"\n---\n\n$text';

      expect(pass.leftOn({_citing: written}), ['$_citing:9 login']);
    });

    test('f06/us02/fr02/e82: a cite form written inside a longer code span stays and counts as left', () {
      const body = 'Run `see ../f01_login/DOMAIN.md now`.\n';
      const text = '# Sign-up architecture\n\n## Components\n\n$body';
      final pass = _passOf({..._baseDocs, _citing: text});

      expect(pass.apply(_citing, text), text);
      expect(pass.planLine, 'cites: 0 rewrites in 0 docs; left: 1');
    });

    test('f06/us02/fr02/e85: a cite in frontmatter, in fenced code, in a Concerns see target, or in a link is never rewritten', () {
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

    test('f06/us02/fr02/e85: a Concerns header the merged type does not hold is no Concerns section, for the pass as for check', () async {
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
      final pass = CitePass.plan([
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
      ]);
      final report = checkOf(
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

    test(
      'f06/us02/fr02/e82: a tree with no old cite form has no cites line',
      () {
        final pass = _passOf({
          ..._baseDocs,
          _citing: '# A\n\nNo cites here.\n',
        });

        expect(pass.planLine, isNull);
        expect(pass.paths, isEmpty);
      },
    );

    test('f06/us02/fr02/e82: each form counts once however many links it becomes, and only typed docs are read', () {
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

    test('f04/us02/fr08/e04: a shared name an item ID settles gives the link check names', () async {
      final docs = {
        for (final MapEntry(:key, :value) in loginProject.entries)
          if (key.startsWith('docs/') && key.endsWith('.md'))
            key.substring('docs/'.length): value,
        _domain: '# Login domain\n\n## Invariants\n\n- **INV-6** One email.\n',
      };
      const citing = 'specs/f02_signup/ARCHITECTURE.md';
      final text = '${docs[citing]}\nSee `login` INV-6 and `login`.\n';
      final index = await indexWith({
        'docs/$_domain': docs[_domain]!,
        'docs/$citing': text,
      });
      final candidates = citeCandidatesOf(text);
      final checked = [
        for (final candidate in candidates)
          resolveCite(IndexCiteTree(index), citing, candidate),
      ];

      final pass = _passOf({...docs, citing: text});

      expect(checked.first, isA<CiteLink>());
      expect(checked.last, isA<CiteAmbiguous>());
      final link = citeLinkMarkdown(citing, checked.first as CiteLink).single;
      expect(link, '[INV-6](../f01_login/DOMAIN.md#invariants)');
      expect(pass.apply(citing, text), endsWith('\nSee $link and `login`.\n'));
      expect(pass.leftOn(const {}), hasLength(1));
    });
  });

  group('runsCitePass', () {
    test('f06/us02/fr02/e78: a prd-core or software-tech pin moved up from below the version that first ships the cite rule runs the pass', () {
      expect(runsCitePass([_upgrade('prd-core', '1.8.0', '1.9.0')]), isTrue);
      expect(
        runsCitePass([_upgrade('software-tech', '1.6.0', '1.7.0')]),
        isTrue,
      );
      expect(runsCitePass([_upgrade('prd-core', '1.0.0', '1.9.0')]), isTrue);
    });

    test('f06/us02/fr02/e86: an upgrade from that version or later, or of another pack, runs no pass', () {
      expect(runsCitePass([_upgrade('prd-core', '1.9.0', '1.10.0')]), isFalse);
      expect(
        runsCitePass([_upgrade('software-tech', '1.7.0', '1.8.0')]),
        isFalse,
      );
      expect(runsCitePass([_upgrade('acme', '1.0.0', '1.2.0')]), isFalse);
      expect(runsCitePass(const []), isFalse);
    });
  });
}
