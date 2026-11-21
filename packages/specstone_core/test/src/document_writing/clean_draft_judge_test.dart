import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/document_writing/clean_draft_judge.dart';
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
String _unreadable(String path, String os) => 'report $path unreadable: $os';
const _noAuditReason = 'no audit report names it';

/// The line ending the report text of the running test is written with.
String Function(String) _lineEnding = _lf;

String _lf(String text) => text;

String _crlf(String text) =>
    text.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');

/// Registers [body] as two tests, one with LF and one with CRLF report text.
void _reportTest(String name, void Function() body) {
  for (final (label, ending) in [('LF', _lf), ('CRLF', _crlf)]) {
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
}) => CleanDraftJudge(
  findings: findings,
  audit: audit,
  noAudit: noAudit,
  authors: authors,
  unreadableReason: unreadableReason,
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
    });

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

    _reportTest('reads a NOT ADDRESSED item under Verdicts as a finding', () {
      final text = [
        _audited(_name, _hash),
        'Verdicts:',
        '- NOT ADDRESSED: $_name#statement: x',
      ].join('\n');
      expect(_reasonForAudit(text), _namedIn('Verdicts', 'audit1.md'));
    });

    _reportTest('reads a bare or unknown item under Verdicts as a finding', () {
      for (final item in ['- $_name#statement: x', '- MAYBE: $_name x']) {
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
      },
    );

    _reportTest('opens Outside the round as a finding section', () {
      final items = [
        _audited(_name, _hash),
        'Outside the round:',
        '- $_name#edge_cases: x',
      ].join('\n');
      expect(
        _reasonForAudit(items),
        _namedIn('Outside the round', 'audit1.md'),
      );

      final first = [
        _audited(_name, _hash),
        'Outside the round: $_name x',
      ].join('\n');
      expect(
        _reasonForAudit(first),
        _namedIn('Outside the round', 'audit1.md'),
      );
    });

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
  });
}
