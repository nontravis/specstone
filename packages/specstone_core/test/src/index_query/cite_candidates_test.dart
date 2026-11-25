import 'dart:convert';

import 'package:specstone_core/src/consistency_check/finding.dart'
    show FindingKind;
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/index_query/cite_candidates.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_words.dart'
    show itemIdPrefixesOf;
import 'package:specstone_core/src/index_query/models/cite_candidate.dart';
import 'package:specstone_core/src/setup_migration/project_files.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart'
    show checkOf, loginRecord, spots, writeCheckProject;
import '../../helpers/record_doc_type.dart';
import '../../helpers/rulebook_fixture.dart';

/// The item ID prefixes of the shipped packs.
final Set<String> _idPrefixes = itemIdPrefixesOf(
  TemplateResolver()
      .resolveCarried(
        packNames: const ['prd-core', 'software-tech'],
        homeDirectory: null,
        projectLayers: parseOverrides(rulebookLayers),
      )
      .docTypes,
);

/// The cite candidates of [lf], one per cite form.
List<CiteCandidate> _candidatesOf(String lf, {Set<int> skipLines = const {}}) =>
    [
      for (final form in citeFormsOf(
        lf,
        idPrefixes: _idPrefixes,
        skipLines: skipLines,
      ))
        form.candidate,
    ];

/// Each candidate of [lf] as `(line, written, sectionKey, item IDs)`, the IDs
/// joined by a space, so a record compares by value.
List<(int, String, String?, String)> _readAll(String lf) => [
  for (final c in _candidatesOf(lf))
    (c.line, c.written, c.sectionKey, c.itemIds.join(' ')),
];

/// A doc whose body starts at file line 6, after a 3-line frontmatter.
String _doc(String body) => '---\nstatus: planned\n---\n\n# T\n$body';

const _recordPath = 'specs/f01_feedback/IMPLEMENTATION.md';

/// A record doc type with no matrix section.
final MergedDocType _plainRecordType = recordDocType(sections: const []);

final MergedDocType _matrixRecordType = recordDocType();

/// A record text whose matrix section holds [rows], the first on file line 5.
String _matrixRecord(String rows) =>
    '# Feedback implementation\n\n## Verification matrix\n\n$rows';

/// Parses the record [lf] as a doc of [type].
ParsedDoc _record(String lf, {MergedDocType? type}) => parseIndexedDoc(
  docPath: _recordPath,
  bytes: utf8.encode(lf),
  match: DocTypeMatcher(
    MergedSet(docTypes: [type ?? _matrixRecordType]),
    targetNames: const [],
  ).match(_recordPath),
  idPrefixes: _idPrefixes,
);

void main() {
  group('citeFormsOf', () {
    test('a prefixed address and a path are candidates, a lone-word span is '
        'not', () {
      final read = _readAll(
        _doc(
          '`rulebook:login`\n'
          '`login`\n'
          'See ../f01_login/DOMAIN.md here.\n'
          '`../f01_login/DOMAIN.md`\n',
        ),
      );
      expect(read, [
        (6, 'rulebook:login', null, ''),
        (8, '../f01_login/DOMAIN.md', null, ''),
        (9, '../f01_login/DOMAIN.md', null, ''),
      ]);
    });

    test('the #key of a name span and of a '
        'path is its section key, and the written text leaves it out', () {
      final read = _readAll(
        _doc(
          '`feature:login#problem` and `charter:doc_model#rules`\n'
          '`../f01_login/DOMAIN.md#invariants` then ../a/B.md#rules.\n',
        ),
      );
      expect(read, [
        (6, 'feature:login', 'problem', ''),
        (6, 'charter:doc_model', 'rules', ''),
        (7, '../f01_login/DOMAIN.md', 'invariants', ''),
        (7, '../a/B.md', 'rules', ''),
      ]);
    });

    test('a section header in a code span right '
        'after a path is its section key', () {
      final read = _readAll(
        _doc('`../f01_login/ERROR.md` `## Error envelope` stays.\n'),
      );
      expect(read, [(6, '../f01_login/ERROR.md', 'error_envelope', '')]);
    });

    test('a name and an ID farther along the line after other text make a '
        'doc cite with no item ID', () {
      final read = _readAll(
        _doc(
          'a feature status is the computed one '
          '(`index_query/view_docs_tree/compute_status`); with two or more '
          'targets it needs `--target` (E10)\n',
        ),
      );
      expect(read, [
        (6, 'index_query/view_docs_tree/compute_status', null, ''),
      ]);
    });

    test('the item IDs right after a candidate are its own run', () {
      final read = _readAll(
        _doc(
          '`rulebook:login` INV-6 and INV-7, '
          'then `charter:doc_model` RULE-12.\n'
          '`a/b` see `c/d` RULE-7 and NFR-P01\n'
          '(`DOMAIN.md` INV-6)\n'
          '`a/b` INV-1 [l](../x.md) INV-2\n',
        ),
      );
      expect(read, [
        (6, 'rulebook:login', null, 'INV-6 INV-7'),
        (6, 'charter:doc_model', null, 'RULE-12'),
        (7, 'a/b', null, ''),
        (7, 'c/d', null, 'RULE-7 NFR-P01'),
        (8, 'DOMAIN.md', null, 'INV-6'),
        (9, 'a/b', null, 'INV-1'),
      ]);
    });

    test('a link or any other text after a run ends it', () {
      final read = _readAll(
        _doc(
          '`rulebook:login` INV-6, see ![d](d.png) INV-7 [f](f.dart) INV-8 '
          '<https://x.dev> INV-9\n'
          '`a/b` INV-1 [l](../x.md) INV-2 [s](#top) INV-3\n',
        ),
      );
      expect(read, [
        (6, 'rulebook:login', null, 'INV-6'),
        (7, 'a/b', null, 'INV-1'),
      ]);
    });

    test(
      'a token of no prefix right after a candidate gives it no item ID',
      () {
        expect(
          _readAll(_doc('`gnfr:gnfr` UTF-8, SHA256, Base64 and NFR-P01\n')),
          [(6, 'gnfr:gnfr', null, '')],
        );
      },
    );

    test('a #key or a header span after a path, then IDs, gives the run after '
        'the key', () {
      final read = _readAll(
        _doc(
          '`../f01_login/DOMAIN.md#invariants` INV-6 and INV-7\n'
          '`../f01_login/ERROR.md` `## Error envelope` E3, E4\n',
        ),
      );
      expect(read, [
        (6, '../f01_login/DOMAIN.md', 'invariants', 'INV-6 INV-7'),
        (7, '../f01_login/ERROR.md', 'error_envelope', 'E3 E4'),
      ]);
    });

    test('an ID at the start of the next line of the same paragraph gives the '
        'candidate no item ID', () {
      expect(_readAll(_doc('`rulebook:login`\nINV-6 follows\n')), [
        (6, 'rulebook:login', null, ''),
      ]);
    });

    test('a lone-word span ends the run, so the ID after it is no item of '
        'the cite', () {
      expect(_readAll(_doc('`rulebook:login` INV-6 and `goal` INV-3.\n')), [
        (6, 'rulebook:login', null, 'INV-6'),
      ]);
    });

    test('a lettered ID makes no item ID', () {
      expect(_readAll(_doc('`a/b` RULE-7a and RULE-8\n')), [
        (6, 'a/b', null, 'RULE-8'),
      ]);
    });

    test('fenced code, a link, its text, a '
        'reference definition, a scenario ref, and frontmatter give none', () {
      final read = _readAll(
        '---\nnote: `rulebook:login`\n---\n\n# T\n'
        '```\n`rulebook:login` ../a/B.md\n```\n'
        '[l](../a/B.md) and [`a/b`](../a/B.md#x)\n'
        '\n[ref]: ../a/B.md\n\n'
        '`S1` and `not a name`\n',
      );
      expect(read, isEmpty);
    });

    test(
      'a doc address inside a longer code span gives none, while a span '
      'that is the whole address, with its #key, and a plain path give one',
      () {
        final read = _readAll(
          _doc(
            '`==> login (rulebook) · ../f01_login/DOMAIN.md#invariants · base 01 <==`\n'
            '`see ../f01_login/DOMAIN.md now` and `lib/src/journeys/`\n'
            '`rulebook:login#invariants`\n'
            'See ../f01_login/DOMAIN.md here.\n',
          ),
        );
        expect(read, [
          (8, 'rulebook:login', 'invariants', ''),
          (9, '../f01_login/DOMAIN.md', null, ''),
        ]);
      },
    );

    test('a doc without a backtick or a .md '
        'path gives none', () {
      expect(_readAll('# T\n\nPlain text, INV-1.\n'), isEmpty);
    });

    test('a line in skipLines gives no candidate, any other line does', () {
      final lf = _doc(
        '`rulebook:login`\n`charter:doc_model`\n`feature:login`\n',
      );
      final read = _candidatesOf(lf, skipLines: const {6, 8});
      expect([for (final c in read) c.written], ['charter:doc_model']);
    });
  });

  group('a record matrix', () {
    /// The candidates `check` reads from the record [lf]: the ones the index
    /// stores for its doc.
    List<(int, String)> candidatesOf(String lf) => [
      for (final c in _record(lf).content.lineFacts.citeCandidates)
        (c.line, c.written),
    ];

    test("a test row's span in the record matrix is no cite candidate", () {
      final read = candidatesOf(
        _matrixRecord(
          '- show_toast E01: `login/email_login`\n'
          '- show_toast E02: `rulebook:login`\n',
        ),
      );
      expect(read, isEmpty);
    });

    test('reads no cite candidate in any span of a per-FR test row', () {
      final read = candidatesOf(
        _matrixRecord(
          '- show_toast: `login/email_login`, `rulebook:login`\n'
          '- show_toast/pin_toast: `charter:doc_model`\n',
        ),
      );
      expect(read, isEmpty);
    });

    test('a span outside the matrix, a skip row, and a line that is no row '
        'still give their candidates', () {
      final read = candidatesOf(
        _matrixRecord(
          '- show_toast E01: `rulebook:login`\n'
          '- show_toast E02 skipped: it needs `charter:doc_model`\n'
          '- see `feature:login` here\n'
          '\n'
          '## Notes\n'
          '\n'
          'See `rulebook:login`.\n',
        ),
      );
      expect(read, [
        (6, 'charter:doc_model'),
        (7, 'feature:login'),
        (11, 'rulebook:login'),
      ]);
    });

    test('a doc type without a matrix section keeps the span of a row-shaped '
        'line', () {
      final read = [
        for (final c in _record(
          _matrixRecord('- show_toast E01: `rulebook:login`\n'),
          type: _plainRecordType,
        ).content.lineFacts.citeCandidates)
          (c.line, c.written),
      ];
      expect(read, [(5, 'rulebook:login')]);
    });

    test(
      'check reports no cite_unlinked for the literal of a test row that '
      'resolves to one doc, and one for the same span outside the matrix',
      () async {
        const record =
            "---\nstatuses:\n  - 'email_login:implemented'\n---\n\n"
            '# Login implementation\n\n'
            '## Verification matrix\n\n'
            '- email_login/check_password E01: `login/email_login`\n\n'
            '## Notes\n\n'
            'See `login/email_login`.\n';
        final report = await checkOf(
          await writeCheckProject(extra: {loginRecord: record}),
        );

        // The fixture's approval stamp adds one frontmatter line, so the span
        // outside the matrix sits on line 15.
        expect(spots(report, FindingKind.citeUnlinked), [
          '$loginRecord:15: cite_unlinked',
        ]);
      },
    );
  });
}
