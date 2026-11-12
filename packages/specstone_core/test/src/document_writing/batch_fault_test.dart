import 'package:specstone_core/src/document_writing/batch_fault.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:test/test.dart';

const _batch = 'edits/batch.txt';
const _story = 'prds/features/f01_login/us01_email_login/USER_STORY.md';
const _hash = 'abc123abc123';

BatchEntry _stale(String file, String key) => BatchEntry(
  code: 'base_mismatch',
  message: 'the doc changed since base $_hash',
  file: file,
  key: key,
  current: const CurrentTarget(
    heading: '==> x <==',
    text: '# Login\n',
    base: 'def456def456',
  ),
);

BatchEntry _gone(String file) => BatchEntry(
  code: 'doc_not_found',
  message: 'no doc at $file',
  file: file,
  key: 'doc',
);

const _badLine = BatchEntry(
  code: 'argument_invalid',
  message: 'text before the first naming line',
  file: _batch,
  line: 3,
);

void main() {
  group('document_writing/edit_one_section_or_field/write_a_batch fault', () {
    test('a file-level fault exits 64 and prints its one line', () {
      final fault = BatchFault.fileLevel(_batch, 'cannot read $_batch');
      expect(fault.exitStatus, 64);
      expect(fault.toText(), '$_batch: cannot read $_batch');
    });

    test('a file-level fault names code, message, and file, no blocks', () {
      final fault = BatchFault.fileLevel(_batch, '$_batch holds no block');
      expect(fault.toJson(), {
        'error': {
          'code': 'argument_invalid',
          'message': '$_batch holds no block',
          'file': _batch,
        },
      });
    });

    test('a batch of stale entries only exits 75', () {
      final fault = BatchFault([_stale(_story, 'doc'), _stale(_story, 'a')]);
      expect(fault.exitStatus, 75);
    });

    test('a batch with any entry that is not stale exits 64', () {
      expect(BatchFault([_stale(_story, 'doc'), _gone('p.md')]).exitStatus, 64);
      expect(BatchFault([_gone('p.md'), _stale(_story, 'doc')]).exitStatus, 64);
      expect(BatchFault([_badLine, _stale(_story, 'doc')]).exitStatus, 64);
      expect(BatchFault([_gone('p.md')]).exitStatus, 64);
    });

    test('a refused batch prints one fault line per entry, in file order', () {
      final fault = BatchFault([
        _badLine,
        _stale(_story, 'doc'),
        _gone('p.md'),
      ]);
      expect(fault.toText().split('\n'), [
        '$_batch:3: text before the first naming line',
        '$_story: doc: the doc changed since base $_hash',
        'p.md: doc: no doc at p.md',
      ]);
    });

    test('a stale block first gives the envelope its file and key', () {
      final fault = BatchFault([_stale(_story, 'doc'), _gone('p.md')]);
      expect(fault.toJson(), {
        'error': {
          'code': 'base_mismatch',
          'message': 'the doc changed since base $_hash',
          'file': _story,
          'key': 'doc',
          'blocks': [
            {
              'code': 'base_mismatch',
              'message': 'the doc changed since base $_hash',
              'file': _story,
              'key': 'doc',
              'current': {'text': '# Login\n', 'base': 'def456def456'},
            },
            {
              'code': 'doc_not_found',
              'message': 'no doc at p.md',
              'file': 'p.md',
              'key': 'doc',
            },
          ],
        },
      });
    });

    test(
      'a refused line first gives the envelope its file and line, no key',
      () {
        final fault = BatchFault([_badLine, _stale(_story, 'doc')]);
        final error = fault.toJson()['error']! as Map<String, Object?>;
        expect(error['code'], 'argument_invalid');
        expect(error['message'], 'text before the first naming line');
        expect(error['file'], _batch);
        expect(error['line'], 3);
        expect(error.containsKey('key'), isFalse);
        final blocks = error['blocks']! as List<Object?>;
        expect(blocks.first, {
          'code': 'argument_invalid',
          'message': 'text before the first naming line',
          'file': _batch,
          'line': 3,
        });
        expect(blocks, hasLength(2));
      },
    );

    test('an entry takes code and message from any fault, current from a '
        'write fault', () {
      final write = WriteFault(
        WriteFaultCode.baseMismatch,
        'the doc changed since base $_hash',
        current: const CurrentTarget(
          heading: '==> x <==',
          text: 'text\n',
          base: 'def456def456',
        ),
      );
      final entry = BatchEntry.fromFault(write, file: _story, key: 'doc');
      expect(entry.code, 'base_mismatch');
      expect(entry.message, 'the doc changed since base $_hash');
      expect(entry.file, _story);
      expect(entry.key, 'doc');
      expect(entry.line, isNull);
      expect(entry.current!.base, 'def456def456');

      final index = BatchEntry.fromFault(
        IndexFault(IndexFaultCode.docNotFound, 'no doc at p.md'),
        file: 'p.md',
        key: 'doc',
      );
      expect(index.code, 'doc_not_found');
      expect(index.message, 'no doc at p.md');
      expect(index.current, isNull);
    });
  });
}
