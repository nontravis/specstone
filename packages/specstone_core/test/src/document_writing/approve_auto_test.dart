import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:specstone_core/src/consistency_check/mermaid_node_run.dart';
import 'package:specstone_core/src/document_writing/approve_auto.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart' as check;
import '../../helpers/relative_link.dart';
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
    (getDoc(root, address)['bases']! as Map)['doc']! as String;

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
  bool noAudit = false,
  String? mode = 'auto',
}) => AutoApproveCall(
  names: names,
  auditPaths: audits,
  authorPaths: const [],
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
  (s) => approveAuto(s, call, mermaidRunner: runner),
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

  test('auto call asks a draft a NOT ADDRESSED item names and approves one an '
      'ADDRESSED item names', () async {
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

  test('approves under no-audit by the check alone', () async {
    final root = await _draftsProject();

    final answer = await _approveAuto(root, _call(root, noAudit: true));

    expect(answer.text, 'mode: auto\napproved $_story\napproved $_fr\n');
    expect(_isApproved(root, check.loginStory), isTrue);
    expect(_isApproved(root, check.loginFr), isTrue);
  });

  test('prints the four JSON keys in doc order', () async {
    final root = await _draftsProject(frHasFinding: true);
    final audit = await _auditNaming(root, [_story, _fr]);

    final answer = await _approveAuto(
      root,
      _call(root, names: [_fr, _story], audits: [audit]),
    );

    expect(answer.json, {
      'approveMode': 'auto',
      'approved': [
        {'name': _story, 'docPath': check.loginStory},
      ],
      'asked': [
        {
          'name': _fr,
          'docPath': check.loginFr,
          'reason': 'check finding required_section_missing',
        },
      ],
    });
    expect(answer.json.keys, ['approveMode', 'approved', 'asked']);
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
