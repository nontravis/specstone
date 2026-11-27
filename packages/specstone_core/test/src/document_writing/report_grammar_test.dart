// A test name is one literal so the sync matrix reads it whole.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/document_writing/author_decisions.dart';
import 'package:specstone_core/src/document_writing/clean_draft_judge.dart';
import 'package:specstone_core/src/document_writing/report_grammar.dart';
import 'package:test/test.dart';

import '../../../tool/generate_agent_text.dart';

// D4: each declared line, filled in each name form it allows, reads as its kind.
const _hash = 'aaaaaaaaaaaa';
const _otherHash = 'bbbbbbbbbbbb';
const _point = 'point';

ReportFile _file(String text) => ReportFile(path: 'reports/r.md', text: text);

String? _ask(String text, NameForm form) {
  final name = sampleNameOf(form);
  final judge = CleanDraftJudge(
    findings: const [],
    audit: AuditSequence.parse([_file(text)]),
    noAudit: false,
    authors: const [],
    unreadableReason: null,
    callNames: {name},
    passedFindings: const {},
    sections: _sampleSections,
  );
  return judge.reasonFor(
    JudgedDraft(
      name: name,
      docPath: sampleNameOf(NameForm.docPath),
      currentHash: _hash,
    ),
  );
}

/// Holds the section of each sample name the filled lines name, so a line's
/// answer rests on its grammar.
const _sampleSections = SectionLookup(_holdsSample);

bool _holdsSample(String docAddress, String key) =>
    key == 'statement' &&
    {
      sampleNameOf(NameForm.typedName),
      sampleNameOf(NameForm.docPath),
    }.contains(docAddress);

String? _authorReason(String text) =>
    AuthorDecisions.read([_file(text)], _sampleSections).reason;

/// The section label of the section line `at` of `lines` opens, or of the
/// nearest one before it.
String _sectionBefore(List<ReportLine> lines, int at) {
  for (var i = at; i >= 0; i--) {
    final line = lines[i];
    if (line.kind == ReportLineKind.verdicts) return 'Verdicts';
    if (line.kind == ReportLineKind.sectionOpen) {
      return line.label.split(':').first;
    }
  }
  throw StateError('no section opens before line $at');
}

void _expectReadAs(
  List<ReportLine> lines,
  int at,
  String filled,
  NameForm form,
  String reason,
) {
  final line = lines[at];
  final name = sampleNameOf(form);
  final audited = 'Audited: $name@$_hash';
  final entry = '- $name: $_point';
  switch (line.kind) {
    case ReportLineKind.audited:
      expect(_ask(filled, form), isNull, reason: reason);
    case ReportLineKind.styled:
      expect(
        _ask('Audited: $name@$_otherHash\n$filled', form),
        isNull,
        reason: reason,
      );
    case ReportLineKind.sectionOpen:
      expect(
        _ask('$audited\n$filled\n$entry', form),
        'named in ${line.label.split(':').first} of r.md',
        reason: reason,
      );
    case ReportLineKind.verdicts:
      expect(
        _ask('$audited\n$filled\n$entry', form),
        'named in Verdicts of r.md',
        reason: reason,
      );
    case ReportLineKind.addressed:
      expect(
        _ask(
          '$audited\nFindings:\n$entry\n## Round 2\nVerdicts:\n$filled',
          form,
        ),
        isNull,
        reason: reason,
      );
    case ReportLineKind.item:
      final section = _sectionBefore(lines, at);
      expect(
        _ask('$audited\n$section:\n$filled', form),
        'named in $section of r.md',
        reason: reason,
      );
    case ReportLineKind.queued:
      expect(AuditSequence.parse([_file('$audited\n$filled')]).queued, {
        name,
      }, reason: reason);
    case ReportLineKind.decision:
      expect(
        _authorReason('Not landed: D1: why\n$filled'),
        isNull,
        reason: reason,
      );
    case ReportLineKind.notLanded:
      expect(_authorReason(filled), 'not landed: D1 in r.md', reason: reason);
    case ReportLineKind.label:
      expect(
        _ask('$audited\nFindings:\n$filled\n$entry', form),
        isNull,
        reason: reason,
      );
    case ReportLineKind.heading:
      expect(
        _ask('Findings:\n$entry\n$filled\n$audited', form),
        isNull,
        reason: reason,
      );
    case ReportLineKind.header || ReportLineKind.observation:
      expect(_ask('$audited\n$filled\n$entry', form), isNull, reason: reason);
    case ReportLineKind.fix:
      final fixes = AuditSequence.parse([
        _file('$audited\nFindings:\n$entry\n$filled\n  ```\n  body\n  ```'),
      ]).fixesInForceOf({name}, from: 0);
      expect([for (final fix in fixes) fix.docName], [name], reason: reason);
  }
}

/// The fence body of [block] in its shipped template, read by the generator's
/// finder.
List<String> _shippedBody(ReportBlock block) => reportBlockBodyOf(
  File('assets/agent/${block.templatePath}').readAsStringSync(),
  block,
);

/// The lines of [block] as its shipped template writes them, each with its
/// declared kind and placeholders.
List<ReportLine> _shippedLines(ReportBlock block) {
  final body = _shippedBody(block);
  expect(body, hasLength(block.lines.length), reason: block.id);
  return [
    for (final (at, line) in block.lines.indexed)
      ReportLine(
        kind: line.kind,
        label: body[at],
        placeholders: line.placeholders,
      ),
  ];
}

void main() {
  test('every declared report line fills in each name form it allows and reads as the answer its kind names', () {
    expect(reportBlocks.map((block) => block.id).toSet(), {
      'author',
      'builderCheck',
      'reReview',
      'decidedAudit',
      'trimAudit',
      'syncDecided',
    });
    final kinds = <ReportLineKind>{};
    for (final lines in [
      for (final block in reportBlocks) _shippedLines(block),
      readerOnlyLines,
    ]) {
      for (final (at, line) in lines.indexed) {
        kinds.add(line.kind);
        var from = 0;
        for (final placeholder in line.placeholders) {
          from = line.label.indexOf(placeholder, from);
          expect(from, isNonNegative, reason: line.label);
          from += placeholder.length;
        }
        expect(formsOf(line), isNotEmpty);
        for (final form in formsOf(line)) {
          final filled = filledLine(line, form);
          final reason = '${form.name}: $filled';
          expect(filled, isNot(contains('<')), reason: reason);
          expect(
            kindOf(filled.trim()),
            line.kind == ReportLineKind.observation
                ? ReportLineKind.item
                : line.kind,
            reason: reason,
          );
          _expectReadAs(lines, at, filled, form, reason);
        }
      }
    }
    expect(kinds, ReportLineKind.values.toSet());
  });

  test('every line inside the report fence of each shipped template is a line its block declares, in order', () {
    // D4: each block reads from its own template, syncDecided included.
    expect({
      for (final block in reportBlocks) block.templatePath,
    }, hasLength(reportBlocks.length));
    for (final block in reportBlocks) {
      expect(_shippedBody(block), [
        for (final line in block.lines) line.label,
      ], reason: block.templatePath);
    }
  });

  // D1: the Decision line takes a DocPath section address too.
  test(
    'the Decision line fills in both name forms and each lands its decision',
    () {
      final decision = reportBlocks
          .firstWhere((block) => block.id == 'syncDecided')
          .lines
          .firstWhere((line) => line.kind == ReportLineKind.decision);
      expect(formsOf(decision), NameForm.values.toSet());
      expect(
        filledLine(decision, NameForm.docPath),
        'Decision: D1 -> a/b.md#statement, …',
      );
      expect(_authorReason(filledLine(decision, NameForm.docPath)), isNull);
    },
  );

  // D2: an address the grammar cannot read whole keeps its decision open.
  test('a Decision line naming a held key that a second # follows, in either name form, keeps its decision open', () {
    for (final form in NameForm.values) {
      final line = 'Decision: D1 -> ${sampleNameOf(form)}#statement#E07';
      expect(_authorReason(line), 'not landed: D1 in r.md', reason: line);
    }
  });

  test('an item lead of keyed and bare names joined by a comma reads as two lead names', () {
    expect(leadNamesOf('fr:a#statement, fr:b: $_point'), ['fr:a', 'fr:b']);
    expect(leadNamesOf('a/b.md#statement, fr:b: $_point'), ['a/b.md', 'fr:b']);
    expect(kindOf('- fr:a#statement, fr:b: $_point'), ReportLineKind.item);
    expect(leadNamesOf('fr:a#statement, prose: $_point'), isNull);
  });

  test('a spaceless Decision or Not landed line closes the open audit section like any label', () {
    for (final lead in ['Decision:x', 'Not landed:x']) {
      expect(
        _ask(
          'Audited: fr:a@$_hash\nFindings:\n$lead\n- fr:a: $_point',
          NameForm.typedName,
        ),
        isNull,
        reason: lead,
      );
    }
  });
}
