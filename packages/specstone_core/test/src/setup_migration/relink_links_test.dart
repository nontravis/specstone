// Test names stay one literal so `specstone check` finds them by exact text.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/setup_migration/followed_links.dart';
import 'package:specstone_core/src/setup_migration/models/relink_rules.dart';
import 'package:specstone_core/src/setup_migration/relink_links.dart';
import 'package:specstone_core/src/templates/models/migration_step.dart';
import 'package:test/test.dart';

const _architecturePath = 'specs/f01_login/ARCHITECTURE.md';
const _apiPath = 'specs/f02_signup/API.md';

const _rules = RelinkRules(
  folds: [
    MergeDoc(
      fromId: 'domain',
      fromPath: 'specs/f{nn}_{slug}/DOMAIN.md',
      toId: 'architecture',
      sections: [
        MergeSection(fromId: 'entities', fromHeader: 'Entities', toId: 'data'),
        MergeSection(
          fromId: 'flows',
          fromHeader: 'Flows',
          toId: 'technical_diagram',
        ),
      ],
    ),
  ],
  drops: [
    DropSection(
      docTypes: ['architecture'],
      sectionId: 'concerns',
      sectionHeader: 'Concerns',
    ),
  ],
  renames: [
    RenameSection(
      docType: 'architecture',
      fromId: 'component_diagram',
      fromHeader: 'Component diagram',
      toId: 'technical_diagram',
      toHeader: 'Technical diagram',
    ),
  ],
);

/// The targets of the tests, the architecture doc holding [slugs].
RelinkTargets _targets({
  List<String> slugs = const ['data', 'technical-diagram'],
}) => RelinkTargets({
  _architecturePath: RelinkDoc(
    typeId: 'architecture',
    name: 'login',
    headingSlugs: slugs,
    sectionHeaders: const {
      'data': 'Data',
      'technical_diagram': 'Technical diagram',
    },
  ),
  _apiPath: const RelinkDoc(
    typeId: 'api',
    name: 'signup',
    headingSlugs: [],
    sectionHeaders: {},
  ),
});

/// Returns the text [line] becomes in the doc at [docPath].
String _relinked(
  String line, {
  String docPath = _apiPath,
  List<String> slugs = const ['data', 'technical-diagram'],
}) => relinkLinks(
  '# Doc\n\n$line\n',
  docPath,
  rules: _rules,
  targets: _targets(slugs: slugs),
).lf.substring('# Doc\n\n'.length).trimRight();

void main() {
  group('relink_merged_docs typed text', () {
    test(
      'typed text of a folded type reaching a to-type doc takes the to type',
      () {
        expect(
          _relinked('[domain:login](../f01_login/ARCHITECTURE.md)'),
          '[architecture:login](../f01_login/ARCHITECTURE.md)',
        );
        expect(
          _relinked(
            '[domain:login#entities](../f01_login/ARCHITECTURE.md#data)',
          ),
          '[architecture:login#data](../f01_login/ARCHITECTURE.md#data)',
        );
        expect(
          _relinked('[domain:login#other](../f01_login/ARCHITECTURE.md)'),
          '[architecture:login#other](../f01_login/ARCHITECTURE.md)',
        );
        expect(
          relinkLinks(
            '[domain:login](../f01_login/ARCHITECTURE.md)\n',
            _apiPath,
            rules: _rules,
            targets: _targets(),
          ).changes,
          [LinkChange.merged],
        );
      },
    );

    test('typed text whose destination reaches no to-type doc stays', () {
      expect(
        _relinked('[domain:login](../f02_signup/API.md)'),
        '[domain:login](../f02_signup/API.md)',
      );
    });
  });

  group('relink_merged_docs self link', () {
    test(
      'a self link once naming the folded doc takes the first mapped heading',
      () {
        expect(
          _relinked(
            '[domain:login](ARCHITECTURE.md)',
            docPath: _architecturePath,
          ),
          '[architecture:login](#data)',
        );
        expect(
          _relinked(
            '[domain:login](ARCHITECTURE.md)',
            docPath: _architecturePath,
            slugs: const ['technical-diagram'],
          ),
          'architecture:login',
        );
        expect(
          _relinked('[see](ARCHITECTURE.md)', docPath: _architecturePath),
          '[see](ARCHITECTURE.md)',
        );
      },
    );

    test('a self link once naming a folded section takes the heading its key maps to, else the first', () {
      const self = 'ARCHITECTURE.md';
      String at(String line, {List<String>? slugs}) => _relinked(
        line,
        docPath: _architecturePath,
        slugs: slugs ?? const ['data', 'technical-diagram'],
      );

      expect(
        at('[domain:login#flows]($self)'),
        '[architecture:login#technical_diagram](#technical-diagram)',
      );
      expect(
        at('[domain:login#other]($self)'),
        '[architecture:login#other](#data)',
      );
      expect(
        at('[domain:login#flows]($self)', slugs: const ['data']),
        'architecture:login#technical_diagram',
      );
    });

    test('a self link whose text is the folded file name takes the first mapped heading', () {
      const self = 'ARCHITECTURE.md';
      String at(String line, {List<String>? slugs}) => _relinked(
        line,
        docPath: _architecturePath,
        slugs: slugs ?? const ['data', 'technical-diagram'],
      );

      expect(at('[`DOMAIN.md`]($self)'), '[`DOMAIN.md`](#data)');
      expect(at('[DOMAIN.md]($self)'), '[DOMAIN.md](#data)');
      expect(at('[`./DOMAIN.md`]($self)'), '[`./DOMAIN.md`](#data)');
      expect(at('[`DOMAIN.md`]($self)', slugs: const []), '`DOMAIN.md`');
      expect(at('[`NOTES.md`]($self)'), '[`NOTES.md`]($self)');
      expect(
        _relinked('[`DOMAIN.md`](../f01_login/ARCHITECTURE.md)'),
        '[`DOMAIN.md`](../f01_login/ARCHITECTURE.md)',
      );
    });

    test(
      'a self link whose text is the to type naming its own doc unwraps',
      () {
        const self = 'ARCHITECTURE.md';
        String at(String line) => _relinked(line, docPath: _architecturePath);

        expect(at('[architecture:login]($self)'), 'architecture:login');
        expect(
          at('[architecture:signup]($self)'),
          '[architecture:signup]($self)',
        );
        expect(
          at('[architecture:login#data]($self)'),
          '[architecture:login#data]($self)',
        );
        expect(
          _relinked('[api:signup](API.md)'),
          '[api:signup](API.md)',
          reason: 'api is no to type of a fold',
        );
      },
    );
  });

  group('relink_merged_docs anchors', () {
    test('a dropped anchor the target lacks goes', () {
      expect(
        _relinked('[x](../f01_login/ARCHITECTURE.md#concerns)'),
        '[x](../f01_login/ARCHITECTURE.md)',
      );
      expect(_relinked('[x](#concerns)', docPath: _architecturePath), 'x');
      expect(
        relinkLinks(
          '[x](#concerns)\n',
          _architecturePath,
          rules: _rules,
          targets: _targets(),
        ).changes,
        [LinkChange.dropped],
      );
      const held = ['data', 'concerns'];
      expect(
        _relinked('[x](../f01_login/ARCHITECTURE.md#concerns)', slugs: held),
        '[x](../f01_login/ARCHITECTURE.md#concerns)',
      );
      expect(
        _relinked('[x](#concerns)', docPath: _architecturePath, slugs: held),
        '[x](#concerns)',
      );
    });

    test(
      'an old renamed anchor takes the new slug only where the target holds it',
      () {
        expect(
          _relinked('[x](../f01_login/ARCHITECTURE.md#component-diagram)'),
          '[x](../f01_login/ARCHITECTURE.md#technical-diagram)',
        );
        expect(
          relinkLinks(
            '[x](../f01_login/ARCHITECTURE.md#component-diagram)\n',
            _apiPath,
            rules: _rules,
            targets: _targets(),
          ).changes,
          [LinkChange.renamed],
        );
        expect(
          _relinked(
            '[x](../f01_login/ARCHITECTURE.md#component-diagram)',
            slugs: const ['data'],
          ),
          '[x](../f01_login/ARCHITECTURE.md#component-diagram)',
        );
      },
    );
  });

  group('relink_merged_docs bounds', () {
    test('links in a fence, a code span, or frontmatter stay', () {
      const links = [
        '[domain:login](../f01_login/ARCHITECTURE.md)',
        '[x](../f01_login/ARCHITECTURE.md#concerns)',
        '[x](../f01_login/ARCHITECTURE.md#component-diagram)',
      ];
      for (final link in links) {
        final lf =
            '---\nnote: "$link"\n---\n# Doc\n\n'
            '```\n$link\n```\n\nSee `$link`.\n';
        final relinked = relinkLinks(
          lf,
          _apiPath,
          rules: _rules,
          targets: _targets(),
        );
        expect(relinked.lf, lf, reason: link);
        expect(relinked.changes, isEmpty, reason: link);
      }
      const self = '[domain:login](ARCHITECTURE.md)';
      const selfLf = '# Doc\n\n```\n$self\n```\n\nSee `$self`.\n';
      expect(
        relinkLinks(
          selfLf,
          _architecturePath,
          rules: _rules,
          targets: _targets(),
        ).lf,
        selfLf,
      );
    });

    test('a doc whose links all resolve comes back as given', () {
      const lf =
          '# Doc\n\n[Data](../f01_login/ARCHITECTURE.md#data) and '
          '[architecture:login](../f01_login/ARCHITECTURE.md) and '
          '[api](API.md).\n';

      final relinked = relinkLinks(
        lf,
        _apiPath,
        rules: _rules,
        targets: _targets(),
      );

      expect(identical(relinked.lf, lf), isTrue);
      expect(relinked.changes, isEmpty);
    });

    test('a dropped anchor the target holds as an html id stays', () {
      final targets = RelinkTargets({
        _architecturePath: const RelinkDoc(
          typeId: 'architecture',
          name: 'login',
          headingSlugs: ['data'],
          sectionHeaders: {'data': 'Data'},
          htmlIds: {'concerns'},
        ),
      });
      const lf = '# Doc\n\n[x](../f01_login/ARCHITECTURE.md#concerns)\n';

      expect(relinkLinks(lf, _apiPath, rules: _rules, targets: targets).lf, lf);
    });

    test('a drop or rename of another doc type leaves the anchor of a doc it does not name', () {
      final targets = RelinkTargets({
        _apiPath: const RelinkDoc(
          typeId: 'api',
          name: 'signup',
          headingSlugs: ['technical-diagram'],
          sectionHeaders: {},
        ),
      });
      const lf =
          '# Doc\n\n[x](../f02_signup/API.md#concerns) '
          '[y](../f02_signup/API.md#component-diagram)\n';

      expect(
        relinkLinks(lf, _architecturePath, rules: _rules, targets: targets).lf,
        lf,
      );
    });
  });

  group('relink_merged_docs folds', () {
    test('a self link written as a reference link becomes an inline section link and keeps its definition', () {
      const lf =
          '# Doc\n\nSee [domain:login][d].\n\n'
          '[d]: ARCHITECTURE.md\n';

      expect(
        relinkLinks(
          lf,
          _architecturePath,
          rules: _rules,
          targets: _targets(),
        ).lf,
        '# Doc\n\nSee [architecture:login](#data).\n\n'
        '[d]: ARCHITECTURE.md\n',
      );
    });

    test('a project-level fold retypes a link to the project doc', () {
      const rules = RelinkRules(
        folds: [
          MergeDoc(
            fromId: 'project_domain',
            fromPath: 'specs/DOMAIN.md',
            toId: 'project_architecture',
            sections: [
              MergeSection(
                fromId: 'entities',
                fromHeader: 'Entities',
                toId: 'data',
              ),
            ],
          ),
        ],
        drops: [],
        renames: [],
      );
      final targets = RelinkTargets({
        'specs/ARCHITECTURE.md': const RelinkDoc(
          typeId: 'project_architecture',
          name: 'project_architecture',
          headingSlugs: ['data'],
          sectionHeaders: {'data': 'Data'},
        ),
      });

      expect(
        relinkLinks(
          '[project_domain:project_domain](../ARCHITECTURE.md)\n',
          _apiPath,
          rules: rules,
          targets: targets,
        ).lf,
        '[project_architecture:project_architecture](../ARCHITECTURE.md)\n',
      );
    });

    test('a typed key names a mapped section by its id or by its header', () {
      const rules = RelinkRules(
        folds: [
          MergeDoc(
            fromId: 'domain',
            fromPath: 'specs/f{nn}_{slug}/DOMAIN.md',
            toId: 'architecture',
            sections: [
              MergeSection(
                fromId: 'ents',
                fromHeader: 'Entities',
                toId: 'data',
              ),
            ],
          ),
        ],
        drops: [],
        renames: [],
      );
      String relinked(String key) => relinkLinks(
        '[domain:login#$key](../f01_login/ARCHITECTURE.md)\n',
        _apiPath,
        rules: rules,
        targets: _targets(),
      ).lf;

      expect(
        relinked('ents'),
        '[architecture:login#data](../f01_login/ARCHITECTURE.md)\n',
      );
      expect(
        relinked('entities'),
        '[architecture:login#data](../f01_login/ARCHITECTURE.md)\n',
      );
    });
  });
}
