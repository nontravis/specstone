import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';

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
const _lineNumber = 13;

/// The path from the login feature to the login domain.
const _fromFeature = '../../../specs/f01_login/DOMAIN.md';

Future<List<Finding>> _citeFindings(Map<String, String> extra) async {
  final report = checkOf(
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
  test('f04/us02/fr08/e01, f04/us02/s20: a typed name and an item ID its doc holds gives cite_unlinked at its line, naming the link', () async {
    final findings = await _citesInFeature(
      'Users forget; `domain:login` INV-6.',
    );
    expect(findings, hasLength(1));
    final finding = findings.single;
    expect(finding.path, loginFeature);
    expect(finding.line, _lineNumber);
    expect(finding.waitsFor, WaitsFor.agent);
    expect(finding.keys, {'cite': 'domain:login'});
    expect(finding.message, contains('[INV-6]($_fromFeature#invariants)'));
  });

  test('f04/us02/fr08/e01: a token shaped like an ID but of no doc type prefix, such as SHA256 or UTF-8, is no item ID', () async {
    final findings = await _citesInFeature(
      'Users forget; `domain:login` with SHA256 and UTF-8.',
    );
    expect(findings, hasLength(1));
    expect(
      findings.single.message,
      contains('write it as [domain:login]($_fromFeature)'),
    );
  });

  test('f04/us02/fr08/e02, f04/us02/s21: a one-slug span that resolves counts, a field name that resolves to no doc does not', () async {
    final findings = await _citesInFeature(
      'Users forget; see `gnfr` and the `user_id` field.',
    );
    expect([for (final f in findings) f.keys['cite']], ['gnfr']);
  });

  test('f04/us02/fr08/e02: a one-slug name with a #key counts; a cite of the doc itself links by its anchor', () async {
    final findings = await _citesInFeature(
      'Users forget; see `login#problem`.',
    );
    expect([for (final f in findings) f.keys['cite']], ['login']);
    expect(findings.single.message, contains('[login](#problem)'));
  });

  test('f04/us02/fr08/e03: a path in a code span, a plain path, and a sibling file name each count', () async {
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
      [for (final f in findings) (f.path, f.keys['cite'])],
      [
        (loginFeature, _fromFeature),
        (loginFeature, _fromFeature),
        (loginApi, 'DOMAIN.md'),
      ],
    );
    expect(findings.last.message, contains('[INV-6](DOMAIN.md#invariants)'));
  });

  test('f04/us02/fr08/e04, f04/us02/s22: a shared name settled by an item ID gives one finding linking that item', () async {
    final findings = await _citesInFeature('Users forget; `login` INV-6.');
    expect(findings, hasLength(1));
    expect(findings.single.keys, {'cite': 'login'});
    expect(
      findings.single.message,
      contains('[INV-6]($_fromFeature#invariants)'),
    );
  });

  test('f04/us02/fr08/e05: a shared name with no #key or item ID still gives cite_unlinked, naming the docs it may mean', () async {
    final findings = await _citesInFeature('Users forget; see `login`.');
    expect(findings, hasLength(1));
    expect(findings.single.keys, {'cite': 'login'});
    expect(findings.single.message, contains('5 docs'));
    expect(findings.single.message, contains('[text](<path>)'));
  });

  test(
    'f04/us02/fr08/e06: an item ID the one doc lacks still gives cite_unlinked',
    () async {
      final findings = await _citesInFeature(
        'Users forget; `domain:login` INV-99.',
      );
      expect(findings, hasLength(1));
      expect(findings.single.message, contains(_domain));
      expect(findings.single.message, contains('INV-99'));
    },
  );

  test('f04/us02/fr08/e07: a one-slug Name equal to a doc type id links that type one doc', () async {
    final findings = await _citesInFeature(
      'Users forget; see `project`, `gnfr`, and `tech_stack`.',
    );
    // Findings on one line sort by message, so the cites read unordered.
    expect([
      for (final f in findings) f.keys['cite'],
    ], unorderedEquals(['project', 'gnfr', 'tech_stack']));
    expect(
      [for (final f in findings) f.message],
      containsAll([
        contains('[project](../../PROJECT.md)'),
        contains('[gnfr](../../GNFR.md)'),
        contains('[tech_stack](../../../specs/TECH_STACK.md)'),
      ]),
    );
  });

  test(
    'f04/us02/fr08/e08: a header span right after a path names its section',
    () async {
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
    },
  );

  test('f04/us02/fr08/e09: a no-lookup name that resolves to no doc gives doc_name_unresolved, never cite_unlinked', () async {
    final report = checkOf(
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

  test('f04/us02/fr08/e10: a one-slug span or a path that resolves to no doc is plain text', () async {
    final findings = await _citesInFeature(
      'Users forget; `user_id` and `../nowhere/DOMAIN.md` are plain.',
    );
    expect(findings, isEmpty);
  });

  test('f04/us02/fr08/e11: a link, frontmatter, fenced code, a mermaid block, and a Concerns see target give none', () async {
    final findings = await _citeFindings({
      ...doc(
        loginFeature,
        _line,
        'Users forget; see [the rules]($_fromFeature#invariants).\n\n'
        '```\n`gnfr` INV-6\n```\n\n'
        '```mermaid\nflowchart LR\n  a["`gnfr`"] --> b\n```',
      ),
      ...edit(loginArchitecture, [
        ('covers:\n', 'note: "`gnfr`"\ncovers:\n'),
        ('- Errors: see Components', '- Errors: see `DOMAIN.md`'),
      ]),
    });
    expect(findings, isEmpty);
  });

  test('f04/us02/fr08/e11: a bare S<N> to the doc own story, plain or in a code span, gives none', () async {
    final findings = await _citeFindings(
      fr(
        'A wrong password must not sign in.',
        'A wrong password must not sign in (S2, `S1`).',
      ),
    );
    expect(findings, isEmpty);
  });

  test('f04/us02/fr08/e01: item IDs one doc holds in two sections name one item link each, never a missing part', () async {
    final findings = await _citeFindings({
      ...doc(
        loginFeature,
        _line,
        'Users forget; `gnfr` NFR-P01 and NFR-Sec01.',
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

  test('f04/us02/fr08/e12: an untyped doc gives no finding', () async {
    final findings = await _citeFindings({
      'docs/prds/notes.md': '# Notes\n\nSee `gnfr` and `domain:login` INV-6.\n',
    });
    expect(findings, isEmpty);
  });

  test(
    'f04/us02/fr08: a one-doc check scope reports the cites of that doc',
    () async {
      final project = await writeCheckProject(
        extra: {
          ..._domainFile,
          ...doc(loginFeature, _line, 'Users forget; `domain:login` INV-6.'),
        },
      );
      final report = checkOf(project, docPath: loginFeature);
      expect(spots(report, FindingKind.citeUnlinked), [
        '$loginFeature:$_lineNumber: cite_unlinked',
      ]);
    },
  );
}
