import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/fault.dart';
import 'package:specstone_core/src/index_query/out_file.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:test/test.dart';

import '../../helpers/temp_tree.dart';

void main() {
  group('outFileName', () {
    test('a command with no flag and no argument ends .all.txt', () {
      expect(
        outFileName(command: 'check', args: const [], asJson: false),
        'check.all.txt',
      );
    });

    test('a flag is written -<flag> after the command', () {
      expect(
        outFileName(
          command: 'check',
          flags: const ['repeats'],
          args: const [],
          asJson: false,
        ),
        'check-repeats.all.txt',
      );
    });

    test('flags come in code point order', () {
      expect(
        outFileName(
          command: 'get',
          flags: const ['summary', 'full', 'Raw'],
          args: const ['a'],
          asJson: false,
        ),
        'get-Raw-full-summary.a.txt',
      );
    });

    test('a flag with a positional argument names it after a dot', () {
      expect(
        outFileName(
          command: 'guide',
          flags: const ['pattern'],
          args: const ['crud'],
          asJson: false,
        ),
        'guide-pattern.crud.txt',
      );
    });

    test(r'each of / \ : # @ in an argument is written -', () {
      expect(
        outFileName(
          command: 'get',
          args: const ['login#components', r'a/b\c:d@e'],
          asJson: false,
        ),
        'get.login-components.a-b-c-d-e.txt',
      );
    });

    test('a code target goes before the extension', () {
      expect(
        outFileName(
          command: 'get',
          args: const ['login'],
          codeTarget: 'jaspr',
          asJson: false,
        ),
        'get.login.jaspr.txt',
      );
    });

    test('json ends the name with .json', () {
      expect(
        outFileName(
          command: 'check',
          args: const [],
          codeTarget: 'flutter',
          asJson: true,
        ),
        'check.all.flutter.json',
      );
    });
  });

  group('bareOutFile', () {
    test('names a file under .specstone/reports/ of the project root', () {
      final file = bareOutFile(Directory('/work/shop'), 'check.all.txt');
      expect(
        file.path.replaceAll(r'\', '/'),
        '/work/shop/.specstone/reports/check.all.txt',
      );
    });
  });

  group('requireOutPath', () {
    late Directory project;
    late Directory docsRoot;
    late String real;

    setUp(() async {
      project = await writeTree({
        '.specstone/config.yaml': 'pins: {}\n',
        '.specstone/records/x.md': '# x\n',
        '.git/config': '[core]\n',
        'docs/prds/PROJECT.md': '# p\n',
        'reports/keep.txt': 'keep\n',
      });
      real = project.resolveSymbolicLinksSync();
      docsRoot = Directory('$real/docs');
    });

    void requireOut(String below, {bool isBare = false}) => requireOutPath(
      '$real/$below',
      projectRoot: project,
      docsRoot: docsRoot,
      isBare: isBare,
    );

    void expectRefused(String below, {String? message, bool isBare = false}) {
      expect(
        () => requireOut(below, isBare: isBare),
        throwsA(
          isA<RenderFault>()
              .having(
                (fault) => fault.code,
                'code',
                RenderFaultCode.outputNotWritable,
              )
              .having((fault) => fault.exitStatus, 'exit status', 73)
              .having(
                (fault) => fault.message,
                'message',
                message == null ? isNotEmpty : contains(message),
              ),
        ),
        reason: below,
      );
    }

    const insideSpecstone =
        'the output path is inside .specstone/ but outside its bundles/ and '
        'reports/';

    test('refuses the config', () {
      expectRefused('.specstone/config.yaml', message: insideSpecstone);
    });

    test('refuses a record under .specstone/', () {
      expectRefused('.specstone/records/x.md', message: insideSpecstone);
    });

    test('refuses .specstone/bundles and .specstone/reports as files', () {
      expectRefused('.specstone/bundles', message: insideSpecstone);
      expectRefused('.specstone/reports', message: insideSpecstone);
    });

    test('refuses a path inside the docs root', () {
      expectRefused(
        'docs/prds/x.txt',
        message: 'the output path is inside the docs root',
      );
    });

    test('refuses a path below .git', () {
      expectRefused('.git/b.txt', message: 'it lies under .git');
    });

    test('refuses a bare path outside the project', () {
      expect(
        () => requireOutPath(
          '${Directory.systemTemp.resolveSymbolicLinksSync()}/b.txt',
          projectRoot: project,
          docsRoot: docsRoot,
          isBare: true,
        ),
        throwsA(isA<RenderFault>()),
      );
    });

    test(
      'accepts a path under .specstone/bundles/ and .specstone/reports/',
      () {
        requireOut('.specstone/bundles/x');
        requireOut('.specstone/reports/x');
        requireOut('.specstone/reports/deep/x', isBare: true);
      },
    );

    test('accepts a named path outside the project', () {
      requireOutPath(
        '${Directory.systemTemp.resolveSymbolicLinksSync()}/b.txt',
        projectRoot: project,
        docsRoot: docsRoot,
        isBare: false,
      );
    });

    test('accepts a named path in the project outside the docs root', () {
      requireOut('reports/out.txt');
    });

    test('a bare path with no project is refused', () {
      expect(
        () => requireOutPath('/tmp/b.txt', isBare: true),
        throwsA(isA<RenderFault>()),
      );
    });

    test('a named path with no project checks only .git', () {
      requireOutPath('/tmp/b.txt', isBare: false);
      expect(
        () => requireOutPath('/tmp/.git/b.txt', isBare: false),
        throwsA(
          isA<RenderFault>().having(
            (fault) => fault.message,
            'message',
            contains('it lies under .git'),
          ),
        ),
      );
    });
  });

  group('answerOutFile', () {
    final linksUnavailable = Platform.isWindows
        ? 'a link needs a privilege on Windows'
        : null;

    late Directory project;
    late String real;
    late File file;

    setUp(() async {
      project = await writeTree({'.specstone/config.yaml': 'pins: {}\n'});
      real = project.resolveSymbolicLinksSync();
      file = File('$real/.specstone/reports/deep/check.all.txt');
    });

    ReadAnswer write(
      String text, {
      File? to,
      bool asJson = false,
      List<String> warnings = const [],
      int exitStatus = 0,
    }) => answerOutFile(
      command: 'check',
      text: text,
      file: to ?? file,
      projectRoot: project,
      docsRoot: Directory('$real/docs'),
      isBare: true,
      asJson: asJson,
      warnings: warnings,
      exitStatus: exitStatus,
    );

    test('writes the text, makes missing folders, prints the header', () {
      final answer = write('one\ntwo\nthree\n');
      expect(file.readAsStringSync(), 'one\ntwo\nthree\n');
      expect(answer.text, '==> check: 3 lines, 3 tokens · ${file.path} <==\n');
    });

    test('carries warnings and the exit status through', () {
      final answer = write('x\n', warnings: const ['careful'], exitStatus: 1);
      expect(answer.warnings, ['careful']);
      expect(answer.exitStatus, 1);
    });

    test('with asJson the file holds the JSON and the reply is the object', () {
      final body = '${jsonEncode({'findings': <String>[]})}\n';
      final answer = write(body, asJson: true);
      expect(file.readAsStringSync(), body);
      expect(answer.json, {'out': file.path, 'lines': 1, 'tokens': 4});
      expect(answer.json.keys, ['out', 'lines', 'tokens']);
    });

    test('refuses a path under .specstone/ and leaves it whole', () {
      final config = File('$real/.specstone/config.yaml');
      expect(
        () => write('overwritten\n', to: config),
        throwsA(isA<SpecstoneFault>()),
      );
      expect(config.readAsStringSync(), 'pins: {}\n');
    });

    test('refuses a reports link into the config and leaves it whole', () {
      Directory('$real/.specstone/reports').createSync(recursive: true);
      final config = File('$real/.specstone/config.yaml');
      final link = Link('$real/.specstone/reports/link.txt')
        ..createSync(config.path);
      expect(
        () => write('overwritten\n', to: File(link.path)),
        throwsA(
          isA<RenderFault>().having(
            (fault) => fault.message,
            'message',
            'the output path is inside .specstone/ but outside its bundles/ '
                'and reports/',
          ),
        ),
      );
      expect(config.readAsStringSync(), 'pins: {}\n');
    }, skip: linksUnavailable);
  });
}
