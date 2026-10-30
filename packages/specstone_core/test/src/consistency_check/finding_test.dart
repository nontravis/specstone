import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:test/test.dart';

void main() {
  test('cc-s03/inv2: the 46 kinds of s02 Finding kinds, snake_case, equal to no Specstone error code', () {
    expect(FindingKind.values.map((k) => k.wire), [
      'frontmatter_invalid',
      'required_field_missing',
      'field_value_mismatch',
      'field_undeclared',
      'feature_status_written',
      'title_missing',
      'required_section_missing',
      'section_undeclared',
      'lines_over_limit',
      'chars_over_limit',
      'vision_quote_missing',
      'banned_word',
      'untyped_doc',
      'doc_type_ambiguous',
      'order_number_duplicate',
      'parent_ambiguous',
      'parent_missing',
      'file_not_utf8',
      'file_unreadable',
      'implements_path_unresolved',
      'implements_symbol_unresolved',
      'covers_path_missing',
      'code_root_missing',
      'code_uncovered',
      'doc_ref_unresolved',
      'link_unresolved',
      'markdown_unparsed',
      'reference_doc_unresolved',
      'listed_file_missing',
      'concerns_target_unresolved',
      'journey_step_unresolved',
      'journey_after_unresolved',
      'journey_step_duplicate',
      'scenario_trace_unresolved',
      'override_kind_mismatch',
      'override_unresolved',
      'role_unresolved',
      'vision_goal_widened',
      'vision_goal_unresolved',
      'fr_trace_unresolved',
      'architecture_missing',
      'implements_missing',
      'suspect',
      'unconfirmed',
      'confirmed_entry_malformed',
      'confirmed_entry_stale',
    ]);
    // document_writing/s05_errors.md's catalog, whose code F-04 does not import.
    const writeCodes = {
      'base_mismatch',
      'field_unknown',
      'field_value_invalid',
      'field_not_writable',
      'required_target',
      'doc_exists',
      'doc_referenced',
      'position_out_of_range',
      'doc_type_not_movable',
      'owner_terminal_required',
      'output_not_writable',
    };
    final codes = {
      for (final c in FaultCode.values) c.wire,
      for (final c in IndexFaultCode.values) c.wire,
      for (final c in RenderFaultCode.values) c.wire,
      ...writeCodes,
    };
    for (final kind in FindingKind.values) {
      expect(kind.wire, matches(RegExp(r'^[a-z][a-z0-9]*(_[a-z0-9]+)*$')));
      expect(codes, isNot(contains(kind.wire)));
    }
    expect(
      [
        for (final k in FindingKind.values)
          if (k.isProjectLevel) k,
      ],
      [FindingKind.codeUncovered, FindingKind.referenceDocUnresolved],
    );
  });

  test('f04/us01/fr02/e01: no finding prints 0 findings and exits 0', () {
    final report = CheckReport(findings: const []);
    expect(report.text, '0 findings\n');
    expect(report.json, {'findings': <Object>[], 'count': 0});
    expect(report.exitStatus, 0);
  });

  test('f04/us01/fr02/e02, cc-s03/inv14: findings sort by path, line, kind, then message', () {
    Finding at(String path, int line, FindingKind kind, String message) =>
        Finding(
          kind: kind,
          path: path,
          name: 'n',
          line: line,
          message: message,
        );
    final report = CheckReport(
      findings: [
        at('b.md', 1, FindingKind.titleMissing, 'm'),
        at('a.md', 12, FindingKind.bannedWord, 'm'),
        at('a.md', 4, FindingKind.untypedDoc, 'z'),
        at('a.md', 4, FindingKind.untypedDoc, 'a'),
        at('a.md', 4, FindingKind.bannedWord, 'm'),
      ],
    );
    expect(report.findings.map((f) => f.textLine), [
      'a.md:4: banned_word: m',
      'a.md:4: untyped_doc: a',
      'a.md:4: untyped_doc: z',
      'a.md:12: banned_word: m',
      'b.md:1: title_missing: m',
    ]);
    expect(report.text.split('\n').reversed.skip(1).first, '5 findings');
    expect(report.exitStatus, 1);
  });

  test('f04/us01/fr02/e03, f04/us01/fr02/e04: an untyped doc and a template file carry no name; warnings print '
      'only when there are some', () {
    const finding = Finding(
      kind: FindingKind.untypedDoc,
      path: 'prds/d01_context.md',
      line: 1,
      message: 'm',
    );
    expect(finding.toJson(), {
      'kind': 'untyped_doc',
      'docPath': 'prds/d01_context.md',
      'line': 1,
      'message': 'm',
    });
    final report = CheckReport(
      findings: const [finding],
      warnings: const ['w'],
    );
    expect(report.text, 'prds/d01_context.md:1: untyped_doc: m\n1 finding\n');
    expect(report.json['warnings'], ['w']);
  });
}
