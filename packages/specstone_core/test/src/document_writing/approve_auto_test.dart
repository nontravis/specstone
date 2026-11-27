// A test name is one literal so the sync matrix reads it whole.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:specstone_core/src/consistency_check/mermaid_node_run.dart';
import 'package:specstone_core/src/document_writing/approve_auto.dart';
import 'package:specstone_core/src/document_writing/approve_drafts.dart';
import 'package:specstone_core/src/document_writing/approved_copy_store.dart';
import 'package:specstone_core/src/document_writing/audited_copy_store.dart';
import 'package:specstone_core/src/document_writing/author_decisions.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart' as check;
import '../../helpers/git_repo.dart';
import '../../helpers/no_generators.dart';
import '../../helpers/relative_link.dart';
import '../../helpers/target_fixture.dart';
import '../../helpers/temp_tree.dart';
import '../../helpers/write_fixture.dart';

const _story = 'user_story:login/email_login';
const _fr = 'fr:login/email_login/check_password';
const _askMode = 'approve mode is ask';
const _noAudit = 'no audit report names it';

final String? _linksUnavailable = Platform.isWindows
    ? 'a link needs a privilege on Windows'
    : null;

/// The check project with the story and the FR drafts, both clean.
Future<Directory> _draftsProject({
  Map<String, String> extra = const {},
  bool frHasFinding = false,
}) => check.writeCheckProject(
  extra: {
    ...check.edit(check.loginStory, [('goals:\n', 'draft: true\ngoals:\n')]),
    ...check.edit(check.loginFr, [
      ('traced_from:\n', 'draft: true\ntraced_from:\n'),
      if (frHasFinding)
        ('## Rationale\n\nA wrong password must not sign in.\n\n', ''),
    ]),
    ...extra,
  },
);

String _hashOf(Directory root, String address) =>
    getDoc(root, address)['base']! as String;

/// Writes an audit report naming each of [addresses] at its current hash.
Future<String> _auditNaming(
  Directory root,
  List<String> addresses, {
  String findings = 'Findings: none',
}) async {
  final folder = await writeTree({
    'audit.md': [
      for (final address in addresses)
        'Audited: $address@${_hashOf(root, address)}',
      findings,
    ].join('\n'),
  });
  return '${folder.path}/audit.md';
}

AutoApproveCall _call(
  Directory root, {
  List<String> names = const [_story, _fr],
  List<String> audits = const [],
  List<String> authors = const [],
  bool noAudit = false,
  String? mode = 'auto',
}) => AutoApproveCall(
  names: names,
  auditPaths: audits,
  authorPaths: authors,
  noAudit: noAudit,
  workingDirectory: root,
  approveModeVariable: mode,
);

Future<ReadAnswer> _approveAuto(
  Directory root,
  AutoApproveCall call, {
  MermaidNodeRun? runner,
  Duration? busyTimeout,
}) => WriteSession.runAsync(
  (s) => approveAuto(s, call, mermaidRunner: runner, generators: noGenerators),
  templates: TemplateResolver(),
  workingDirectory: root,
  homeDirectory: testHome(),
  busyTimeout: busyTimeout ?? indexBusyTimeout,
);

/// The bytes of every file of the docs folder.
Map<String, List<int>> _docBytes(Directory root) => {
  for (final MapEntry(:key, :value) in treeBytes(root).entries)
    if (key.startsWith('docs/')) key: value,
};

bool _isApproved(Directory root, String docPath) {
  final text = readDoc(root, docPath);
  return text.contains('\napproved: ') && !text.contains('draft: true');
}

bool _isDraft(Directory root, String docPath) {
  final text = readDoc(root, docPath);
  return text.contains('draft: true') && !text.contains('\napproved: ');
}

const _shortEdge = '1. E01 — An empty password → refused.\n';
const _longEdge =
    'E02 — An empty password → refused. A blank one is refused. A short one '
    'is refused. Each refusal shows one message. The page never tells which '
    'part was wrong. Each refusal takes the same time. Timing tells nothing '
    'either. No refusal locks the account. None of them is a real guess. The '
    'log keeps one line per refusal. That line holds no password. The line '
    'holds the time and the account. A reader of the log learns nothing '
    'more about the password. Each line stays for one week only. A password '
    'with a space in it is refused the same way. The refusal never echoes '
    'the password back to the page. A refused person may try again at once.';

/// The check project whose FR draft holds a long second edge case, approved
/// by the Owner's walk, so its approved copy is saved under the project.
Future<Directory> _approvedWithLongItem() async {
  final root = await check.writeCheckProject(
    extra: check.fr(_shortEdge, '${_shortEdge}2. $_longEdge\n'),
  );
  writeIn(
    root,
    (s) => approveDrafts(
      s,
      names: [_fr],
      readLine: () => 'y',
      out: StringBuffer(),
      generators: noGenerators,
    ),
  );
  ApprovedCopyStore(root).save(toLf(readDoc(root, check.loginFr)));
  return root;
}

/// The check project whose FR is a draft with a long second edge case, never
/// approved.
Future<Directory> _draftWithLongItem() => check.writeCheckProject(
  extra: check.edit(check.loginFr, [
    ('traced_from:\n', 'draft: true\ntraced_from:\n'),
    (_shortEdge, '${_shortEdge}2. $_longEdge\n'),
  ]),
);

/// Edits the approved FR of [root] to a draft, its approved mark kept, with
/// [change] added to its Rationale.
void _reopenAsDraft(Directory root, {String change = ''}) {
  final text = readDoc(root, check.loginFr)
      .replaceFirst('---\n', '---\ndraft: true\n')
      .replaceFirst(
        'A wrong password must not sign in.',
        'A wrong password must not sign in.${change.isEmpty ? '' : ' $change'}',
      );
  docFile(root, check.loginFr).writeAsStringSync(text);
}

void main() {
  test('approves clean drafts and asks a draft with a finding', () async {
    final root = await _draftsProject(frHasFinding: true);
    final audit = await _auditNaming(root, [_story, _fr]);

    final answer = await _approveAuto(root, _call(root, audits: [audit]));

    expect(
      answer.text,
      'mode: auto\n'
      'approved $_story\n'
      'ask $_fr: check finding required_section_missing\n',
    );
    expect(_isApproved(root, check.loginStory), isTrue);
    expect(_isDraft(root, check.loginFr), isTrue);
  });

  test('approves a draft whose Outside the drafts citer is queued', () async {
    final root = await _draftsProject();
    final audit = await _auditNaming(
      root,
      [_story, _fr],
      findings: [
        'Outside the drafts:',
        '- fr:login/other#statement: names $_fr',
      ].join('\n'),
    );
    final queued = await writeTree({'queued.md': 'Queued: fr:login/other'});

    final answer = await _approveAuto(
      root,
      _call(root, audits: [audit, '${queued.path}/queued.md']),
    );

    expect(answer.text, 'mode: auto\napproved $_story\napproved $_fr\n');
    expect(_isApproved(root, check.loginFr), isTrue);
  });

  test('auto call asks a draft a NOT ADDRESSED item names and approves one an ADDRESSED item names', () async {
    final root = await _draftsProject();
    final audit = await _auditNaming(
      root,
      [_story, _fr],
      findings: [
        'Verdicts:',
        '- ADDRESSED: $_story#goals: x',
        '- NOT ADDRESSED: $_fr#statement: x',
      ].join('\n'),
    );

    final answer = await _approveAuto(root, _call(root, audits: [audit]));

    expect(
      answer.text,
      'mode: auto\n'
      'approved $_story\n'
      'ask $_fr: named in Verdicts of audit.md\n',
    );
    expect(_isApproved(root, check.loginStory), isTrue);
    expect(_isDraft(root, check.loginFr), isTrue);
  });

  test(
    'the ask mode writes no approval and warns on an unknown value',
    () async {
      for (final (mode, warnings) in [
        ('ask', <String>[]),
        (null, <String>[]),
        (
          'yes',
          ['SPECSTONE_APPROVE_MODE=yes is neither ask nor auto; ask is used'],
        ),
      ]) {
        final root = await _draftsProject();
        final audit = await _auditNaming(root, [_story, _fr]);
        final before = _docBytes(root);

        final answer = await _approveAuto(
          root,
          _call(root, audits: [audit], mode: mode),
        );

        expect(
          answer.text,
          'mode: ask\n'
          'ask $_story: $_askMode\n'
          'ask $_fr: $_askMode\n',
        );
        expect(answer.warnings, warnings);
        expect(_docBytes(root), before);
      }
    },
  );

  test('leaves each draft a draft when no report flag is given', () async {
    final root = await _draftsProject();

    final answer = await _approveAuto(root, _call(root));

    expect(
      answer.text,
      'mode: auto\n'
      'ask $_story: $_noAudit\n'
      'ask $_fr: $_noAudit\n',
    );
    expect(_isDraft(root, check.loginStory), isTrue);
    expect(_isDraft(root, check.loginFr), isTrue);
  });

  // D2: a Decision line lands only on a section or field its doc holds.
  test('approves a draft whose Decision line names a field key its doc type declares', () async {
    final root = await _draftsProject();
    final folder = await writeTree({
      'author.md': 'Decision: D1 -> $_story#goals\n',
    });

    final answer = await _approveAuto(
      root,
      _call(root, noAudit: true, authors: ['${folder.path}/author.md']),
    );

    expect(answer.text, 'mode: auto\napproved $_story\napproved $_fr\n');
  });

  test('approves a draft whose Decision line names a section by its typed address or its DocPath', () async {
    for (final line in [
      'Decision: D1 -> $_story#use_case',
      'Decision: D1 -> ${check.loginStory}#use_case',
    ]) {
      final root = await _draftsProject();
      final folder = await writeTree({'author.md': '$line\n'});

      final answer = await _approveAuto(
        root,
        _call(root, noAudit: true, authors: ['${folder.path}/author.md']),
      );

      expect(
        answer.text,
        'mode: auto\napproved $_story\napproved $_fr\n',
        reason: line,
      );
    }
  });

  test(
    'asks every draft when a Decision line names a doc type the project lacks',
    () async {
      final root = await _draftsProject();
      final folder = await writeTree({
        'author.md': 'Decision: D1 -> nosuchtype:x#a\n',
      });

      final answer = await _approveAuto(
        root,
        _call(root, noAudit: true, authors: ['${folder.path}/author.md']),
      );

      expect(
        answer.text,
        'mode: auto\n'
        'ask $_story: not landed: D1 in author.md\n'
        'ask $_fr: not landed: D1 in author.md\n',
      );
    },
  );

  test('holds a twin doc only under the code target that names one, never on two docs', () async {
    final root = await writeTwinProject();
    final held = await WriteSession.runAsync(
      (s) async => [
        SectionLookup.ofIndex(s.index)
            .holds('architecture:login', 'components'),
        SectionLookup.ofIndex(
          s.index,
          codeTarget: 'jaspr',
        ).holds('architecture:login', 'components'),
        SectionLookup.ofIndex(
          s.index,
          codeTarget: 'jaspr',
        ).holds('architecture:login', 'no_such_key'),
      ],
      templates: TemplateResolver(),
      workingDirectory: root,
      homeDirectory: testHome(),
      busyTimeout: indexBusyTimeout,
    );

    expect(held, [false, true, false]);
  });

  test('asks every draft when a Decision line names a key its doc lacks or a doc the project lacks', () async {
    for (final line in [
      'Decision: D1 -> $_story#missing_key',
      'Decision: D1 -> user_story:login/missing_doc#goals',
    ]) {
      final root = await _draftsProject();
      final folder = await writeTree({'author.md': '$line\n'});

      final answer = await _approveAuto(
        root,
        _call(root, noAudit: true, authors: ['${folder.path}/author.md']),
      );

      expect(
        answer.text,
        'mode: auto\n'
        'ask $_story: not landed: D1 in author.md\n'
        'ask $_fr: not landed: D1 in author.md\n',
        reason: line,
      );
      expect(_isDraft(root, check.loginStory), isTrue, reason: line);
    }
  });

  test('approves under no-audit by the check alone', () async {
    final root = await _draftsProject();

    final answer = await _approveAuto(root, _call(root, noAudit: true));

    expect(answer.text, 'mode: auto\napproved $_story\napproved $_fr\n');
    expect(_isApproved(root, check.loginStory), isTrue);
    expect(_isApproved(root, check.loginFr), isTrue);
  });

  test('tags each asked draft with the one who clears it', () async {
    const longSentence =
        'word word word word word word word word word word '
        'word word word word word word word word word word word word word '
        'word word word word word word word word word word word word word '
        'word word word word word word word word word word.';
    const cases = [
      ('audit', 'audited at', 'stale', 'a stale audit'),
      ('owner', _askMode, 'ask', 'the ask mode'),
      ('owner', _noAudit, 'no audit', 'no audit report'),
      ('owner', 'check finding words_over_limit', 'long', 'a check finding'),
    ];

    for (final (waitsFor, reason, how, label) in cases) {
      final root = await _draftsProject();
      final audit = await _auditNaming(root, [_story, _fr]);
      if (how == 'stale' || how == 'long') {
        docFile(root, check.loginFr).writeAsStringSync(
          readDoc(root, check.loginFr).replaceFirst(
            'A wrong password must not sign in.',
            how == 'stale'
                ? 'A wrong password must not sign in at all.'
                : longSentence,
          ),
        );
      }
      final answer = await _approveAuto(
        root,
        _call(
          root,
          names: [_fr],
          audits: how == 'no audit' ? const [] : [audit],
          mode: how == 'ask' ? 'ask' : 'auto',
        ),
      );

      final ask = (answer.json['asked']! as List).single as Map;
      expect(ask['waitsFor'], waitsFor, reason: label);
      expect(ask['reason'], startsWith(reason), reason: label);
      expect(answer.text, contains('ask $_fr: ${ask['reason']}\n'));
    }
  });

  test('an audit ask carries its changed sections in doc order', () async {
    final root = await _draftsProject();
    final audit = await _auditNaming(root, [_fr]);
    AuditedCopyStore(root).save(check.loginFr, readDoc(root, check.loginFr));
    docFile(root, check.loginFr).writeAsStringSync(
      readDoc(root, check.loginFr)
          .replaceFirst(
            'A wrong password must not sign in.',
            'A wrong password is refused.',
          )
          .replaceFirst(
            '1. E01 — An empty password → refused.',
            '1. E01 — An empty password → rejected.',
          ),
    );

    final answer = await _approveAuto(
      root,
      _call(root, names: [_fr], audits: [audit]),
    );

    final ask = (answer.json['asked']! as List).single as Map;
    expect(ask['reason'], startsWith('audited at'));
    expect(ask['waitsFor'], 'audit');
    expect(ask['changedSections'], ['edge_cases', 'rationale']);
  });

  test(
    "approves a draft rewritten with its audit's fix text in one call",
    () async {
      final root = await _draftsProject();
      final before = _hashOf(root, _fr);
      AuditedCopyStore(root).save(check.loginFr, readDoc(root, check.loginFr));
      const fixed = 'A wrong password is refused.';
      docFile(root, check.loginFr).writeAsStringSync(
        readDoc(
          root,
          check.loginFr,
        ).replaceFirst('A wrong password must not sign in.', fixed),
      );
      final folder = await writeTree({
        'audit.md': [
          'Audited: $_fr@$before',
          'Findings:',
          '- $_fr#rationale: reword',
          '  Fix: $_fr#rationale',
          '  ```',
          '  $fixed',
          '  ```',
        ].join('\n'),
      });

      final answer = await _approveAuto(
        root,
        _call(root, names: [_fr], audits: ['${folder.path}/audit.md']),
      );

      expect(answer.text, 'mode: auto\napproved $_fr\n');
      expect(_isApproved(root, check.loginFr), isTrue);
    },
  );

  test('asks a draft whose fix line names a doc that is not UTF-8 and keeps the approvals before it', () async {
    final root = await _draftsProject();
    final audit = await _auditNaming(
      root,
      [_story, _fr],
      findings: [
        'Findings:',
        '- $_fr#rationale: reword',
        '  Fix: ${check.loginNf}#statement',
        '  ```',
        '  Text.',
        '  ```',
      ].join('\n'),
    );
    final nf = docFile(root, check.loginNf);
    nf.writeAsBytesSync([...nf.readAsBytesSync(), 0xff]);

    final answer = await _approveAuto(root, _call(root, audits: [audit]));

    expect(
      answer.text,
      'mode: auto\napproved $_story\n'
      'ask $_fr: named in Findings of audit.md\n',
    );
    expect(_isApproved(root, check.loginStory), isTrue);
  });

  test('prints the JSON keys in doc order', () async {
    final root = await _draftsProject(frHasFinding: true);
    final audit = await _auditNaming(root, [_story, _fr]);

    final answer = await _approveAuto(
      root,
      _call(root, names: [_fr, _story], audits: [audit]),
    );

    expect(answer.json, {
      'approveMode': 'auto',
      'approved': [
        {'doc': _story, 'path': check.loginStory, 'carried': <Object>[]},
      ],
      'asked': [
        {
          'doc': _fr,
          'path': check.loginFr,
          'reason': 'check finding required_section_missing',
          'waitsFor': 'owner',
        },
      ],
      'rewritten': <Object>[],
      'deleted': <Object>[],
    });
    expect(answer.json.keys, [
      'approveMode',
      'approved',
      'asked',
      'rewritten',
      'deleted',
    ]);
    expect(answer.warnings, isEmpty);

    final other = await _draftsProject();
    final warned = await _approveAuto(other, _call(other, mode: 'yes'));
    expect(warned.warnings, [
      'SPECSTONE_APPROVE_MODE=yes is neither ask nor auto; ask is used',
    ]);
  });

  test("stores each approval's copy, then prunes the store", () async {
    final root = await _draftsProject();
    final stale = File('${root.path}/.specstone/approved/${'0' * 12}.md')
      ..createSync(recursive: true)
      ..writeAsStringSync('---\napproved: "${'0' * 12}"\n---\n\n# Stale\n');

    await _approveAuto(root, _call(root, noAudit: true));

    final copies = Directory('${root.path}/.specstone/approved')
        .listSync()
        .map((entry) => entry.uri.pathSegments.last)
        .toSet();
    final mark = RegExp('approved: "([0-9a-f]+)"');
    final marks = {
      for (final docPath in [check.loginStory, check.loginFr])
        '${mark.firstMatch(readDoc(root, docPath))![1]}.md',
    };
    expect(copies, marks);
    expect(stale.existsSync(), isFalse);
  });

  test('refuses a name that is no draft before the mode gate', () async {
    for (final mode in ['auto', 'ask']) {
      final root = await _draftsProject();
      final before = _docBytes(root);

      await expectLater(
        _approveAuto(
          root,
          _call(
            root,
            names: [_story, 'feature:login'],
            noAudit: true,
            mode: mode,
          ),
        ),
        throwsA(
          isA<WriteFault>().having(
            (f) => f.code,
            'code',
            WriteFaultCode.draftNotFound,
          ),
        ),
      );
      expect(_docBytes(root), before);
    }
  });

  test('refuses while the roots wait for the trust record', () async {
    final base = await writeTree({
      for (final MapEntry(:key, :value) in writeProject.entries)
        if (key.startsWith('docs/'))
          'ext/${key.substring(5)}': value
        else
          'src/clone/$key': value,
    });
    createRelativeLink('${base.path}/src/clone/docs', '../../ext');
    final clone = Directory('${base.path}/src/clone');
    final before = treeBytes(Directory('${base.path}/ext'));

    for (final mode in ['auto', 'ask']) {
      await expectLater(
        _approveAuto(
          clone,
          _call(clone, names: ['feature:signup'], noAudit: true, mode: mode),
        ),
        throwsA(
          isA<RenderFault>()
              .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
              .having((f) => f.exitStatus, 'exit', 73),
        ),
      );
    }
    expect(treeBytes(Directory('${base.path}/ext')), before);
  }, skip: _linksUnavailable);

  test('holds the lock from the check to the last write', () async {
    final root = await _draftsProject(
      extra: check.edit(check.loginArchitecture, [
        ('One box.', '```mermaid\nsequenceDiagram\n  A->>B: ok\n```'),
      ]),
    );
    _createIndex(root);
    // A long report makes the judgment between the check and the writes take
    // long enough for a second connection to take any gap in the hold.
    final audit = await _auditNaming(
      root,
      [_story, _fr],
      findings: [
        'Findings:',
        for (var i = 0; i < 100000; i++) '- a finding of no draft $i',
      ].join('\n'),
    );
    final taker = _LockTaker(root);
    addTearDown(taker.dispose);

    await _approveAuto(
      root,
      _call(root, audits: [audit]),
      runner: MermaidNodeRun(
        start: (arguments) async {
          await taker.start();
          return _startFakeNode(arguments);
        },
      ),
    );

    final story = await taker.storyAtFirstFreeLock();
    expect(story, contains('\napproved: '));
    expect(story, isNot(contains('draft: true')));
    expect(_isApproved(root, check.loginFr), isTrue);
  });

  test('faults index_busy on a held lock and writes no doc', () async {
    final root = await _draftsProject();
    _createIndex(root);
    final before = _docBytes(root);
    final other = sqlite3.open('${root.path}/.specstone/index.sqlite')
      ..execute('BEGIN IMMEDIATE');
    addTearDown(other.close);

    await expectLater(
      _approveAuto(
        root,
        _call(root, noAudit: true),
        busyTimeout: const Duration(milliseconds: 200),
      ),
      throwsA(
        isA<IndexFault>()
            .having((f) => f.code, 'code', IndexFaultCode.indexBusy)
            .having((f) => f.exitStatus, 'exit', 75),
      ),
    );

    other.close();
    expect(_docBytes(root), before);
  });

  test('a draft gone inside the hold is base_mismatch, exit 75, '
      'and nothing is approved', () async {
    final root = await _draftsProject(
      extra: check.edit(check.loginArchitecture, [
        ('One box.', '```mermaid\nsequenceDiagram\n  A->>B: ok\n```'),
      ]),
    );
    final storyBefore = readDoc(root, check.loginStory);

    await expectLater(
      _approveAuto(
        root,
        _call(root, noAudit: true),
        runner: MermaidNodeRun(
          start: (arguments) async {
            docFile(root, check.loginFr).deleteSync();
            return _startFakeNode(arguments);
          },
        ),
      ),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.code, 'code', WriteFaultCode.baseMismatch)
            .having((f) => f.exitStatus, 'exitStatus', 75)
            .having((f) => f.file, 'file', check.loginFr)
            .having(
              (f) => f.message,
              'message',
              'changed since their hash was taken: $_fr; '
                  'read each again and approve it with its new hash',
            ),
      ),
    );
    expect(readDoc(root, check.loginStory), storyBefore);
  });

  test('stores a fresh diagram parse inside the auto hold', () async {
    const block = 'sequenceDiagram\n  A->>B: ok';
    final root = await _draftsProject(
      extra: check.edit(check.loginArchitecture, [
        ('One box.', '```mermaid\n$block\n```'),
      ]),
    );
    _createIndex(root);
    final other = IndexStore.open(root, busyTimeout: Duration.zero);
    addTearDown(other.close);
    Object? duringCheck;

    final answer = await _approveAuto(
      root,
      _call(root, noAudit: true),
      runner: MermaidNodeRun(
        start: (arguments) async {
          try {
            other.write(() {});
          } on IndexFault catch (fault) {
            duringCheck = fault.code;
          }
          return _startFakeNode(arguments);
        },
      ),
    );

    expect(answer.text, 'mode: auto\napproved $_story\napproved $_fr\n');
    expect(duringCheck, IndexFaultCode.indexBusy);
    final raw = sqlite3.open('${root.path}/.specstone/index.sqlite');
    addTearDown(raw.close);
    expect(
      raw.select('SELECT count(*) AS n FROM diagram_parses').single['n'],
      1,
    );
  });

  test("carries the check's warnings into the answer", () async {
    final root = await _draftsProject(
      extra: check.edit(check.loginArchitecture, [
        ('One box.', '```mermaid\nsequenceDiagram\n  A->>B: ok\n```'),
      ]),
    );

    final answer = await _approveAuto(
      root,
      _call(root, noAudit: true),
      runner: MermaidNodeRun(
        start: (_) => throw const ProcessException('node', [], 'gone', 2),
      ),
    );

    expect(answer.text, 'mode: auto\napproved $_story\napproved $_fr\n');
    expect(answer.warnings, ['Mermaid parse skipped: node not found']);
  });

  group('a long item the approved copy holds', () {
    final skipGit = hasGit ? null : 'git is not available';

    test('passes a long item the committed approved copy holds', () async {
      final root = await _approvedWithLongItem();
      expect(git(root, ['init', '-q']).exitCode, 0);
      commitAll(root, 'approved');
      Directory('${root.path}/.specstone/approved').deleteSync(recursive: true);
      _reopenAsDraft(root, change: 'It must not.');

      final answer = await _approveAuto(
        root,
        _call(root, names: [_fr], noAudit: true),
      );

      expect(answer.text, 'mode: auto\napproved $_fr\n');
      expect(_isApproved(root, check.loginFr), isTrue);
    }, skip: skipGit);

    test(
      'passes a long item the saved copy holds when git cannot answer',
      () async {
        final root = await _approvedWithLongItem();
        _reopenAsDraft(root, change: 'It must not.');

        final answer = await _approveAuto(
          root,
          _call(root, names: [_fr], noAudit: true),
        );

        expect(answer.text, 'mode: auto\napproved $_fr\n');
        expect(_isApproved(root, check.loginFr), isTrue);
      },
    );

    test('asks a long item the run changed', () async {
      final root = await _approvedWithLongItem();
      _reopenAsDraft(root);
      final text = readDoc(
        root,
        check.loginFr,
      ).replaceFirst('one message', 'two messages');
      docFile(root, check.loginFr).writeAsStringSync(text);

      final answer = await _approveAuto(
        root,
        _call(root, names: [_fr], noAudit: true),
      );

      expect(
        answer.text,
        'mode: auto\nask $_fr: check finding item_over_limit\n',
      );
      expect(readDoc(root, check.loginFr), contains('draft: true'));
    });
  });

  group('a long item with no approved copy', () {
    final skipGit = hasGit ? null : 'git is not available';

    test('asks a long item of a draft never approved', () async {
      final root = await _draftWithLongItem();

      final answer = await _approveAuto(
        root,
        _call(root, names: [_fr], noAudit: true),
      );

      expect(
        answer.text,
        'mode: auto\nask $_fr: check finding item_over_limit\n',
      );
      expect(_isApproved(root, check.loginFr), isFalse);
    });

    test('asks a long item of a draft git has no approved copy of', () async {
      final root = await _draftWithLongItem();
      expect(git(root, ['init', '-q']).exitCode, 0);
      commitAll(root, 'draft');

      final answer = await _approveAuto(
        root,
        _call(root, names: [_fr], noAudit: true),
      );

      expect(
        answer.text,
        'mode: auto\nask $_fr: check finding item_over_limit\n',
      );
      expect(_isApproved(root, check.loginFr), isFalse);
    }, skip: skipGit);
  });

  group('a finding the approved copy carries', () {
    /// The check project whose FR holds a bulky Rationale and whose story holds
    /// a scenario with two items, each approved with its copy saved, then both
    /// reopened as drafts, unchanged.
    Future<Directory> reopenedWithFindings() async {
      final root = await check.writeCheckProject(
        extra: {
          ...check.edit(check.loginFr, [
            ('A wrong password must not sign in.\n', '$_bulkyRationale\n'),
          ]),
          ...check.edit(check.loginStory, [
            (
              '### Scenario 1 — [happy] Sign in\n\n- **Given** an account\n',
              '### Scenario 1 — [happy] Sign in\n\n',
            ),
          ]),
        },
      );
      writeIn(
        root,
        (s) => approveDrafts(
          s,
          names: [_story, _fr],
          readLine: () => 'y',
          out: StringBuffer(),
          generators: noGenerators,
        ),
      );
      for (final path in [check.loginStory, check.loginFr]) {
        ApprovedCopyStore(root).save(toLf(readDoc(root, path)));
      }
      _reopenAsDraft(root);
      final story = readDoc(root, check.loginStory);
      docFile(
        root,
        check.loginStory,
      ).writeAsStringSync(story.replaceFirst('---\n', '---\ndraft: true\n'));
      return root;
    }

    test(
      'an approved entry lists each carried finding, empty when none',
      () async {
        final root = await reopenedWithFindings();

        final answer = await _approveAuto(
          root,
          _call(root, names: [_fr, _story], noAudit: true),
        );

        final approved = (answer.json['approved']! as List)
            .cast<Map<String, Object?>>();
        expect(approved.map((entry) => entry['doc']), [_story, _fr]);
        expect(approved[0]['carried'], [
          {
            'kind': 'item_count_out_of_range',
            'place': 'acceptance_criteria ### Scenario 1 — [happy] Sign in',
          },
        ]);
        expect(approved[1]['carried'], [
          {'kind': 'chars_over_limit', 'place': 'doc'},
          {'kind': 'chars_over_limit', 'place': 'rationale'},
        ]);

        final clean = await _draftsProject();
        final plain = await _approveAuto(clean, _call(clean, noAudit: true));
        expect(
          (plain.json['approved']! as List).cast<Map<String, Object?>>().map(
            (entry) => entry['carried'],
          ),
          [<Object>[], <Object>[]],
        );
      },
    );

    test('prints a carried place for the doc, a section, and a subsection', () async {
      final root = await reopenedWithFindings();

      final answer = await _approveAuto(
        root,
        _call(root, names: [_fr, _story], noAudit: true),
      );

      expect(
        answer.text,
        'mode: auto\n'
        'approved $_story\n'
        'carried $_story: item_count_out_of_range at acceptance_criteria ### Scenario 1 — [happy] Sign in\n'
        'approved $_fr\n'
        'carried $_fr: chars_over_limit at doc\n'
        'carried $_fr: chars_over_limit at rationale\n',
      );
    });

    test('a draft with no found copy passes no finding as carried', () async {
      final never = await check.writeCheckProject(
        extra: check.edit(check.loginFr, [
          ('traced_from:\n', 'draft: true\ntraced_from:\n'),
          ('A wrong password must not sign in.\n', '$_bulkyRationale\n'),
        ]),
      );
      const asked = 'mode: auto\nask $_fr: check finding chars_over_limit\n';

      final answer = await _approveAuto(
        never,
        _call(never, names: [_fr], noAudit: true),
      );

      expect(answer.text, asked);
      expect(_isApproved(never, check.loginFr), isFalse);

      if (!hasGit) return;
      expect(git(never, ['init', '-q']).exitCode, 0);
      commitAll(never, 'draft');
      final committed = await _approveAuto(
        never,
        _call(never, names: [_fr], noAudit: true),
      );
      expect(committed.text, asked);
    });

    test('a clean call runs no copy check', () async {
      const copyBlock = 'sequenceDiagram\n  A->>B: copy';
      final root = await check.writeCheckProject(
        extra: check.edit(check.loginFr, [
          (
            'A wrong password must not sign in.\n',
            'A wrong password must not sign in.\n\n```mermaid\n$copyBlock\n```\n',
          ),
        ]),
      );
      writeIn(
        root,
        (s) => approveDrafts(
          s,
          names: [_fr],
          readLine: () => 'y',
          out: StringBuffer(),
          generators: noGenerators,
        ),
      );
      ApprovedCopyStore(root).save(toLf(readDoc(root, check.loginFr)));
      docFile(root, check.loginFr).writeAsStringSync(
        readDoc(root, check.loginFr)
            .replaceFirst('---\n', '---\ndraft: true\n')
            .replaceFirst('A->>B: copy', 'A->>B: draft'),
      );
      final parsed = <String>[];

      final answer = await _approveAuto(
        root,
        _call(root, names: [_fr], noAudit: true),
        runner: MermaidNodeRun(
          start: (arguments) {
            parsed.add(arguments.join(' '));
            return _startFakeNode(arguments);
          },
        ),
      );

      expect(answer.text, 'mode: auto\napproved $_fr\n');
      expect(parsed, hasLength(1));
    });
  });

  group('a size finding the approved copy holds', () {
    test('approves a draft whose doc-level chars finding its committed copy already had', () async {
      final root = await _approvedWithSize(rationale: _bulkyRationale);
      expect(git(root, ['init', '-q']).exitCode, 0);
      commitAll(root, 'approved');
      Directory('${root.path}/.specstone/approved').deleteSync(recursive: true);
      _reopenAsDraft(root);

      final answer = await _approveAuto(
        root,
        _call(root, names: [_fr], noAudit: true),
      );

      expect(answer.text, _approvedBulky);
      expect(_isApproved(root, check.loginFr), isTrue);
    }, skip: hasGit ? null : 'git is not available');

    test('approves an unchanged reopened draft whose doc-level chars finding its saved copy already had', () async {
      final root = await _approvedWithSize(rationale: _bulkyRationale);
      _reopenAsDraft(root);

      final answer = await _approveAuto(
        root,
        _call(root, names: [_fr], noAudit: true),
      );

      expect(answer.text, _approvedBulky);
      expect(_isApproved(root, check.loginFr), isTrue);
    });

    test(
      'asks a draft whose new edge case pushed its section over its item cap',
      () async {
        final root = await _approvedWithSize(edgeCases: 8);
        _reopenAsDraft(root);
        docFile(root, check.loginFr).writeAsStringSync(
          readDoc(root, check.loginFr).replaceFirst(
            '8. E08 — An empty password 8 → refused.\n',
            '8. E08 — An empty password 8 → refused.\n'
                '9. E09 — An empty password 9 → refused.\n',
          ),
        );

        final answer = await _approveAuto(
          root,
          _call(root, names: [_fr], noAudit: true),
        );

        expect(
          answer.text,
          'mode: auto\nask $_fr: check finding item_count_out_of_range\n',
        );
        expect(readDoc(root, check.loginFr), contains('draft: true'));
      },
    );
  });
}

/// The answer for the reopened FR whose bulky Rationale its copy already had.
const _approvedBulky =
    'mode: auto\napproved $_fr\n'
    'carried $_fr: chars_over_limit at doc\n'
    'carried $_fr: chars_over_limit at rationale\n';

final String _bulkyRationale = [
  for (var i = 1; i <= 48; i++)
    'Case $i: ${'A wrong password must not sign in. ' * 13}'.trim(),
].join('\n\n');

/// The check project whose FR holds [edgeCases] edge cases and a Rationale of
/// [rationale], approved by the Owner's walk, its approved copy saved.
Future<Directory> _approvedWithSize({
  int edgeCases = 1,
  String rationale = 'A wrong password must not sign in.',
}) async {
  final edges = [
    for (var i = 1; i <= edgeCases; i++)
      '$i. E0$i — An empty password $i → refused.',
  ];
  final root = await check.writeCheckProject(
    extra: check.edit(check.loginFr, [
      (
        '$_shortEdge\n## Rationale\n\nA wrong password must not sign in.\n',
        '${edges.join('\n')}\n\n## Rationale\n\n$rationale\n',
      ),
    ]),
  );
  writeIn(
    root,
    (s) => approveDrafts(
      s,
      names: [_fr],
      readLine: () => 'y',
      out: StringBuffer(),
      generators: noGenerators,
    ),
  );
  ApprovedCopyStore(root).save(toLf(readDoc(root, check.loginFr)));
  return root;
}

void _createIndex(Directory root) => WriteSession.run(
  (_) {},
  templates: TemplateResolver(),
  workingDirectory: root,
  homeDirectory: testHome(),
);

/// A second connection that tries for the write lock in a tight loop from
/// [start], so it takes the first moment the lock is free, and reads the story
/// at that moment.
final class _LockTaker {
  new(this._root);

  final Directory _root;
  final _messages = ReceivePort();
  final _ready = Completer<void>();
  final _story = Completer<String>();
  Isolate? _isolate;

  Future<void> start() async {
    _messages.listen((message) {
      if (message == 'ready') _ready.complete();
      if (message is String && message != 'ready') _story.complete(message);
      if (message is List) _story.completeError(StateError('${message[0]}'));
    });
    _isolate = await Isolate.spawn(_takeLock, (
      _root.path,
      _messages.sendPort,
    ), onError: _messages.sendPort);
    await _ready.future.timeout(const Duration(seconds: 10));
  }

  /// The story as it stood when the lock was first free.
  Future<String> storyAtFirstFreeLock() =>
      _story.future.timeout(const Duration(seconds: 20));

  void dispose() {
    _messages.close();
    _isolate?.kill();
  }
}

void _takeLock((String, SendPort) arguments) {
  final (path, port) = arguments;
  final database = sqlite3.open('$path/.specstone/index.sqlite');
  port.send('ready');
  while (true) {
    try {
      database.execute('BEGIN IMMEDIATE');
    } on SqliteException {
      continue;
    }
    final story = File('$path/docs/${check.loginStory}').readAsStringSync();
    database
      ..execute('ROLLBACK')
      ..close();
    port.send(story);
    return;
  }
}

Future<Process> _startFakeNode(List<String> arguments) async {
  final stdin = StreamController<List<int>>();
  unawaited(stdin.stream.drain<void>());
  return _FakeNodeProcess(
    IOSink(stdin),
    Stream.value(utf8.encode('{"i":0,"diagram":"sequence","parses":true}\n')),
  );
}

final class _FakeNodeProcess implements Process {
  new(this.stdin, this.stdout);

  @override
  final IOSink stdin;

  @override
  final Stream<List<int>> stdout;

  @override
  Future<int> get exitCode async => 0;

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  int get pid => 0;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
}
