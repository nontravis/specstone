import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:test/test.dart';

void main() {
  test('consistency_check: 57 snake_case kinds, no error code', () {
    expect(FindingKind.values.map((k) => k.wire), [
      'frontmatter_invalid',
      'required_field_missing',
      'field_group_missing',
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
      'feature_mixed_children',
      'sub_feature_too_small',
      'nesting_over_limit',
      'path_over_limit',
      'file_not_utf8',
      'file_unreadable',
      'pattern_banned',
      'pattern_missing',
      'item_id_missing',
      'item_id_duplicate',
      'item_id_lettered',
      'implements_path_unresolved',
      'implements_symbol_unresolved',
      'covers_path_missing',
      'code_root_missing',
      'code_uncovered',
      'doc_ref_unresolved',
      'doc_ref_duplicate',
      'doc_ref_self',
      'link_unresolved',
      'link_anchor_missing',
      'link_self',
      'reference_malformed',
      'link_target_missing',
      'markdown_unparsed',
      'doc_name_unresolved',
      'number_label',
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
      'goal_serves_missing',
      'fr_trace_unresolved',
      'architecture_missing',
      'implements_missing',
      'suspect',
      'unconfirmed',
      'confirmed_entry_malformed',
      'confirmed_entry_stale',
      'format_drift',
      'agent_block_stale',
      'tbr_open',
      'approval_stale',
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
      [
        FindingKind.codeUncovered,
        FindingKind.referenceDocUnresolved,
        FindingKind.agentBlockStale,
      ],
    );
  });

  test('consistency_check/find_template_breaks/print_findings: every kind '
      'waits for the Owner or the Agent, the Owner only for the kinds the '
      'Output lists', () {
    const owner = {
      FindingKind.approvalStale,
      FindingKind.charsOverLimit,
      FindingKind.linesOverLimit,
      FindingKind.tbrOpen,
    };
    for (final kind in FindingKind.values) {
      expect(
        kind.waitsFor,
        owner.contains(kind) ? WaitsFor.owner : WaitsFor.agent,
        reason: kind.wire,
      );
    }
    expect(WaitsFor.values.map((w) => w.wire), ['owner', 'agent']);
  });

  test('consistency_check/find_template_breaks/print_findings: a finding '
      'takes the waitsFor of its kind unless a rule sets it', () {
    const byKind = Finding(
      kind: FindingKind.unconfirmed,
      path: 'a.md',
      line: 1,
      message: 'm',
    );
    const byRule = Finding(
      kind: FindingKind.unconfirmed,
      path: 'a.md',
      line: 1,
      message: 'm',
      waitsFor: WaitsFor.owner,
    );
    expect(byKind.waitsFor, WaitsFor.agent);
    expect(byRule.waitsFor, WaitsFor.owner);
  });

  test('consistency_check/find_template_breaks/print_findings E08: an owner '
      'finding ends its line with the tag; its JSON holds waitsFor after '
      'message and no tag in the message', () {
    const finding = Finding(
      kind: FindingKind.approvalStale,
      path: 'prds/a.md',
      name: 'a',
      line: 3,
      message: 'waits',
    );
    expect(finding.textLines, [
      'prds/a.md:3: approval_stale: waits (waits for the Owner)',
    ]);
    expect(finding.toJson().keys, [
      'kind',
      'docPath',
      'name',
      'line',
      'message',
      'waitsFor',
    ]);
    expect(finding.toJson()['message'], 'waits');
    expect(finding.toJson()['waitsFor'], 'owner');
    expect(
      CheckReport(findings: const [finding]).text,
      'prds/a.md:3: approval_stale: waits (waits for the Owner)\n1 finding\n',
    );
  });

  test('consistency_check/find_template_breaks/print_findings: a finding with '
      'a text key prints the block indented 4 spaces, an empty line as exactly '
      '4 spaces, then the fingerprint last', () {
    const finding = Finding(
      kind: FindingKind.suspect,
      path: 'prds/a.md',
      line: 3,
      message: 'read it',
      keys: {
        'text': '### Scenario 2\n\nfingerprint 000000000000 in the block',
        'fingerprint': '9a1c03be55d2',
      },
    );
    expect(finding.textLines, [
      'prds/a.md:3: suspect: read it',
      '    ### Scenario 2',
      '    ',
      '    fingerprint 000000000000 in the block',
      '    fingerprint 9a1c03be55d2',
    ]);
  });

  test('consistency_check/find_template_breaks/print_findings: a '
      'reference_malformed finding keeps its own text key off the printed '
      'lines', () {
    const finding = Finding(
      kind: FindingKind.referenceMalformed,
      path: 'prds/a.md',
      line: 3,
      message: 'bad',
      keys: {'form': 'item_id', 'text': 'FR-01'},
    );
    expect(finding.textLines, ['prds/a.md:3: reference_malformed: bad']);
  });

  test('consistency_check/find_template_breaks/print_findings: a finding with '
      'no text key prints its line alone', () {
    const finding = Finding(
      kind: FindingKind.unconfirmed,
      path: 'prds/a.md',
      line: 3,
      message: 'waits',
      waitsFor: WaitsFor.owner,
      keys: {'fingerprint': '9a1c03be55d2'},
    );
    expect(finding.textLines, [
      'prds/a.md:3: unconfirmed: waits (waits for the Owner)',
    ]);
  });

  test('consistency_check/find_template_breaks/print_findings: an agent '
      'finding carries no tag, and its JSON waitsFor sits before the '
      'keys of its kind', () {
    const finding = Finding(
      kind: FindingKind.bannedWord,
      path: 'a.md',
      line: 2,
      message: 'm',
      keys: {'word': 'w'},
    );
    expect(finding.textLines, ['a.md:2: banned_word: m']);
    expect(finding.toJson().keys, [
      'kind',
      'docPath',
      'line',
      'message',
      'waitsFor',
      'word',
    ]);
    expect(finding.toJson()['waitsFor'], 'agent');
  });

  test('consistency_check/find_template_breaks/print_findings E12: an owner '
      'finding counts and exits 1 as any other', () {
    final report = CheckReport(
      findings: const [
        Finding(
          kind: FindingKind.approvalStale,
          path: 'a.md',
          line: 1,
          message: 'm',
        ),
      ],
    );
    expect(report.exitStatus, 1);
    expect(report.json['count'], 1);
    expect(report.text.split('\n').reversed.skip(1).first, '1 finding');
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
      'waitsFor': 'agent',
    });
    final report = CheckReport(
      findings: const [finding],
      warnings: const ['w'],
    );
    expect(report.text, 'prds/d01_context.md:1: untyped_doc: m\n1 finding\n');
    expect(report.json['warnings'], ['w']);
  });
}
