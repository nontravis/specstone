import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/cold_node.dart';
import '../../helpers/rulebook_fixture.dart';
import '../../helpers/target_fixture.dart';

/// The DocPath of the login domain the tests add.
const _domain = 'specs/f01_login/DOMAIN.md';

/// The login domain, whose `## Invariants` holds INV-6.
const _domainFile = {
  'docs/$_domain':
      '# Login domain\n\n## Entities\n\n- Account\n\n'
      '## Invariants\n\n- **INV-6** An account holds one email.\n',
};

/// The body line of the login feature that the tests replace.
const _line = 'Users forget passwords.';

/// The file line of [_line] in the login feature.
const _lineNumber = 14;

/// The path from the login feature to the login domain.
const _fromFeature = '../../../specs/f01_login/DOMAIN.md';

/// The path from the login feature to the sub-feature domain below.
const _subDomainFromFeature = '../../../specs/f01_login/f01_sso/DOMAIN.md';

/// A sub-feature `login/sso` with a feature doc, a domain doc holding INV-6,
/// and an architecture doc: three docs share its Name.
const _subFeature = {
  'docs/prds/features/f01_login/f01_sso/FEATURE.md': '# Single sign-on\n',
  'docs/specs/f01_login/f01_sso/DOMAIN.md':
      '# SSO domain\n\n## Entities\n\n- Account\n\n'
      '## Invariants\n\n- **INV-6** An account holds one email.\n',
  'docs/specs/f01_login/f01_sso/ARCHITECTURE.md': '# SSO architecture\n',
};

Future<List<Finding>> _citeFindings(Map<String, String> extra) async {
  final report = await checkOf(
    await writeCheckProject(extra: {..._domainFile, ...extra}),
  );
  return [
    for (final finding in report.findings)
      if (finding.kind == FindingKind.citeUnlinked) finding,
  ];
}

Future<List<Finding>> _citesInFeature(String replacement) =>
    _citeFindings(doc(loginFeature, _line, replacement));

void main() {
  useColdHostNode();

  test('a cite_unlinked finding names its cite under value', () async {
    final findings = await _citesInFeature(
      'Users forget; `rulebook:login` INV-6.',
    );
    final keys = findings.single.keys;
    expect(keys['value'], 'rulebook:login');
    expect(keys, isNot(contains('cite')));
  });

  test('a typed name and an item ID its doc holds gives cite_unlinked at '
      'its line, naming the link', () async {
    final findings = await _citesInFeature(
      'Users forget; `rulebook:login` INV-6.',
    );
    expect(findings, hasLength(1));
    final finding = findings.single;
    expect(finding.path, loginFeature);
    expect(finding.line, _lineNumber);
    expect(finding.waitsFor, WaitsFor.agent);
    expect(finding.keys['value'], 'rulebook:login');
    expect(finding.message, contains('[INV-6]($_fromFeature#invariants)'));
  });

  test('a resolving mermaid token raises no cite_unlinked', () async {
    final findings = await _citesInFeature(
      'Users forget.\n\n```mermaid\nflowchart LR\n'
      '  N[rulebook:login INV-6]\n```',
    );
    expect(findings, isEmpty);
  });

  test('a token shaped like an ID but of no doc type prefix, such as SHA256 '
      'or UTF-8, is no item ID', () async {
    final findings = await _citesInFeature(
      'Users forget; `rulebook:login` with SHA256 and UTF-8.',
    );
    expect(findings, hasLength(1));
    expect(
      findings.single.message,
      contains('write it as [rulebook:login]($_fromFeature)'),
    );
  });

  test('a lone-word span raises nothing, named doc or not', () async {
    final findings = await _citesInFeature(
      'Users forget; see `gnfr` and the `user_id` field.',
    );
    expect(findings, isEmpty);
  });

  test('a lone-word span with a #key or an item ID raises nothing', () async {
    final findings = await _citesInFeature(
      'Users forget; see `login#problem` and `login` INV-6.',
    );
    expect(findings, isEmpty);
  });

  test(
    'a path in a code span, a plain path, and a sibling file name each count',
    () async {
      final findings = await _citeFindings({
        ...doc(
          loginFeature,
          _line,
          'Users forget; `$_fromFeature` INV-6.\nRead $_fromFeature too.',
        ),
        ...doc(
          loginApi,
          'Signs the Agent in.',
          'Signs the Agent in (`DOMAIN.md` INV-6).',
        ),
      });
      expect(
        [for (final f in findings) (f.path, f.keys['value'])],
        [
          (loginFeature, _fromFeature),
          (loginFeature, _fromFeature),
          (loginApi, 'DOMAIN.md'),
        ],
      );
      expect(findings.last.message, contains('[INV-6](DOMAIN.md#invariants)'));
    },
  );

  test(
    'a shared name settled by an item ID gives one finding linking that item',
    () async {
      final findings = await _citeFindings({
        ..._subFeature,
        ...doc(loginFeature, _line, 'Users forget; `login/sso` INV-6.'),
      });
      expect(findings, hasLength(1));
      expect(findings.single.keys['value'], 'login/sso');
      expect(
        findings.single.message,
        contains('[INV-6]($_subDomainFromFeature#invariants)'),
      );
    },
  );

  test('a shared name with no #key or item ID still gives cite_unlinked, '
      'naming the docs it may mean', () async {
    final findings = await _citeFindings({
      ..._subFeature,
      ...doc(loginFeature, _line, 'Users forget; see `login/sso`.'),
    });
    expect(findings, hasLength(1));
    expect(findings.single.keys, {'value': 'login/sso'});
    expect(findings.single.message, contains('3 docs'));
    expect(findings.single.message, contains('[text](<path>)'));
  });

  test('an item ID the one doc lacks still gives cite_unlinked', () async {
    final findings = await _citesInFeature(
      'Users forget; `rulebook:login` INV-99.',
    );
    expect(findings, hasLength(1));
    expect(findings.single.message, contains(_domain));
    expect(findings.single.message, contains('INV-99'));
  });

  test('a cite_unlinked finding names its one doc as targetPath and its link '
      'as fix', () async {
    final one = await _citesInFeature('Users forget; `rulebook:login` INV-6.');
    const oneLink = '[INV-6]($_fromFeature#invariants)';
    expect(one.single.keys, {
      'value': 'rulebook:login',
      'targetPath': 'docs/$_domain',
      'fix': oneLink,
    });
    expect(one.single.message, contains(oneLink));

    final run = await _citeFindings({
      'docs/$_domain':
          '# Login domain\n\n## Entities\n\n- Account\n\n'
          '## Invariants\n\n- **INV-6** An account holds one email.\n'
          '- **INV-7** A login is rate limited.\n',
      ...doc(
        loginFeature,
        _line,
        'Users forget; `rulebook:login` INV-6, INV-7.',
      ),
    });
    const twoLinks =
        '[INV-6]($_fromFeature#invariants), [INV-7]($_fromFeature#invariants)';
    expect(run.single.keys['fix'], twoLinks);
    expect(run.single.keys['targetPath'], 'docs/$_domain');
    expect(run.single.message, contains(twoLinks));
  });

  test("a cite_unlinked finding of a missing part names the doc's project "
      'path', () async {
    final findings = await _citesInFeature(
      'Users forget; `rulebook:login` INV-99.',
    );
    final keys = findings.single.keys;
    expect(keys['targetPath'], 'docs/$_domain');
    expect(keys, isNot(contains('fix')));
    expect(findings.single.message, contains('${keys['targetPath']} lacks'));
  });

  test('a cite_unlinked finding of an ambiguous cite has no targetPath and no '
      'fix key', () async {
    final findings = await _citeFindings({
      ..._subFeature,
      ...doc(loginFeature, _line, 'Users forget; see `login/sso`.'),
    });
    expect(findings.single.keys, {'value': 'login/sso'});
  });

  test('an ID beyond the run of a cite is no item of the cite', () async {
    final findings = await _citesInFeature(
      'Users forget (`rulebook:login`); with two targets it needs it (INV-6).',
    );
    expect(findings, hasLength(1));
    expect(findings.single.keys['value'], 'rulebook:login');
    expect(
      findings.single.message,
      contains('write it as [rulebook:login]($_fromFeature)'),
    );
    expect(findings.single.message, isNot(contains('[INV-6]')));
  });

  test(
    'a run of IDs and a range give one finding with one item link per ID',
    () async {
      final findings = await _citeFindings({
        'docs/$_domain':
            '# Login domain\n\n## Entities\n\n- Account\n\n'
            '## Invariants\n\n- **INV-6** An account holds one email.\n'
            '- **INV-7** A login is rate limited.\n'
            '- **INV-8** A session expires.\n',
        ...doc(
          loginFeature,
          _line,
          'Users forget; `rulebook:login` INV-6 and INV-7 to INV-8.',
        ),
      });
      expect(findings, hasLength(1));
      expect(
        findings.single.message,
        contains(
          '[INV-6]($_fromFeature#invariants), '
          '[INV-7]($_fromFeature#invariants), '
          '[INV-8]($_fromFeature#invariants)',
        ),
      );
    },
  );

  test("a prefixed one-word Name links that type's one doc", () async {
    final findings = await _citesInFeature('Users forget; see `gnfr:gnfr`.');
    expect(findings, hasLength(1));
    expect(findings.single.keys['value'], 'gnfr:gnfr');
    expect(findings.single.message, contains('[gnfr:gnfr](../../GNFR.md)'));
  });

  test("a singular type's layout path raises nothing; the same doc by a "
      'folder-relative path does', () async {
    expect(
      await _citesInFeature('Users forget; see `$goalDoc` and docs/$goalDoc.'),
      isEmpty,
    );
    final findings = await _citesInFeature(
      'Users forget; see `../../GOAL.md`.',
    );
    expect(findings, hasLength(1));
    expect(findings.single.keys['value'], '../../GOAL.md');
  });

  test("a project spec type's layout path raises nothing", () async {
    final findings = await _citeFindings({
      'docs/specs/DOMAIN.md': '# Project domain\n',
      ...doc(loginFeature, _line, 'Users forget; see `specs/DOMAIN.md`.'),
    });
    expect(findings, isEmpty);
  });

  test('a header span right after a path names its section', () async {
    final findings = await _citesInFeature(
      'Users forget; see `../../../specs/f01_login/ARCHITECTURE.md` `## Components`.',
    );
    expect(findings, hasLength(1));
    expect(
      findings.single.message,
      contains(
        '[architecture:login](../../../specs/f01_login/ARCHITECTURE.md#components)',
      ),
    );
  });

  test('a no-lookup name that resolves to no doc gives doc_name_unresolved, '
      'never cite_unlinked', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: {
          ..._domainFile,
          ...doc(loginFeature, _line, 'Users forget; see `login/nowhere`.'),
        },
      ),
    );
    expect([
      for (final f in report.findings) f.kind,
    ], contains(FindingKind.docNameUnresolved));
    expect([
      for (final f in report.findings) f.kind,
    ], isNot(contains(FindingKind.citeUnlinked)));
  });

  test(
    'a one-slug span or a path that resolves to no doc is plain text',
    () async {
      final findings = await _citesInFeature(
        'Users forget; `user_id` and `../nowhere/DOMAIN.md` are plain.',
      );
      expect(findings, isEmpty);
    },
  );

  test('a doc address inside a longer code span, such as a path in quoted '
      'bundle output, gives no cite_unlinked, while the same path outside '
      'a span does', () async {
    const header =
        '`==> login (rulebook) · $_domain#invariants · base 0123456789ab <==`';
    expect(await _citesInFeature('Users forget; $header.'), isEmpty);

    final findings = await _citesInFeature('Users forget; see $_domain here.');
    expect(findings, hasLength(1));
    expect(findings.single.keys['value'], _domain);
  });

  test('a span that is a code path, not a doc address, gives no '
      'cite_unlinked', () async {
    final findings = await _citesInFeature(
      'Users forget; code lives in `lib/src/journeys/` and `login.dart`.',
    );
    expect(findings, isEmpty);
  });

  test('a link, frontmatter, fenced code, a mermaid block, and a Concerns '
      'see target give none', () async {
    final findings = await _citeFindings({
      ...doc(
        loginFeature,
        _line,
        'Users forget; see [the rules]($_fromFeature#invariants).\n\n'
        '```\n`gnfr` INV-6\n```\n\n'
        '```mermaid\nflowchart LR\n  a["`gnfr`"] --> b\n```',
      ),
      concernsLayerFile: concernsLayer,
      ...edit(loginArchitecture, [
        (
          '# Login architecture\n',
          '---\nnote: "`gnfr`"\n---\n\n# Login architecture\n',
        ),
        (
          'Takes the form |\n',
          'Takes the form |\n\n## Concerns\n\n- Errors: see `DOMAIN.md`\n',
        ),
      ]),
    });
    expect(findings, isEmpty);
  });

  test(
    'a bare S<N> to the doc own story, plain or in a code span, gives none',
    () async {
      final findings = await _citeFindings(
        fr(
          'A wrong password must not sign in.',
          'A wrong password must not sign in (S2, `S1`).',
        ),
      );
      expect(findings, isEmpty);
    },
  );

  test('item IDs one doc holds in two sections name one item link each, '
      'never a missing part', () async {
    final findings = await _citeFindings({
      ...doc(
        loginFeature,
        _line,
        'Users forget; `gnfr:gnfr` NFR-P01 and NFR-Sec01.',
      ),
      ...doc(
        gnfrDoc,
        '## Security\n\nN/A — none applies.\n',
        '## Security\n\n### NFR-Sec01 — No plain text\n\nHashed.\n',
      ),
    });
    expect(findings, hasLength(1));
    expect(
      findings.single.message,
      contains(
        '[NFR-P01](../../GNFR.md#performance), '
        '[NFR-Sec01](../../GNFR.md#security)',
      ),
    );
    expect(findings.single.message, isNot(contains('lacks')));
  });

  test('typed and story spans with a #key give cite_unlinked, never '
      'doc_name_unresolved, whether the doc holds the key or not', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: {
          ..._domainFile,
          ...doc(
            loginFeature,
            _line,
            'Users forget; `feature:login`, '
            '`login/email_login#acceptance_criteria`, and '
            '`login/email_login#nowhere`.',
          ),
        },
      ),
    );
    expect(
      [
        for (final f in report.findings)
          if (f.kind == FindingKind.citeUnlinked) f.keys['value'],
      ],
      ['feature:login', 'login/email_login', 'login/email_login'],
    );
    expect(
      report.findings.map((f) => f.kind),
      isNot(contains(FindingKind.docNameUnresolved)),
    );
  });

  test(
    'a #key the one doc lacks gives cite_unlinked naming the section',
    () async {
      final findings = await _citesInFeature(
        'Users forget; `rulebook:login#nowhere`.',
      );
      expect(findings, hasLength(1));
      expect(findings.single.keys['value'], 'rulebook:login');
      expect(findings.single.message, contains(_domain));
      expect(findings.single.message, contains('lacks section nowhere'));
    },
  );

  test('a #key of a section the doc holds gives cite_unlinked linking that '
      'section', () async {
    final findings = await _citesInFeature(
      'Users forget; `rulebook:login#invariants`.',
    );
    expect(findings, hasLength(1));
    expect(
      findings.single.message,
      contains('write it as [rulebook:login]($_fromFeature#invariants)'),
    );
  });

  test('a name under no feature slug gives neither cite_unlinked nor '
      'doc_name_unresolved', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: {
          ..._domainFile,
          ...doc(
            loginFeature,
            _line,
            'Users forget; see `nowhere/email_login`.',
          ),
        },
      ),
    );
    final kinds = report.findings.map((f) => f.kind);
    expect(kinds, isNot(contains(FindingKind.citeUnlinked)));
    expect(kinds, isNot(contains(FindingKind.docNameUnresolved)));
  });

  test('a resolving mention in frontmatter, fenced code, a mermaid block, or '
      'a code root file gives no cite_unlinked', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: {
          ..._domainFile,
          ...edit(loginFeature, [
            (
              'summary: Lets an agent sign in.',
              'summary: Lets in `rulebook:login` INV-6.',
            ),
            (
              _line,
              'Users forget.\n\n```\n`rulebook:login` INV-6\n```\n\n'
                  '```mermaid\nflowchart LR\n  N[rulebook:login INV-6]\n```',
            ),
          ]),
          'app/lib/login.dart':
              '// See `rulebook:login` INV-6\nclass SignInPage {}\n\n'
              'bool checkPassword(String password) => password.isNotEmpty;\n',
        },
      ),
    );
    final kinds = report.findings.map((f) => f.kind);
    expect(kinds, isNot(contains(FindingKind.citeUnlinked)));
    expect(kinds, contains(FindingKind.docCitedInCode));
  });

  test(
    'a DocPath as the whole text of a code span gives cite_unlinked',
    () async {
      final findings = await _citesInFeature('Users forget; see `$_domain`.');
      expect(findings, hasLength(1));
      expect(findings.single.keys['value'], _domain);
    },
  );

  test("a per-target type's layout path of each target raises nothing, while "
      'a folder-relative path to one does', () async {
    final project = await writeTwinProject(
      extra: doc(
        loginFeature,
        _line,
        'Users forget; see `specs/flutter/TECH_STACK.md` and '
        'specs/jaspr/TECH_STACK.md and '
        '`../../../specs/flutter/TECH_STACK.md`.',
      ),
    );
    final findings = [
      for (final f in (await checkOf(project)).findings)
        if (f.kind == FindingKind.citeUnlinked) f,
    ];
    expect(
      [for (final f in findings) f.keys['value']],
      ['../../../specs/flutter/TECH_STACK.md'],
    );
  });

  test('a #key run and a comma-and run each give one cite_unlinked', () async {
    final domain = {
      'docs/$_domain':
          '# Login domain\n\n## Entities\n\n- Account\n\n'
          '## Invariants\n\n- **INV-6** An account holds one email.\n'
          '- **INV-7** A login is rate limited.\n'
          '- **INV-9** A session expires.\n',
    };
    final keyRun = await _citeFindings({
      ...domain,
      ...doc(
        loginFeature,
        _line,
        'Users forget; `rulebook:login#invariants` INV-6 and INV-7.',
      ),
    });
    expect(keyRun, hasLength(1));
    expect(keyRun.single.keys['value'], 'rulebook:login');
    expect(
      keyRun.single.message,
      contains(
        '[INV-6]($_fromFeature#invariants), [INV-7]($_fromFeature#invariants)',
      ),
    );

    final commaRun = await _citeFindings({
      ...domain,
      ...doc(
        loginFeature,
        _line,
        'Users forget; `rulebook:login` INV-6, INV-7, and INV-9.',
      ),
    });
    expect(commaRun, hasLength(1));
    expect(commaRun.single.keys['value'], 'rulebook:login');
    expect(
      commaRun.single.message,
      contains(
        '[INV-6]($_fromFeature#invariants), [INV-7]($_fromFeature#invariants), '
        '[INV-9]($_fromFeature#invariants)',
      ),
    );
  });

  test('an untyped doc gives no finding', () async {
    final findings = await _citeFindings({
      'docs/prds/notes.md':
          '# Notes\n\nSee `gnfr` and `rulebook:login` INV-6.\n',
    });
    expect(findings, isEmpty);
  });

  group('a skip line of a listed feature pattern', () {
    /// The login feature listing [patterns] and holding [skip] under its
    /// Out-of-scope section, beside a story the span `crud/paged_list` names.
    Future<List<Finding>> citesWithSkip(
      String skip, {
      List<String> patterns = const ['crud'],
    }) => _citeFindings({
      '.specstone/templates/feature.yaml':
          'fields:\n  - id: patterns\n    type: string\n    list: true\n',
      'docs/prds/features/f02_crud/FEATURE.md': '# Crud\n',
      'docs/prds/features/f02_crud/us01_paged_list/USER_STORY.md':
          '# Paged list\n',
      ...edit(loginFeature, [
        (
          'goals:\n  - PG-01\n',
          'goals:\n  - PG-01\npatterns:\n'
              '${[for (final id in patterns) '  - $id\n'].join()}',
        ),
        (
          '- Social sign-in — not planned\n',
          '- Social sign-in — not planned\n$skip\n',
        ),
      ]),
    });

    test('a skip line of a listed pattern is no cite candidate', () async {
      final findings = await citesWithSkip(
        '- `crud/paged_list` — one page is enough',
      );
      expect(findings, isEmpty);
    });

    test('the same span in a feature that does not list the pattern '
        'still gives cite_unlinked', () async {
      final findings = await citesWithSkip(
        '- `crud/paged_list` — one page is enough',
        patterns: const [],
      );
      expect([for (final f in findings) f.keys['value']], ['crud/paged_list']);
    });

    test('guard: a hyphen separator makes it no skip line, so its span is '
        'a cite', () async {
      final findings = await citesWithSkip(
        '- `crud/paged_list` - one page is enough',
      );
      expect([for (final f in findings) f.keys['value']], ['crud/paged_list']);
    });

    test('guard: a double hyphen separator makes it no skip line, so its '
        'span is a cite', () async {
      final findings = await citesWithSkip(
        '- `crud/paged_list` -- one page is enough',
      );
      expect([for (final f in findings) f.keys['value']], ['crud/paged_list']);
    });
  });

  test('a one-doc check scope reports the cites of that doc', () async {
    final project = await writeCheckProject(
      extra: {
        ..._domainFile,
        ...doc(loginFeature, _line, 'Users forget; `rulebook:login` INV-6.'),
      },
    );
    final report = await checkOf(project, docPath: loginFeature);
    expect(spots(report, FindingKind.citeUnlinked), [
      '$loginFeature:$_lineNumber: cite_unlinked',
    ]);
  });
}
