// A matrix row matches a test name as one literal, so long names stay whole.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/code_fingerprint.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/set_sync.dart';
import 'package:specstone_core/src/document_writing/sync_lines.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/write_fixture.dart' hide loginFeature;

const _arch = 'charter:login';

/// The doc whose `covers` the tests stamp: a charter, which holds `covers`
/// and `tasks` both.
const _coversDoc = 'specs/topics/login.md';
const _record = 'implementation:login';
const _login = 'app/lib/login.dart';
const _old = '0123456789ab';
const _checkPassword = 'email_login/check_password';
const _signIn = 'email_login:$_login:SignInPage';
const _check = '$_checkPassword:$_login:checkPassword';
const _gone = 'app/lib/gone.dart';
const _other = 'app/lib/other.dart';
const _otherText = 'class Other {}\n';
const _removal = 'remove-task ENG-1 $_coversDoc $_login';

final String _loginFingerprint = fileCodeFingerprint(
  utf8.encode(checkProjectFiles()[_login]!),
  path: _login,
);
final String _otherFingerprint = fileCodeFingerprint(
  utf8.encode(_otherText),
  path: _other,
);
final String _contractFingerprint = fingerprintFor(
  '## Statement\n\n$checkPasswordStatement\n\n'
  '## Edge cases\n\n1. E01 — An empty password → refused.',
);

/// The login FR as a pending draft.
Map<String, String> _draftFr() =>
    edit(loginFr, [('traced_from:', 'draft: true\ntraced_from:')]);

/// Returns the record: one `implemented` story, one `planned` FR, and their
/// `implements` lines, with no fingerprint; [head] leads its frontmatter.
String _recordText({String head = ''}) =>
    "---\n${head}statuses:\n  - 'email_login:implemented'\n"
    "  - '$_checkPassword:planned'\nimplements:\n"
    "  - '$_signIn'\n  - '$_check'\n"
    '---\n\n# Login implementation\n';

/// Returns the check fixture, its charter doc covering [covers] and
/// holding [tasks], and its record from [_recordText], both with code links as
/// written; a key in [extra] replaces or adds a file.
Future<Directory> _project({
  List<String> covers = const [_login],
  List<String> tasks = const [],
  String recordHead = '',
  Map<String, String> extra = const {},
}) => writeCheckProject(
  extra: {
    'docs/$_coversDoc':
        '---\ncovers:\n${[for (final entry in covers) '  - $entry\n', if (tasks.isNotEmpty) 'tasks:\n', for (final task in tasks) '  - $task\n'].join()}---\n\n# Login rules\n',
    loginRecord: _recordText(head: recordHead),
    ...extra,
  },
  unstamped: {loginRecord},
  unfingerprinted: {'docs/$_coversDoc', loginRecord},
);

ParsedSync _parsed(List<String> lines) =>
    parseSyncFile('sync.txt', '${lines.join('\n')}\n');

ReadAnswer _sync(Directory root, List<String> lines) =>
    writeIn(root, (session) => answerSetSync(session, _parsed(lines)));

SyncFault _refused(Directory root, List<String> lines) {
  try {
    _sync(root, lines);
  } on SyncFault catch (fault) {
    return fault;
  }
  fail('the sync was not refused');
}

/// The docs of [root] as bytes, for the check that a run wrote nothing.
Map<String, List<int>> _docBytes(Directory root) => {
  ...treeBytes(Directory('${root.path}/docs')),
  loginRecord: File('${root.path}/$loginRecord').readAsBytesSync(),
};

/// The naming line of [address] as a written sync prints it, its base the
/// one `get` prints now.
String _namingLine(Directory root, String address) {
  final doc = getDoc(root, address);
  final base = doc['base'];
  return '==> ${doc['name']} (${doc['docType']}) · ${doc['path']} · base $base <==\n';
}

/// The address a waiting line names [docPath] by.
String _address(Directory root, String docPath) {
  final doc = getDoc(root, docPath);
  return '${doc['docType']}:${doc['name']}';
}

void main() {
  test('matches on two docs write both in one journal and print each naming line in doc path order', () async {
    final root = await _project();
    final archBefore = readDoc(root, _coversDoc);
    final recordBefore = readDoc(root, loginRecord);

    final answer = _sync(root, [
      'match $_arch $_login $_loginFingerprint',
      'match $_record $_signIn $_loginFingerprint',
    ]);

    expect(
      readDoc(root, _coversDoc),
      archBefore.replaceFirst(
        '  - $_login\n',
        '  - $_login $_loginFingerprint\n',
      ),
    );
    expect(
      readDoc(root, loginRecord),
      recordBefore.replaceFirst("'$_signIn'", "'$_signIn $_loginFingerprint'"),
    );
    final lines = {
      for (final address in [_arch, _record])
        getDoc(root, address)['path']! as String: _namingLine(root, address),
    };
    final paths = lines.keys.toList()..sort();
    expect(answer.text, paths.map((path) => lines[path]).join());
    expect(MoveJournal.pending(root), isFalse);
  });

  test('a match on a planned entry sets it implemented, and a planned line stamps it and keeps it planned', () async {
    for (final (kind, status) in [
      ('match', 'implemented'),
      ('planned', 'planned'),
    ]) {
      final root = await _project();

      _sync(root, ['$kind $_record $_check $_loginFingerprint']);

      final record = readDoc(root, loginRecord);
      expect(record, contains("'$_check $_loginFingerprint'"), reason: kind);
      expect(record, contains("'$_checkPassword:$status'"), reason: kind);
      expect(record, contains("'email_login:implemented'"), reason: kind);
    }
  });

  test('a repoint and a verdict line of one entry land in one write, the verdict naming the old path or the new one, before or after it', () async {
    const gone = 'app/lib/gone.dart';
    const repoint = 'repoint $_arch $gone $_login';
    for (final lines in [
      [repoint, 'match $_arch $gone $_loginFingerprint'],
      [repoint, 'match $_arch $_login $_loginFingerprint'],
      ['match $_arch $gone $_loginFingerprint', repoint],
      ['match $_arch $_login $_loginFingerprint', repoint],
    ]) {
      final root = await _project(covers: const ['$gone $_old']);
      final before = readDoc(root, _coversDoc);

      _sync(root, lines);

      expect(
        readDoc(root, _coversDoc),
        before.replaceFirst(
          '  - $gone $_old\n',
          '  - $_login $_loginFingerprint\n',
        ),
        reason: '$lines',
      );
    }
  });

  test(
    'a repoint keeps an implements entry item, Symbol, and fingerprint',
    () async {
      const moved = 'app/lib/sign_in.dart';
      final root = await _project();
      File('${root.path}/$_login').renameSync('${root.path}/$moved');

      _sync(root, [
        'planned $_record $_check $_loginFingerprint',
        'repoint $_record $_check $moved',
      ]);

      expect(
        readDoc(root, loginRecord),
        contains("'$_checkPassword:$moved:checkPassword $_loginFingerprint'"),
      );
    },
  );

  test('a match line beside a verdict line naming its entry another way, by DocPath or by the path a repoint gives, refuses argument_invalid naming both lines and writes nothing', () async {
    const gone = 'app/lib/gone.dart';
    for (final (covers, lines) in [
      (
        const [_login],
        [
          'match $_arch $_login $_loginFingerprint',
          'mismatch $_coversDoc $_login: a point',
        ],
      ),
      (
        const [gone],
        [
          'repoint $_arch $gone $_login',
          'match $_arch $gone $_loginFingerprint',
          'match $_arch $_login $_loginFingerprint',
        ],
      ),
    ]) {
      final root = await _project(covers: covers);
      final before = _docBytes(root);

      final fault = _refused(root, lines);

      final refusal = fault.refusals.single;
      expect(refusal.line, lines.length, reason: '$lines');
      expect(refusal.code, 'argument_invalid', reason: '$lines');
      expect(
        refusal.message,
        endsWith(
          'already holds the verdict of line ${lines.length - 1}; '
          'a match or planned line stands alone',
        ),
        reason: '$lines',
      );
      expect(fault.exitStatus, 64, reason: '$lines');
      expect(_docBytes(root), before, reason: '$lines');
    }
  });

  test(
    'a line left ? refuses verdict_unjudged naming the line and writes no doc',
    () async {
      final root = await _project();
      final before = _docBytes(root);

      final fault = _refused(root, [
        'match $_arch $_login $_loginFingerprint',
        '? $_record $_signIn $_loginFingerprint',
      ]);

      expect(fault.exitStatus, 64);
      final refusal = fault.refusals.single;
      expect(refusal.line, 2);
      expect(refusal.code, WriteFaultCode.verdictUnjudged.wire);
      expect(
        refusal.message,
        'the verdict is still ?; write match, planned, or mismatch',
      );
      expect(_docBytes(root), before);
    },
  );

  test('a match whose fingerprint differs from the code refuses stamp_stale with exit status 75 and writes no doc', () async {
    final root = await _project();
    final before = _docBytes(root);

    final fault = _refused(root, [
      'match $_record $_signIn $_loginFingerprint',
      'match $_arch $_login $_old',
    ]);

    expect(fault.exitStatus, 75);
    final refusal = fault.refusals.single;
    expect(refusal.line, 2);
    expect(refusal.code, 'stamp_stale');
    expect(refusal.message, '$_login changed after $_old; judge it again');
    expect(_docBytes(root), before);
  });

  test('an entry its doc does not hold refuses stamp_entry_unknown, and one that does not resolve refuses stamp_entry_unresolved, each line named and no doc written', () async {
    final root = await _project(covers: const [_login, 'app/lib/gone.dart']);
    final before = _docBytes(root);

    final fault = _refused(root, [
      'match $_arch $_login $_loginFingerprint',
      'match $_arch app/lib/none.dart $_old',
      'repoint $_record email_login:app/lib/none.dart:X app/lib/x.dart',
      'planned $_arch app/lib/gone.dart $_old',
      'mismatch $_record email_login:app/lib/none.dart:X: the page is gone',
    ]);

    expect(fault.exitStatus, 64);
    expect(
      [
        for (final refusal in fault.refusals)
          '${refusal.line} ${refusal.code}: ${refusal.message}',
      ],
      [
        '2 stamp_entry_unknown: no entry of $_arch reads app/lib/none.dart',
        '3 stamp_entry_unknown: no entry of $_record reads email_login:app/lib/none.dart:X',
        '4 stamp_entry_unresolved: app/lib/gone.dart does not resolve: covers_path_missing',
        '5 stamp_entry_unknown: no entry of $_record reads email_login:app/lib/none.dart:X',
      ],
    );
    expect(_docBytes(root), before);
  });

  test('mismatch lines alone write no doc and no journal and list each line under Mismatches', () async {
    final root = await _project();
    final before = _docBytes(root);
    const lines = [
      'mismatch $_arch $_login: the form takes no email',
      'mismatch $_arch $_login: the page has no title',
    ];

    final answer = writeInNoHome(
      root,
      (session) => answerSetSync(session, _parsed(lines)),
    );

    expect(answer.text, 'Mismatches:\n${lines.join('\n')}\n');
    expect(answer.json['docs'], isEmpty);
    expect(answer.json['mismatches'], lines);
    expect(_docBytes(root), before);
  });

  test('a rerun of a written sync file writes no doc and no journal', () async {
    const gone = 'app/lib/gone.dart';
    final root = await _project(covers: const ['$gone $_old']);
    final lines = [
      'repoint $_arch $gone $_login',
      'match $_arch $gone $_loginFingerprint',
      'match $_record $_check $_loginFingerprint',
    ];
    _sync(root, lines);
    final after = _docBytes(root);

    final again = writeInNoHome(
      root,
      (session) => answerSetSync(session, _parsed(lines)),
    );

    expect(again.text, isEmpty);
    expect(again.json['docs'], isEmpty);
    expect(_docBytes(root), after);
  });

  test(
    'each written doc keeps its draft flag and its approval as they were',
    () async {
      final root = await _project(recordHead: 'draft: true\n');
      final approved = RegExp(
        r'^approved: .*$',
        multiLine: true,
      ).firstMatch(readDoc(root, _coversDoc))![0];

      _sync(root, [
        'match $_arch $_login $_loginFingerprint',
        'match $_record $_check $_loginFingerprint',
      ]);

      final arch = readDoc(root, _coversDoc);
      expect(arch, contains('$approved\n'));
      expect(arch, isNot(contains('draft:')));
      expect(readDoc(root, loginRecord), contains('\ndraft: true\n'));
    },
  );

  test('a match, planned, or repoint line whose covering doc is a draft writes nothing and is listed under Waiting with the draft address, the other lines written', () async {
    final root = await _project(
      covers: const ['$_gone $_old', _other],
      extra: {..._draftFr(), _other: _otherText},
    );
    final archBefore = readDoc(root, _coversDoc);
    final recordBefore = readDoc(root, loginRecord);
    final waiting = [
      'repoint $_arch $_gone $_login',
      'match $_arch $_gone $_loginFingerprint',
      'planned $_record $_check $_loginFingerprint',
    ];

    final answer = _sync(root, [
      ...waiting,
      'match $_arch $_other $_otherFingerprint',
    ]);

    final listed = [
      for (final line in waiting)
        '$line · waits for ${_address(root, loginFr)}',
    ];
    expect(
      readDoc(root, _coversDoc),
      archBefore.replaceFirst(
        '  - $_other\n',
        '  - $_other $_otherFingerprint\n',
      ),
    );
    expect(readDoc(root, loginRecord), recordBefore);
    expect(
      answer.text,
      '${_namingLine(root, _arch)}Waiting:\n${listed.join('\n')}\n',
    );
    expect(answer.json['waiting'], listed);
  });

  test('a remove-task line whose link match waits waits too and keeps the task refs', () async {
    final root = await _project(tasks: const ['ENG-1'], extra: _draftFr());
    final before = _docBytes(root);
    final lines = ['match $_arch $_login $_loginFingerprint', _removal];

    final answer = _sync(root, lines);

    final draft = _address(root, loginFr);
    expect(
      answer.text,
      'Waiting:\n${[for (final line in lines) '$line · waits for $draft'].join('\n')}\n',
    );
    expect(answer.json['kept'], isEmpty);
    expect(answer.json['noRefs'], isEmpty);
    expect(_docBytes(root), before);
  });

  test('a remove-task line on a named tests entry waits for the draft FR its test file traces to', () async {
    const entry =
        '$_checkPassword:app/test/login_test.dart:refuses an empty password';
    const line = 'remove-task ENG-1 $_record $entry';
    final root = await _project(
      extra: {
        ..._draftFr(),
        loginRecord: _recordText().replaceFirst(
          'implements:',
          "tests:\n  - '$entry'\nimplements:",
        ),
      },
    );

    final answer = _sync(root, [line]);

    expect(answer.json['waiting'], [
      '$line · waits for ${_address(root, loginFr)}',
    ]);
    expect(answer.json['kept'], isEmpty);
  });

  test('a remove-task line whose link is a mismatch or has no match line keeps the task refs and lists the task under Kept with that link', () async {
    const mismatch = 'mismatch $_arch $_login: the form takes no email';
    for (final (lines, mismatches) in [
      (const [mismatch, _removal], 'Mismatches:\n$mismatch\n'),
      (const [_removal], ''),
    ]) {
      final root = await _project(tasks: const ['ENG-1']);
      final before = _docBytes(root);

      final answer = _sync(root, lines);

      expect(
        answer.text,
        '${mismatches}Kept:\nENG-1 · kept by $_coversDoc $_login\n',
        reason: '$lines',
      );
      expect(answer.json['kept'], ['ENG-1'], reason: '$lines');
      expect(_docBytes(root), before, reason: '$lines');
    }
  });

  test('a remove-task line whose link matched removes the task refs from every doc in scope, each doc written once with its stamps', () async {
    final root = await _project(
      tasks: const ['ENG-1', 'ENG-2'],
      extra: edit(loginApi, [('confirmed:', 'tasks:\n  - ENG-1\nconfirmed:')]),
    );
    final archBefore = readDoc(root, _coversDoc);
    final apiBefore = readDoc(root, loginApi);

    final answer = _sync(root, [
      'match $_arch $_login $_loginFingerprint',
      _removal,
    ]);

    expect(
      readDoc(root, _coversDoc),
      archBefore
          .replaceFirst('  - $_login\n', '  - $_login $_loginFingerprint\n')
          .replaceFirst('  - ENG-1\n', ''),
    );
    expect(
      readDoc(root, loginApi),
      apiBefore.replaceFirst('tasks:\n  - ENG-1\n', ''),
    );
    expect(
      answer.text,
      '${_namingLine(root, loginApi)}${_namingLine(root, _coversDoc)}',
    );
    expect(answer.json['kept'], isEmpty);
    expect(answer.json['noRefs'], isEmpty);
    expect(MoveJournal.pending(root), isFalse);
  });

  test('a second group file naming a task the first removed, through its own matched link, prints its no refs line', () async {
    final root = await _project(
      covers: const [_login, _other],
      tasks: const ['ENG-1'],
      extra: {_other: _otherText},
    );
    _sync(root, ['match $_arch $_login $_loginFingerprint', _removal]);
    final archBefore = readDoc(root, _coversDoc);

    final second = _sync(root, [
      'match $_arch $_other $_otherFingerprint',
      'remove-task ENG-1 $_coversDoc $_other',
    ]);

    expect(
      readDoc(root, _coversDoc),
      archBefore.replaceFirst(
        '  - $_other\n',
        '  - $_other $_otherFingerprint\n',
      ),
    );
    expect(second.text, '${_namingLine(root, _arch)}ENG-1 · no refs\n');
    expect(second.json['noRefs'], ['ENG-1']);
    expect(second.json['kept'], isEmpty);
  });

  test('a remove-task line naming an entry its doc does not hold refuses stamp_entry_unknown and writes no doc', () async {
    final root = await _project(tasks: const ['ENG-1']);
    final before = _docBytes(root);

    final fault = _refused(root, [
      'match $_arch $_login $_loginFingerprint',
      'remove-task ENG-1 $_coversDoc app/lib/none.dart',
    ]);

    final refusal = fault.refusals.single;
    expect(refusal.line, 2);
    expect(refusal.code, 'stamp_entry_unknown');
    expect(refusal.message, 'no entry of $_arch reads app/lib/none.dart');
    expect(_docBytes(root), before);
  });

  test('a row line of a draft FR is written and a match on its row waits for the FR approval', () async {
    final root = await _project(extra: _draftFr());
    final match = 'match $_record $_checkPassword $_contractFingerprint';

    final answer = _sync(root, [
      'row $_record $_checkPassword: +`a wrong password is refused`',
      match,
    ]);

    expect(
      readDoc(root, loginRecord),
      contains('\n- $_checkPassword: `a wrong password is refused`\n'),
    );
    expect(
      answer.text,
      '${_namingLine(root, _record)}Waiting:\n'
      '$match · waits for ${_address(root, loginFr)}\n',
    );
  });
}
