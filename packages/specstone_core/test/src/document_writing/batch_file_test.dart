import 'dart:io';

import 'package:specstone_core/src/document_writing/batch_fault.dart';
import 'package:specstone_core/src/document_writing/batch_file.dart';
import 'package:test/test.dart';

const _batch = 'edits/batch.txt';
const _hash = 'abc123abc123';
const _other = 'def456def456';
const _storyPath = 'prds/features/f01_login/FEATURE.md';

String _head(String path, [String hash = _hash]) =>
    '==> login (feature) · $path · base $hash <==';

BatchFault _refusal(void Function() run) {
  try {
    run();
  } on BatchFault catch (fault) {
    return fault;
  }
  fail('expected a BatchFault');
}

void main() {
  group('E17 read', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('batch_file_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('reads a relative path from the working directory', () {
      File('${dir.path}/b.txt').writeAsStringSync('text\n');
      expect(readBatchFile('b.txt', workingDirectory: dir), 'text\n');
    });

    test('reads an absolute path', () {
      final file = File('${dir.path}/b.txt')..writeAsStringSync('text\n');
      final elsewhere = Directory.systemTemp.createTempSync('batch_cwd_');
      addTearDown(() => elsewhere.deleteSync(recursive: true));
      expect(readBatchFile(file.path, workingDirectory: elsewhere), 'text\n');
    });

    test('a missing path refuses alone, `cannot read <path>`', () {
      final fault = _refusal(
        () => readBatchFile('none.txt', workingDirectory: dir),
      );
      expect(fault.exitStatus, 64);
      expect(fault.toText(), 'none.txt: cannot read none.txt');
      final error = fault.toJson()['error']! as Map<String, Object?>;
      expect(error, {
        'code': 'argument_invalid',
        'message': 'cannot read none.txt',
        'file': 'none.txt',
      });
    });

    test('a folder refuses as a missing path does', () {
      Directory('${dir.path}/sub').createSync();
      final fault = _refusal(() => readBatchFile('sub', workingDirectory: dir));
      expect(fault.toText(), 'sub: cannot read sub');
    });

    test('a file of bytes that are no text is unreadable', () {
      File('${dir.path}/b.txt').writeAsBytesSync([0xff, 0xfe, 0x41]);
      final fault = _refusal(
        () => readBatchFile('b.txt', workingDirectory: dir),
      );
      expect(fault.toText(), 'b.txt: cannot read b.txt');
    });

    test('a file the process may not read is unreadable', () {
      final file = File('${dir.path}/b.txt')..writeAsStringSync('text\n');
      Process.runSync('chmod', ['000', file.path]);
      addTearDown(() => Process.runSync('chmod', ['600', file.path]));
      final fault = _refusal(
        () => readBatchFile('b.txt', workingDirectory: dir),
      );
      expect(fault.toText(), 'b.txt: cannot read b.txt');
    }, skip: Platform.isWindows ? 'no POSIX modes on Windows' : null);
  });

  group('E17 split', () {
    test('an empty file holds no block', () {
      final fault = _refusal(() => parseBatchFile(_batch, ''));
      expect(fault.exitStatus, 64);
      expect(fault.toText(), '$_batch: $_batch holds no block');
    });

    test('text with no naming line holds no block, nothing else named', () {
      final fault = _refusal(
        () => parseBatchFile(_batch, 'some words\n\nmore words\n'),
      );
      expect(fault.toText(), '$_batch: $_batch holds no block');
      expect(fault.toJson()['error'], isNot(contains('blocks')));
    });

    test('a naming line inside fenced code is no naming line', () {
      final fault = _refusal(
        () => parseBatchFile(_batch, '```text\n${_head(_storyPath)}\n```\n'),
      );
      expect(fault.toText(), '$_batch: $_batch holds no block');
    });
  });

  group('blocks', () {
    test(
      'splits at each naming line, each block holding the lines under it',
      () {
        final text =
            '${_head(_storyPath)}\n'
            '# Login\n'
            '\n'
            'body\n'
            '\n'
            '${_head('$_storyPath#problem', _other)}\n'
            '## Problem\n'
            '\n'
            'words\n';
        final parsed = parseBatchFile(_batch, text);
        expect(parsed.lineFaults, isEmpty);
        expect(parsed.blocks, hasLength(2));
        final [first, second] = parsed.blocks;
        expect(first.line, 1);
        expect(first.naming.path, _storyPath);
        expect(first.naming.base, _hash);
        expect(first.text, '# Login\n\nbody\n');
        expect(first.leavesFenceOpen, isFalse);
        expect(second.line, 6);
        expect(second.naming.path, '$_storyPath#problem');
        expect(second.naming.base, _other);
        expect(second.text, '## Problem\n\nwords\n');
        expect(second.leavesFenceOpen, isFalse);
      },
    );

    test('a block with no lines under its naming line holds empty text', () {
      final parsed = parseBatchFile(
        _batch,
        '${_head('$_storyPath#_lead')}\n${_head('$_storyPath#problem')}\n',
      );
      expect(parsed.blocks.map((block) => block.text), ['', '']);
    });

    test('trailing blank lines of a block are dropped, leading ones kept', () {
      final parsed = parseBatchFile(
        _batch,
        '${_head(_storyPath)}\n\n\nbody\n \t\n\n\n'
        '${_head(_storyPath, _other)}\n',
      );
      expect(parsed.blocks.first.text, '\n\nbody\n');
      expect(parsed.blocks.last.text, '');
    });

    test('the last line needs no line end', () {
      final parsed = parseBatchFile(_batch, '${_head(_storyPath)}\nbody');
      expect(parsed.blocks.single.text, 'body\n');
    });

    test('CRLF line ends and a leading BOM read as LF text', () {
      final parsed = parseBatchFile(
        _batch,
        '\uFEFF${_head(_storyPath)}\r\nline one\r\nline two\r\n'
        '${_head('$_storyPath#problem')}\r\n',
      );
      expect(parsed.lineFaults, isEmpty);
      expect(parsed.blocks, hasLength(2));
      expect(parsed.blocks.first.naming.base, _hash);
      expect(parsed.blocks.first.text, 'line one\nline two\n');
    });

    test('blank lines before the first naming line are allowed', () {
      final parsed = parseBatchFile(
        _batch,
        '\n \t\n\n${_head(_storyPath)}\nbody\n',
      );
      expect(parsed.lineFaults, isEmpty);
      expect(parsed.blocks.single.line, 4);
    });

    test('a naming-line-shaped line in fenced code is block text', () {
      final text =
          '${_head(_storyPath)}\n'
          '# Login\n'
          '\n'
          '```text\n'
          '${_head('$_storyPath#problem')}\n'
          '==> sign_in (journey) · prds/j.md <==\n'
          '```\n'
          '\n'
          'after\n';
      final parsed = parseBatchFile(_batch, text);
      expect(parsed.lineFaults, isEmpty);
      final block = parsed.blocks.single;
      expect(
        block.text,
        '# Login\n\n```text\n${_head('$_storyPath#problem')}\n'
        '==> sign_in (journey) · prds/j.md <==\n```\n\nafter\n',
      );
      expect(block.leavesFenceOpen, isFalse);
    });

    test('an indented naming-line-shaped line is block text', () {
      final parsed = parseBatchFile(
        _batch,
        '${_head(_storyPath)}\nsee\n  ${_head('$_storyPath#problem')}\n',
      );
      expect(parsed.lineFaults, isEmpty);
      expect(
        parsed.blocks.single.text,
        'see\n  ${_head('$_storyPath#problem')}\n',
      );
    });

    test('a naming line after a closed fence opens a block again', () {
      final parsed = parseBatchFile(
        _batch,
        '${_head(_storyPath)}\n```\ncode\n```\n${_head(_storyPath, _other)}\n',
      );
      expect(parsed.blocks, hasLength(2));
      expect(parsed.blocks.first.text, '```\ncode\n```\n');
    });
  });

  group('E10 fence', () {
    test('a fence that stays open to the end is left open by its block', () {
      final text =
          '${_head(_storyPath)}\n'
          'one\n'
          '${_head('$_storyPath#problem', _other)}\n'
          '```text\n'
          'never closed\n'
          '${_head('$_storyPath#goal')}\n';
      final parsed = parseBatchFile(_batch, text);
      expect(parsed.lineFaults, isEmpty);
      expect(parsed.blocks, hasLength(2));
      expect(parsed.blocks.first.leavesFenceOpen, isFalse);
      expect(parsed.blocks.last.leavesFenceOpen, isTrue);
      expect(parsed.blocks.last.line, 3);
      expect(parsed.blocks.last.text, contains(_head('$_storyPath#goal')));
    });
  });

  group('E18 lines', () {
    test('text before the first naming line is refused by line number', () {
      final parsed = parseBatchFile(
        _batch,
        'intro\n\n  more\n${_head(_storyPath)}\nbody\n',
      );
      expect(parsed.blocks.single.line, 4);
      expect(parsed.lineFaults.map((entry) => entry.line), [1, 3]);
      for (final entry in parsed.lineFaults) {
        expect(entry.code, 'argument_invalid');
        expect(entry.file, _batch);
        expect(entry.key, isNull);
      }
      expect(
        BatchFault(parsed.lineFaults).toText().split('\n').first,
        '$_batch:1: text before the first naming line',
      );
    });

    test('a journey line is refused by line number', () {
      final parsed = parseBatchFile(
        _batch,
        '${_head(_storyPath)}\nbody\n'
        '==> sign_in (journey) · prds/journeys/sign_in/JOURNEY.md <==\n',
      );
      expect(parsed.blocks.map((block) => block.line), [1]);
      expect(parsed.lineFaults.map((entry) => entry.line), [3]);
      expect(
        BatchFault(parsed.lineFaults).toText(),
        '$_batch:3: the naming line holds no base of 12 lowercase hex '
        'characters',
      );
    });

    test('a bundle line with a summary part is refused', () {
      final parsed = parseBatchFile(
        _batch,
        '==> login (feature) · $_storyPath · summary <==\nbody\n',
      );
      expect(parsed.blocks, isEmpty);
      expect(parsed.lineFaults.map((entry) => entry.line), [1]);
    });

    test('a reply line ending in unchanged is refused', () {
      final parsed = parseBatchFile(
        _batch,
        '${_head(_storyPath)}\nbody\n'
        '==> login (feature) · $_storyPath · base $_hash · unchanged <==\n',
      );
      expect(parsed.blocks.map((block) => block.line), [1]);
      expect(parsed.blocks.single.text, 'body\n');
      expect(parsed.lineFaults.map((entry) => entry.line), [3]);
    });

    test('a malformed hash is refused, the path in a base tail unharmed', () {
      final text =
          '${_head(_storyPath, 'ABC123ABC123')}\n'
          '${_head(_storyPath, 'abc123abc12')}\n'
          '${_head(_storyPath, 'abc123abc123  ')}\n'
          '${_head(_storyPath, _hash)}\n';
      final parsed = parseBatchFile(_batch, text);
      expect(parsed.lineFaults.map((entry) => entry.line), [1, 2, 3]);
      expect(parsed.blocks.map((block) => block.line), [4]);
    });

    test('a guide line is refused as a line, never taken as block text', () {
      final parsed = parseBatchFile(
        _batch,
        '${_head(_storyPath)}\nbody\n==> feature <==\nmore\n',
      );
      expect(parsed.lineFaults.map((entry) => entry.line), [3]);
      expect(parsed.blocks.single.text, 'body\n');
    });

    test('a file of one bad naming line holds a line fault and no block', () {
      final parsed = parseBatchFile(_batch, '==> feature <==\n');
      expect(parsed.blocks, isEmpty);
      expect(parsed.lineFaults.map((entry) => entry.line), [1]);
    });

    test('a line shaped like a naming line that reads as none is refused', () {
      const unread = '==> b (t) · specs/b.md · base abcdef123456<==';
      for (final tail in ['', '\u00A0', '\r', ' \u2003']) {
        final parsed = parseBatchFile(
          _batch,
          '${_head(_storyPath)}\nbody\n$unread${tail.replaceAll('\r', '\r\r')}'
          '\nmore\n',
        );
        final reason = 'tail ${tail.codeUnits}';
        expect(parsed.blocks.map((block) => block.line), [1], reason: reason);
        expect(parsed.lineFaults.map((entry) => entry.line), [
          3,
        ], reason: reason);
        expect(
          BatchFault(parsed.lineFaults).toText(),
          '$_batch:3: the line is shaped like a naming line but reads as none',
          reason: reason,
        );
      }
    });

    test('text before the first naming line is one fault, shaped or not', () {
      final parsed = parseBatchFile(
        _batch,
        '==> b (t) · specs/b.md · base abcdef123456<==\n${_head(_storyPath)}\n',
      );
      expect(parsed.lineFaults.map((entry) => entry.line), [1]);
      expect(parsed.blocks.map((block) => block.line), [2]);
    });

    test('faults of every kind come in file order', () {
      final parsed = parseBatchFile(
        _batch,
        'intro\n${_head(_storyPath)}\n==>b<==\n==> feature <==\n'
        '${_head(_storyPath, _other)}\n==><==\n',
      );
      expect(parsed.lineFaults.map((entry) => entry.line), [1, 3, 4, 6]);
    });

    test(
      'a prose line that opens with an arrow but does not close is text',
      () {
        final parsed = parseBatchFile(
          _batch,
          '${_head(_storyPath)}\n==> see below\nthen <== it ends\n==>\n',
        );
        expect(parsed.lineFaults, isEmpty);
        expect(
          parsed.blocks.single.text,
          '==> see below\nthen <== it ends\n==>\n',
        );
      },
    );

    test('an indented or fenced line of that shape is text', () {
      final parsed = parseBatchFile(
        _batch,
        '${_head(_storyPath)}\n  ==>b<==\n```\n==>b<==\n```\n',
      );
      expect(parsed.lineFaults, isEmpty);
    });

    test('a refused line inside fenced code is text, not a fault', () {
      final parsed = parseBatchFile(
        _batch,
        '${_head(_storyPath)}\n```\n==> feature <==\n```\n',
      );
      expect(parsed.lineFaults, isEmpty);
    });
  });
}
