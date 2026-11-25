// Each test name stays one literal.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/grouped_fixture.dart';
import '../../helpers/skill_doc_fixture.dart';

const _frLayer = '.specstone/templates/fr.yaml';
const _placeholderLine = '1. E01 — <trigger> → <response>';

String _edgeLayer(String template) =>
    'sections:\n  - id: edge_cases\n    template: |-\n'
    '${template.split('\n').map((line) => '      $line').join('\n')}\n';

/// A check run: the project and every finding it reported.
final class _Checked {
  const new(this.project, this.findings);

  final Directory project;
  final List<Finding> findings;

  /// The `template_text_left` findings of [path].
  Iterable<Finding> left([String path = loginFr]) => findings.where(
    (f) => f.kind == FindingKind.templateTextLeft && f.path == path,
  );
}

Future<_Checked> _check(
  String template,
  Map<String, String> edits, {
  Map<String, String> more = const {},
}) async {
  final project = await writeCheckProject(
    extra: {_frLayer: _edgeLayer(template), ...edits, ...more},
  );
  return _Checked(project, (await checkOf(project)).findings);
}

Map<String, String> _frEdge(String edge) =>
    fr('1. E01 — An empty password → refused.', edge);

void main() {
  test('a leftover template line is one finding at its line', () async {
    final checked = await _check(_placeholderLine, _frEdge(_placeholderLine));
    final left = checked.left().single;
    expect(left.line, lineOfFirst(checked.project, loginFr, '<trigger>'));
    expect(left.path, loginFr);
    expect(left.waitsFor, WaitsFor.agent);
    expect(left.toJson(), containsPair('section', 'edge_cases'));
  });

  test('a renumbered or rewrapped line still equals its placeholder line', () async {
    final checked = await _check(
      _placeholderLine,
      _frEdge(
        '3.  E01 —   <trigger>  →\t<response>\n- E01 — <trigger> → <response>',
      ),
    );
    expect(checked.left(), hasLength(2));
  });

  test(
    'a template line with no angle span never flags the doc line equal to it',
    () async {
      final checked = await _check(
        '1. E01 — a fixed line\n2. E02 — <trigger> → <response>',
        _frEdge('1. E01 — a fixed line'),
      );
      expect(checked.left(), isEmpty);
    },
  );

  test('an angle span in backticks makes no placeholder line', () async {
    const line = '1. E01 — `<trigger>` → refused';
    final checked = await _check(line, _frEdge(line));
    expect(checked.left(), isEmpty);
  });

  test('a leftover template line in a CRLF doc is one finding', () async {
    final edits = {
      for (final MapEntry(:key, :value) in _frEdge(_placeholderLine).entries)
        key: value.replaceAll('\n', '\r\n'),
    };
    final checked = await _check(_placeholderLine, edits);
    expect(checked.left(), hasLength(1));
  });

  test('a required section of leftover template lines alone gives the leftover finding and no missing section', () async {
    final checked = await _check(_placeholderLine, _frEdge(_placeholderLine));
    expect(checked.left(), hasLength(1));
    expect(
      checked.findings.where(
        (f) => f.kind == FindingKind.requiredSectionMissing,
      ),
      isEmpty,
    );
  });

  test(
    'a story titled with its own slug gets the title finding at the title line',
    () async {
      final checked = await _check(
        _placeholderLine,
        edit(loginStory, [('# Agent signs in with email', '# email_login')]),
      );
      final left = checked.left(loginStory).single;
      expect(
        left.line,
        lineOfFirst(checked.project, loginStory, '# email_login'),
      );
      expect(left.toJson(), containsPair('section', '_title'));
    },
  );

  test(
    'a title differing from its slug only in letter case gets no title finding',
    () async {
      final checked = await _check(
        _placeholderLine,
        edit(loginStory, [('# Agent signs in with email', '# Email_Login')]),
      );
      expect(checked.left(loginStory), isEmpty);
    },
  );

  test(
    'a spec doc titled with its feature slug gets no title finding',
    () async {
      final checked = await _check(
        _placeholderLine,
        edit(loginArchitecture, [('# Login architecture', '# login')]),
      );
      expect(checked.left(loginArchitecture), isEmpty);
    },
  );

  test('a grouped feature titled with its numbered slug gets the title finding, not one titled with its group', () async {
    for (final (title, count) in [('recipes', 1), ('kitchen', 0)]) {
      final project = await writeGroupedProject(
        extra: {'docs/$kitchenRecipes': '# $title\n'},
      );
      final found = (await checkOf(project)).findings.where(
        (f) =>
            f.kind == FindingKind.templateTextLeft &&
            f.path == kitchenRecipes &&
            f.toJson()['section'] == '_title',
      );
      expect(found, hasLength(count), reason: 'title "$title"');
    }
  });

  test('a skill doc titled with its own slug gets no title finding', () async {
    final checked = await _check(
      _placeholderLine,
      skillDocFile(['.claude/skills/review/']),
      more: {'.specstone/config.yaml': skillPinsConfig(), skillFile: skillText},
    );
    expect(checked.left(skillDoc), isEmpty);
  });
}
