// The expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/index_query/cite_resolution.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/models/cite_candidate.dart';
import 'package:specstone_core/src/index_query/models/cite_item.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';

const _domain = 'specs/f01_login/DOMAIN.md';
const _signupArchitecture = 'specs/f02_signup/ARCHITECTURE.md';
const _loginApi = 'specs/f01_login/API.md';

/// The login domain with an `## Invariants` section that holds INV-6.
const _domainWithInvariants = {
  'docs/$_domain':
      '# Login domain\n\n## Entities\n- Account\n\n'
      '## Invariants\n\n- **INV-6** An account holds one email.\n',
};

CiteCandidate _cite(
  String written, {
  String? sectionKey,
  List<String> itemIds = const [],
}) => CiteCandidate(
  line: 1,
  written: written,
  sectionKey: sectionKey,
  itemIds: itemIds,
);

Future<DocIndex> _index() => indexWith(_domainWithInvariants);

CiteResolution _resolve(DocIndex index, String citing, CiteCandidate cite) =>
    resolveCite(IndexCiteTree(index), citing, cite);

/// The one markdown link [link] makes from [citing].
String _markdown(String citing, CiteLink link) =>
    citeLinkMarkdown(citing, link).single;

void main() {
  group('resolveCite', () {
    test(
      'a typed name with an item ID its one doc holds is a link to that item',
      () async {
        final index = await _index();
        final resolved = _resolve(
          index,
          _signupArchitecture,
          _cite('domain:login', itemIds: ['INV-6']),
        );
        final link = resolved as CiteLink;
        expect(link.docPath, _domain);
        expect(link.sectionKey, isNull);
        expect(link.items, [
          const CiteItem(
            itemId: 'INV-6',
            sectionKey: 'invariants',
            anchor: 'invariants',
          ),
        ]);
        expect(link.linkText, 'domain:login');
        expect(
          _markdown(_signupArchitecture, link),
          '[INV-6](../f01_login/DOMAIN.md#invariants)',
        );
      },
    );

    test('item IDs one doc holds in two sections link each item to its own section', () async {
      final index = await indexWith({
        'docs/prds/GNFR.md':
            '# Global non-functional requirements\n\n## Performance\n\n'
            '### NFR-P03 — Check time\n\nFast.\n\n'
            '## Security\n\n### NFR-Sec01 — No plain text\n\nHashed.\n',
      });
      final link = _resolve(
        index,
        _signupArchitecture,
        _cite('gnfr', itemIds: ['NFR-P03', 'NFR-Sec01']),
      ) as CiteLink;
      expect(
        [for (final item in link.items) item.sectionKey],
        ['performance', 'security'],
      );
      expect(citeLinkMarkdown(_signupArchitecture, link), [
        '[NFR-P03](../../prds/GNFR.md#performance)',
        '[NFR-Sec01](../../prds/GNFR.md#security)',
      ]);
    });

    test('two item IDs give one item link each, which the caller joins with the cite words', () async {
      final index = await indexWith({
        'docs/$_domain':
            '# Login domain\n\n## Entities\n- Account\n\n## Invariants\n\n'
            '- **INV-6** An account holds one email.\n'
            '- **INV-7** An email names one account.\n',
      });
      final link = _resolve(
        index,
        _signupArchitecture,
        _cite('domain:login', itemIds: ['INV-6', 'INV-7']),
      ) as CiteLink;
      expect(
        citeLinkMarkdown(_signupArchitecture, link).join(' and '),
        '[INV-6](../f01_login/DOMAIN.md#invariants) and [INV-7](../f01_login/DOMAIN.md#invariants)',
      );
    });

    test(
      'a range gives two item links, which the caller joins with its to',
      () async {
        final index = await indexWith({
          'docs/specs/topics/doc_model.md':
              '# Doc model\n\n## Purpose\nModel docs.\n\n## Rules\n\n'
              '- **RULE-14** One.\n- **RULE-19** Two.\n',
        });
        final link = _resolve(
          index,
          _signupArchitecture,
          _cite(
            'topic:doc_model',
            sectionKey: 'rules',
            itemIds: ['RULE-14', 'RULE-19'],
          ),
        ) as CiteLink;
        expect(link.sectionKey, 'rules');
        expect(
          citeLinkMarkdown(_signupArchitecture, link).join(' to '),
          '[RULE-14](../topics/doc_model.md#rules) to [RULE-19](../topics/doc_model.md#rules)',
        );
      },
    );

    test('a bare one-slug name that one doc carries is a doc link', () async {
      final index = await _index();
      final link = _resolve(
        index,
        _signupArchitecture,
        _cite('password_rules'),
      ) as CiteLink;
      expect(link.docPath, 'prds/references/password_rules/REFERENCE.md');
      expect(link.sectionKey, isNull);
      expect(
        _markdown(_signupArchitecture, link),
        '[password_rules](../../prds/references/password_rules/REFERENCE.md)',
      );
    });

    test('a path, read from the citing doc, is a link whose text is the doc type and Name', () async {
      final index = await _index();
      final link = _resolve(
        index,
        _signupArchitecture,
        _cite('../f01_login/DOMAIN.md', itemIds: ['INV-6']),
      ) as CiteLink;
      expect(link.docPath, _domain);
      expect(link.linkText, 'domain:login');
      final whole = _resolve(
        index,
        _signupArchitecture,
        _cite('../f01_login/DOMAIN.md'),
      ) as CiteLink;
      expect(
        _markdown(_signupArchitecture, whole),
        '[domain:login](../f01_login/DOMAIN.md)',
      );
    });

    test('a sibling file name resolves from the citing doc folder', () async {
      final index = await _index();
      final link = _resolve(
        index,
        _loginApi,
        _cite('DOMAIN.md', itemIds: ['INV-6']),
      ) as CiteLink;
      expect(link.docPath, _domain);
      expect(_markdown(_loginApi, link), '[INV-6](DOMAIN.md#invariants)');
    });

    test(
      'a path no doc folder reaches resolves by its deepest alignment',
      () async {
        final index = await _index();
        final link = _resolve(
          index,
          'prds/features/f01_login/FEATURE.md',
          _cite('specs/f01_login/DOMAIN.md'),
        ) as CiteLink;
        expect(link.docPath, _domain);
      },
    );

    test('a name a feature and its four spec docs share, settled by an item ID only the domain doc holds, links that item', () async {
      final index = await _index();
      expect(index.resolve('login'), hasLength(5));
      final link = _resolve(
        index,
        _signupArchitecture,
        _cite('login', itemIds: ['INV-6']),
      ) as CiteLink;
      expect(link.docPath, _domain);
      expect(
        _markdown(_signupArchitecture, link),
        '[INV-6](../f01_login/DOMAIN.md#invariants)',
      );
    });

    test('a #key only one doc of a shared name holds settles it', () async {
      final index = await _index();
      final link = _resolve(
        index,
        _signupArchitecture,
        _cite('login', sectionKey: 'problem'),
      ) as CiteLink;
      expect(link.docPath, 'prds/features/f01_login/FEATURE.md');
      expect(link.sectionKey, 'problem');
      expect(
        _markdown(_signupArchitecture, link),
        '[login](../../prds/features/f01_login/FEATURE.md#problem)',
      );
    });

    test('a shared name with no #key or item ID is ambiguous', () async {
      final index = await _index();
      final resolved = _resolve(index, _signupArchitecture, _cite('login'));
      expect(resolved, isA<CiteAmbiguous>());
      expect((resolved as CiteAmbiguous).docPaths, hasLength(5));
    });

    test(
      'a shared name whose item ID no doc holds picks none, so it is ambiguous',
      () async {
        final index = await _index();
        expect(
          _resolve(
            index,
            _signupArchitecture,
            _cite('login', itemIds: ['INV-99']),
          ),
          isA<CiteAmbiguous>(),
        );
      },
    );

    test('an item ID or a #key the one doc lacks is a missing part', () async {
      final index = await _index();
      final item = _resolve(
        index,
        _signupArchitecture,
        _cite('domain:login', itemIds: ['INV-99']),
      );
      expect(item, isA<CiteMissingPart>());
      expect((item as CiteMissingPart).docPath, _domain);
      expect(
        _resolve(
          index,
          _signupArchitecture,
          _cite('domain:login', sectionKey: 'rules'),
        ),
        isA<CiteMissingPart>(),
      );
    });

    test(
      'a one-slug Name equal to a doc type id links that type one doc',
      () async {
        final index = await _index();
        final link =
            _resolve(index, _signupArchitecture, _cite('gnfr')) as CiteLink;
        expect(link.docPath, 'prds/GNFR.md');
        expect(
          _markdown(_signupArchitecture, link),
          '[gnfr](../../prds/GNFR.md)',
        );
      },
    );

    test(
      'a #key names a section whose heading anchor differs from its key',
      () async {
        final index = await indexWith({
          'docs/$_loginApi':
              '# Login API\n\n## FR trace\n\n| FR | Operation |\n|---|---|\n\n'
              '## Operations\n- sign in\n',
        });
        final link = _resolve(
          index,
          _signupArchitecture,
          _cite('api:login', sectionKey: 'fr_trace'),
        ) as CiteLink;
        expect(link.sectionKey, 'fr_trace');
        expect(
          _markdown(_signupArchitecture, link),
          '[api:login](../f01_login/API.md#fr-trace)',
        );
      },
    );

    test('the header after a path names its section', () async {
      final index = await _index();
      final link = _resolve(
        index,
        _loginApi,
        _cite('ERROR.md', sectionKey: 'error_catalog'),
      ) as CiteLink;
      expect(
        _markdown(_loginApi, link),
        '[error:login](ERROR.md#error-catalog)',
      );
    });

    test('a name or a path no doc carries resolves to no doc', () async {
      final index = await _index();
      for (final written in [
        'login/nowhere',
        'user_id',
        'superpowers:writing-plans',
        '../f09_none/DOMAIN.md',
      ]) {
        expect(
          _resolve(index, _signupArchitecture, _cite(written)),
          isA<CiteNoDoc>(),
          reason: written,
        );
      }
    });

    test('an S<N> after a story name links its scenario', () async {
      final index = await indexWith({
        'docs/prds/features/f01_login/us01_email_login/USER_STORY.md':
            '# Agent signs in with email\n\n## Use Case\nSign in.\n\n'
            '## Acceptance Criteria\n\n### Scenario 1 — [happy] Sign in\n\n- **Given** an account\n',
      });
      final link = _resolve(
        index,
        _signupArchitecture,
        _cite('login/email_login', itemIds: ['S1']),
      ) as CiteLink;
      expect(
        _markdown(_signupArchitecture, link),
        '[S1](../../prds/features/f01_login/us01_email_login/USER_STORY.md#acceptance-criteria)',
      );
    });

    test(
      'a cite of the citing doc itself links into it by its anchor alone',
      () async {
        final index = await _index();
        final link = _resolve(
          index,
          _domain,
          _cite('domain:login', itemIds: ['INV-6']),
        ) as CiteLink;
        expect(_markdown(_domain, link), '[INV-6](#invariants)');
      },
    );
  });
}
