import 'dart:io';

import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/set_doc.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../../helpers/posix_modes.dart';
import '../../helpers/temp_tree.dart';
import '../../helpers/write_fixture.dart';

TypeMatcher<IndexFault> _faultCode(IndexFaultCode code) =>
    isA<IndexFault>().having((f) => f.code, 'code', code);

void main() {
  test(
    'dw-s03/inv2, f02/us01/fr01/e09: a bare name is argument_invalid',
    () async {
      final root = await writeWriteProject();
      expect(
        () => writeIn(root, (s) => s.target('login/email_login')),
        throwsA(_faultCode(IndexFaultCode.argumentInvalid)),
      );
    },
  );

  test(
    'dw-s03/inv2, f02/us01/fr01/e10: an untyped doc is untyped_target',
    () async {
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
    },
  );

  test('f02/us01/fr01/e09: a bare name no doc carries is argument_invalid with the name prompt', () async {
    final root = await writeWriteProject();
    expect(
      () => writeIn(root, (s) => s.target('nobody_here')),
      throwsA(
        _faultCode(IndexFaultCode.argumentInvalid).having(
          (f) => f.message,
          'message',
          'name the doc as <doc type>:<name>, such as user_story:login/email_login',
        ),
      ),
    );
  });

  test('f02/us01/fr01/e11: a name no doc carries is doc_not_found', () async {
    final root = await writeWriteProject();
    expect(
      () => writeIn(root, (s) => s.target('user_story:login/nobody')),
      throwsA(_faultCode(IndexFaultCode.docNotFound)),
    );
  });

  test(
    'f02/us01/fr01, dw-s03/inv2: a typed name one doc carries resolves to it',
    () async {
      final root = await writeWriteProject();
      expect(
        writeIn(root, (s) => s.target('user_story:login/email_login').docPath),
        story1,
      );
    },
  );

  test('f02/us01/fr01/e09, PD8: a typed name two docs carry is argument_invalid naming both', () async {
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

  test('f02/us01/fr05, dw-s03/inv3: locked runs inside the write lock and returns its result', () async {
    final root = await writeWriteProject();
    expect(writeIn(root, (s) => [s.locked(() => 1), s.locked(() => 2)]), [
      1,
      2,
    ]);
  });

  test(
    'f02/us01/fr05, dw-s03/inv3: locked holds the write lock while it runs',
    () async {
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
    },
  );

  test('f02/us01/fr05, dw-s03/inv3: a fault from locked propagates', () async {
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

  test('f02/us01/fr05/e03, dw-s03/inv3: a lock held past the busy timeout is index_busy, exit 75', () async {
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

  test('f02/us01/fr05/e05, f02/us04/fr03, dw-s03/inv3: an unfinished journal is replayed before names resolve', () async {
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

  test('X1, f02/us04/fr03: projectPathOf and docPathOf are inverses under the docs root', () async {
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
  });

  test('X1, f02/us04/fr03: a docs root linked outside the project keeps the docs/ prefix', () async {
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
  }, skip: Platform.isWindows ? 'links need privileges on Windows' : false);

  test(
    'D4, f02/us01/fr01: writeDoc writes the text with its line ending',
    () async {
      final root = await writeWriteProject();
      writeIn(root, (s) => s.writeDoc(story2, 'a\nb\n', LineEnding.crlf));
      expect(readDoc(root, story2), 'a\r\nb\r\n');
    },
  );

  test('D4, f02/us01/fr05/e07: writeDoc maps a refused write to output_not_writable naming the DocPath', () async {
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
  });

  test('f02/us01/fr05/e07: an index that cannot be written is index_not_writable, exit 73, and no doc is written', () async {
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

  test('f02/us01/fr01/e13, nfr-di01, H05: an unreadable doc is output_not_writable cannot read <DocPath>, bytes unchanged', () async {
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

  test(
    'dw-s03/inv2: an unknown doc type in a target is doc_type_unknown',
    () async {
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
    },
  );

  test('dw-s03/inv3, dw-s03/inv9: a replay waits for the write lock', () async {
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

  test(
    'dw-s03/inv9: a replay fault rolls back and releases the lock',
    () async {
      final root = await writeWriteProject();
      final journal = File('${root.path}/${MoveJournal.journalPath}')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('not json');
      expect(() => writeIn(root, (_) {}), throwsA(isA<RenderFault>()));
      expect(journal.existsSync(), isTrue);
      final other = IndexStore.open(root, busyTimeout: Duration.zero);
      addTearDown(other.close);
      other.write(() {});
    },
  );

  test('dw-s03/inv2, H07: writeDoc refuses a path that is not a .md under the docs root', () async {
    final root = await writeWriteProject();
    for (final path in [
      'notes.txt',
      '../x.md',
      '${root.path}/x.md',
      'prds//x.md',
      'prds/../x.md',
    ]) {
      expect(
        () => writeIn(root, (s) => s.writeDoc(path, 'x\n', LineEnding.lf)),
        throwsArgumentError,
        reason: path,
      );
    }
    expect(File('${root.path}/x.md').existsSync(), isFalse);
    expect(File('${root.path}/docs/notes.txt').existsSync(), isFalse);
  });
}
