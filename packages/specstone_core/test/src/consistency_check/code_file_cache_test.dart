import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/code_link_rules.dart';
import 'package:specstone_core/src/consistency_check/code_mention_rules.dart';
import 'package:specstone_core/src/consistency_check/code_rules.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/implements_rule.dart';
import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/forwarding_entities.dart';
import '../../helpers/index_fixture.dart';
import '../../helpers/posix_modes.dart';
import '../../helpers/target_fixture.dart';

const _fr = 'login/email_login/check_password';

/// [_fr] with its last letter changed, so it names no doc and keeps its length.
const _noDoc = 'login/email_login/check_passworx';

const _hourAgo = Duration(hours: 1);
const _halfHourAgo = Duration(minutes: 30);

/// Sets the mtime of every code file, each file outside `docs/` and
/// `.specstone/`, to [age] before now, so no file lies in the racy window.
void _age(Directory project, Duration age) {
  final then = DateTime.now().subtract(age);
  final prefix = '${project.path}/';
  for (final file in project.listSync(recursive: true).whereType<File>()) {
    final path = file.path.substring(prefix.length);
    if (path.startsWith('docs/') || path.startsWith('.specstone/')) continue;
    file.setLastModifiedSync(then);
  }
}

/// Returns the paths of `code_files` by root, as stored.
Set<String> _storedKeys(Directory project) {
  final db = sqlite3.open('${project.path}/$indexFilePath');
  try {
    return {
      for (final row in db.select('SELECT root, path FROM code_files'))
        '${row['root']}|${row['path']}',
    };
  } finally {
    db.close();
  }
}

/// Returns the rows of `code_files` by path, each as `rowid`, `fingerprint`,
/// `mention_texts`, and `resolved`.
Map<String, Map<String, Object?>> _rows(Directory project) {
  final db = sqlite3.open('${project.path}/$indexFilePath');
  try {
    return {
      for (final row in db.select(
        'SELECT path, rowid, fingerprint, mention_texts, resolved '
        'FROM code_files',
      ))
        row['path'] as String: {...row},
    };
  } finally {
    db.close();
  }
}

List<String> _cited(CheckReport report) => [
  for (final f in report.findings)
    if (f.kind == FindingKind.docCitedInCode)
      '${f.path}:${f.line} ${f.keys['mention']}',
];

void main() {
  test('a file whose mtime or ctime changed is read again though its size '
      'did not', () async {
    final project = await writeCheckProject(
      extra: {'app/lib/auth.dart': '// Implements `$_noDoc`.\n'},
    );
    _age(project, _hourAgo);
    final first = await checkOf(project);
    expect(_cited(first), isEmpty);
    expect(
      _rows(project)['app/lib/auth.dart']!['mention_texts'],
      '["$_noDoc"]',
    );

    File('${project.path}/app/lib/auth.dart')
        .writeAsStringSync('// Implements `$_fr`.\n');
    _age(project, _halfHourAgo);

    expect(_cited(await checkOf(project)), ['app/lib/auth.dart:1 $_fr']);
  });

  test(
    'a file edited in the racy window is never stored, an aged one is',
    () async {
      final project = await writeCheckProject(
        extra: {'app/lib/fresh.dart': '// Implements `$_noDoc`.\n'},
      );
      _age(project, _hourAgo);
      File('${project.path}/app/lib/fresh.dart')
          .setLastModifiedSync(DateTime.now());

      await checkOf(project);

      final rows = _rows(project);
      expect(rows.keys, contains('app/lib/login.dart'));
      expect(rows.keys, isNot(contains('app/lib/fresh.dart')));

      File('${project.path}/app/lib/fresh.dart')
          .writeAsStringSync('// Implements `$_fr`.\n');
      expect(_cited(await checkOf(project)), ['app/lib/fresh.dart:1 $_fr']);
    },
  );

  test('an unchanged file whose stored mention now names a doc is read '
      'again and gives its finding at its line', () async {
    const mention = 'docs/prds/NOTE.md';
    final project = await writeCheckProject(
      extra: {'app/lib/later.dart': 'class L {}\n\n// See $mention\n'},
    );
    _age(project, _hourAgo);
    expect(_cited(await checkOf(project)), isEmpty);
    expect(
      _rows(project)['app/lib/later.dart']!['mention_texts'],
      '["$mention"]',
    );

    File('${project.path}/$mention').writeAsStringSync('# Note\n');

    expect(_cited(await checkOf(project)), ['app/lib/later.dart:3 $mention']);
  });

  test('a warm run reads no code file and rewrites no row', () async {
    final project = await writeCheckProject();
    _age(project, _hourAgo);
    expect((await checkOf(project)).findings, isEmpty);
    final stored = _rows(project);
    expect(stored.keys, contains('app/lib/login.dart'));

    final session = openSession(project);
    addTearDown(session.close);
    final context = CheckContext(session);
    final work = ImplementedWork(context, context.targets);
    final findings = [
      ...checkImplements(context, session.index.at(loginRecord)!),
      ...checkCodeLinks(context, work, session.index.at(loginRecord)!),
      ...checkCodeLinks(context, work, session.index.at(loginArchitecture)!),
      ...docNamesInCode(context, work),
    ];
    expect(findings, isEmpty);
    expect(context.codeFilesRead, 0);

    expect((await checkOf(project)).findings, isEmpty);
    expect(_rows(project), stored);
  });

  test('a file that is not UTF-8 stores no mention texts, so its warning '
      'prints every run', () async {
    final project = await writeCheckProject();
    File('${project.path}/app/lib/bad.dart')
        .writeAsBytesSync([0x2F, 0x2F, 0x20, 0xFF, 0xFE, 0x0A]);
    _age(project, _hourAgo);
    const warning =
        'app/lib/bad.dart: not UTF-8; doc names in it are not checked';

    expect((await checkOf(project)).warnings, [warning]);
    expect((await checkOf(project)).warnings, [warning]);
    expect(_rows(project)['app/lib/bad.dart']?['mention_texts'], isNull);
  });

  test('an index of the previous layout is rebuilt with the table and the '
      'same report', () async {
    final project = await writeCheckProject();
    _age(project, _hourAgo);
    await checkOf(project);
    sqlite3.open('${project.path}/$indexFilePath')
      ..execute('DROP TABLE code_files')
      ..execute('UPDATE meta SET layout = ${indexLayoutVersion - 1}')
      ..close();

    final report = await checkOf(project);

    expect(report.findings, isEmpty);
    expect(_rows(project).keys, contains('app/lib/login.dart'));
  });

  test('an index another connection holds locked makes the check finish at '
      'once with the facts unstored and the report whole', () async {
    final project = await writeCheckProject();
    _age(project, _hourAgo);
    final session = openSession(
      project,
      busyTimeout: const Duration(minutes: 1),
    );
    final holder = sqlite3.open('${project.path}/$indexFilePath')
      ..execute('BEGIN IMMEDIATE');
    addTearDown(() {
      if (!holder.autocommit) holder.execute('ROLLBACK');
      holder.close();
    });
    final watch = Stopwatch()..start();

    final report = await runCheck(session);
    session.close();

    // A run that waits out the 1 min busy timeout fails this bound; no load
    // slows the small fixture this far.
    expect(watch.elapsed, lessThan(const Duration(seconds: 30)));
    expect(report.findings, isEmpty);
    holder.execute('ROLLBACK');
    expect(_rows(project), isEmpty);
  });

  test('the racy window counts from the start of the run, not from the '
      'first use of the cache', () async {
    final project = await writeCheckProject();
    _age(project, _hourAgo);
    final session = openSession(project);
    addTearDown(session.close);
    final context = CheckContext(session);
    final root = context.codeRootOf(context.targets.first);
    const path = 'app/lib/login.dart';
    File('${root.path}/$path').setLastModifiedSync(
      DateTime.now().subtract(const Duration(milliseconds: 1500)),
    );
    await Future<void>.delayed(const Duration(milliseconds: 700));

    context.codeFiles.putFingerprint(root, path, 'late');

    expect(context.codeFiles.fingerprintOf(root, path), isNull);
  });

  test('a peer that reset the index under another stamp gets no row from '
      'this run', () async {
    final project = await writeCheckProject();
    _age(project, _hourAgo);
    final session = openSession(project);
    final peer = IndexStore.open(project);
    peer.write(
      () => peer.reset(
        const IndexStamp(binaryVersion: 'another build', docTypes: 'x'),
      ),
    );
    peer.close();

    await runCheck(session);
    session.close();

    expect(_rows(project), isEmpty);
  });

  test('a whole-project run drops the rows of a deleted file and of a root '
      'no run reads from, and a doc-target run drops none', () async {
    final project = await writeCheckProject(
      extra: {'app/lib/doomed.dart': 'class D {}\n'},
    );
    _age(project, _hourAgo);
    await checkOf(project);
    sqlite3.open('${project.path}/$indexFilePath')
      ..execute(
        'INSERT INTO code_files (root, path, stat_size, stat_mtime, '
        "stat_ctime, stat_mode, resolved) VALUES ('/gone', 'a.dart', 1, 2, "
        "3, 4, '[]')",
      )
      ..close();
    File('${project.path}/app/lib/doomed.dart').deleteSync();
    final before = _storedKeys(project);
    expect(
      before.where((k) => k.endsWith('|app/lib/doomed.dart')),
      hasLength(1),
    );
    expect(before, contains('/gone|a.dart'));

    await checkOf(project, target: 'login');
    expect(_storedKeys(project), before);

    await checkOf(project);
    final after = _storedKeys(project);
    expect(after.where((k) => k.endsWith('|app/lib/doomed.dart')), isEmpty);
    expect(after, isNot(contains('/gone|a.dart')));
    expect(after.where((k) => k.endsWith('|app/lib/login.dart')), hasLength(1));
  });

  test(
    'a run kept to one code target drops no row of another target',
    () async {
      final project = await writeTwinProject();
      _age(project, _hourAgo);
      await checkOf(project);
      final before = _storedKeys(project);
      expect(before.where((k) => k.contains('flutter_ws')), isNotEmpty);
      final session = openSession(project);
      await runCheck(session, codeTarget: 'jaspr');
      session.close();

      expect(
        _storedKeys(project).where((k) => k.contains('flutter_ws')),
        before.where((k) => k.contains('flutter_ws')),
      );
    },
  );

  // D15: the stat key alone vouches for a stored row; `chmod` moves `ctime`
  // and `mode`, so a file made unreadable after a run is read again.
  test(
    'a file made unreadable after a stored run is read again, since its stat '
    'key changed, so its warning prints',
    skip: unreadablePathSkipReason(),
    () async {
      final project = await writeCheckProject();
      _age(project, _hourAgo);
      await checkOf(project);
      final file = File('${project.path}/app/lib/login.dart');
      Process.runSync('chmod', ['000', file.path]);
      addTearDown(() => Process.runSync('chmod', ['644', file.path]));

      final report = await checkOf(project);

      expect(
        report.warnings,
        contains(startsWith('app/lib/login.dart: cannot read the file;')),
      );
    },
  );

  // D15: a trusted file is never opened or read to confirm its row.
  test(
    'a warm run whose stat keys all match opens or reads no code file',
    () async {
      final project = await writeCheckProject();
      _age(project, _hourAgo);
      await checkOf(project);
      final stored = _rows(project).keys.toList();
      expect(stored, isNotEmpty);
      final touched = <String>[];

      await IOOverrides.runWithIOOverrides(
        () => checkOf(project),
        _OpenRecordingHook(touched.add),
      );

      expect(touched.where((path) => stored.any(path.endsWith)), isEmpty);
    },
  );
}

final class _OpenRecordingHook extends IOOverrides {
  new(this._record);

  final void Function(String path) _record;

  @override
  File createFile(String path) =>
      _OpenRecordingFile(super.createFile(path), _record);
}

final class _OpenRecordingFile extends ForwardingFile {
  const new(super.inner, this._record);

  final void Function(String path) _record;

  @override
  RandomAccessFile openSync({FileMode mode = FileMode.read}) {
    _record(path);
    return super.openSync(mode: mode);
  }

  @override
  Uint8List readAsBytesSync() {
    _record(path);
    return super.readAsBytesSync();
  }

  @override
  String readAsStringSync({Encoding encoding = utf8}) {
    _record(path);
    return super.readAsStringSync(encoding: encoding);
  }
}
