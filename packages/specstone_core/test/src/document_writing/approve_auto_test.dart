// The test names are plan text kept as written.
// ignore_for_file: lines_longer_than_80_chars

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
    final marks = {
      for (final docPath in [check.loginStory, check.loginFr])
        '${RegExp('approved: "([0-9a-f]+)"').firstMatch(readDoc(root, docPath))![1]}.md',
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
    const block = 'sequenceDiagram\n  A->>B: ok';
    final root = await _draftsProject(
      extra: check.edit(check.loginArchitecture, [
        ('One box.', '```mermaid\n$block\n```'),
      ]),
    );
    _createIndex(root);
    final peer = _PeerWrite(root);
    addTearDown(peer.dispose);

    await _approveAuto(
      root,
      _call(root, noAudit: true),
      runner: MermaidNodeRun(
        start: (arguments) async {
          await peer.startWaiting();
          return _startFakeNode(arguments);
        },
      ),
    );

    final seen = await peer.docSeenOnceFree();
    expect(seen, contains('\napproved: '));
    expect(seen, isNot(contains('draft: true')));
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

  test(
    'asks a draft whose file is gone before the lock and approves no other',
    () async {
      final root = await _draftsProject(
        extra: check.edit(check.loginArchitecture, [
          ('One box.', '```mermaid\nsequenceDiagram\n  A->>B: ok\n```'),
        ]),
      );

      final answer = await _approveAuto(
        root,
        _call(root, noAudit: true),
        runner: MermaidNodeRun(
          start: (arguments) async {
            docFile(root, check.loginFr).deleteSync();
            return _startFakeNode(arguments);
          },
        ),
      );

      expect(
        answer.text,
        'mode: auto\n'
        'approved $_story\n'
        'ask $_fr: ${check.loginFr} is gone\n',
      );
    },
  );

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

    await _approveAuto(
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

    expect(duringCheck, IndexFaultCode.indexBusy);
    final raw = sqlite3.open('${root.path}/.specstone/index.sqlite');
    addTearDown(raw.close);
    expect(
      raw.select('SELECT count(*) AS n FROM diagram_parses').single['n'],
      1,
    );
  });
}

void _createIndex(Directory root) => WriteSession.run(
  (_) {},
  templates: TemplateResolver(),
  workingDirectory: root,
  homeDirectory: testHome(),
);

/// A second isolate that retries for the write lock at once, so it takes the
/// first gap between two holds, then reads the story.
final class _PeerWrite {
  new(this._root);

  final Directory _root;
  final _messages = ReceivePort();
  final _trying = Completer<void>();
  final _seen = Completer<String>();
  Isolate? _isolate;

  /// Starts the peer and returns once it has begun to wait for the lock.
  Future<void> startWaiting() async {
    _messages.listen((message) {
      if (message == 'trying') _trying.complete();
      if (message is String && message != 'trying') _seen.complete(message);
      if (message is List) _seen.completeError(StateError('${message.first}'));
    });
    _isolate = await Isolate.spawn(_writeWhenFree, (
      _root.path,
      _messages.sendPort,
    ), onError: _messages.sendPort);
    await _trying.future.timeout(const Duration(seconds: 10));
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  /// The story the peer read once its write got the lock.
  Future<String> docSeenOnceFree() =>
      _seen.future.timeout(const Duration(seconds: 20));

  void dispose() {
    _messages.close();
    _isolate?.kill();
  }
}

void _writeWhenFree((String, SendPort) arguments) {
  final (path, port) = arguments;
  final store = IndexStore.open(Directory(path), busyTimeout: Duration.zero);
  port.send('trying');
  String? text;
  while (text == null) {
    try {
      store.write(() {
        text = File('$path/docs/${check.loginStory}').readAsStringSync();
      });
    } on IndexFault {
      // The lock is held: try again at once.
    }
  }
  store.close();
  port.send(text);
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
