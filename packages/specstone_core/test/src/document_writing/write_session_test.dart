// Test names carry the story, FR, and edge-case IDs on one line.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/mermaid_node_run.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/set_doc.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:specstone_core/src/rendering/models/line_ending.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart' show openSession;
import '../../helpers/posix_modes.dart';
import '../../helpers/temp_tree.dart';
import '../../helpers/write_fixture.dart';

TypeMatcher<IndexFault> _faultCode(IndexFaultCode code) =>
    isA<IndexFault>().having((f) => f.code, 'code', code);

void main() {
  test('a bare name one typed doc carries resolves to it', () async {
    final root = await writeWriteProject();
    expect(writeIn(root, (s) => s.target('login/email_login').docPath), story1);
  });

  test('a bare name 2 docs carry is argument_invalid listing each <type>:<name> in tree order', () async {
    final root = await writeWriteProject();
    expect(
      () => writeIn(root, (s) => s.target('login')),
      throwsA(
        _faultCode(IndexFaultCode.argumentInvalid).having(
          (f) => f.message,
          'message',
          'login names 2 docs: feature:login, architecture:login',
        ),
      ),
    );
  });

  test('an untyped doc is untyped_target', () async {
    final root = await writeWriteProject();
    expect(
      () => writeIn(root, (s) => s.target('prds/d01_context.md')),
      throwsA(
        _faultCode(IndexFaultCode.untypedTarget).having(
          (f) => f.message,
          'message',
          'prds/d01_context.md has no doc type; migrate it to one before a write',
        ),
      ),
    );
  });

  test('a bare name no doc carries is doc_not_found', () async {
    final root = await writeWriteProject();
    expect(
      () => writeIn(root, (s) => s.target('nobody_here')),
      throwsA(_faultCode(IndexFaultCode.docNotFound)),
    );
  });

  test('a name no doc carries is doc_not_found', () async {
    final root = await writeWriteProject();
    expect(
      () => writeIn(root, (s) => s.target('user_story:login/nobody')),
      throwsA(_faultCode(IndexFaultCode.docNotFound)),
    );
  });

  test('a typed name one doc carries resolves to it', () async {
    final root = await writeWriteProject();
    expect(
      writeIn(root, (s) => s.target('user_story:login/email_login').docPath),
      story1,
    );
  });

  test('a typed doc named by its path is a write target', () async {
    final root = await writeWriteProject();
    for (final address in [story1, 'docs/$story1', 'user_story:$story1']) {
      expect(writeIn(root, (s) => s.target(address).docPath), story1);
    }
  });

  test(
    'an untyped doc named by docs/ and its DocPath is untyped_target',
    () async {
      final root = await writeWriteProject();
      expect(
        () => writeIn(root, (s) => s.target('docs/prds/d01_context.md')),
        throwsA(_faultCode(IndexFaultCode.untypedTarget)),
      );
    },
  );

  test('a path names one of the two docs a typed name carries', () async {
    final root = await writeWriteProject(
      extra: {'docs/prds/features/f03_login/FEATURE.md': '# Login again\n'},
    );
    const again = 'prds/features/f03_login/FEATURE.md';
    expect(writeIn(root, (s) => s.target(again).docPath), again);
  });

  test('a typed name two docs carry is argument_invalid naming both', () async {
    final root = await writeWriteProject(
      extra: {'docs/prds/features/f03_login/FEATURE.md': '# Login again\n'},
    );
    expect(
      () => writeIn(root, (s) => s.target('feature:login')),
      throwsA(
        isA<IndexFault>().having(
          (f) => f.message,
          'message',
          'feature:login names 2 docs: prds/features/f01_login/FEATURE.md, prds/features/f03_login/FEATURE.md',
        ),
      ),
    );
  });

  test('locked runs inside the write lock and returns its result', () async {
    final root = await writeWriteProject();
    expect(writeIn(root, (s) => [s.locked(() => 1), s.locked(() => 2)]), [
      1,
      2,
    ]);
  });

  test('locked holds the write lock while it runs', () async {
    final root = await writeWriteProject();
    writeIn(root, (_) {}); // creates the index
    writeIn(root, (s) {
      s.locked(() {
        final other = IndexStore.open(root, busyTimeout: Duration.zero);
        addTearDown(other.close);
        expect(
          () => other.write(() {}),
          throwsA(_faultCode(IndexFaultCode.indexBusy)),
        );
      });
    });
  });

  test('a fault from locked propagates', () async {
    final root = await writeWriteProject();
    expect(
      () => writeIn(
        root,
        (s) => s.locked(
          () => throw IndexFault(IndexFaultCode.argumentInvalid, 'stop'),
        ),
      ),
      throwsA(_faultCode(IndexFaultCode.argumentInvalid)),
    );
  });

  test('lockedAsync reruns the body on a stale snapshot', () async {
    final root = await writeWriteProject();
    writeIn(root, (_) {}); // creates the index
    var runs = 0;
    var writes = 0;
    await WriteSession.runAsync(
      (s) async {
        runs++;
        if (runs == 1) {
          final peer = IndexStore.open(root);
          peer
            ..write(() => peer.setCheckedAt(1))
            ..close();
        }
        await s.lockedAsync(() async {
          await Future<void>.delayed(Duration.zero);
          writes++;
        });
      },
      templates: TemplateResolver(),
      workingDirectory: root,
      homeDirectory: testHome(),
    );
    expect((runs, writes), (2, 1));
  });

  test('runProjectCheck sees the findings a bare check sees', () async {
    final root = await writeWriteProject();
    final runner = MermaidNodeRun(
      start: (_) async => throw const ProcessException('node', [], 'none', 2),
    );
    List<String> lines(CheckReport report) => [
      for (final f in report.findings)
        '${f.kind} ${f.path}:${f.line} ${f.message}',
    ];
    final bareSession = openSession(root);
    final List<String> bare;
    try {
      bare = lines(await runCheck(bareSession, mermaidRunner: runner));
    } finally {
      bareSession.close();
    }
    final projectWide = await WriteSession.runAsync(
      (s) => s.lockedAsync(
        () async => lines(await s.runProjectCheck(mermaidRunner: runner)),
      ),
      templates: TemplateResolver(),
      workingDirectory: root,
      homeDirectory: testHome(),
    );
    expect(bare, isNotEmpty);
    expect(projectWide, bare);
  });

  test('runProjectCheck outside lockedAsync is a StateError', () async {
    final root = await writeWriteProject();
    await expectLater(
      WriteSession.runAsync(
        (s) async => s.runProjectCheck(),
        templates: TemplateResolver(),
        workingDirectory: root,
        homeDirectory: testHome(),
      ),
      throwsStateError,
    );
  });

  test('runProjectCheck stores a fresh parse inside the hold, visible after it commits', () async {
    const block = 'sequenceDiagram\n  A->>B: ok';
    final root = await writeWriteProject(
      extra: {
        'docs/$signupArch':
            '---\ndraft: true\n---\n\n# Signup architecture\n\n## Technical diagram\n\n```mermaid\n$block\n```\n\n## Components\n\n| Component | Responsibility |\n|---|---|\n| Signup form | Collects the email |\n',
      },
    );
    final runner = MermaidNodeRun(start: _startFakeNode);
    final other = IndexStore.open(root, busyTimeout: Duration.zero);
    addTearDown(other.close);
    await WriteSession.runAsync(
      (s) => s.lockedAsync(() async {
        await s.runProjectCheck(mermaidRunner: runner);
        expect(
          () => other.write(() {}),
          throwsA(_faultCode(IndexFaultCode.indexBusy)),
        );
      }),
      templates: TemplateResolver(),
      workingDirectory: root,
      homeDirectory: testHome(),
    );
    final raw = sqlite3.open('${root.path}/.specstone/index.sqlite');
    addTearDown(raw.close);
    expect(
      raw.select('SELECT count(*) AS n FROM diagram_parses').single['n'],
      1,
    );
  });

  test('a lock held past the busy timeout is index_busy, exit 75', () async {
    final root = await writeWriteProject();
    writeIn(root, (_) {}); // creates the index
    final other = sqlite3.open('${root.path}/.specstone/index.sqlite')
      ..execute('BEGIN IMMEDIATE');
    addTearDown(other.close);
    expect(
      () => writeIn(
        root,
        (s) => s.locked(() {}),
        busyTimeout: const Duration(milliseconds: 200),
      ),
      throwsA(isA<IndexFault>().having((f) => f.exitStatus, 'exitStatus', 75)),
    );
  });

  test('a set held off by a lock held past the 10 s busy timeout is '
      'index_busy, exit 75, and writes no file', () async {
    expect(indexBusyTimeout, const Duration(seconds: 10));
    final root = await writeWriteProject();
    const target = 'user_story:login/email_login#acceptance_criteria';
    final request = SetRequest.parse(
      target,
      base: getDoc(root, target)['base']! as String,
    );
    final docs = Directory('${root.path}/docs');
    final before = treeBytes(docs);
    // Windows locks bytes of index.sqlite-shm while a connection is open, so
    // the snapshot reads only the docs.
    final other = sqlite3.open('${root.path}/.specstone/index.sqlite')
      ..execute('BEGIN IMMEDIATE');
    addTearDown(other.close);
    expect(
      () => writeIn(
        root,
        (s) => answerSet(s, request, '\n- **Given** a changed text\n'),
        busyTimeout: const Duration(milliseconds: 200),
      ),
      throwsA(
        isA<IndexFault>()
            .having((f) => f.code, 'code', IndexFaultCode.indexBusy)
            .having((f) => f.exitStatus, 'exit', 75),
      ),
    );
    final after = treeBytes(docs);
    expect(after.keys, before.keys);
    for (final MapEntry(:key, :value) in before.entries) {
      expect(after[key], value, reason: key);
    }
  });

  group('an unfinished journal of one write command', () {
    const loginFolder = 'docs/prds/features/f01_login';

    test('a reorder journal is finished by the next write', () async {
      final root = await writeWriteProject();
      writeJournal(root, [
        const MoveStep(
          '$loginFolder/us03_reset_password',
          '$loginFolder/us02_reset_password',
        ),
        const MoveStep(
          '$loginFolder/us02_sign_out',
          '$loginFolder/us03_sign_out',
        ),
      ]);
      writeIn(root, (_) {});
      expect(
        Directory('${root.path}/$loginFolder/us02_reset_password').existsSync(),
        isTrue,
      );
      expect(
        Directory('${root.path}/$loginFolder/us03_sign_out').existsSync(),
        isTrue,
      );
      expect(
        Directory('${root.path}/$loginFolder/us03_reset_password').existsSync(),
        isFalse,
      );
      expect(
        File('${root.path}/${MoveJournal.journalPath}').existsSync(),
        isFalse,
      );
    });

    test('a rename journal is finished by the next write', () async {
      final root = await writeWriteProject();
      writeJournal(root, [
        const MoveStep(
          '$loginFolder/us02_sign_out',
          '$loginFolder/us02_log_out',
        ),
      ]);
      expect(
        writeIn(root, (s) => s.target('user_story:login/log_out').docPath),
        'prds/features/f01_login/us02_log_out/USER_STORY.md',
      );
      expect(
        File('${root.path}/${MoveJournal.journalPath}').existsSync(),
        isFalse,
      );
    });

    test('a move journal is finished by the next write', () async {
      final root = await writeWriteProject();
      writeJournal(root, [
        const MoveStep(
          '$loginFolder/us03_reset_password',
          'docs/prds/features/f02_signup/us01_reset_password',
        ),
      ]);
      writeIn(root, (_) {});
      expect(
        hasDoc(
          root,
          'prds/features/f02_signup/us01_reset_password/USER_STORY.md',
        ),
        isTrue,
      );
      expect(
        File('${root.path}/${MoveJournal.journalPath}').existsSync(),
        isFalse,
      );
    });

    test('a single set writes no journal', () async {
      final root = await writeWriteProject();
      const target = 'user_story:login/email_login#acceptance_criteria';
      final request = SetRequest.parse(
        target,
        base: getDoc(root, target)['base']! as String,
      );
      final journal = File('${root.path}/${MoveJournal.journalPath}');
      var sawJournal = false;
      writeIn(root, (s) {
        final answer = answerSet(s, request, '\n- **Given** a changed text\n');
        sawJournal = journal.existsSync();
        return answer;
      });
      expect(readDoc(root, story1), contains('a changed text'));
      expect(sawJournal, isFalse);
      expect(journal.existsSync(), isFalse);
      expect(Directory('${root.path}/.specstone/trash').existsSync(), isFalse);
    });
  });

  test('an unfinished journal is replayed before names resolve', () async {
    final root = await writeWriteProject();
    writeJournal(root, [
      const MoveStep('docs/prds/personas/buyer', 'docs/prds/personas/shopper'),
    ]);
    expect(
      writeIn(root, (s) => s.target('persona:shopper').docPath),
      'prds/personas/shopper/PERSONA.md',
    );
    expect(Directory('${root.path}/.specstone/trash').existsSync(), isFalse);
  });

  test('a replay warning is the first of the session warnings', () async {
    final root = await writeWriteProject();
    writeJournal(root, [
      WriteStep('docs/$story1', 'new text\n', before: textHashOf('old text\n')),
    ]);

    final warnings = writeIn(root, (s) => s.warnings);

    expect(
      warnings.first,
      'docs/$story1 changed since the stopped run; left as it is',
    );
  });

  test('a refresh keeps the warnings of the snapshot it replaces', () async {
    final root = await writeWriteProject();
    File('${root.path}/$indexFilePath')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('not a database');

    final warnings = writeIn(root, (s) {
      s.refresh();
      return s.warnings;
    });

    expect(warnings, contains(damagedIndexWarning));
  });

  test(
    'the open that precedes a replay keeps its warnings, listed once',
    () async {
      final root = await writeWriteProject();
      File('${root.path}/$indexFilePath')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('not a database');
      writeJournal(root, [
        const MoveStep(
          'docs/prds/personas/buyer',
          'docs/prds/personas/shopper',
        ),
      ]);

      final warnings = writeIn(root, (s) => s.warnings);

      expect(
        warnings.where((line) => line == damagedIndexWarning),
        hasLength(1),
      );
    },
  );

  test('a journal run through the session target adds its warning to the session warnings', () async {
    final root = await writeWriteProject();

    final warnings = writeIn(root, (s) {
      s.journalTarget.warn('a warning from a run');
      return s.warnings;
    });

    expect(warnings.first, 'a warning from a run');
  });

  test(
    'projectPathOf and docPathOf are inverses under the docs root',
    () async {
      final root = await writeWriteProject();
      writeIn(root, (s) {
        expect(s.projectPathOf(story1), 'docs/$story1');
        expect(s.docPathOf('docs/$story1'), story1);
        expect(
          s.fileOf(story1).path,
          endsWith(
            'docs${Platform.pathSeparator}'
            '${story1.replaceAll('/', Platform.pathSeparator)}',
          ),
        );
      });
    },
  );

  test('a record keeps its DocPath as its project path and its file lies under the project root', () async {
    final root = await writeWriteProject();
    const record = '.specstone/records/f01_login/IMPLEMENTATION.md';
    writeIn(root, (s) {
      expect(s.projectPathOf(record), record);
      expect(s.docPathOf(record), record);
      expect(s.listedPathOf(record), record);
      expect(
        s.fileOf(record).path,
        '${s.project.projectRoot.path}${Platform.pathSeparator}'
        '${record.replaceAll('/', Platform.pathSeparator)}',
      );
    });
  });

  test(
    'a docs root linked outside the project keeps the docs/ prefix',
    () async {
      final root = await writeWriteProject(
        without: {
          for (final k in writeProject.keys)
            if (k.startsWith('docs/')) k,
        },
      );
      final outside = await writeTree({
        for (final MapEntry(:key, :value) in writeProject.entries)
          if (key.startsWith('docs/')) key.substring(5): value,
      });
      Link('${root.path}/docs').createSync(outside.path);
      writeIn(root, (s) {
        expect(s.projectPathOf(story1), 'docs/$story1');
        expect(s.docPathOf('docs/$story1'), story1);
        expect(s.target('user_story:login/email_login').docPath, story1);
      });
    },
    skip: Platform.isWindows ? 'links need privileges on Windows' : false,
  );

  test('writeDoc writes the text with its line ending', () async {
    final root = await writeWriteProject();
    writeIn(root, (s) => s.writeDoc(story2, 'a\nb\n', LineEnding.crlf));
    expect(readDoc(root, story2), 'a\r\nb\r\n');
  });

  group('writeDoc lays out', () {
    const padded =
        '---\ndraft: true\n---\n\n# Signup architecture\n\n## Components\n'
        '| Component   | Responsibility |\n|-------------|----------------|\n'
        '| Signup form | Collects the email |\n';
    const laidOut =
        '---\ndraft: true\n---\n\n# Signup architecture\n\n## Components\n\n'
        '| Component | Responsibility |\n|---|---|\n'
        '| Signup form | Collects the email |\n';

    test('a typed doc is written laid out, and the returned text is the file LF text', () async {
      final root = await writeWriteProject();
      final written = writeIn(
        root,
        (s) => s.writeDoc(signupArch, padded, LineEnding.lf),
      );
      expect(written, laidOut);
      expect(readDoc(root, signupArch), laidOut);
    });

    test('an untyped doc is written as given', () async {
      final root = await writeWriteProject();
      const text = '# Context   \n\n\n## Features\nSee.\n';
      const path = 'prds/d01_context.md';
      final written = writeIn(
        root,
        (s) => s.writeDoc(path, text, LineEnding.lf),
      );
      expect(written, text);
      expect(readDoc(root, path), text);
    });

    test('a doc formatDoc refuses is written as given', () async {
      final root = await writeWriteProject();
      const text =
          '---\ndraft: true\n---\n\n# Signup architecture\n\n## Not a section\nx\n';
      final written = writeIn(
        root,
        (s) => s.writeDoc(signupArch, text, LineEnding.lf),
      );
      expect(written, text);
      expect(readDoc(root, signupArch), text);
    });

    test('CRLF and a BOM are kept on a laid-out write, and the returned text is LF', () async {
      final root = await writeWriteProject();
      docFile(
        root,
        signupArch,
      ).writeAsBytesSync([0xEF, 0xBB, 0xBF, ...padded.codeUnits]);
      final written = writeIn(root, (s) {
        s.readDocBytes(signupArch);
        return s.writeDoc(signupArch, padded, LineEnding.crlf);
      });
      final bytes = docFile(root, signupArch).readAsBytesSync();
      expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
      expect(written, laidOut);
      expect(
        String.fromCharCodes(bytes.skip(3)),
        written.replaceAll('\n', '\r\n'),
      );
    });
  });

  test(
    'writeDoc maps a refused write to output_not_writable naming the DocPath',
    () async {
      final root = await writeWriteProject();
      expect(
        () => writeIn(
          root,
          (s) => s.writeDoc('prds/no_such_folder/X.md', 'a\n', LineEnding.lf),
        ),
        throwsA(
          isA<RenderFault>()
              .having((e) => e.code, 'code', RenderFaultCode.outputNotWritable)
              .having(
                (e) => e.message,
                'message',
                startsWith('cannot write prds/no_such_folder/X.md: '),
              ),
        ),
      );
    },
  );

  test('an index that cannot be written is index_not_writable, exit 73, and no doc is written', () async {
    final root = await writeWriteProject();
    writeIn(root, (_) {});
    final dot = Directory('${root.path}/.specstone');
    final files = [for (final e in dot.listSync().whereType<File>()) e.path];
    Process.runSync('chmod', ['555', dot.path]);
    Process.runSync('chmod', ['444', ...files]);
    addTearDown(() {
      Process.runSync('chmod', ['755', dot.path]);
      Process.runSync('chmod', ['644', ...files]);
    });
    final before = readDoc(root, story1);
    docFile(root, story1).writeAsStringSync('$before\nedited by hand\n');
    final edited = readDoc(root, story1);

    expect(
      () => writeIn(root, (s) => s.writeDoc(story2, 'x\n', LineEnding.lf)),
      throwsA(
        isA<IndexFault>()
            .having((f) => f.code, 'code', IndexFaultCode.indexNotWritable)
            .having((f) => f.exitStatus, 'exitStatus', 73),
      ),
    );
    expect(readDoc(root, story1), edited);
    expect(readDoc(root, story2), isNot('x\n'));
  }, skip: unreadablePathSkipReason() ?? false);

  test('an unreadable doc is output_not_writable cannot read <DocPath>, bytes unchanged', () async {
    final root = await writeWriteProject();
    const target = 'user_story:login/email_login#use_case';
    final base = getDoc(root, target)['base']! as String;
    final file = docFile(root, story1);
    final before = file.readAsBytesSync();
    addTearDown(() => Process.runSync('chmod', ['644', file.path]));
    expect(
      () => writeIn(root, (s) {
        Process.runSync('chmod', ['000', file.path]);
        return answerSet(s, SetRequest.parse(target, base: base), 'New.\n');
      }),
      throwsA(
        isA<RenderFault>()
            .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
            .having(
              (f) => f.message,
              'message',
              startsWith('cannot read $story1: '),
            ),
      ),
    );
    Process.runSync('chmod', ['644', file.path]);
    expect(file.readAsBytesSync(), before);
  }, skip: unreadablePathSkipReason() ?? false);

  test('an unknown doc type in a target is doc_type_unknown', () async {
    final root = await writeWriteProject();
    expect(
      () => writeIn(root, (s) => s.target('no_such_type:login/email_login')),
      throwsA(
        isA<TemplateFault>().having(
          (f) => f.code,
          'code',
          FaultCode.docTypeUnknown,
        ),
      ),
    );
  });

  test('a replay waits for the write lock', () async {
    final root = await writeWriteProject();
    // An old mtime keeps the open's refresh from taking the lock, so only the
    // replay can meet the busy store.
    final anHourAgo = DateTime.now().subtract(const Duration(hours: 1));
    for (final file in root.listSync(recursive: true).whereType<File>()) {
      file.setLastModifiedSync(anHourAgo);
    }
    writeIn(root, (_) {}); // creates the index
    writeJournal(root, [
      const MoveStep('docs/prds/personas/buyer', 'docs/prds/personas/shopper'),
    ]);
    final journal = File('${root.path}/${MoveJournal.journalPath}');
    final journalText = journal.readAsStringSync();
    final other = IndexStore.open(root, busyTimeout: Duration.zero);
    addTearDown(other.close);
    other.write(() {
      expect(
        () => writeIn(root, (_) {}, busyTimeout: Duration.zero),
        throwsA(_faultCode(IndexFaultCode.indexBusy)),
      );
    });
    expect(journal.readAsStringSync(), journalText);
    expect(hasDoc(root, persona), isTrue);
    expect(hasDoc(root, 'prds/personas/shopper/PERSONA.md'), isFalse);
  });

  test('a replay fault rolls back and releases the lock', () async {
    final root = await writeWriteProject();
    final journal = File('${root.path}/${MoveJournal.journalPath}')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('not json');
    expect(() => writeIn(root, (_) {}), throwsA(isA<RenderFault>()));
    expect(journal.existsSync(), isTrue);
    final other = IndexStore.open(root, busyTimeout: Duration.zero);
    addTearDown(other.close);
    other.write(() {});
  });

  test(
    'writeDoc refuses a path that is not a .md under the docs root',
    () async {
      final root = await writeWriteProject();
      for (final path in [
        'notes.txt',
        '../x.md',
        '${root.path}/x.md',
        'prds//x.md',
        'prds/../x.md',
        r'prds\x.md',
      ]) {
        expect(
          () => writeIn(root, (s) => s.writeDoc(path, 'x\n', LineEnding.lf)),
          throwsArgumentError,
          reason: path,
        );
      }
      expect(File('${root.path}/x.md').existsSync(), isFalse);
      expect(File('${root.path}/docs/notes.txt').existsSync(), isFalse);
    },
  );

  group('a pending migrate journal', () {
    const move = MoveStep(
      'docs/prds/personas/buyer',
      'docs/prds/personas/shopper',
    );
    const commit = CommitStep(
      message: 'move',
      paths: ['docs/prds/personas'],
      base: '0000000',
    );

    test(
      'refuses every write with migrate_pending and replays nothing',
      () async {
        final root = await writeWriteProject();
        writeJournal(root, [move, commit]);
        expect(
          () => writeIn(root, (session) => null),
          throwsA(
            isA<WriteFault>()
                .having((f) => f.code, 'code', WriteFaultCode.migratePending)
                .having((f) => f.exitStatus, 'exit', 75),
          ),
        );
        expect(
          Directory('${root.path}/docs/prds/personas/buyer').existsSync(),
          isTrue,
        );
        expect(
          Directory('${root.path}/docs/prds/personas/shopper').existsSync(),
          isFalse,
        );
      },
    );

    test('refuses with the message that names specstone migrate and its '
        'interactive ways, exit 75', () async {
      final root = await writeWriteProject();
      writeJournal(root, [move, commit]);
      expect(
        () => writeIn(root, (session) => null),
        throwsA(
          isA<WriteFault>()
              .having(
                (f) => f.message,
                'message',
                'a migration is unfinished; run specstone migrate at an '
                    "interactive terminal, or with --yes after the Owner's ok "
                    'in the chat, to finish it, then run the command again',
              )
              .having((f) => f.exitStatus, 'exit', 75)
              .having((f) => f.file, 'file', '.specstone/trash/journal.json'),
        ),
      );
    });

    test('refuses in a legacy tree whose config is not written yet', () async {
      final root = await writeTree({'docs/prds/PROJECT.md': '# Legacy\n'});
      writeJournal(root, [move, commit]);
      expect(File('${root.path}/.specstone/config.yaml').existsSync(), isFalse);
      expect(
        () => writeIn(root, (session) => null),
        throwsA(
          isA<WriteFault>().having(
            (f) => f.code,
            'code',
            WriteFaultCode.migratePending,
          ),
        ),
      );
    });

    test('refuses from a folder below the project root', () async {
      final root = await writeWriteProject();
      writeJournal(root, [move, commit]);
      final nested = Directory('${root.path}/docs/prds')
        ..createSync(recursive: true);
      expect(
        () => WriteSession.run(
          (session) => null,
          templates: TemplateResolver(),
          workingDirectory: nested,
          homeDirectory: testHome(),
        ),
        throwsA(
          isA<WriteFault>()
              .having((f) => f.code, 'code', WriteFaultCode.migratePending)
              .having((f) => f.file, 'file', '.specstone/trash/journal.json'),
        ),
      );
    });

    test('a journal with no commit step is still replayed', () async {
      final root = await writeWriteProject();
      writeJournal(root, [move]);
      expect(
        writeIn(root, (s) => s.target('persona:shopper').docPath),
        'prds/personas/shopper/PERSONA.md',
      );
      expect(Directory('${root.path}/.specstone/trash').existsSync(), isFalse);
    });

    test('an unparsable journal is not a migrate journal', () async {
      final root = await writeWriteProject();
      File('${root.path}/${MoveJournal.journalPath}')
        ..createSync(recursive: true)
        ..writeAsStringSync('{not json');
      expect(MoveJournal.pendingMigrate(root), isFalse);
    });
  });
}

/// Starts a fake Node child that answers block 0 as a parsing sequence diagram.
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
