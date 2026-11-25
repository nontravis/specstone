import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/code_fingerprint.dart';
import 'package:specstone_core/src/consistency_check/models/file_fingerprint.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/templates/code_target.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';
import '../../helpers/posix_modes.dart';
import '../../helpers/target_fixture.dart';
import '../../helpers/temp_tree.dart';

const _bom = [0xEF, 0xBB, 0xBF];
const _twelveHex = r'^[0-9a-f]{12}$';
const _goneWarning =
    'gone.dart: cannot read the file; implements Symbols in it are not checked';

List<int> _utf8(String text) => utf8.encode(text);

String _rawHash(List<int> bytes) =>
    sha256.convert(bytes).toString().substring(0, 12);

void main() {
  group('fileCodeFingerprint', () {
    String fp(String text, {String path = 'lib/a.dart'}) =>
        fileCodeFingerprint(_utf8(text), path: path);

    test('hashes the kept lines, each with one LF', () {
      final lf = fp('a\nb\n');
      expect(lf, baseHashOf('a\nb\n'));
      expect(lf, matches(RegExp(_twelveHex)));
      expect(fp('a\nb'), lf);
    });

    test('gives one fingerprint to UTF-8 text with CRLF and with LF', () {
      expect(fp('a\r\nb\r\n'), fp('a\nb\n'));
    });

    test(
      'keeps a BOM and gives one fingerprint to BOM text with CRLF or LF',
      () {
        final lf = fileCodeFingerprint([
          ..._bom,
          ..._utf8('a\nb\n'),
        ], path: 'lib/a.dart');
        final crlf = fileCodeFingerprint([
          ..._bom,
          ..._utf8('a\r\nb\r\n'),
        ], path: 'lib/a.dart');
        expect(crlf, lf);
        expect(lf, isNot(fp('a\nb\n')));
        expect(lf, baseHashOf('\uFEFFa\nb\n'));
        expect(
          fileCodeFingerprint(_bom, path: 'lib/a.dart'),
          baseHashOf('\uFEFF'),
        );
      },
    );

    test(
      'hashes a BOM ahead of the kept lines, whatever the first line is',
      () {
        String withBom(String text) =>
            fileCodeFingerprint([..._bom, ..._utf8(text)], path: 'lib/a.dart');
        expect(withBom('// (c)\nint a;\n'), isNot(fp('// (c)\nint a;\n')));
        expect(withBom('int a;\n'), isNot(fp('int a;\n')));
        expect(withBom('// (c)\nint a;\n'), baseHashOf('\uFEFFint a;\n'));
      },
    );

    test('writes the BOM character as an escape in its source and test', () {
      for (final path in [
        'lib/src/consistency_check/code_fingerprint.dart',
        'test/src/consistency_check/code_fingerprint_test.dart',
      ]) {
        expect(File(path).readAsStringSync(), isNot(contains('\uFEFF')));
      }
    });

    test('turns only a CRLF pair into LF, never a lone CR', () {
      expect(fp('a\rb\n'), isNot(fp('a\nb\n')));
    });

    test('keeps a whole comment line added, changed, or removed out of it', () {
      final plain = fp('a\nb\n');
      expect(fp('// added\na\nb\n'), plain);
      expect(fp('a\n  // note\nb\n'), plain);
      expect(fp('a\n// changed\nb\n'), plain);
      expect(fp('a\n//\nb\n'), plain);
      expect(fp('a\n\t# note\nb\n', path: 'tool/a.sh'), plain);
    });

    test('drops a comment line by the mark of its extension alone', () {
      expect(fp('a\n# note\n'), isNot(fp('a\n')));
      expect(fp('a\n// note\n', path: 'tool/a.py'), isNot(fp('a\n')));
      expect(fp('a\n# note\n', path: 'tool/a.py'), fp('a\n'));
    });

    test('drops a blank line, empty or of spaces and tabs only', () {
      final plain = fp('a\nb\n');
      expect(fp('a\n\nb\n'), plain);
      expect(fp('a\n \t \nb\n'), plain);
      expect(fp('a\nb\n\n\n'), plain);
      expect(fp('\n\na\nb\n'), plain);
      expect(fp('a\r\n\r\nb\r\n'), plain);
    });

    group('ASCII text with no CR', () {
      // A non-ASCII comment line drops out of the hash, and its bytes send the
      // file to the text path, so each pair compares the two paths.
      final nonAsciiComment = String.fromCharCode(0x00E9);
      final noBreakSpace = String.fromCharCode(0x00A0);

      for (final (extension, mark) in [
        ('.dart', '//'),
        ('.js', '//'),
        ('.ts', '//'),
        ('.sh', '#'),
        ('.ps1', '#'),
        ('.yaml', '#'),
        ('.yml', '#'),
        ('.py', '#'),
      ]) {
        test('hashes a $extension file as the text path does', () {
          const body = 'a\n  b\n\n \t \n\tc\nd // e\n';
          final plain = '$mark one\n  $mark two\n$body$mark end';
          final viaText = '$mark $nonAsciiComment\n$plain';
          expect(
            fp(plain, path: 'src/a$extension'),
            fp(viaText, path: 'src/a$extension'),
          );
          expect(
            fp(plain, path: 'src/a$extension'),
            baseHashOf('a\n  b\n\tc\nd // e\n'),
          );
        });
      }

      test('keeps a mark line of an extension with no mark, and the lines of '
          'a file with no final line feed or no bytes', () {
        expect(fp('# a\nb', path: 'x.txt'), baseHashOf('# a\nb\n'));
        expect(fp('# a\nb', path: 'Makefile'), baseHashOf('# a\nb\n'));
        expect(fp('', path: 'a.dart'), baseHashOf(''));
        expect(fp('\n \n', path: 'a.dart'), baseHashOf(''));
      });

      test('reads a line that opens with other ASCII whitespace as the text '
          'path does', () {
        expect(fp('a\n\u000B// c\nb\n'), baseHashOf('a\nb\n'));
        expect(fp('a\n\f\nb\n'), baseHashOf('a\n\f\nb\n'));
      });

      test('sends a file with a CR or a non-ASCII byte to the text path', () {
        expect(fp('a\r\n// c\r\nb\r\n'), baseHashOf('a\nb\n'));
        expect(
          fp('$nonAsciiComment\n// c\nb\n'),
          baseHashOf('$nonAsciiComment\nb\n'),
        );
        expect(fp('a\n$noBreakSpace// c\nb\n'), baseHashOf('a\nb\n'));
      });
    });

    test('gives a new fingerprint to an end-of-line comment change', () {
      expect(fp('show(); // was hide\n'), isNot(fp('show(); // was show\n')));
    });

    test('gives a new fingerprint to a code line change', () {
      expect(fp('a\nb\n'), isNot(fp('a\nc\n')));
      expect(fp('a\nb\n'), isNot(fp('a \nb\n')));
      expect(fp('a\nb\n'), isNot(fp('a\n b\n')));
    });

    test('keeps a line inside a block comment', () {
      expect(fp('/*\n note\n*/\n'), isNot(fp('/*\n other\n*/\n')));
    });

    test('drops a string literal line that opens with a comment mark', () {
      expect(fp("var s = '''\n// text\n''';\n"), fp("var s = '''\n''';\n"));
    });

    test('hashes a file of comments and blank lines only as empty text', () {
      expect(fp('// a\n\n  // b\n \n'), emptyBaseHash);
      expect(fp('// a\n\n  // b\n \n'), 'e3b0c44298fc');
      expect(fp(''), emptyBaseHash);
    });

    test('hashes bytes that are not UTF-8 raw, line ends and all', () {
      const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0xFF];
      expect(fileCodeFingerprint(png, path: 'logo.png'), _rawHash(png));
      final changed = [...png]..[8] = 0xFE;
      expect(
        fileCodeFingerprint(changed, path: 'logo.png'),
        isNot(fileCodeFingerprint(png, path: 'logo.png')),
      );
      const commentBytes = [0x2F, 0x2F, 0x20, 0xFF, 0x0A];
      expect(
        fileCodeFingerprint(commentBytes, path: 'a.dart'),
        _rawHash(commentBytes),
      );
    });
  });

  group('folderCodeFingerprint', () {
    const one = FileFingerprint(
      path: 'lib/a.dart',
      fingerprint: 'aaaaaaaaaaaa',
    );
    const two = FileFingerprint(
      path: 'lib/b.dart',
      fingerprint: 'bbbbbbbbbbbb',
    );

    test('hashes a folder with no listed file to the empty base', () {
      expect(folderCodeFingerprint(const []), emptyBaseHash);
    });

    test('hashes one `<path> <fingerprint>` line per file, in list order', () {
      expect(
        folderCodeFingerprint(const [one, two]),
        baseHashOf('lib/a.dart aaaaaaaaaaaa\nlib/b.dart bbbbbbbbbbbb\n'),
      );
    });
  });

  group('codeLinkFiles', () {
    Future<Directory> tree(Map<String, String> files) => writeTree(files);

    test('lists the files of a folder entry sorted by code point', () async {
      final root = await tree({
        'lib/b.dart': 'b',
        'lib/a.dart': 'a',
        'lib/sub/c.dart': 'c',
        'other/d.dart': 'd',
      });
      expect(codeLinkFiles(root, 'lib/'), [
        'lib/a.dart',
        'lib/b.dart',
        'lib/sub/c.dart',
      ]);
    });

    test('lists the one file of a file entry', () async {
      final root = await tree({'lib/a.dart': 'a', 'lib/b.dart': 'b'});
      expect(codeLinkFiles(root, 'lib/a.dart'), ['lib/a.dart']);
    });

    test('lists nothing for a path that names nothing', () async {
      final root = await tree({'lib/a.dart': 'a'});
      expect(codeLinkFiles(root, 'gone/'), isEmpty);
    });

    test('skips dot names, as the code root lister does', () async {
      final root = await tree({'lib/a.dart': 'a', 'lib/.hidden.dart': 'h'});
      expect(codeLinkFiles(root, 'lib'), ['lib/a.dart']);
    });

    test(
      'leaves out the code root of another target nested in the folder',
      () async {
        final root = await tree({'app/lib/a.dart': 'a', 'app/web/w.dart': 'w'});
        const flutter = CodeTarget('flutter', codeRoot: 'app');
        const jaspr = CodeTarget('jaspr', codeRoot: 'app/web');
        const targets = [flutter, jaspr];
        expect(
          codeLinkFiles(
            Directory('${root.path}/app'),
            '.',
            nestedRoots: nestedRootsOf(root, flutter, targets),
          ),
          ['lib/a.dart'],
        );
        expect(
          codeLinkFiles(
            Directory('${root.path}/app/web'),
            '.',
            nestedRoots: nestedRootsOf(root, jaspr, targets),
          ),
          ['w.dart'],
        );
      },
    );

    test('passes a folder that cannot be listed to onUnlistable', () async {
      final root = await tree({'lib/locked/x.dart': 'x', 'lib/a.dart': 'a'});
      final locked = '${root.path}/lib/locked';
      Process.runSync('chmod', ['000', locked]);
      addTearDown(() => Process.runSync('chmod', ['755', locked]));
      final unlistable = <String>[];
      final files = codeLinkFiles(root, 'lib', onUnlistable: unlistable.add);
      expect(files, ['lib/a.dart']);
      expect(unlistable, ['lib/locked']);
    }, skip: unreadablePathSkipReason());
  });

  group('CheckContext.codeBytesOf', () {
    test('returns the raw bytes of a file and reads each file once', () async {
      const bytes = [0x00, 0x0D, 0x0A, 0xFF, 0xEF, 0xBB, 0xBF];
      final project = await writeLoginProject();
      File('${project.path}/blob.bin').writeAsBytesSync(bytes);
      final session = openSession(project);
      addTearDown(session.close);
      final context = CheckContext(session);
      final target = context.targets.single;

      expect(
        context.codeBytesOf(target, 'blob.bin', reason: CodeRead.symbols),
        bytes,
      );
      File('${project.path}/blob.bin').deleteSync();
      expect(
        context.codeBytesOf(target, 'blob.bin', reason: CodeRead.symbols),
        bytes,
      );
      expect(context.codeFilesRead, 1);
    });

    test('shares one read with codeTextOf', () async {
      final project = await writeLoginProject();
      File('${project.path}/a.dart').writeAsStringSync('class A {}\r\n');
      final session = openSession(project);
      addTearDown(session.close);
      final context = CheckContext(session);
      final target = context.targets.single;

      expect(context.codeTextOf(target, 'a.dart'), 'class A {}\r\n');
      File('${project.path}/a.dart').deleteSync();
      expect(
        context.codeBytesOf(target, 'a.dart', reason: CodeRead.symbols),
        _utf8('class A {}\r\n'),
      );
      expect(context.codeFilesRead, 1);
      expect(context.unstatedWarnings, isEmpty);
    });

    test(
      'returns null for a missing file and warns once, in codeTextOf form',
      () async {
        final project = await writeLoginProject();
        final session = openSession(project);
        addTearDown(session.close);
        final context = CheckContext(session);
        final target = context.targets.single;

        expect(
          context.codeBytesOf(target, 'gone.dart', reason: CodeRead.symbols),
          isNull,
        );
        expect(context.codeTextOf(target, 'gone.dart'), isNull);
        expect(
          context.codeBytesOf(target, 'gone.dart', reason: CodeRead.symbols),
          isNull,
        );
        expect(context.unstatedWarnings, [_goneWarning]);
      },
    );

    test(
      'opens the warning with the target name when the project has two targets',
      () async {
        final session = openSession(await writeTwinProject());
        addTearDown(session.close);
        final context = CheckContext(session);
        final jaspr = session.project.targets.singleWhere(
          (target) => target.name == 'jaspr',
        );

        expect(
          context.codeBytesOf(jaspr, 'gone.dart', reason: CodeRead.symbols),
          isNull,
        );
        expect(context.unstatedWarnings, ['jaspr: $_goneWarning']);
      },
    );
  });
}
