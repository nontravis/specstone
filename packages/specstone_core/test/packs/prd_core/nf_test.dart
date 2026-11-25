import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart' as check;
import '../../helpers/pattern_findings.dart';
import '../../helpers/prd_core.dart';

void main() {
  late MergedDocType nf;
  setUpAll(() async {
    nf = prdCoreDocType(await resolvePrdCore(), 'nf');
  });

  test('nf sits under its story folder with parent user_story, '
      'its fields, and four sections', () {
    expect(
      nf.path,
      'prds/features/f{nn}_{slug}/us{nn}_{slug}/nf{nn}_{slug}.md',
    );
    expect(nf.parent, 'user_story');
    expectOwnFields(nf, const [
      FieldSpec(
        'kind',
        FieldType.enumType,
        required: true,
        enumValues: ['tighten', 'relax', 'add'],
      ),
      FieldSpec('overrides', FieldType.string),
      FieldSpec('traced_from', FieldType.string, list: true),
      FieldSpec(
        'verify_method',
        FieldType.enumType,
        required: true,
        enumValues: ['test', 'analysis', 'inspection', 'demonstration'],
      ),
      FieldSpec('owner', FieldType.string),
      FieldSpec('confirmed', FieldType.string, list: true),
    ]);
    expectStatusValues(nf, ['planned', 'implemented', 'deprecated']);
    expectSections(nf, const [
      SectionSpec('statement', 'Statement', required: true),
      SectionSpec('rationale', 'Rationale', required: true),
      SectionSpec('verification', 'Verification', required: true),
      SectionSpec('tbr', 'TBR'),
    ]);
  });

  test('nf lints the 29 NASA words on '
      'the Statement section only, and the NASA handbook', () {
    expectNasaLint(nf, sections: ['statement']);
  });

  test('no starter template holds a listed word', () {
    expectTemplatesFreeOfListedWords(nf);
  });

  test('nf marks statement summary', () {
    expect(
      [
        for (final s in nf.sections)
          if (s.summary == true) s.id,
      ],
      ['statement'],
    );
  });

  group('trace and verification entries', () {
    const hits = <String>[
      'The system shall sign in within 1 s, as `S2` asks.',
      'The system shall sign in within 1 s per NFR-Pe01.',
      'The system shall sign in within 1 s per PG-01.',
      'The system shall sign in within 1 s per ISO 25010.',
      'The system shall sign in within 1 s per ISO/IEC 25010.',
    ];
    const passes = <String>[
      'The system shall sign in within 1 s.',
      'The system shall sign in within 1 s on 2 CPUs.',
    ];

    test('the Statement flags an ID or a standard cite and passes the '
        'others', () async {
      Future<List<String>> flagged(List<String> lines) => bannedLines(
        check.edit(check.loginNf, [
          ('The system shall sign in within 1 s.', lines.join('\n')),
        ]),
        check.loginNf,
        'trace_outside_field',
      );

      expect(await flagged(hits), hits);
      expect(await flagged(passes), isEmpty);
    });

    test('the same cite in the Rationale and in a fenced block gives no '
        'finding', () async {
      final found = await bannedLines(
        check.edit(check.loginNf, [
          (
            'Users wait.',
            'Users wait per NFR-Pe01 and ISO 25010.\n\n```text\n'
                'The system shall sign in per S2.\n```',
          ),
        ]),
        check.loginNf,
        'trace_outside_field',
      );

      expect(found, isEmpty);
    });

    test('a Verification with no Level line gives pattern_missing '
        'level_line', () async {
      Future<List<String>> missing(String verification) => missingPatterns(
        check.edit(check.loginNf, [(check.verificationLines, verification)]),
        check.loginNf,
      );

      expect(await missing(check.verificationLines), isEmpty);
      expect(await missing('- **Pass criteria:** a timed sign-in.\n'), [
        'level_line',
      ]);
    });
  });

  test('an nf doc with no traced_from gives no field finding', () async {
    Future<List<String>> found(List<(String, String)> changes) async {
      final report = await check.checkOf(
        await check.writeCheckProject(
          extra: check.edit(check.loginNf, changes),
        ),
      );
      return [
        for (final f in report.findings)
          if (f.path == check.loginNf &&
              (f.toJson()['field'] == 'traced_from' ||
                  f.toJson()['field'] == 'verify_method'))
            '${f.kind.wire} ${f.toJson()['field']}',
      ];
    }

    expect(await found(const []), isEmpty);
    expect(await found(const [('verify_method: test\n', '')]), [
      'required_field_missing verify_method',
    ]);
  });
}
