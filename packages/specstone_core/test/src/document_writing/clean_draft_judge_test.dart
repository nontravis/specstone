// A test name is one literal so the sync matrix reads it whole.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/size_excess.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/document_writing/clean_draft_judge.dart';
import 'package:specstone_core/src/document_writing/draft_sections.dart'
    show sectionBodyOf;
import 'package:specstone_core/src/document_writing/held_items.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

const _name = 'fr:a';
const _docPath = 'prds/features/f01_x/fr01_a.md';
const _hash = 'aaaaaaaaaaaa';
const _otherHash = 'bbbbbbbbbbbb';
const _thirdHash = 'cccccccccccc';

const _draft = JudgedDraft(name: _name, docPath: _docPath, currentHash: _hash);

String _audited(String name, String hash) => 'Audited: $name@$hash';
String _styled(String name, String hash) => 'Styled: $name@$hash';

// The reason text patterns, built here, never imported from the code.
String _checkFinding(String kind) => 'check finding $kind';
String _auditedAt(String then, String now) => 'audited at $then, now $now';
String _namedIn(String section, String file) => 'named in $section of $file';
String _notLandedIn(String file) => 'Not landed line in $file';
String _openDecisions(List<(String, String)> open) =>
    'not landed: ${open.map((d) => '${d.$1} in ${d.$2}').join(', ')}';
String _unreadable(String path, String os) => 'report $path unreadable: $os';
const _noAuditReason = 'no audit report names it';

/// The line ending the report text of the running test is written with.
String Function(String) _lineEnding = _lf;

String _lf(String text) => text;

String _crlf(String text) =>
    text.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');

/// Registers [body] with LF report text, and again with CRLF when [crlf].
///
/// Report text is stripped of its byte order mark and `\r` before any parse,
/// so only a test of that strip needs the CRLF run.
void _reportTest(String name, void Function() body, {bool crlf = false}) {
  for (final (label, ending) in [('LF', _lf), if (crlf) ('CRLF', _crlf)]) {
    test('$name ($label)', () {
      _lineEnding = ending;
      addTearDown(() => _lineEnding = _lf);
      body();
    });
  }
}

ReportFile _file(String text, {String path = 'reports/audit1.md'}) =>
    ReportFile(path: path, text: _lineEnding(text));

AuditSequence _sequence(List<String> texts) => AuditSequence.parse([
  for (var i = 0; i < texts.length; i++)
    _file(texts[i], path: 'reports/audit${i + 1}.md'),
]);

CleanDraftJudge _judge({
  List<Finding> findings = const [],
  AuditSequence? audit,
  bool noAudit = false,
  List<ReportFile> authors = const [],
  String? unreadableReason,
  Set<String> callNames = const {},
  Set<String> passedFindings = const {},
  Set<Finding> carried = const {},
}) => CleanDraftJudge(
  findings: findings,
  audit: audit,
  noAudit: noAudit,
  authors: authors,
  unreadableReason: unreadableReason,
  callNames: callNames,
  passedFindings: passedFindings,
  carriedFindings: carried,
);

String? _reasonForAudit(
  String text, {
  JudgedDraft? draft,
  List<String> later = const [],
}) => _judge(audit: _sequence([text, ...later])).reasonFor(draft ?? _draft);

Finding _finding(
  FindingKind kind, {
  String path = _docPath,
  WaitsFor? waitsFor,
}) =>
    Finding(kind: kind, path: path, line: 1, message: 'm', waitsFor: waitsFor);

const _longEdge =
    'E02 — an empty password, a password of only blanks, and a password '
    'one character short are each refused with the one message a wrong '
    'password gets, so the page never tells which part was wrong.';

/// A doc whose Edge cases hold [edge] as item 2 and whose Rationale holds
/// [rationale].
String _doc({String edge = _longEdge, String rationale = 'Why.'}) =>
    '# T\n\n## Edge cases\n\n1. E01 — short.\n2. $edge\n\n'
    '## Rationale\n\n$rationale\n';

/// The `item_over_limit` finding at the first line of [text] holding [marker].
Finding _longAt(String text, String marker, {String section = 'edge_cases'}) =>
    _longItem(
      line: text.split('\n').indexWhere((l) => l.contains(marker)) + 1,
      section: section,
    );

/// The reason a judge gives [_draft] whose long item the run [draft] holds and
/// the approved copy [approved] holds, or whose approved copy is none.
String? _reasonWithCopy(String draft, String? approved) {
  final long = _longAt(draft, 'E02');
  return _judge(
    noAudit: true,
    findings: [long],
    passedFindings: approved == null
        ? const {}
        : heldItemKeysOf(
            findings: [long],
            draftLf: draft,
            approvedLf: approved,
            type: null,
          ),
  ).reasonFor(_draft);
}

Finding _longItem({int line = 12, String section = 'edge_cases'}) => Finding(
  kind: FindingKind.itemOverLimit,
  path: _docPath,
  line: line,
  message: 'm',
  keys: {'section': section},
);

void main() {
  group('Report lines', () {
    _reportTest('reads an Audited line per part', () {
      final audit = _sequence([
        _audited(_name, _otherHash),
        _audited(_name, _hash),
      ]);
      expect(_judge(audit: audit).reasonFor(_draft), isNull);

      final stale = _sequence([
        _audited(_name, _hash),
        _audited(_name, _otherHash),
      ]);
      expect(
        _judge(audit: stale).reasonFor(_draft),
        _auditedAt(_otherHash, _hash),
      );
    });

    _reportTest('splits parts at every round heading line', () {
      final earlier = [
        '## Round 1',
        _audited(_name, _otherHash),
        'Findings:',
        '- $_name is broken',
        '## Round 2',
        _audited(_name, _hash),
        'Findings: none',
      ].join('\n');
      expect(_reasonForAudit(earlier), isNull);

      final later = [
        '## Round 1',
        _audited(_name, _hash),
        '## Round 2',
        'Findings:',
        '- $_name is broken',
      ].join('\n');
      expect(_reasonForAudit(later), _namedIn('Findings', 'audit1.md'));

      final third = [
        '## Round 1',
        _audited(_name, _hash),
        '## Round 2',
        'Lenses: none',
        '## Round 3',
        'Outside the drafts:',
        '- $_docPath: check',
      ].join('\n');
      expect(
        _reasonForAudit(third),
        _namedIn('Outside the drafts', 'audit1.md'),
      );
    });

    _reportTest(
      'keeps lines before the first round heading as their own part',
      () {
        final preamble = [
          _audited(_name, _hash),
          'Findings:',
          '- $_name is broken',
          '## Round 1',
          _audited('fr:other', _otherHash),
        ].join('\n');
        expect(_reasonForAudit(preamble), _namedIn('Findings', 'audit1.md'));

        final blank = [
          '',
          '  ',
          '## Round 1',
          _audited(_name, _hash),
        ].join('\n');
        expect(_reasonForAudit(blank), isNull);
      },
    );

    _reportTest('drops a byte order mark and carriage returns', () {
      final lf = [
        _audited(_name, _hash),
        'Findings:',
        '- $_name is broken',
        '',
      ].join('\n');
      final crlf = '﻿${lf.replaceAll('\n', '\r\n')}';
      final expected = _namedIn('Findings', 'audit1.md');
      expect(_reasonForAudit(lf), expected);
      expect(_reasonForAudit(crlf), expected);

      final clean = '﻿${_audited(_name, _hash)}\r\nFindings: none\r\n';
      expect(_reasonForAudit(clean), isNull);
    }, crlf: true);

    _reportTest('continues an item on an indented raw line', () {
      final named = [
        _audited(_name, _hash),
        'Findings:',
        '- the item has a wrapped second line',
        '  naming $_name here',
      ].join('\n');
      expect(_reasonForAudit(named), _namedIn('Findings', 'audit1.md'));

      final tabbed = [
        _audited(_name, _hash),
        'Findings:',
        '- wrapped',
        '\t$_name',
      ].join('\n');
      expect(_reasonForAudit(tabbed), _namedIn('Findings', 'audit1.md'));

      final noItem = [
        _audited(_name, _hash),
        'Findings:',
        '   $_name stands alone',
      ].join('\n');
      expect(_reasonForAudit(noItem), _namedIn('Findings', 'audit1.md'));

      final continuesStyle = [
        _audited(_name, _hash),
        _styled(_name, _hash),
        'Findings:',
        '- $_name wording',
        '    [style] one more',
      ].join('\n');
      expect(_reasonForAudit(continuesStyle), isNull);

      final blankIndent = [
        _audited(_name, _hash),
        'Findings:',
        '- other thing',
        '   ',
        '$_name closing',
      ].join('\n');
      expect(_reasonForAudit(blankIndent), _namedIn('Findings', 'audit1.md'));
    });

    _reportTest('reads an unknown line inside a section as an item', () {
      final plain = [
        _audited(_name, _hash),
        'Findings:',
        '$_name is broken',
      ].join('\n');
      expect(_reasonForAudit(plain), _namedIn('Findings', 'audit1.md'));

      final fenced = [
        _audited(_name, _hash),
        'Outside the drafts:',
        '```',
        '- $_name pasted',
        '```',
      ].join('\n');
      expect(
        _reasonForAudit(fenced),
        _namedIn('Outside the drafts', 'audit1.md'),
      );

      final outside = [
        _audited(_name, _hash),
        '$_name is mentioned before any section',
      ].join('\n');
      expect(_reasonForAudit(outside), isNull);
    });

    _reportTest('keeps a line led by a hash that is no heading as an item', () {
      for (final line in [
        '#1 $_name is wrong',
        '####### $_name',
        '#x $_name',
      ]) {
        final text = [_audited(_name, _hash), 'Findings:', line].join('\n');
        expect(
          _reasonForAudit(text),
          _namedIn('Findings', 'audit1.md'),
          reason: line,
        );
      }
      for (final heading in ['#', '# $_name', '###### x', '#\tx']) {
        final text = [
          _audited(_name, _hash),
          'Findings:',
          heading,
          '- $_name after the heading',
        ].join('\n');
        expect(_reasonForAudit(text), isNull, reason: heading);
      }
    });

    _reportTest(
      'splits parts at a round heading line inside a fenced block',
      () {
        final text = [
          _audited(_name, _hash),
          'Findings:',
          '```',
          '## Round 2',
          '```',
          '- $_name is broken',
        ].join('\n');
        // The heading splits the part, so no section is open after it.
        expect(_reasonForAudit(text), isNull);

        final inFence = [
          _audited(_name, _hash),
          '```',
          '## Round 2',
          'Findings:',
          '- $_name is broken',
          '```',
        ].join('\n');
        expect(_reasonForAudit(inFence), _namedIn('Findings', 'audit1.md'));
      },
    );

    _reportTest('closes a section at any other label line', () {
      for (final closer in [
        'Waits on the Owner:',
        'Lenses: none',
        "Owner's note:",
        'Design: x',
        'Not landed: none',
        '# Heading',
        '## Notes',
      ]) {
        final text = [
          _audited(_name, _hash),
          'Findings:',
          '- none',
          closer,
          '- $_name after the closer',
          '$_name wrapped after the closer',
        ].join('\n');
        expect(_reasonForAudit(text), isNull, reason: closer);
      }
    });

    _reportTest('opens a section with its first item after the colon', () {
      final first = [
        _audited(_name, _hash),
        'Findings: $_name is broken',
      ].join('\n');
      expect(_reasonForAudit(first), _namedIn('Findings', 'audit1.md'));

      final outside = [
        _audited(_name, _hash),
        'Outside the drafts: $_docPath is broken',
      ].join('\n');
      expect(
        _reasonForAudit(outside),
        _namedIn('Outside the drafts', 'audit1.md'),
      );

      final none = [
        _audited(_name, _hash),
        'Findings: none',
        'Outside the drafts: none',
      ].join('\n');
      expect(_reasonForAudit(none), isNull);

      final trimmed = [
        _audited(_name, _hash),
        '  Findings:   $_name ',
      ].join('\n');
      expect(_reasonForAudit(trimmed), _namedIn('Findings', 'audit1.md'));

      final roundItems = [
        _audited(_name, _hash),
        'Outside the round:',
        '- $_name#edge_cases: x',
      ].join('\n');
      expect(
        _reasonForAudit(roundItems),
        _namedIn('Outside the round', 'audit1.md'),
      );

      final roundFirst = [
        _audited(_name, _hash),
        'Outside the round: $_name x',
      ].join('\n');
      expect(
        _reasonForAudit(roundFirst),
        _namedIn('Outside the round', 'audit1.md'),
      );
    });

    _reportTest('reads a none item as naming nothing', () {
      final text = [
        _audited(_name, _hash),
        'Findings:',
        '- none',
        'Outside the drafts:',
        '- none',
      ].join('\n');
      expect(_reasonForAudit(text), isNull);
    });

    _reportTest('reads a bare or unknown item under Verdicts as a finding', () {
      for (final item in [
        '- NOT ADDRESSED: $_name#statement: x',
        '- $_name#statement: x',
        '- MAYBE: $_name x',
      ]) {
        final text = [_audited(_name, _hash), 'Verdicts:', item].join('\n');
        expect(
          _reasonForAudit(text),
          _namedIn('Verdicts', 'audit1.md'),
          reason: item,
        );
      }
    });

    _reportTest(
      'an ADDRESSED item names nothing, its continuation included',
      () {
        final text = [
          _audited(_name, _hash),
          'Verdicts:',
          '- ADDRESSED: fr:b x',
          '  $_name#statement',
        ].join('\n');
        expect(_reasonForAudit(text), isNull);

        final indented = [
          _audited(_name, _hash),
          'Verdicts:',
          '  - ADDRESSED: $_name x',
        ].join('\n');
        expect(_reasonForAudit(indented), isNull);

        final underFindings = [
          _audited(_name, _hash),
          'Findings:',
          '- ADDRESSED: $_name x',
        ].join('\n');
        expect(
          _reasonForAudit(underFindings),
          _namedIn('Findings', 'audit1.md'),
        );
      },
    );

    _reportTest('a later ADDRESSED verdict clears an earlier finding item equal by Equal text', () {
      final first = [
        _audited(_name, _hash),
        'Findings:',
        '- $_name#edge_cases: E02 cites x',
        '  and a continuation line',
      ].join('\n');
      final second = [
        'Verdicts:',
        '- ADDRESSED: $_name#edge_cases:   E02 cites x',
      ].join('\n');
      expect(_reasonForAudit(first, later: [second]), isNull);
    });

    _reportTest(
      'an ADDRESSED verdict clears no item of its own part or a later one',
      () {
        const item = '- $_name#edge_cases: E02 cites x';
        const verdict = '- ADDRESSED: $_name#edge_cases: E02 cites x';
        final sameVerdictFirst = [
          _audited(_name, _hash),
          'Verdicts:',
          verdict,
          'Findings:',
          item,
        ].join('\n');
        final sameItemFirst = [
          _audited(_name, _hash),
          'Findings:',
          item,
          'Verdicts:',
          verdict,
        ].join('\n');
        for (final text in [sameVerdictFirst, sameItemFirst]) {
          expect(_reasonForAudit(text), _namedIn('Findings', 'audit1.md'));
        }

        final laterItem = ['Findings:', item].join('\n');
        final earlierVerdict = [
          _audited(_name, _hash),
          'Verdicts:',
          verdict,
        ].join('\n');
        expect(
          _reasonForAudit(earlierVerdict, later: [laterItem]),
          _namedIn('Findings', 'audit2.md'),
        );
      },
    );

    _reportTest('a NOT ADDRESSED verdict keeps the earlier finding', () {
      final first = [
        _audited(_name, _hash),
        'Findings:',
        '- $_name#edge_cases: E02 cites x',
      ].join('\n');
      final second = [
        'Verdicts:',
        '- NOT ADDRESSED: $_name#edge_cases: E02 cites x',
      ].join('\n');
      expect(
        _reasonForAudit(first, later: [second]),
        _namedIn('Findings', 'audit1.md'),
      );
    });

    _reportTest(
      'an ADDRESSED verdict equal to no earlier item clears nothing',
      () {
        final first = [
          _audited(_name, _hash),
          'Findings:',
          '- $_name#edge_cases: E02 cites x',
        ].join('\n');
        final second = [
          'Verdicts:',
          '- ADDRESSED: $_name#edge_cases: E02 cites y',
        ].join('\n');
        expect(
          _reasonForAudit(first, later: [second]),
          _namedIn('Findings', 'audit1.md'),
        );
      },
    );

    _reportTest('a label line inside Verdicts closes it', () {
      final unDashed = [
        _audited(_name, _hash),
        'Verdicts:',
        'NOT ADDRESSED: $_name x',
        '- $_name x',
      ].join('\n');
      expect(_reasonForAudit(unDashed), isNull);

      final oneLine = [
        _audited(_name, _hash),
        'Verdicts: - NOT ADDRESSED: $_name x',
        '- $_name x',
      ].join('\n');
      expect(_reasonForAudit(oneLine), isNull);
    });

    _reportTest('a Queued line ends the section above it', () {
      final after = [
        _audited(_name, _hash),
        'Outside the drafts:',
        '- fr:b x',
        'Queued: fr:c',
        '- $_name y',
      ].join('\n');
      expect(_reasonForAudit(after), isNull);

      final before = [
        _audited(_name, _hash),
        'Outside the drafts:',
        '- $_name y',
        'Queued: fr:c',
      ].join('\n');
      expect(
        _reasonForAudit(before),
        _namedIn('Outside the drafts', 'audit1.md'),
      );
    });

    _reportTest('reads an indented Queued line as a continuation', () {
      final text = [
        _audited(_name, _hash),
        'Verdicts:',
        '- NOT ADDRESSED: fr:c#edge_cases: names $_name',
        '  Queued: fr:c',
      ].join('\n');
      expect(_reasonForAudit(text), _namedIn('Verdicts', 'audit1.md'));
    });

    _reportTest(
      'a Queued line clears a NOT ADDRESSED verdict its lead names',
      () {
        final text = [
          _audited(_name, _hash),
          'Verdicts:',
          '- NOT ADDRESSED: fr:c#edge_cases: names $_name',
          'Queued: fr:c',
        ].join('\n');
        expect(_reasonForAudit(text), isNull);
      },
    );

    _reportTest(
      'a Queued line clears no Findings or Outside the round item',
      () {
        for (final label in ['Findings', 'Outside the round']) {
          final text = [
            _audited(_name, _hash),
            '$label:',
            '- $_name: x',
            'Queued: $_name',
          ].join('\n');
          expect(_reasonForAudit(text), _namedIn(label, 'audit1.md'));
        }
      },
    );

    _reportTest('an outside item counts only by its lead name, a findings item by any mention', () {
      for (final (label, isLeadOnly) in [
        ('Outside the drafts', true),
        ('Outside the round', true),
        ('Findings', false),
        ('Verdicts', false),
      ]) {
        final mentioned = [
          _audited(_name, _hash),
          '$label:',
          '- fr:c#statement: names $_name',
        ].join('\n');
        expect(
          _reasonForAudit(mentioned),
          isLeadOnly ? isNull : _namedIn(label, 'audit1.md'),
          reason: '$label, a name past the lead name',
        );

        final led = [
          _audited(_name, _hash),
          '$label:',
          '- $_name#statement: x',
        ].join('\n');
        expect(
          _reasonForAudit(led),
          _namedIn(label, 'audit1.md'),
          reason: '$label, a lead name',
        );
      }
    });

    _reportTest('an item with no lead name counts beside a Queued line', () {
      final text = [
        _audited(_name, _hash),
        'Verdicts:',
        '- NOT ADDRESSED: Open question for the Owner: $_name',
        'Queued: fr:c',
      ].join('\n');
      expect(_reasonForAudit(text), _namedIn('Verdicts', 'audit1.md'));
    });

    _reportTest(
      'a Queued line for a draft of the same call clears no item',
      () {
        const callDraft = JudgedDraft(
          name: 'fr:c',
          docPath: 'prds/features/f01_x/fr03_c.md',
          currentHash: _hash,
        );
        final text = [
          _audited('fr:c', _hash),
          'Verdicts:',
          '- NOT ADDRESSED: fr:c#statement: x',
          'Queued: fr:c',
        ].join('\n');
        final judge = _judge(audit: _sequence([text]), callNames: {'fr:c'});
        expect(judge.reasonFor(callDraft), _namedIn('Verdicts', 'audit1.md'));
      },
    );

    _reportTest('a Queued line holding no doc name clears no item', () {
      final text = [
        _audited(_name, _hash),
        'Verdicts:',
        '- NOT ADDRESSED: fr:c#edge_cases: names $_name',
        'Queued: later',
      ].join('\n');
      expect(_reasonForAudit(text), _namedIn('Verdicts', 'audit1.md'));
    });

    test('reads the lead name through backticks and up to its right bound', () {
      expect(leadNameOf('`fr:a`#edge_cases: x'), 'fr:a');
      expect(leadNameOf('NOT ADDRESSED: fr:a#x: y'), 'fr:a');
      expect(leadNameOf('check: prds/a.md:3: y'), 'prds/a.md');
      expect(leadNameOf('fr:ab x'), 'fr:ab');
      expect(leadNameOf('Open question for the Owner: fr:a'), isNull);
    });
  });

  group('Names', () {
    _reportTest('matches a name and a docPath within their bounds', () {
      const items = [
        '$_name is broken',
        '- $_name',
        '- ($_name)',
        '- [$_name]',
        '- `$_name`',
        '- x\t$_name',
        '- check: $_docPath: size',
        '- $_name@$_hash',
        '- $_name#edge_cases',
        '- $_name, again',
        '- $_name. Done',
        '- $_name; next',
        '- see ($_docPath)',
        '- see [$_docPath]',
        '- see `$_docPath`',
        '- $_docPath.',
        '- $_docPath,',
        '- $_docPath#sec',
      ];
      for (final item in items) {
        final text = [
          _audited(_name, _hash),
          'Findings:',
          if (item.startsWith('- ')) item else 'Findings: $item',
        ].join('\n');
        expect(
          _reasonForAudit(text),
          _namedIn('Findings', 'audit1.md'),
          reason: item,
        );
      }
    });

    _reportTest('does not match a name inside a longer name', () {
      const items = [
        '- fr:ab',
        '- xfr:a',
        '- fr:a_b',
        '- fr:a-b',
        '- fr:a/b',
        '- other/$_docPath',
        '- ${_docPath}x',
        '- fr:A',
      ];
      for (final item in items) {
        final text = [_audited(_name, _hash), 'Findings:', item].join('\n');
        expect(_reasonForAudit(text), isNull, reason: item);
      }
    });

    _reportTest(
      'names a draft by the typed address of its Audited line only',
      () {
        final text = [
          _audited('fr:ab', _hash),
          _audited('fr:a ', _hash),
        ].join('\n');
        expect(_reasonForAudit(text), _noAuditReason);
      },
    );
  });

  group('Clean-draft tests', () {
    _reportTest('uses the last Styled hash at or after the audit part', () {
      final styledLater = _sequence([
        _audited(_name, _otherHash),
        _styled(_name, _hash),
      ]);
      expect(_judge(audit: styledLater).reasonFor(_draft), isNull);

      final lastWins = _sequence([
        [_audited(_name, _otherHash), _styled(_name, _hash)].join('\n'),
        _styled(_name, _thirdHash),
      ]);
      expect(
        _judge(audit: lastWins).reasonFor(_draft),
        _auditedAt(_thirdHash, _hash),
      );

      final sameLastWins = _sequence([
        [
          _audited(_name, _otherHash),
          _styled(_name, _thirdHash),
          _styled(_name, _hash),
        ].join('\n'),
      ]);
      expect(_judge(audit: sameLastWins).reasonFor(_draft), isNull);

      final beforeAuditPart = _sequence([
        [
          '## Round 1',
          _audited(_name, _hash),
          _styled(_name, _thirdHash),
          '## Round 2',
          _audited(_name, _hash),
        ].join('\n'),
      ]);
      expect(_judge(audit: beforeAuditPart).reasonFor(_draft), isNull);

      final otherDraft = _sequence([
        [_audited(_name, _hash), _styled('fr:other', _thirdHash)].join('\n'),
      ]);
      expect(_judge(audit: otherDraft).reasonFor(_draft), isNull);
    });

    _reportTest(
      'skips a style item of a part with a Styled line for the draft',
      () {
        final styled = [
          _audited(_name, _otherHash),
          _styled(_name, _hash),
          'Findings:',
          '- $_name wording [style]',
          '- [style] $_docPath lead',
        ].join('\n');
        expect(_reasonForAudit(styled), isNull);

        final unstyled = [
          _audited(_name, _hash),
          'Findings:',
          '- $_name wording [style]',
        ].join('\n');
        expect(_reasonForAudit(unstyled), _namedIn('Findings', 'audit1.md'));

        final mixed = [
          _audited(_name, _otherHash),
          _styled(_name, _hash),
          'Findings:',
          '- $_name wording [style]',
          '- $_name is wrong',
        ].join('\n');
        expect(_reasonForAudit(mixed), _namedIn('Findings', 'audit1.md'));

        final otherDraftStyled = [
          _audited(_name, _hash),
          _styled('fr:other', _hash),
          'Findings:',
          '- $_name wording [style]',
        ].join('\n');
        expect(
          _reasonForAudit(otherDraftStyled),
          _namedIn('Findings', 'audit1.md'),
        );

        final laterStyledOnly = _sequence([
          [_audited(_name, _hash), 'Findings:', '- $_name [style]'].join('\n'),
          _styled(_name, _hash),
        ]);
        expect(
          _judge(audit: laterStyledOnly).reasonFor(_draft),
          _namedIn('Findings', 'audit1.md'),
        );
      },
    );

    _reportTest(
      'asks a draft whose audit names only its typed name by its DocPath',
      () {
        const shared = JudgedDraft(
          name: _docPath,
          docPath: _docPath,
          currentHash: _hash,
        );
        final text = [
          _audited(_name, _hash),
          'Audited: $_docPath@$_hash',
        ].join('\n');
        expect(_reasonForAudit(text, draft: shared), _noAuditReason);
      },
    );

    _reportTest('an unreadable report fails each draft', () {
      final folder = Directory.systemTemp.createTempSync('clean_judge_');
      addTearDown(() => folder.deleteSync(recursive: true));
      File('${folder.path}${Platform.pathSeparator}audit.md')
          .writeAsStringSync(_audited(_name, _hash));

      final missing = ReportFiles.read(
        auditPaths: ['audit.md', 'gone.md'],
        authorPaths: const [],
        workingDirectory: folder,
      );
      var osMessage = '';
      try {
        File('${folder.path}${Platform.pathSeparator}gone.md')
            .readAsBytesSync();
      } on FileSystemException catch (error) {
        osMessage = error.osError?.message ?? error.message;
      }
      expect(osMessage, isNotEmpty);
      expect(missing.unreadableReason, _unreadable('gone.md', osMessage));

      const typed = JudgedDraft(
        name: 'fr:b',
        docPath: 'prds/b.md',
        currentHash: _otherHash,
      );
      final judge = _judge(
        audit: _sequence([
          [_audited(_name, _hash), _audited('fr:b', _otherHash)].join('\n'),
        ]),
        unreadableReason: missing.unreadableReason,
      );
      for (final draft in [_draft, typed]) {
        expect(
          judge.reasonFor(draft),
          _unreadable('gone.md', osMessage),
          reason: draft.name,
        );
      }

      final authorMissing = ReportFiles.read(
        auditPaths: ['audit.md'],
        authorPaths: ['author.md'],
        workingDirectory: folder,
      );
      expect(
        authorMissing.unreadableReason,
        startsWith('report author.md unreadable: '),
      );

      final firstWins = ReportFiles.read(
        auditPaths: ['b.md', 'audit.md'],
        authorPaths: ['a.md'],
        workingDirectory: folder,
      );
      expect(
        firstWins.unreadableReason,
        startsWith('report b.md unreadable: '),
      );

      final directory = ReportFiles.read(
        auditPaths: [folder.path],
        authorPaths: const [],
        workingDirectory: folder,
      );
      expect(
        directory.unreadableReason,
        startsWith('report ${folder.path} unreadable: '),
      );

      File('${folder.path}${Platform.pathSeparator}binary.md')
          .writeAsBytesSync([0xC3, 0x28]);
      final binary = ReportFiles.read(
        auditPaths: const [],
        authorPaths: ['binary.md'],
        workingDirectory: folder,
      );
      expect(
        binary.unreadableReason,
        startsWith('report binary.md unreadable: '),
      );
    });

    _reportTest('reads every report file when none is unreadable', () {
      final folder = Directory.systemTemp.createTempSync('clean_judge_');
      addTearDown(() => folder.deleteSync(recursive: true));
      final sub = Directory('${folder.path}${Platform.pathSeparator}sub')
        ..createSync();
      File('${sub.path}${Platform.pathSeparator}audit.md')
          .writeAsStringSync('audit text');
      final absolute = File('${folder.path}${Platform.pathSeparator}author.md')
        ..writeAsStringSync('author text');

      final read = ReportFiles.read(
        auditPaths: ['sub${Platform.pathSeparator}audit.md'],
        authorPaths: [absolute.path],
        workingDirectory: folder,
      );
      expect(read.unreadableReason, isNull);
      expect(read.audits.map((file) => file.text), ['audit text']);
      expect(read.authors.map((file) => file.text), ['author text']);
      expect(read.audits.single.path, 'sub${Platform.pathSeparator}audit.md');
      expect(read.authors.single.path, absolute.path);
    });

    _reportTest('fails every draft on a Not landed line', () {
      final audit = _sequence([_audited(_name, _hash)]);
      const other = JudgedDraft(
        name: 'fr:b',
        docPath: 'prds/b.md',
        currentHash: _otherHash,
      );
      final audited = _sequence([
        [_audited(_name, _hash), _audited('fr:b', _otherHash)].join('\n'),
      ]);
      final judge = _judge(
        audit: audited,
        authors: [
          _file('Not landed: none', path: 'reports/author1.md'),
          _file(
            'Not landed: a promised line is missing',
            path: 'reports/author2.md',
          ),
        ],
      );
      expect(judge.reasonFor(_draft), _notLandedIn('author2.md'));
      expect(judge.reasonFor(other), _notLandedIn('author2.md'));

      final clean = _judge(
        audit: audit,
        authors: [
          _file('Not landed: none', path: 'reports/author1.md'),
          _file('Notes: Not landed in prose', path: 'reports/author2.md'),
        ],
      );
      expect(clean.reasonFor(_draft), isNull);

      final crlf = _judge(
        noAudit: true,
        authors: [_file('﻿Done: x\r\n  Not landed: x\r\n')],
      );
      expect(crlf.reasonFor(_draft), _notLandedIn('audit1.md'));

      final bare = _judge(noAudit: true, authors: [_file('Not landed:')]);
      expect(bare.reasonFor(_draft), _notLandedIn('audit1.md'));
    });

    group('author decisions', () {
      final audit = _sequence([_audited(_name, _hash)]);

      CleanDraftJudge judgeOf(Map<String, String> files) => _judge(
        audit: audit,
        authors: [
          for (final MapEntry(:key, :value) in files.entries)
            _file(value, path: 'reports/$key'),
        ],
      );

      String? reasonOf(Map<String, String> files) =>
          judgeOf(files).reasonFor(_draft);

      _reportTest(
        'lands a decision a later round of the same file marks with a section',
        () {
          expect(
            reasonOf({
              'author1.md': [
                'NOT LANDED',
                'Not landed: D2: no doc took it',
                '## Round 1',
                'Decision: D2 -> fr:a#statement',
              ].join('\n'),
            }),
            isNull,
          );
        },
      );

      _reportTest('names an open decision and an unkeyed Not landed line, each with its file, in the order the files were passed', () {
        const keyed = 'Not landed: D3: x';
        const unkeyed = 'Not landed: a promised line is missing';
        expect(
          reasonOf({'author1.md': keyed, 'author2.md': unkeyed}),
          '${_openDecisions([('D3', 'author1.md')])}; ${_notLandedIn('author2.md')}',
        );
        expect(
          reasonOf({'author1.md': unkeyed, 'author2.md': keyed}),
          '${_notLandedIn('author1.md')}; ${_openDecisions([('D3', 'author2.md')])}',
        );
        expect(
          reasonOf({
            'author1.md': keyed,
            'author2.md': [
              unkeyed,
              'Decision: D3 -> fr:a#statement',
            ].join('\n'),
          }),
          _notLandedIn('author2.md'),
        );
      });

      _reportTest(
        'keeps a decision open when its last line in the file leaves it open',
        () {
          for (final last in [
            'Decision: D2 -> NOT LANDED',
            'Not landed: D2: no doc took it',
            'Decision: D2 -> fr:a',
          ]) {
            expect(
              reasonOf({
                'author1.md': [
                  'Decision: D2 -> fr:a#statement',
                  last,
                ].join('\n'),
              }),
              _openDecisions([('D2', 'author1.md')]),
              reason: last,
            );
          }
        },
      );

      _reportTest("lands a decision one file leaves open once another file's line marks it with a section", () {
        const open = 'Not landed: D3: no doc took it';
        const landed = 'Decision: D3 -> fr:a#statement';
        expect(reasonOf({'author1.md': open, 'author2.md': landed}), isNull);
        expect(reasonOf({'author1.md': landed, 'author2.md': open}), isNull);
        expect(
          reasonOf({
            'author1.md': landed,
            'author2.md': [
              landed,
              '## Round 1',
              'Not landed: D3: reopened',
            ].join('\n'),
          }),
          isNull,
        );
        expect(
          reasonOf({
            'author1.md': 'Not landed: D1: x',
            'author2.md': 'Decision: D10 -> fr:a#statement',
          }),
          _openDecisions([('D1', 'author1.md')]),
        );
      });

      _reportTest('names each open decision in ID order, once per file that leaves it open', () {
        expect(
          reasonOf({
            'author1.md': 'Not landed: D10: no doc took it',
            'author2.md': 'Not landed: D7: no doc took it',
            'author3.md': 'Not landed: D3: no doc took it',
          }),
          _openDecisions([
            ('D3', 'author3.md'),
            ('D7', 'author2.md'),
            ('D10', 'author1.md'),
          ]),
        );
        expect(
          reasonOf({
            'author1.md': 'Not landed: D3: x',
            'author2.md': 'Not landed: D3: y',
          }),
          _openDecisions([('D3', 'author1.md'), ('D3', 'author2.md')]),
        );
        expect(
          reasonOf({
            'author1.md': 'Not landed: D3: x',
            'author2.md': 'Not landed: D7: y',
            'author3.md': 'Decision: D3 -> fr:a#statement',
          }),
          _openDecisions([('D7', 'author2.md')]),
        );
      });

      _reportTest('reads no Decision line that names no decision key', () {
        expect(
          reasonOf({'author1.md': 'Decision: Calls made (x) -> y'}),
          isNull,
        );
      });

      _reportTest(
        'reads decision keys from a CRLF report with a byte order mark',
        () {
          const text =
              '\u{FEFF}Not landed: D2: x\r\n## Round 1\r\n'
              'Decision: D2 -> fr:a#statement\r\n';
          final landed = _judge(
            audit: audit,
            authors: [const ReportFile(path: 'reports/author1.md', text: text)],
          );
          expect(landed.reasonFor(_draft), isNull);
          final open = _judge(
            audit: audit,
            authors: [
              const ReportFile(
                path: 'reports/author1.md',
                text: '\u{FEFF}Not landed: D5: why',
              ),
            ],
          );
          expect(
            open.reasonFor(_draft),
            _openDecisions([('D5', 'author1.md')]),
          );
        },
        crlf: true,
      );

      _reportTest('leaves a decision open when its key ends the line', () {
        for (final line in ['Not landed: D5', 'Decision: D5']) {
          expect(
            reasonOf({'author1.md': line}),
            _openDecisions([('D5', 'author1.md')]),
            reason: line,
          );
        }
      });

      _reportTest('keys D1 and D10 apart and reads a key ended by a colon or a parenthesis', () {
        expect(
          reasonOf({
            'author1.md': [
              'Not landed: D1: why',
              'Decision: D1 (merge) -> fr:a#x',
              'Not landed: D10: why',
            ].join('\n'),
          }),
          _openDecisions([('D10', 'author1.md')]),
        );
      });
    });

    _reportTest('lets an owner-waiting unconfirmed finding pass', () {
      final judge = _judge(
        noAudit: true,
        findings: [_finding(FindingKind.unconfirmed, waitsFor: WaitsFor.owner)],
      );
      expect(judge.reasonFor(_draft), isNull);
    });

    _reportTest(
      'asks a draft with an unconfirmed finding that waits for the agent',
      () {
        final judge = _judge(
          noAudit: true,
          findings: [_finding(FindingKind.unconfirmed)],
        );
        expect(
          judge.reasonFor(_draft),
          _checkFinding(FindingKind.unconfirmed.wire),
        );

        final size = _judge(
          noAudit: true,
          findings: [_finding(FindingKind.linesOverLimit)],
        );
        expect(
          size.reasonFor(_draft),
          _checkFinding(FindingKind.linesOverLimit.wire),
        );

        final elsewhere = _judge(
          noAudit: true,
          findings: [
            _finding(FindingKind.linesOverLimit, path: 'prds/other.md'),
          ],
        );
        expect(elsewhere.reasonFor(_draft), isNull);

        final mixed = _judge(
          noAudit: true,
          findings: [
            _finding(FindingKind.unconfirmed, waitsFor: WaitsFor.owner),
            _finding(FindingKind.suspect),
          ],
        );
        expect(
          mixed.reasonFor(_draft),
          _checkFinding(FindingKind.suspect.wire),
        );
      },
    );

    _reportTest('reads no Waits on the Owner item', () {
      final text = [
        _audited(_name, _hash),
        'Findings:',
        '- none',
        'Waits on the Owner:',
        '- $_name unconfirmed',
        '- check: $_docPath: unconfirmed',
      ].join('\n');
      expect(_reasonForAudit(text), isNull);
    });

    _reportTest("gives the first failing test's reason", () {
      final everything = [
        _audited(_name, _otherHash),
        'Findings:',
        '- $_name is broken',
      ].join('\n');
      final authors = [_file('Not landed: x', path: 'reports/author1.md')];
      final audit = _sequence([everything]);
      final check = [_finding(FindingKind.suspect)];

      expect(
        _judge(
          findings: check,
          audit: audit,
          authors: authors,
        ).reasonFor(_draft),
        _checkFinding(FindingKind.suspect.wire),
      );
      expect(
        _judge(audit: null, authors: authors).reasonFor(_draft),
        _noAuditReason,
      );
      expect(
        _judge(audit: audit, authors: authors).reasonFor(_draft),
        _auditedAt(_otherHash, _hash),
      );

      final hashOk = _sequence([
        [_audited(_name, _hash), 'Findings:', '- $_name is broken'].join('\n'),
      ]);
      expect(
        _judge(audit: hashOk, authors: authors).reasonFor(_draft),
        _namedIn('Findings', 'audit1.md'),
      );

      final noFindings = _sequence([_audited(_name, _hash)]);
      expect(
        _judge(audit: noFindings, authors: authors).reasonFor(_draft),
        _notLandedIn('author1.md'),
      );
      expect(_judge(audit: noFindings).reasonFor(_draft), isNull);
    });

    _reportTest('takes no audit test under no-audit', () {
      final judge = _judge(
        noAudit: true,
        audit: _sequence([
          [_audited(_name, _otherHash), 'Findings:', '- $_name x'].join('\n'),
        ]),
      );
      expect(judge.reasonFor(_draft), isNull);
      expect(_judge(noAudit: true).reasonFor(_draft), isNull);
    });

    _reportTest('passes an item_over_limit finding the call holds', () {
      final long = _longItem();
      final judge = _judge(
        noAudit: true,
        findings: [long],
        passedFindings: {findingKeyOf(long)},
      );
      expect(judge.reasonFor(_draft), isNull);
    });

    _reportTest('asks an item_over_limit finding the call does not hold', () {
      final long = _longItem();
      final held = {
        findingKeyOf(_longItem(line: 13)),
        findingKeyOf(_longItem(section: 'rationale')),
      };
      final judge = _judge(
        noAudit: true,
        findings: [long],
        passedFindings: held,
      );
      expect(
        judge.reasonFor(_draft),
        _checkFinding(FindingKind.itemOverLimit.wire),
      );
      expect(
        _judge(noAudit: true, findings: [long]).reasonFor(_draft),
        _checkFinding(FindingKind.itemOverLimit.wire),
      );
    });

    _reportTest('asks a draft whose other finding comes after a held one', () {
      final long = _longItem();
      final judge = _judge(
        noAudit: true,
        findings: [long, _finding(FindingKind.suspect)],
        passedFindings: {findingKeyOf(long)},
      );
      expect(judge.reasonFor(_draft), _checkFinding(FindingKind.suspect.wire));
    });

    test('passes a long item the approved copy holds in the same section', () {
      final rewrapped = _doc(
        edge: _longEdge.replaceFirst(' a password of', '\n   a password of'),
      );
      expect(_reasonWithCopy(_doc(), rewrapped), isNull);
      expect(_reasonWithCopy(_doc(), _doc()), isNull);

      final quoted = _doc(edge: 'E02 — short.', rationale: '> $_longEdge');
      final quotedWrap = _doc(
        edge: 'E02 — short.',
        rationale:
            '> E02 — an empty password, a password of only blanks,\n'
            '> and a password one character short are each refused with the '
            'one message a wrong\n> password gets, so the page never tells '
            'which part was wrong.',
      );
      final long = _longAt(quoted, '> E02', section: 'rationale');
      expect(
        heldItemKeysOf(
          findings: [long],
          draftLf: quoted,
          approvedLf: quotedWrap,
          type: null,
        ),
        {findingKeyOf(long)},
      );
    });

    test('passes a long item the run renumbered', () {
      const renumbered =
          '# T\n\n## Edge cases\n\n1. $_longEdge\n\n'
          '## Rationale\n\nWhy.\n';
      expect(_reasonWithCopy(renumbered, _doc()), isNull);
    });

    test('asks a long item the run changed', () {
      final changed = _doc(
        edge: _longEdge.replaceFirst('one character', 'two characters'),
      );
      expect(
        _reasonWithCopy(_doc(), changed),
        _checkFinding(FindingKind.itemOverLimit.wire),
      );
    });

    test('asks a long item the approved copy holds in another section', () {
      final elsewhere = _doc(edge: 'E02 — short.', rationale: _longEdge);
      expect(
        _reasonWithCopy(_doc(), elsewhere),
        _checkFinding(FindingKind.itemOverLimit.wire),
      );
    });

    test('asks a long item with no approved copy', () {
      expect(
        _reasonWithCopy(_doc(), null),
        _checkFinding(FindingKind.itemOverLimit.wire),
      );
    });

    test('holds only the long item the copy holds, not a second one', () {
      final draft = _doc().replaceFirst(
        '1. E01 — short.',
        '1. E01 — $_longEdge',
      );
      final first = _longAt(draft, '1. E01');
      final second = _longAt(draft, '2. E02');
      final held = heldItemKeysOf(
        findings: [first, second],
        draftLf: draft,
        approvedLf: _doc(),
        type: null,
      );
      expect(held, {findingKeyOf(second)});
    });
  });

  group('A finding the draft carries from its approved copy', () {
    const sized = MergedDocType(
      id: 'fr',
      fields: [],
      sections: [
        MergedSection(
          id: 'notes',
          header: 'Notes',
          itemCount: ItemCountLint(max: 2, waitsForOwner: true),
        ),
        MergedSection(
          id: 'rules',
          header: 'Rules',
          itemCount: ItemCountLint(
            max: 2,
            perSubsection: true,
            waitsForOwner: true,
          ),
        ),
        MergedSection(
          id: 'renamed',
          header: 'Renamed',
          itemCount: ItemCountLint(max: 2, waitsForOwner: true),
        ),
        MergedSection(
          id: 'floor',
          header: 'Floor',
          itemCount: ItemCountLint(min: 2, waitsForOwner: true),
        ),
        MergedSection(id: 'chars', header: 'Chars', maxChars: 20),
        MergedSection(
          id: 'must',
          header: 'Must',
          required: true,
          itemCount: ItemCountLint(min: 2, waitsForOwner: true),
        ),
      ],
      lint: MergedLint(),
      files: [],
    );

    String items(int count) =>
        [for (var i = 1; i <= count; i++) '- item $i'].join('\n');

    String notes(int count) => '# T\n\n## Notes\n\n${items(count)}\n';

    String rules(Map<String, int> subsections) {
      final blocks = [
        for (final MapEntry(:key, :value) in subsections.entries)
          '### $key\n\n${items(value)}\n',
      ];
      return '# T\n\n## Rules\n\n${blocks.join('\n')}';
    }

    Finding countAt(String draft, String marker, {required int actual}) =>
        Finding(
          kind: FindingKind.itemCountOutOfRange,
          path: _docPath,
          line: draft.split('\n').indexWhere((l) => l.contains(marker)) + 1,
          message: 'm',
          waitsFor: WaitsFor.owner,
          keys: {'limit': 2, 'actual': actual},
        );

    /// Every size finding `check` gives [lf], a doc of [type].
    List<Finding> sizeFindingsOf(String lf, {MergedDocType type = sized}) {
      final ParsedDoc(:doc, :content) = parseIndexedDoc(
        docPath: '',
        bytes: utf8.encode(lf),
        match: MatchedDocType(type),
        statusesOutside: false,
      );
      return [
        for (final excess in sizeExcessesOf(doc, content, type))
          Finding(
            kind: excess.kind,
            path: _docPath,
            line: excess.line,
            message: 'm',
            waitsFor: WaitsFor.owner,
            keys: {
              'section': ?excess.sectionKey,
              'limit': excess.limit,
              'actual': excess.actual,
            },
          ),
      ];
    }

    /// The reason a judge gives [_draft] holding [finding] when [draft] and
    /// its approved copy [copy] are read for their carried findings.
    String? reasonWith(String draft, String? copy, Finding finding) => _judge(
      noAudit: true,
      findings: [finding],
      carried: copy == null
          ? const {}
          : carriedFindingsOf(
              draftFindings: [finding],
              copyFindings: sizeFindingsOf(copy),
              draftLf: draft,
              copyLf: copy,
              type: sized,
            ),
    ).reasonFor(_draft);

    String floor(int count) => '# T\n\n## Floor\n\n${items(count)}\n';

    String must(int count) => '# T\n\n## Must\n\n${items(count)}\n';

    String chars(int count) => '# T\n\n## Chars\n\n${'x' * count}\n';

    /// The `chars_over_limit` finding `check` gives the one over-limit section
    /// of [text].
    Finding charsOf(String text) => sizeFindingsOf(text).single;

    final askedCount = _checkFinding(FindingKind.itemCountOutOfRange.wire);

    test('passes a size finding the approved copy already had with no larger excess', () {
      final finding = countAt(notes(3), '## Notes', actual: 3);
      expect(reasonWith(notes(3), notes(3), finding), isNull);
      expect(reasonWith(notes(3), notes(4), finding), isNull);
    });

    test('asks a size finding whose excess grew over the approved copy', () {
      final finding = countAt(notes(4), '## Notes', actual: 4);
      expect(reasonWith(notes(4), notes(3), finding), askedCount);
      expect(reasonWith(notes(4), notes(2), finding), askedCount);
    });

    test('asks a size finding at a place the copy lacks', () {
      final finding = countAt(notes(3), '## Notes', actual: 3);
      expect(reasonWith(notes(3), '# T\n', finding), askedCount);
      final renamed = notes(3).replaceFirst('## Notes', '## Renamed');
      expect(reasonWith(notes(3), renamed, finding), askedCount);
    });

    test('never pairs findings of sibling subsections', () {
      final draft = rules({'A': 3, 'B': 2});
      final finding = countAt(draft, '### A', actual: 3);
      expect(reasonWith(draft, rules({'A': 2, 'B': 3}), finding), askedCount);
      expect(reasonWith(draft, rules({'B': 2, 'A': 3}), finding), isNull);
      expect(reasonWith(draft, rules({'A': 3}), finding), isNull);
    });

    test('asks a size finding on a draft with no found copy', () {
      final finding = countAt(notes(3), '## Notes', actual: 3);
      expect(reasonWith(notes(3), notes(3), finding), isNull);
      expect(reasonWith(notes(3), null, finding), askedCount);
    });

    test(
      'passes a count under its floor the approved copy was no farther under',
      () {
        final finding = countAt(floor(1), '## Floor', actual: 1);
        expect(reasonWith(floor(1), floor(1), finding), isNull);
        expect(reasonWith(floor(1), floor(0), finding), isNull);
      },
    );

    test('asks a count farther under its floor than the approved copy', () {
      final finding = countAt(floor(0), '## Floor', actual: 0);
      expect(reasonWith(floor(0), floor(1), finding), askedCount);
      expect(reasonWith(floor(0), notes(3), finding), askedCount);
    });

    test(
      'asks a count under its floor when the approved copy section is blank',
      () {
        final finding = countAt(must(1), '## Must', actual: 1);
        expect(reasonWith(must(1), must(1), finding), isNull);
        expect(reasonWith(must(1), must(0), finding), askedCount);
      },
    );

    test('pairs a section chars finding by its section and its excess', () {
      final finding = charsOf(chars(30));
      final asked = _checkFinding(FindingKind.charsOverLimit.wire);
      expect(reasonWith(chars(30), chars(30), finding), isNull);
      expect(reasonWith(chars(30), chars(40), finding), isNull);
      expect(reasonWith(chars(30), chars(25), finding), asked);
      expect(reasonWith(chars(30), chars(10), finding), asked);
      final renamed = chars(30).replaceFirst('## Chars', '## Renamed');
      expect(reasonWith(chars(30), renamed, finding), asked);
    });

    test("approval_marks_leave_chars: a draft at its approved copy's size is unworsened", () {
      const capped = MergedDocType(
        id: 'fr',
        fields: [],
        sections: [],
        lint: MergedLint(maxChars: 40),
        files: [],
      );
      final body = '# T\n\n${'x' * 50}\n';
      final approved = '---\napproved: "abc123"\n---\n\n$body';
      final draft = '---\ndraft: true\napproved: "abc123"\n---\n\n$body';
      final finding = sizeFindingsOf(draft, type: capped).single;
      expect(
        carriedFindingsOf(
          draftFindings: [finding],
          copyFindings: sizeFindingsOf(approved, type: capped),
          draftLf: draft,
          copyLf: approved,
          type: capped,
        ),
        {finding},
      );
    });

    test('a long item still passes only when its copy holds it', () {
      final draft = _doc();
      final long = _longAt(draft, 'E02');
      expect(
        carriedFindingsOf(
          draftFindings: [long],
          copyFindings: [long],
          draftLf: draft,
          copyLf: draft,
          type: sized,
        ),
        isEmpty,
      );
      expect(_reasonWithCopy(draft, draft), isNull);
      expect(
        _reasonWithCopy(draft, _doc(edge: 'E02 — short.')),
        _checkFinding(FindingKind.itemOverLimit.wire),
      );
    });

    group('a finding of any other kind', () {
      Finding banned(String text, String marker) => Finding(
        kind: FindingKind.bannedWord,
        path: _docPath,
        line: text.split('\n').indexWhere((l) => l.contains(marker)) + 1,
        message: 'm',
      );

      String? reasonOf(
        String draft,
        String copy,
        List<Finding> draftFindings,
        List<Finding> copyFindings,
      ) => _judge(
        noAudit: true,
        findings: draftFindings,
        carried: carriedFindingsOf(
          draftFindings: draftFindings,
          copyFindings: copyFindings,
          draftLf: draft,
          copyLf: copy,
          type: sized,
        ),
      ).reasonFor(_draft);

      final asked = _checkFinding(FindingKind.bannedWord.wire);

      test('passes a finding its approved copy also gives in that section', () {
        const draft = '# T\n\n## Notes\n\n- one\n- bad\n';
        const copy = '# T\n\nA lead line.\n\n## Notes\n\n- bad\n';
        expect(
          reasonOf(draft, copy, [banned(draft, 'bad')], [banned(copy, 'bad')]),
          isNull,
        );
      });

      test('asks a finding the approved copy gives in another section', () {
        const draft = '# T\n\n## Notes\n\n- bad\n\n## Chars\n\nok\n';
        const copy = '# T\n\n## Notes\n\n- ok\n\n## Chars\n\nbad\n';
        expect(
          reasonOf(draft, copy, [banned(draft, 'bad')], [banned(copy, 'bad')]),
          asked,
        );
      });

      test('asks a draft that adds a second finding of a kind its copy gives once at that place', () {
        const draft = '# T\n\n## Notes\n\n- bad 1\n- bad 2\n';
        const copy = '# T\n\n## Notes\n\n- bad 1\n- ok\n';
        final found = [banned(draft, 'bad 1'), banned(draft, 'bad 2')];
        expect(reasonOf(draft, copy, found, [banned(copy, 'bad 1')]), asked);
        expect(
          reasonOf(draft, copy, [found.first], [banned(copy, 'bad 1')]),
          isNull,
        );
      });

      test(
        'asks a draft whose one line holds more findings than its copy line',
        () {
          const draft = '# T\n\n## Notes\n\n- bad and bad\n';
          const copy = '# T\n\n## Notes\n\n- bad\n';
          final twice = [banned(draft, 'bad'), banned(draft, 'bad')];
          expect(reasonOf(draft, copy, twice, [banned(copy, 'bad')]), asked);
          expect(
            carriedFindingsOf(
              draftFindings: twice,
              copyFindings: [banned(copy, 'bad')],
              draftLf: draft,
              copyLf: copy,
              type: sized,
            ),
            hasLength(1),
          );
        },
      );

      test('two sibling subsections keep their findings apart', () {
        final draft = rules({'A': 1, 'B': 1})
            .replaceFirst('### A', '### A bad');
        final copyB = rules({'A': 1, 'B': 1})
            .replaceFirst('### B', '### B bad');
        final copyA = rules({'B': 1, 'A': 1})
            .replaceFirst('### A', '### A bad');
        final found = [banned(draft, 'A bad')];
        expect(reasonOf(draft, copyB, found, [banned(copyB, 'B bad')]), asked);
        expect(reasonOf(draft, copyA, found, [banned(copyA, 'A bad')]), isNull);
        final inBody = [banned(copyA, '- item 1')];
        expect(reasonOf(draft, copyA, found, inBody), asked);
      });
    });
  });

  group('Reports as the skills write them', () {
    const other = JudgedDraft(
      name: 'fr:b',
      docPath: 'prds/b.md',
      currentHash: _otherHash,
    );

    String builderCheck(List<String> findings) => [
      'Findings:',
      ...findings,
      _audited(_name, _hash),
      _audited('fr:b', _otherHash),
    ].join('\n');

    _reportTest('reads each label of a builder check as a finding item', () {
      for (final label in [
        'Guess',
        'Contradiction',
        'Stale reader',
        'Not carried',
      ]) {
        final text = builderCheck(['- $label: $_name#statement: a point']);
        expect(
          _reasonForAudit(text),
          _namedIn('Findings', 'audit1.md'),
          reason: label,
        );
        expect(_reasonForAudit(text, draft: other), isNull, reason: label);
      }
    });

    _reportTest('reads a builder check name by its DocPath and its key', () {
      final text = builderCheck([
        '- Not carried: $_docPath#out_of_scope: p/item neither covered',
      ]);
      expect(_reasonForAudit(text), _namedIn('Findings', 'audit1.md'));
      expect(_reasonForAudit(text, draft: other), isNull);
    });

    _reportTest('reads a ranked builder check as one section to its end', () {
      final text = builderCheck([
        '- Guess: fr:b#statement: a point',
        '- Contradiction: fr:b#edge_cases: restates a rule $_name owns',
        '- Stale reader: fr:c#statement: a point',
      ]);
      expect(_reasonForAudit(text), _namedIn('Findings', 'audit1.md'));
      expect(
        _reasonForAudit(text, draft: other),
        _namedIn('Findings', 'audit1.md'),
      );
    });

    _reportTest('reads a clean builder check as naming no draft', () {
      final text = builderCheck(const [])
          .replaceFirst('Findings:', 'Findings: nothing important left');
      expect(_reasonForAudit(text), isNull);
      expect(_reasonForAudit(text, draft: other), isNull);
    });

    _reportTest('reads a writer report for its Not landed lines only', () {
      const lines = [
        "Drafts for the Owner's specstone approve fr:a: fr:a, fr:b",
        'Decision: D1 -> fr:a#statement, D2 -> fr:b#statement',
        'Readers: fr:a#statement changed: the rule moved',
        'Elsewhere: fr:c#statement: still states the old rule',
        'Move: specstone move fr:b --under fr:a',
        'Delete: fr:old',
        'Open questions: fr:a needs an answer',
        'Check: reports/check.txt',
        'Counts: 2 drafts; fr:a: 0 dropped, 1 new',
        'Other drafts: none',
        'Findings: fr:a is thin',
      ];
      final audit = _sequence([builderCheck(const [])]);
      final landed = _judge(
        audit: audit,
        authors: [_file(lines.join('\n'), path: 'reports/author1.md')],
      );
      expect(landed.reasonFor(_draft), isNull);
      expect(landed.reasonFor(other), isNull);

      final notLanded = _judge(
        audit: audit,
        authors: [
          _file(
            [
              ...lines.take(2),
              'Not landed: D3: no doc took it',
              ...lines.skip(2),
            ].join('\n'),
            path: 'reports/author1.md',
          ),
        ],
      );
      expect(
        notLanded.reasonFor(_draft),
        _openDecisions([('D3', 'author1.md')]),
      );
      expect(
        notLanded.reasonFor(other),
        _openDecisions([('D3', 'author1.md')]),
      );
    });
  });

  group('Fix lines', () {
    String report(List<String> lines) =>
        [_audited(_name, _hash), 'Findings:', ...lines].join('\n');

    List<List<String>> fixesOf(String text) => [
      for (final fix in _sequence([text]).fixesInForceOf({_name}, from: 0))
        [fix.docName, fix.sectionKey, fix.body],
    ];

    test('reads a fix line and its fenced body under a findings item', () {
      final text = report([
        '- fr:a#rationale: too long',
        '  Fix: fr:a#rationale',
        '  ```',
        '  Short why.',
        '  ```',
      ]);
      expect(fixesOf(text), [
        ['fr:a', 'rationale', 'Short why.'],
      ]);
    });

    test('drops the opening fence line indent from each body line and keeps inner indent', () {
      final text = report([
        '- fr:a#behavior: shape',
        '    Fix: fr:a#behavior',
        '    ```',
        '    1. One',
        '       - nested',
        '',
        '    2. Two',
        '    ```',
      ]);
      expect(fixesOf(text), [
        ['fr:a', 'behavior', '1. One\n   - nested\n\n2. Two'],
      ]);
    });

    test('closes a fix block only at a fence of its own length', () {
      final text = report([
        '- fr:a#behavior: shape',
        '  Fix: fr:a#behavior',
        '  ````',
        '  ```',
        '  code',
        '  ```',
        '  after',
        '  ````',
      ]);
      expect(fixesOf(text), [
        ['fr:a', 'behavior', '```\ncode\n```\nafter'],
      ]);
    });

    test('reads a fix block from a CRLF report', () {
      final text = _crlf(
        report([
          '- fr:a#rationale: too long',
          '  Fix: fr:a#rationale',
          '  ```',
          '  Line one',
          '    Line two',
          '  ```',
        ]),
      );
      expect(fixesOf(text), [
        ['fr:a', 'rationale', 'Line one\n  Line two'],
      ]);
    });

    test('an unclosed fix block yields no fix line', () {
      final text = report([
        '- fr:a#rationale: too long',
        '  Fix: fr:a#rationale',
        '  ```',
        '  Short why.',
      ]);
      expect(fixesOf(text), isEmpty);
      expect(_reasonForAudit(text), _namedIn('Findings', 'audit1.md'));
    });

    test('reads several fix lines under one item', () {
      final text = report([
        '- fr:a: two sections',
        '  Fix: fr:a#rationale',
        '  ```',
        '  First.',
        '  ```',
        '  Fix: fr:a#edge_cases',
        '  ```',
        '  Second.',
        '  ```',
      ]);
      expect(fixesOf(text), [
        ['fr:a', 'rationale', 'First.'],
        ['fr:a', 'edge_cases', 'Second.'],
      ]);
    });

    test('a fix line outside a findings item is no fix', () {
      final text = [
        _audited(_name, _hash),
        'Outside the drafts:',
        '- fr:a: lead',
        '  Fix: fr:a#rationale',
        '  ```',
        '  Short.',
        '  ```',
        'Verdicts:',
        '- NOT ADDRESSED: fr:a#rationale',
        '  Fix: fr:a#rationale',
        '  ```',
        '  Short.',
        '  ```',
      ].join('\n');
      expect(fixesOf(text), isEmpty);
    });

    test(
      'an unindented fix line under findings is an item head, not a fix',
      () {
        final text = report([
          'Fix: fr:a#rationale',
          '  ```',
          '  Short.',
          '  ```',
        ]);
        expect(fixesOf(text), isEmpty);
      },
    );

    test('an unclosed fix block does not swallow the next item', () {
      final text = report([
        '- fr:a#rationale: first',
        '  Fix: fr:a#rationale',
        '  ```',
        '  Lost.',
        '- fr:a#behavior: second',
        '  Fix: fr:a#behavior',
        '  ```',
        '  Kept.',
        '  ```',
      ]);
      expect(fixesOf(text), [
        ['fr:a', 'behavior', 'Kept.'],
      ]);
      expect(_sequence([text]).fixesInForceOf({_name}, from: 0), hasLength(1));
    });
  });

  group('A draft fixed by its audit', () {
    const audited = '# T\n\n## Rules\n\n1. Old rule.\n\n## Rationale\n\nWhy.\n';
    const fixedRules =
        '# T\n\n## Rules\n\n1. New rule.\n\n## Rationale\n\nWhy.\n';

    String report(List<String> fixLines) => [
      _audited(_name, _otherHash),
      'Findings:',
      '- $_name#rules: old',
      ...fixLines,
    ].join('\n');

    List<String> fix(String key, String body, {String name = _name}) => [
      '  Fix: $name#$key',
      '  ```',
      '  $body',
      '  ```',
    ];

    JudgedDraft draftOf(
      String current, {
      String? copy = audited,
      Map<String, String> others = const {},
    }) => JudgedDraft(
      name: _name,
      docPath: _docPath,
      currentHash: _hash,
      currentLf: current,
      auditedTextAt: copy == null ? null : (hash) => copy,
      sectionTextOf: (docName, key) => docName == _name
          ? sectionBodyOf(current, null, key)
          : others[docName],
    );

    DraftAsk? askOf(String text, JudgedDraft draft) =>
        _judge(audit: _sequence([text])).askFor(draft);

    test('passes test three when each changed section equals a fix block of its audit part', () {
      expect(
        askOf(report(fix('rules', '1. New rule.')), draftOf(fixedRules)),
        isNull,
      );
      expect(
        askOf(report(fix('rules', '9. New   rule.')), draftOf(fixedRules)),
        isNull,
      );
    });

    test('asks a draft whose changed section differs from its fix block', () {
      final ask = askOf(
        report(fix('rules', '1. Another rule.')),
        draftOf(fixedRules),
      );
      expect(ask?.reason, _auditedAt(_otherHash, _hash));
      expect(ask?.waitsFor, AskWaitsFor.audit);
      expect(ask?.changedSections, ['rules']);
    });

    test('asks a draft whose title changed beside a fixed section with no changed sections, so the fix read reads it whole', () {
      final retitled = fixedRules.replaceFirst('# T', '# U');
      final ask = askOf(
        report(fix('rules', '1. New rule.')),
        draftOf(retitled),
      );
      expect(ask?.reason, _auditedAt(_otherHash, _hash));
      expect(ask?.waitsFor, AskWaitsFor.audit);
      expect(ask?.changedSections, isNull);
      expect(ask?.toJson(), isNot(contains('changedSections')));
    });

    test('asks a draft with no audited copy with no changed sections, so the fix read reads it whole', () {
      final ask = askOf(
        report(fix('rules', '1. New rule.')),
        draftOf(fixedRules, copy: null),
      );
      expect(ask?.reason, _auditedAt(_otherHash, _hash));
      expect(ask?.changedSections, isNull);
    });

    test('a fix block body that cites another draft does not name it', () {
      final text = [
        _audited(_name, _otherHash),
        _audited('fr:b', _hash),
        'Findings:',
        '- $_name#rules: old',
        ...fix('rules', '1. See fr:b for the rule.'),
      ].join('\n');
      const other = JudgedDraft(
        name: 'fr:b',
        docPath: 'prds/features/f01_x/fr02_b.md',
        currentHash: _hash,
      );
      expect(askOf(text, other), isNull);
    });

    test(
      'a findings item whose fix lines all match no longer names the draft',
      () {
        final text = report([
          ...fix('rules', '1. New rule.'),
          ...fix('rationale', 'Why.', name: 'fr:other'),
        ]);
        final draft = draftOf(fixedRules, others: {'fr:other': 'Why.\n'});
        expect(askOf(text, draft), isNull);
      },
    );

    test(
      'a findings item with one unmatched fix line still names the draft',
      () {
        final text = report([
          ...fix('rules', '1. Old rule.'),
          ...fix('rationale', 'Other.', name: 'fr:other'),
        ]);
        expect(
          askOf(text, draftOf(audited, others: {'fr:other': 'Why.\n'}))?.reason,
          _namedIn('Findings', 'audit1.md'),
        );
        expect(
          askOf(text, draftOf(audited))?.reason,
          _namedIn('Findings', 'audit1.md'),
        );
      },
    );

    group('the fix line in force', () {
      const ruleA = '# T\n\n## Rules\n\n1. Rule A.\n\n## Rationale\n\nWhy.\n';

      DraftAsk? askTwoParts(String later, JudgedDraft draft) =>
          _judge(audit: _sequence([report(fix('rules', '1. Rule A.')), later]))
              .askFor(draft);

      test('takes the last fix line of a key in the audit sequence as the one in force', () {
        final later = [
          'Findings:',
          '- $_name#rules: again',
          ...fix('rules', '1. New rule.'),
        ].join('\n');
        expect(askTwoParts(later, draftOf(fixedRules)), isNull);
        expect(
          askTwoParts(later, draftOf(ruleA))?.reason,
          _auditedAt(_otherHash, _hash),
        );
      });

      test(
        'a later fix line on another doc replaces the earlier one for that doc',
        () {
          final first = report([
            ...fix('rules', '1. New rule.'),
            ...fix('why', 'Body A.', name: 'fr:other'),
          ]);
          final later = [
            'Findings:',
            '- fr:b#x: y',
            ...fix('why', 'Body B.', name: 'fr:other'),
          ].join('\n');
          final draft = draftOf(fixedRules, others: {'fr:other': 'Body A.\n'});
          expect(
            _judge(audit: _sequence([first, later])).askFor(draft)?.reason,
            _namedIn('Findings', 'audit1.md'),
          );
        },
      );

      test('an earlier fix line on a key a later part fixes asks nothing', () {
        final later = [
          'Findings:',
          '- fr:b#x: y',
          ...fix('rules', '1. New rule.'),
        ].join('\n');
        expect(
          askTwoParts(later, draftOf(fixedRules))?.reason,
          isNot(startsWith('named in')),
        );
        expect(askTwoParts(later, draftOf(fixedRules)), isNull);
      });
    });
  });
}
