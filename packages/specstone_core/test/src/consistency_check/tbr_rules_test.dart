// The marker is built from parts so this file holds no stray marker text.

import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/tbr_rules.dart'
    show tbrValueLimit;
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';

const _name = 'consistency_check/find_template_breaks/report_open_tbrs';
const _dash = '—';
const _marker = 'TBR $_dash ';
const _openNoValue = 'the value is still to be resolved';
const _stillOpen = '$_openNoValue: ';
const _rationale = 'A wrong password must not sign in.';
const _nfRationale = 'Users wait.';
const _gnfrBlock = '- **Rationale:** Users wait.\n';

Future<({Directory project, List<Finding> found})> _run(
  Map<String, String> extra,
) async {
  final project = await writeCheckProject(extra: extra);
  return (
    project: project,
    found: [
      for (final finding in checkOf(project).findings)
        if (finding.kind == FindingKind.tbrOpen) finding,
    ],
  );
}

/// Returns the 1-based file line of the first line of [docPath] holding
/// [needle].
int _lineOf(Directory project, String docPath, String needle) {
  final lines = File('${project.path}/docs/$docPath').readAsLinesSync();
  return lines.indexWhere((line) => line.contains(needle)) + 1;
}

Map<String, String> _frWith(String replacement) =>
    doc(loginFr, _rationale, replacement);

Map<String, String> _frWithSection(String section, {String? status}) =>
    edit(loginFr, [
      (
        '## Verification\n\nTest: a wrong password is refused.\n',
        '## Verification\n\nTest: a wrong password is refused.\n\n$section',
      ),
      if (status != null) ('status: implemented', 'status: $status'),
    ]);

void main() {
  test('$_name: a project with no TBR gives no finding', () async {
    expect((await _run(const {})).found, isEmpty);
  });

  test('$_name E01: a marker after a bold label gives one marker finding '
      'at its line', () async {
    const text = '${_marker}legacy states none';
    final (:project, :found) = await _run(_frWith('- **Consistency:** $text'));

    expect(found, hasLength(1));
    final finding = found.single;
    expect(finding.path, loginFr);
    expect(finding.line, _lineOf(project, loginFr, _marker));
    expect(finding.keys, {'form': 'marker'});
    expect(finding.message, '${_stillOpen}legacy states none');
    expect(finding.waitsFor, WaitsFor.owner);
    expect(finding.toJson(), containsPair('waitsFor', 'owner'));
  });

  test('$_name E01: after the value is written, no finding', () async {
    final (:found, project: _) = await _run(
      _frWith('- **Consistency:** immediate'),
    );
    expect(found, isEmpty);
  });

  test('$_name E02: a marker in a table cell and one in a paragraph each '
      'give one finding at their line', () async {
    final (:project, :found) = await _run(
      _frWith(
        'Plain paragraph ${_marker}1 s.\n\n'
        '| Field | Value |\n|---|---|\n| time | ${_marker}2 s |',
      ),
    );

    expect(
      [for (final f in found) f.line],
      [
        _lineOf(project, loginFr, 'Plain paragraph'),
        _lineOf(project, loginFr, '| time |'),
      ],
    );
    expect([for (final f in found) f.keys['form']], ['marker', 'marker']);
    expect(found.first.message, '${_stillOpen}1 s.');
    expect(found.last.message, '${_stillOpen}2 s |');
  });

  test('$_name E03: a marker inside a code span or fenced code gives no '
      'finding', () async {
    final (:found, project: _) = await _run(
      _frWith(
        'The form `${_marker}x` is named here.\n\n'
        '```\n${_marker}y\n```',
      ),
    );
    expect(found, isEmpty);
  });

  test('$_name E04: an fr holding a tbr section gives one section finding '
      'at its header line, whatever the section holds', () async {
    final (:project, :found) = await _run(
      _frWithSection('## TBR\n\n- **Value:** 2 s\n- **Why:** unmeasured\n'),
    );

    expect(found, hasLength(1));
    final finding = found.single;
    expect(finding.line, _lineOf(project, loginFr, '## TBR'));
    expect(finding.keys, {'form': 'section'});
    expect(finding.message, 'the TBR section is open');
    expect(finding.waitsFor, WaitsFor.owner);
  });

  test('$_name E04: an nf holding a tbr section gives one section '
      'finding', () async {
    final (:project, :found) = await _run(
      edit(loginNf, [
        (
          '## Verification\n\nTest: a timed sign-in.\n',
          '## Verification\n\nTest: a timed sign-in.\n\n## TBR\n\n'
              '- **Value:** 1 s\n',
        ),
      ]),
    );

    expect(found, hasLength(1));
    expect(found.single.path, loginNf);
    expect(found.single.line, _lineOf(project, loginNf, '## TBR'));
    expect(found.single.keys, {'form': 'section'});
  });

  test('$_name E04: the same fr gives one finding with its tbr section '
      'and none once the section is removed', () async {
    const section = '## TBR\n\n- **Value:** 2 s\n';
    final open = await _run(_frWithSection(section));
    final closed = await _run(_frWithSection(''));

    expect(open.found, hasLength(1));
    expect(open.found.single.keys, {'form': 'section'});
    expect(closed.found, isEmpty);
  });

  test('$_name E05: a gnfr bullet reading none gives no finding', () async {
    final (:found, project: _) = await _run(
      doc(gnfrDoc, _gnfrBlock, '$_gnfrBlock- **TBR:** none\n'),
    );
    expect(found, isEmpty);
  });

  test('$_name E05: a gnfr bullet with a value gives one bullet finding '
      'at its line', () async {
    const value = '2 s until the benchmark runs';
    final (:project, :found) = await _run(
      doc(gnfrDoc, _gnfrBlock, '$_gnfrBlock- **TBR:** $value\n'),
    );

    expect(found, hasLength(1));
    final finding = found.single;
    expect(finding.path, gnfrDoc);
    expect(finding.line, _lineOf(project, gnfrDoc, '**TBR:**'));
    expect(finding.keys, {'form': 'bullet'});
    expect(finding.message, '$_stillOpen$value');
    expect(finding.waitsFor, WaitsFor.owner);
  });

  test('$_name E05: none is read exactly after trim, so None, none. and '
      'none $_dash reason each give a bullet finding', () async {
    for (final value in ['None', 'none.', 'none $_dash reason']) {
      final (:project, :found) = await _run(
        doc(gnfrDoc, _gnfrBlock, '$_gnfrBlock- **TBR:**   $value  \n'),
      );

      expect(found, hasLength(1), reason: value);
      expect(found.single.keys, {'form': 'bullet'}, reason: value);
      expect(found.single.message, '$_stillOpen$value', reason: value);
      expect(found.single.line, _lineOf(project, gnfrDoc, '**TBR:**'));
    }
  });

  test('$_name E05: a bullet with no value names no value after the '
      'sentence', () async {
    final (:found, project: _) = await _run(
      doc(gnfrDoc, _gnfrBlock, '$_gnfrBlock- **TBR:**\n'),
    );

    expect(found, hasLength(1));
    expect(found.single.keys, {'form': 'bullet'});
    expect(found.single.message, _openNoValue);
  });

  test('$_name E01: a long text after a marker shows its first '
      '$tbrValueLimit characters and an ellipsis', () async {
    final text = 'x' * (tbrValueLimit * 2);
    final (:found, project: _) = await _run(
      _frWith('Cite $_marker$text TBR $_dash second.'),
    );

    expect(
      [for (final f in found) f.message],
      unorderedEquals([
        '$_stillOpen${text.substring(0, tbrValueLimit)}\u2026',
        '${_stillOpen}second.',
      ]),
    );
  });

  test('$_name E01: a marker with nothing after it names no value after '
      'the sentence', () async {
    final (:found, project: _) = await _run(
      _frWith('Cite ${_marker.trimRight()} '),
    );

    expect(found, hasLength(1));
    expect(found.single.keys, {'form': 'marker'});
    expect(found.single.message, _openNoValue);
  });

  test('$_name E01: a marker at the end of its line, as a write stores it, '
      'is open with no value', () async {
    final (:found, project: _) = await _run(
      _frWith('Cite ${_marker.trimRight()}'),
    );

    expect(found, hasLength(1));
    expect(found.single.keys, {'form': 'marker'});
    expect(found.single.message, _openNoValue);
  });

  test('$_name E05: a bullet label inside fenced code of a gnfr gives no '
      'finding', () async {
    final (:found, project: _) = await _run(
      doc(gnfrDoc, _gnfrBlock, '$_gnfrBlock```\n- **TBR:** 3 s\n```\n'),
    );
    expect(found, isEmpty);
  });

  test('$_name E06: a marker inside a tbr section gives the section '
      'finding only', () async {
    final (:found, project: _) = await _run(
      _frWithSection('## TBR\n\n- **Value:** ${_marker}2 s\n'),
    );

    expect(found, hasLength(1));
    expect(found.single.keys, {'form': 'section'});
  });

  test('$_name E06: a marker on a gnfr bullet gives the bullet finding '
      'only', () async {
    final (:found, project: _) = await _run(
      doc(gnfrDoc, _gnfrBlock, '$_gnfrBlock- **TBR:** ${_marker}2 s\n'),
    );

    expect(found, hasLength(1));
    expect(found.single.keys, {'form': 'bullet'});
    expect(found.single.message, '$_stillOpen${_marker}2 s');
  });

  test('$_name E06: a marker beside a tbr section, in another section, '
      'still gives its own finding', () async {
    final (:project, :found) = await _run(
      edit(loginFr, [
        (_rationale, 'Cite ${_marker}3 s here.'),
        (
          '## Verification\n\nTest: a wrong password is refused.\n',
          '## Verification\n\nTest: a wrong password is refused.\n\n'
              '## TBR\n\n- **Value:** 2 s\n',
        ),
      ]),
    );

    expect([for (final f in found) f.keys['form']], ['marker', 'section']);
    expect(found.first.line, _lineOf(project, loginFr, 'Cite'));
  });

  test('$_name E07: a hyphen or a missing dash is no marker', () async {
    final (:found, project: _) = await _run(
      _frWith('Value TBR - 2 s and TBR 3 s are no marker.'),
    );
    expect(found, isEmpty);
  });

  test('$_name E08: a marker in a frontmatter value gives no tbr_open, the '
      'typed field its own finding', () async {
    final project = await writeCheckProject(
      extra: fr('verify_method: test', 'verify_method: ${_marker}later'),
    );
    final report = checkOf(project);

    expect(spots(report, FindingKind.tbrOpen), isEmpty);
    expect(spots(report, FindingKind.fieldValueMismatch), [
      '$loginFr:6: field_value_mismatch',
    ]);
  });

  test('$_name E09: a planned fr that keeps its code paths in a tbr section '
      'gives a section finding', () async {
    final (:found, project: _) = await _run(
      _frWithSection(
        '## TBR\n\n- **Value:** app/lib/login.dart\n',
        status: 'planned',
      ),
    );

    expect(found, hasLength(1));
    expect(found.single.keys, {'form': 'section'});
  });

  test('$_name E10: an untyped doc gives no tbr_open', () async {
    const untyped = 'prds/features/f01_login/notes.md';
    final project = await writeCheckProject(
      extra: {'docs/$untyped': '# Notes\n\nValue ${_marker}later.\n'},
    );
    final report = checkOf(project);

    expect(spots(report, FindingKind.tbrOpen), isEmpty);
    expect(spots(report, FindingKind.untypedDoc), ['$untyped:1: untyped_doc']);
  });

  test('$_name: a marker in a doc type with no tbr section is still read '
      'as a marker', () async {
    final (:project, :found) = await _run(
      doc(loginNf, _nfRationale, 'Wait ${_marker}1 s.'),
    );

    expect(found, hasLength(1));
    expect(found.single.line, _lineOf(project, loginNf, _marker));
    expect(found.single.keys, {'form': 'marker'});
  });
}
