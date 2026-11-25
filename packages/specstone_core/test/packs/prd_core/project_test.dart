import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart' as check;
import '../../helpers/pattern_findings.dart';
import '../../helpers/prd_core.dart';

void main() {
  late MergedDocType project;
  setUpAll(() async {
    project = prdCoreDocType(await resolvePrdCore(), 'project');
  });

  test('project sits at prds/PROJECT.md with no parent, an '
      'owner field, and four sections', () {
    expect(project.path, 'prds/PROJECT.md');
    expect(project.parent, isNull);
    expectOwnFields(project, const [
      FieldSpec('owner', FieldType.string, required: true),
    ]);
    expectStatusValues(project, ['planned', 'implemented', 'deprecated']);
    expectSections(project, const [
      SectionSpec('name', 'Project name', required: true),
      SectionSpec('vision', 'Project vision', prefixId: 'PV-', required: true),
      SectionSpec('roles', 'Role', required: true),
      SectionSpec('out_of_scope', 'Out-of-scope', required: true),
    ]);
  });

  test('the description states no number a lint key holds', () {
    final vision = sectionOf(project, 'vision');
    expect(sectionOf(project, 'name').description, isNot(contains('one line')));
    expect(vision.description, isNot(contains('15 words')));
    expect(vision.description, isNot(contains('one sentence each')));
    expect(vision.template, isNot(contains('15 words')));
    expect(vision.template, isNot(contains('one sentence')));
    final roles = sectionOf(project, 'roles');
    expect(roles.description, isNot(contains('one-line')));
    expect(roles.template, isNot(contains('one-line')));
  });

  test('name and roles carry their item line cap', () {
    for (final id in ['name', 'roles']) {
      expect(sectionOf(project, id).maxItemLines, 1, reason: id);
    }
  });

  test('the quote_words message states the cap alone', () {
    final quoteWords = sectionOf(
      project,
      'vision',
    ).bannedPatterns!.singleWhere((p) => p.id == 'quote_words');
    expect(quoteWords.message, 'quote over 15 words');
  });

  test('project sets bundle_refs, joins every bundle mode, and marks roles '
      'and out_of_scope query', () {
    expect(project.bundleRefs, isTrue);
    expect(project.bundle, ['query', 'implement', 'design']);
    expect(
      [
        for (final s in project.sections)
          if (s.query == true) s.id,
      ],
      ['roles', 'out_of_scope'],
    );
  });

  test('a Project name section with no Code line holding one code span gives '
      'pattern_missing code_line', () async {
    const codeLine = '- **Code:** `login_demo`';
    Future<List<String>> missing(String replacement) => missingPatterns(
      check.edit(check.projectDoc, [(codeLine, replacement)]),
      check.projectDoc,
    );

    expect(await missing(codeLine), isEmpty);
    expect(await missing('- **Code:** `a1_b2`'), isEmpty);
    expect(await missing(''), ['code_line']);
    expect(await missing('- Code: login_demo'), ['code_line']);
    expect(await missing('```text\n$codeLine\n```'), ['code_line']);
    expect(await missing('- **Code:** [`login_demo`](login.md)'), [
      'code_line',
    ]);
    expect(await missing('- **Code:** [login_demo](login.md)'), ['code_line']);
    expect(await missing('- **Code:** login_demo'), ['code_line']);
    expect(await missing('- **Code:** `login demo`'), ['code_line']);
    expect(await missing('- **Code:** `Login_demo`'), ['code_line']);
    expect(await missing('$codeLine and more'), ['code_line']);
  });

  test('a Code line with a trailing space, a tab, or a CRLF line end gives no '
      'pattern_missing', () async {
    const codeLine = '- **Code:** `login_demo`';
    Map<String, String> crlf(Map<String, String> files) => {
      for (final MapEntry(:key, :value) in files.entries)
        key: value.replaceAll('\n', '\r\n'),
    };
    final docs = {
      'a space': check.edit(check.projectDoc, [(codeLine, '$codeLine ')]),
      'a tab': check.edit(check.projectDoc, [(codeLine, '$codeLine\t')]),
      'a CRLF line end': crlf(
        check.edit(check.projectDoc, [(codeLine, codeLine)]),
      ),
    };

    for (final MapEntry(key: tail, value: files) in docs.entries) {
      expect(
        await missingPatterns(files, check.projectDoc),
        isEmpty,
        reason: tail,
      );
    }
  });

  test('the code_line entry reads the line as written and its message names '
      'the one code span and the guide line', () {
    final codeLine = sectionOf(
      project,
      'name',
    ).requiredPatterns!.singleWhere((p) => p.id == 'code_line');
    expect(codeLine.scope, PatternScope.all);
    expect(
      codeLine.message,
      'no Code line holding one code span; '
      'guide line: The Code line stays here',
    );
  });

  test('the vision template labels each entry line in English', () {
    final template = sectionOf(project, 'vision').template!;

    expect(
      template,
      allOf(
        contains('- **Why:** '),
        contains('- **Problem:** '),
        contains('- **Audience:** '),
      ),
    );
  });

  test('a vision quote at the word cap in a two-letter language gives no '
      'quote finding', () async {
    const quote = '> en: One sign-in for every app.';
    Future<List<String>> flagged(int words, String pattern) => bannedLines(
      check.edit(check.projectDoc, [
        (quote, '> en: ${List.filled(words, 'word').join(' ')}'),
      ]),
      check.projectDoc,
      pattern,
    );

    expect(await flagged(15, 'quote_words'), isEmpty);
    expect(await flagged(15, 'quote_language'), isEmpty);
    expect(await flagged(16, 'quote_words'), hasLength(1));
  });
}
