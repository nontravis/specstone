import 'dart:convert';

import 'package:specstone_core/src/consistency_check/implements_entry.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/matrix_rows.dart';
import 'package:specstone_core/src/index_query/record_entries.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:test/test.dart';

import '../../helpers/record_doc_type.dart';

/// The record doc type `domain:template_packs` INV-31 gives: found by its
/// `record_status` field, per-target.
final MergedDocType _recordType = recordDocType(
  sections: const [],
  isPerTarget: true,
  fields: const [
    statusesField,
    MergedField(
      id: 'implements',
      type: FieldType.outputRef,
      list: true,
      pointer: PointerKind.itemExact,
    ),
    MergedField(
      id: 'tests',
      type: FieldType.outputRef,
      list: true,
      pointer: PointerKind.itemTest,
    ),
  ],
);

/// [_recordType] with the matrix section the record doc type may carry.
final MergedDocType _matrixRecordType = _recordType.copyWith(
  sections: const [matrixSection],
);

const _matrixPath = 'specs/jaspr/f02_feedback/IMPLEMENTATION.md';

/// A record text whose matrix section holds [rows], the first on file line 10.
String _matrixRecord(
  List<String> rows, {
  String header = 'Verification matrix',
}) =>
    '---\n'
    'statuses:\n'
    '  - show_toast/queue_toasts:implemented\n'
    '---\n\n'
    '# Feedback implementation\n\n'
    '## $header\n\n'
    '${rows.join('\n')}\n';

/// Parses the record at [path] with [text] under a two-target project whose
/// record doc type is [type].
IndexedDoc _record(String path, String text, {MergedDocType? type}) =>
    parseIndexedDoc(
      docPath: path,
      bytes: utf8.encode(text),
      match: DocTypeMatcher(
        MergedSet(docTypes: [type ?? _recordType]),
        targetNames: const ['flutter', 'jaspr'],
      ).match(path),
      statusesOutside: true,
      codeTarget: 'jaspr',
    ).doc;

void main() {
  test('domain:index_query RecordEntry: a record indexes its entries, the '
      'feature itself named by an empty item', () {
    final doc = _record(
      'specs/jaspr/f02_feedback/IMPLEMENTATION.md',
      '---\n'
          'statuses:\n'
          '  - show_toast:implemented\n'
          '  - show_toast/queue_toasts:planned\n'
          "  - ':skipped:no web view on the web'\n"
          'implements:\n'
          '  - show_toast:lib/toast.dart:showToast\n'
          '  - show_toast:lib/toast_host.dart\n'
          '---\n\n# Feedback implementation\n',
    );

    expect(recordEntriesOf(doc, _recordType), const [
      RecordEntry(
        item: 'show_toast',
        status: RecordStatus.implemented,
        codePaths: ['lib/toast.dart:showToast', 'lib/toast_host.dart'],
      ),
      RecordEntry(
        item: 'show_toast/queue_toasts',
        status: RecordStatus.planned,
      ),
      RecordEntry(
        item: '',
        status: RecordStatus.skipped,
        reason: 'no web view on the web',
      ),
    ]);
  });

  test('domain:index_query RecordEntry: a status line no RecordStatus names '
      'gives the entry no status', () {
    final doc = _record(
      'specs/jaspr/f02_feedback/IMPLEMENTATION.md',
      '---\n'
          'statuses:\n'
          '  - show_toast:wip\n'
          '  - show_toast/pin_toast:deprecated\n'
          '---\n\n# Feedback implementation\n',
    );

    expect(recordEntriesOf(doc, _recordType), const [
      RecordEntry(item: 'show_toast'),
      RecordEntry(
        item: 'show_toast/pin_toast',
        status: RecordStatus.deprecated,
      ),
    ]);
  });

  test(
    'Review Focus 3: a second `:` before the Symbol stays inside the path',
    () {
      final doc = _record(
        'specs/jaspr/f02_feedback/IMPLEMENTATION.md',
        '---\n'
            'implements:\n'
            '  - show_toast:lib/toast.dart:Toast:showToast\n'
            '---\n\n# Feedback implementation\n',
      );

      expect(recordEntriesOf(doc, _recordType), const [
        RecordEntry(
          item: 'show_toast',
          codePaths: ['lib/toast.dart:Toast:showToast'],
        ),
      ]);
    },
  );

  test('Review Focus 5: a CRLF record keeps its entries', () {
    final doc = _record(
      'specs/jaspr/f02_feedback/IMPLEMENTATION.md',
      '---\r\n'
          'statuses:\r\n'
          '  - show_toast:implemented\r\n'
          'implements:\r\n'
          '  - show_toast:lib/toast.dart\r\n'
          '---\r\n\r\n# Feedback implementation\r\n',
    );

    expect(recordEntriesOf(doc, _recordType), const [
      RecordEntry(
        item: 'show_toast',
        status: RecordStatus.implemented,
        codePaths: ['lib/toast.dart'],
      ),
    ]);
  });

  test('Review Focus 5: a record whose frontmatter is not valid YAML is kept '
      'with a warning and holds no entries', () {
    final doc = _record(
      'specs/jaspr/f02_feedback/IMPLEMENTATION.md',
      '---\n'
          'statuses: [show_toast\n'
          '---\n\n# Feedback implementation\n',
    );

    const warning =
        'specs/jaspr/f02_feedback/IMPLEMENTATION.md: frontmatter is not '
        'valid YAML; its values are not indexed';
    expect(doc.warnings, [warning]);
    expect(recordEntriesOf(doc, _recordType), isEmpty);
  });

  test('a skipped entry with no reason and an entry with code paths but no '
      'status line keep what their lines hold', () {
    final doc = _record(
      'specs/jaspr/f02_feedback/IMPLEMENTATION.md',
      '---\n'
          'statuses:\n'
          '  - show_toast:skipped\n'
          'implements:\n'
          '  - show_toast/pin_toast:lib/pin.dart\n'
          '---\n\n# Feedback implementation\n',
    );

    expect(recordEntriesOf(doc, _recordType), const [
      RecordEntry(item: 'show_toast', status: RecordStatus.skipped),
      RecordEntry(item: 'show_toast/pin_toast', codePaths: ['lib/pin.dart']),
    ]);
  });

  test('a scalar statuses value reads as one line; a non-scalar implements '
      'line yields no entry', () {
    final doc = _record(
      'specs/jaspr/f02_feedback/IMPLEMENTATION.md',
      '---\n'
          'statuses: show_toast:implemented\n'
          'implements:\n'
          '  - lib/toast.dart: {item: show_toast}\n'
          '---\n\n# Feedback implementation\n',
    );

    expect(recordEntriesOf(doc, _recordType), const [
      RecordEntry(item: 'show_toast', status: RecordStatus.implemented),
    ]);
  });

  test('an implements line with a fingerprint gives its pointer alone', () {
    final doc = _record(
      'specs/jaspr/f02_feedback/IMPLEMENTATION.md',
      '---\n'
          'implements:\n'
          '  - show_toast:lib/toast.dart:showToast 0123456789ab\n'
          '  - show_toast:lib/toast_host.dart 0123456789ab\n'
          '  - show_toast:lib/toast_queue.dart\n'
          '---\n\n# Feedback implementation\n',
    );

    expect(recordEntriesOf(doc, _recordType), const [
      RecordEntry(
        item: 'show_toast',
        codePaths: [
          'lib/toast.dart:showToast',
          'lib/toast_host.dart',
          'lib/toast_queue.dart',
        ],
      ),
    ]);
  });

  test('a tests line gives its item the path part alone, the name aside', () {
    final doc = _record(
      'specs/jaspr/f02_feedback/IMPLEMENTATION.md',
      '---\n'
          'statuses:\n'
          '  - show_toast:implemented\n'
          'implements:\n'
          '  - show_toast:lib/toast.dart:showToast\n'
          'tests:\n'
          '  - show_toast:test/toast_test.dart\n'
          '  - "show_toast:test/toast_host_test.dart:queue: a group #1"\n'
          '  - show_toast/queue_toasts:test/queue_test.dart:drops the oldest\n'
          '---\n\n# Feedback implementation\n',
    );

    expect(recordEntriesOf(doc, _recordType), const [
      RecordEntry(
        item: 'show_toast',
        status: RecordStatus.implemented,
        codePaths: ['lib/toast.dart:showToast'],
        testPaths: ['test/toast_test.dart', 'test/toast_host_test.dart'],
      ),
      RecordEntry(
        item: 'show_toast/queue_toasts',
        testPaths: ['test/queue_test.dart'],
      ),
    ]);
  });

  test('a tests line with no item or no colon names no entry', () {
    final doc = _record(
      'specs/jaspr/f02_feedback/IMPLEMENTATION.md',
      '---\n'
          'tests:\n'
          '  - test/lonely_test.dart\n'
          '  - ":test/featureless_test.dart"\n'
          '---\n\n# Feedback implementation\n',
    );

    expect(recordEntriesOf(doc, _recordType), isEmpty);
  });

  group('ImplementsEntry.testName', () {
    test('a name keeps its colons and spaces whole, the path stops at the '
        'first colon', () {
      const entry = ImplementsEntry(
        'test/auth_test.dart:rejects: a wrong password #2',
      );

      expect(entry.path, 'test/auth_test.dart');
      expect(entry.testName, 'rejects: a wrong password #2');
    });

    test('a line with no name has none, and an empty name stays empty', () {
      expect(const ImplementsEntry('test/auth_test.dart').testName, isNull);
      expect(const ImplementsEntry('test/auth_test.dart:').testName, '');
    });
  });

  test('a record with no fields written holds no entries', () {
    final doc = _record(
      'specs/jaspr/f02_feedback/IMPLEMENTATION.md',
      '# Feedback implementation\n',
    );

    expect(recordEntriesOf(doc, _recordType), isEmpty);
  });

  group('matrix rows', () {
    // The record text puts its first matrix line on file line 10.
    const firstRowLine = 10;

    List<MatrixLine> linesOf(List<String> rows) =>
        matrixLinesIn(_matrixRecord(rows), _matrixRecordType);

    test('a test row reads its item, edge case, literal, and fingerprint', () {
      final lines = linesOf([
        '- show_toast/queue_toasts E01: `queues a second toast` 3f9a1c0b7e2d',
        '- show_toast/queue_toasts E02: `drops a toast past the limit`',
      ]);

      expect(lines, const [
        TestRow(
          item: 'show_toast/queue_toasts',
          edgeCase: 'E01',
          literal: 'queues a second toast',
          fingerprint: '3f9a1c0b7e2d',
          line: firstRowLine,
        ),
        TestRow(
          item: 'show_toast/queue_toasts',
          edgeCase: 'E02',
          literal: 'drops a toast past the limit',
          line: firstRowLine + 1,
        ),
      ]);
      expect((lines.first as MatrixRow).label, 'show_toast/queue_toasts#E01');
    });

    test('an uppercase hex tail makes a test row malformed', () {
      const row = '- show_toast E01: `queues a toast` 3F9A1C0B7E2D';

      expect(linesOf([row]), const [
        MalformedRow(line: firstRowLine, text: row),
      ]);
    });

    test('a skip row takes its last token as a fingerprint only when it is '
        '12 lowercase hex', () {
      final lines = linesOf([
        '- show_toast E04 skipped: needs root on CI 9a1c03be55d2',
        '- show_toast E05 skipped: needs root on CI',
      ]);

      expect(lines, const [
        SkipRow(
          item: 'show_toast',
          edgeCase: 'E04',
          reason: 'needs root on CI',
          fingerprint: '9a1c03be55d2',
          line: firstRowLine,
        ),
        SkipRow(
          item: 'show_toast',
          edgeCase: 'E05',
          reason: 'needs root on CI',
          line: firstRowLine + 1,
        ),
      ]);
    });

    test('a skip row left with no reason after its fingerprint is '
        'malformed', () {
      const row = '- show_toast E04 skipped: 9a1c03be55d2';

      expect(linesOf([row]), const [
        MalformedRow(line: firstRowLine, text: row),
      ]);
    });

    test('a skip row keeps no space after its reason', () {
      expect(
        linesOf([
          '- show_toast E04 skipped: needs root on CI  9a1c03be55d2',
          '- show_toast E05 skipped: needs root on CI ',
        ]),
        const [
          SkipRow(
            item: 'show_toast',
            edgeCase: 'E04',
            reason: 'needs root on CI',
            fingerprint: '9a1c03be55d2',
            line: firstRowLine,
          ),
          SkipRow(
            item: 'show_toast',
            edgeCase: 'E05',
            reason: 'needs root on CI',
            line: firstRowLine + 1,
          ),
        ],
      );
    });

    for (final tail in const ['9a1c03be55d', '9a1c03be55d29']) {
      test('a ${tail.length}-hex tail is no fingerprint', () {
        const head = '- show_toast E01';
        final testRow = '$head: `queues a toast` $tail';

        expect(linesOf([testRow, '$head skipped: needs root $tail']), [
          MalformedRow(line: firstRowLine, text: testRow),
          SkipRow(
            item: 'show_toast',
            edgeCase: 'E01',
            reason: 'needs root $tail',
            line: firstRowLine + 1,
          ),
        ]);
      });
    }

    test('the section is found by the key of the record type, whatever its '
        'header or output_ref flag', () {
      const row = '- show_toast E01: `queues a toast`';
      const expected = [
        TestRow(
          item: 'show_toast',
          edgeCase: 'E01',
          literal: 'queues a toast',
          line: firstRowLine,
        ),
      ];
      MergedDocType typeWith(MergedSection section) =>
          _recordType.copyWith(sections: [section]);

      expect(
        matrixLinesIn(
          _matrixRecord([row], header: 'Test evidence'),
          typeWith(
            const MergedSection(
              id: verificationMatrixKey,
              header: 'Test evidence',
              isOutputRef: true,
            ),
          ),
        ),
        expected,
      );
      expect(
        matrixLinesIn(
          _matrixRecord([row]),
          typeWith(
            const MergedSection(
              id: verificationMatrixKey,
              header: 'Verification matrix',
            ),
          ),
        ),
        expected,
      );
      expect(
        matrixLinesIn(
          _matrixRecord([row]),
          typeWith(
            const MergedSection(
              id: 'other_section',
              header: 'Verification matrix',
              isOutputRef: true,
            ),
          ),
        ),
        isEmpty,
      );
    });

    for (final (written, literal) in const [
      (r'`` a`b$c\d ``', r'a`b$c\d'),
      ('``a`b``', 'a`b'),
      ('`` `edge ``', '`edge'),
      (r'`ends in \`', r'ends in \'),
    ]) {
      test('a literal read from $written is $literal', () {
        final lines = linesOf(['- show_toast E01: $written 3f9a1c0b7e2d']);

        expect(lines, [
          TestRow(
            item: 'show_toast',
            edgeCase: 'E01',
            literal: literal,
            fingerprint: '3f9a1c0b7e2d',
            line: firstRowLine,
          ),
        ]);
      });
    }

    for (final row in const [
      'A paragraph about the toast.',
      '- show_toast E01 queues a toast',
      '- show_toast E01: `queues a toast` (flaky)',
      '- show_toast E01: `queues a toast` `a second span`',
      '- show_toast E01: no span here',
      '- show_toast E01 skipped:',
      '- show_toast E1x: `queues a toast`',
    ]) {
      test('the line "$row" is a malformed line', () {
        expect(linesOf([row]), [MalformedRow(line: firstRowLine, text: row)]);
      });
    }

    test('blank lines give no line, and a later section stays out', () {
      final lines = matrixLinesIn(
        '${_matrixRecord(['- show_toast E01: `queues a toast`', '', 'stray'])}'
        '\n## Other\n\nnot a row\n',
        _matrixRecordType,
      );

      expect(lines, const [
        TestRow(
          item: 'show_toast',
          edgeCase: 'E01',
          literal: 'queues a toast',
          line: firstRowLine,
        ),
        MalformedRow(line: firstRowLine + 2, text: 'stray'),
      ]);
    });

    test('a record without the section has no rows', () {
      const text =
          '---\nstatuses:\n  - show_toast:planned\n---\n\n# Feedback\n';

      expect(matrixLinesIn(text, _matrixRecordType), isEmpty);
      expect(matrixLinesIn(text, _recordType), isEmpty);
    });

    test('an empty section has no rows', () {
      expect(linesOf(const []), isEmpty);
      expect(linesOf(const ['']), isEmpty);
    });

    test('a record type without the section reads no rows', () {
      expect(
        matrixLinesIn(
          _matrixRecord(['- show_toast E01: `queues a toast`']),
          _recordType,
        ),
        isEmpty,
      );
    });

    test('rows read the same from a CRLF record', () {
      final rows = [
        '- show_toast E01: `queues a toast` 3f9a1c0b7e2d',
        '- show_toast E02 skipped: no clock on CI',
        'stray',
      ];
      final crlf = _matrixRecord(rows).replaceAll('\n', '\r\n');

      expect(matrixLinesIn(toLf(crlf), _matrixRecordType), linesOf(rows));
    });

    test('recordEntriesOf hangs each row on its item', () {
      final text = _matrixRecord([
        '- show_toast/queue_toasts E01: `queues a toast` 3f9a1c0b7e2d',
        '- show_toast/queue_toasts E02 skipped: no clock on CI',
        'stray',
        '- show_toast/queue_toasts E03: `drops a toast`',
      ]);
      final doc = _record(_matrixPath, text, type: _matrixRecordType);

      expect(recordEntriesOf(doc, _matrixRecordType), const [
        RecordEntry(
          item: 'show_toast/queue_toasts',
          status: RecordStatus.implemented,
          matrixRows: [
            TestRow(
              item: 'show_toast/queue_toasts',
              edgeCase: 'E01',
              literal: 'queues a toast',
              fingerprint: '3f9a1c0b7e2d',
              line: firstRowLine,
            ),
            SkipRow(
              item: 'show_toast/queue_toasts',
              edgeCase: 'E02',
              reason: 'no clock on CI',
              line: firstRowLine + 1,
            ),
            TestRow(
              item: 'show_toast/queue_toasts',
              edgeCase: 'E03',
              literal: 'drops a toast',
              line: firstRowLine + 3,
            ),
          ],
        ),
      ]);
    });

    test('an item that only rows name gets an entry', () {
      final text = _matrixRecord(['- show_toast/pin_toast E01: `pins`']);
      final doc = _record(_matrixPath, text, type: _matrixRecordType);

      expect(recordEntriesOf(doc, _matrixRecordType), const [
        RecordEntry(
          item: 'show_toast/queue_toasts',
          status: RecordStatus.implemented,
        ),
        RecordEntry(
          item: 'show_toast/pin_toast',
          matrixRows: [
            TestRow(
              item: 'show_toast/pin_toast',
              edgeCase: 'E01',
              literal: 'pins',
              line: firstRowLine,
            ),
          ],
        ),
      ]);
    });

    test('a record of a type without the section holds no matrix lines', () {
      final doc = _record(
        _matrixPath,
        _matrixRecord(['- show_toast/queue_toasts E01: `queues`']),
      );

      expect(doc.matrixLines, isEmpty);
      expect(recordEntriesOf(doc, _recordType), const [
        RecordEntry(
          item: 'show_toast/queue_toasts',
          status: RecordStatus.implemented,
        ),
      ]);
    });

    test('an indexed CRLF record holds the lines of its LF twin, malformed '
        'lines included', () {
      final rows = ['- show_toast E01: `queues a toast` 3f9a1c0b7e2d', 'stray'];
      final crlf = _matrixRecord(rows).replaceAll('\n', '\r\n');

      expect(
        _record(_matrixPath, crlf, type: _matrixRecordType).matrixLines,
        linesOf(rows),
      );
    });

    test('entries with rows that differ in any field are not equal', () {
      RecordEntry entryOf(MatrixRow row) =>
          RecordEntry(item: 'show_toast', matrixRows: [row]);
      const base = TestRow(
        item: 'show_toast',
        edgeCase: 'E01',
        literal: 'queues',
        line: 11,
      );

      expect(entryOf(base), entryOf(base));
      expect(entryOf(base).hashCode, entryOf(base).hashCode);
      for (final other in const [
        TestRow(
          item: 'show_toast',
          edgeCase: 'E01',
          literal: 'drops',
          line: 11,
        ),
        TestRow(
          item: 'show_toast',
          edgeCase: 'E01',
          literal: 'queues',
          fingerprint: '3f9a1c0b7e2d',
          line: 11,
        ),
        TestRow(
          item: 'show_toast',
          edgeCase: 'E01',
          literal: 'queues',
          line: 12,
        ),
        SkipRow(
          item: 'show_toast',
          edgeCase: 'E01',
          reason: 'queues',
          line: 11,
        ),
      ]) {
        expect(entryOf(other), isNot(entryOf(base)));
      }
    });
  });

  group('rewriteRecordItems', () {
    const record =
        '---\n'
        'statuses:\n'
        '  - show_toast:implemented\n'
        '  - show_toast/queue_toasts:planned\n'
        "  - ':skipped:no web view on the web'\n"
        'implements:\n'
        '  - show_toast:lib/toast.dart:showToast\n'
        '  - show_toast/queue_toasts:lib/queue.dart\n'
        'vision: PV-01\n'
        '---\n\n# Feedback implementation\n';

    test(
      'a dropped item leaves both fields, and no other line or key moves',
      () {
        final text = rewriteRecordItems(
          record,
          _recordType,
          (item) => item == 'show_toast/queue_toasts' ? null : item,
        );

        expect(
          text,
          '---\n'
          'statuses:\n'
          '  - show_toast:implemented\n'
          "  - ':skipped:no web view on the web'\n"
          'implements:\n'
          '  - show_toast:lib/toast.dart:showToast\n'
          'vision: PV-01\n'
          '---\n\n# Feedback implementation\n',
        );
      },
    );

    test('a renamed item keeps its status, reason, and code path', () {
      final text = rewriteRecordItems(
        record,
        _recordType,
        (item) =>
            item.startsWith('show_toast') ? 'toast${item.substring(10)}' : item,
      );

      expect(text, contains("  - 'toast/queue_toasts:planned'\n"));
      expect(text, contains('  - toast:lib/toast.dart:showToast\n'));
      expect(text, contains("  - ':skipped:no web view on the web'\n"));
    });

    test('a renamed or dropped item takes its tests lines with it', () {
      const withTests =
          '---\n'
          'tests:\n'
          '  - show_toast:test/toast_test.dart:shows a toast\n'
          '  - show_toast/queue_toasts:test/queue_test.dart\n'
          '  - lib_only\n'
          '---\n\n# R\n';

      final renamed = rewriteRecordItems(
        withTests,
        _recordType,
        (item) => item == 'show_toast' ? 'toast' : item,
      );
      final dropped = rewriteRecordItems(
        withTests,
        _recordType,
        (item) => item == 'show_toast/queue_toasts' ? null : item,
      );

      expect(
        renamed,
        '---\n'
        'tests:\n'
        '  - toast:test/toast_test.dart:shows a toast\n'
        '  - show_toast/queue_toasts:test/queue_test.dart\n'
        '  - lib_only\n'
        '---\n\n# R\n',
      );
      expect(
        dropped,
        '---\n'
        'tests:\n'
        '  - show_toast:test/toast_test.dart:shows a toast\n'
        '  - lib_only\n'
        '---\n\n# R\n',
      );
    });

    test('the empty item of a feature skip reaches the callback', () {
      final seen = <String>[];
      rewriteRecordItems(record, _recordType, (item) {
        seen.add(item);
        return item;
      });

      expect(seen, contains(''));
    });

    test('nothing to change returns null', () {
      expect(rewriteRecordItems(record, _recordType, (item) => item), isNull);
      expect(
        rewriteRecordItems(
          '# Feedback implementation\n',
          _recordType,
          (item) => null,
        ),
        isNull,
      );
    });

    test('a field with no line left is dropped, and a field that does not '
        'change stays as written', () {
      final text = rewriteRecordItems(
        '---\nstatuses:\n  - a:planned\nimplements:\n  - b:lib/b.dart\n---\n\n# R\n',
        _recordType,
        (item) => item == 'a' ? null : item,
      );

      expect(text, '---\nimplements:\n  - b:lib/b.dart\n---\n\n# R\n');
    });

    test(
      'a line that names no item and a non-scalar line stay as they are',
      () {
        final text = rewriteRecordItems(
          '---\nimplements:\n'
          '  - lib/toast.dart: {item: show_toast}\n'
          '  - no_colon_here\n'
          '  - a:lib/a.dart\n'
          '---\n\n# R\n',
          _recordType,
          (item) => item == 'a' ? null : item,
        );

        expect(
          text,
          '---\nimplements:\n'
          '  - lib/toast.dart: {item: show_toast}\n'
          '  - no_colon_here\n'
          '---\n\n# R\n',
        );
      },
    );

    test('a quote inside a changed reason is doubled in single quotes', () {
      final text = rewriteRecordItems(
        "---\nstatuses:\n  - 'a:skipped:it''s out'\n  - b:planned\n"
        '---\n\n# R\n',
        _recordType,
        (item) => switch (item) {
          'a' => 'c',
          'b' => null,
          _ => item,
        },
      );

      expect(text, "---\nstatuses:\n  - 'c:skipped:it''s out'\n---\n\n# R\n");
    });

    test('a kept line keeps the quotes it was written in', () {
      final text = rewriteRecordItems(
        '---\nstatuses:\n  - "a:skipped:it\'s out"\n  - b:planned\n'
        '---\n\n# R\n',
        _recordType,
        (item) => item == 'b' ? null : item,
      );

      expect(text, '---\nstatuses:\n  - "a:skipped:it\'s out"\n---\n\n# R\n');
    });

    test('an implements line with an empty item stays, as the parser skips '
        'it', () {
      final seen = <String>[];
      final text = rewriteRecordItems(
        '---\nimplements:\n  - ":lib/a.dart"\n  - b:lib/b.dart\n'
        '---\n\n# R\n',
        _recordType,
        (item) {
          seen.add(item);
          return null;
        },
      );

      expect(seen, ['b']);
      expect(text, '---\nimplements:\n  - ":lib/a.dart"\n---\n\n# R\n');
    });

    group('matrix rows', () {
      const header = '## Verification matrix\n\n';

      String? Function(String) rename(String from, String to) =>
          (item) => item == from ? to : item;

      String sectionOf(String? text) => text!.substring(text.indexOf(header));

      test('a renamed item sets each row of it and keeps the rest of the row, '
          'the literal, the edge case, the fingerprint, and every other '
          'line', () {
        final text = rewriteRecordItems(
          _matrixRecord([
            '- show_toast/queue_toasts E01: `queues a second toast` 3f9a1c0b7e2d',
            '- show_toast/queue_toasts E02 skipped: needs root on CI  9a1c03be55d2 ',
            '- show_toast E03: `shows a toast`',
            'A paragraph that names show_toast/queue_toasts E01.',
          ]),
          _matrixRecordType,
          rename('show_toast/queue_toasts', 'toast/queue'),
        );

        expect(
          sectionOf(text),
          '$header'
          '- toast/queue E01: `queues a second toast` 3f9a1c0b7e2d\n'
          '- toast/queue E02 skipped: needs root on CI  9a1c03be55d2 \n'
          '- show_toast E03: `shows a toast`\n'
          'A paragraph that names show_toast/queue_toasts E01.\n',
        );
      });

      test('a row whose item the rewrite drops leaves the section', () {
        final text = rewriteRecordItems(
          _matrixRecord([
            '- show_toast/queue_toasts E01: `queues a second toast`',
            '- show_toast E03: `shows a toast`',
            '- show_toast/queue_toasts E02 skipped: needs root on CI',
          ]),
          _matrixRecordType,
          (item) => item == 'show_toast/queue_toasts' ? null : item,
        );

        expect(sectionOf(text), '$header- show_toast E03: `shows a toast`\n');
      });

      test('a malformed line is left unchanged', () {
        const malformed = '- show_toast/queue_toasts E01 `no colon`';
        final text = rewriteRecordItems(
          _matrixRecord([malformed, '- show_toast/queue_toasts E02: `ok`']),
          _matrixRecordType,
          rename('show_toast/queue_toasts', 'toast/queue'),
        );

        expect(sectionOf(text), '$header$malformed\n- toast/queue E02: `ok`\n');
      });

      test('a literal holding a backtick, a colon, a dollar sign, and a '
          'backslash keeps its span exactly', () {
        const literal = r'a `b`: $c \d';
        const tail = 'E01: ``$literal`` 3f9a1c0b7e2d';
        final text = rewriteRecordItems(
          _matrixRecord(['- show_toast/queue_toasts $tail']),
          _matrixRecordType,
          rename('show_toast/queue_toasts', 'toast/queue'),
        );

        expect(sectionOf(text), '$header- toast/queue $tail\n');
      });

      test('a record without rows is untouched by the row rewrite', () {
        expect(
          rewriteRecordItems(
            _matrixRecord(const []),
            _matrixRecordType,
            rename('show_toast', 'toast'),
          ),
          isNull,
        );
        expect(
          rewriteRecordItems(
            _matrixRecord(['- show_toast E01: `shows a toast`']),
            _matrixRecordType,
            (item) => item,
          ),
          isNull,
        );
        expect(
          rewriteRecordItems(
            _matrixRecord(['- show_toast E01: `shows a toast`']),
            _recordType,
            rename('show_toast', 'toast'),
          ),
          isNull,
        );
      });
    });
  });
  group('recordLinesCarried and addRecordLines', () {
    const record =
        '---\nstatuses:\n'
        '  - a:implemented\n'
        '  - a/x:planned\n'
        "  - ':skipped:no tablet'\n"
        '  - b:skipped:out of scope\n'
        'implements:\n'
        '  - a:lib/a.dart:A\n'
        '  - b:lib/b.dart\n'
        '---\n\n# R\n';

    String? carry(String item) => switch (item) {
      'a' => 'k/a',
      'a/x' => 'k/a/x',
      _ => null,
    };

    test('E19: the lines of the carried items come back with the new item and '
        'the rest of the line as written', () {
      final lines = recordLinesCarried(record, _recordType, carry);

      expect(lines.statuses, ['k/a:implemented', 'k/a/x:planned']);
      expect(lines.code, ['k/a:lib/a.dart:A']);
    });

    test('E21: the own line of the feature is left out when carry gives its '
        'empty item no name', () {
      final lines = recordLinesCarried(
        record,
        _recordType,
        (item) => item.isEmpty ? null : 'k/$item',
      );

      expect(lines.statuses, isNot(contains(contains('skipped:no tablet'))));
      expect(lines.statuses, hasLength(3));
    });

    test('E19: a skip reason keeps its text', () {
      final lines = recordLinesCarried(
        record,
        _recordType,
        (item) => item == 'b' ? 'k/b' : null,
      );

      expect(lines.statuses, ['k/b:skipped:out of scope']);
    });

    test('E19: added lines follow the held ones, each field written as a block '
        'list over the lines held', () {
      final text = addRecordLines(
        '---\nstatuses:\n  - c:planned\n---\n\n# R\n',
        _recordType,
        const RecordLines(
          statuses: ['k/a:implemented'],
          code: ['k/a:lib/a.dart:A'],
          tests: ['k/a:test/a_test.dart:holds'],
        ),
      );

      expect(
        text,
        '---\nstatuses:\n  - c:planned\n  - k/a:implemented\n'
        'implements:\n  - k/a:lib/a.dart:A\n'
        'tests:\n  - k/a:test/a_test.dart:holds\n---\n\n# R\n',
      );
    });

    test('E20: a skeleton key with no value takes the lines', () {
      final text = addRecordLines(
        '---\ndraft: true\nstatuses:\n---\n\n# R\n',
        _recordType,
        const RecordLines(statuses: ['k/a:implemented']),
      );

      expect(
        text,
        '---\ndraft: true\nstatuses:\n  - k/a:implemented\n---\n\n# R\n',
      );
    });

    test('E20: no line to add leaves the text and returns null', () {
      expect(addRecordLines(record, _recordType, const RecordLines()), isNull);
    });

    group('matrix rows', () {
      const quoted = '- a/x E01: `shows a toast` 5d1e0c4b7a92';
      const skipped = '- a/x E02 skipped: needs a device 9a1c03be55d2';

      test('the rows of the carried items come back with the new item and '
          'the rest of the row as written', () {
        final lines = recordLinesCarried(
          _matrixRecord([quoted, skipped, '- b E01: `stays`']),
          _matrixRecordType,
          (item) => item == 'a/x' ? 'k/a/x' : null,
        );

        expect(lines.rows, [
          '- k/a/x E01: `shows a toast` 5d1e0c4b7a92',
          '- k/a/x E02 skipped: needs a device 9a1c03be55d2',
        ]);
      });

      test('a malformed line and a record without the section carry no '
          'row', () {
        final malformed = _matrixRecord(['- a/x', 'stray']);
        expect(
          recordLinesCarried(malformed, _matrixRecordType, (_) => 'k').rows,
          isEmpty,
        );
        expect(
          recordLinesCarried(
            _matrixRecord([quoted]),
            _recordType,
            (_) => 'k',
          ).rows,
          isEmpty,
        );
      });

      test('added rows follow the rows the section holds', () {
        final text = addRecordLines(
          _matrixRecord(['- k/b E01: `holds`']),
          _matrixRecordType,
          const RecordLines(rows: ['- k/a/x E01: `shows a toast`']),
        );

        expect(
          text,
          _matrixRecord(['- k/b E01: `holds`', '- k/a/x E01: `shows a toast`']),
        );
      });

      test('added rows keep the blank line before the next section', () {
        const held = '- k/b E01: `holds`';
        const added = '- k/a/x E01: `shows a toast`';
        const notes = '\n## Notes\n\nSee rows.\n';
        final text = addRecordLines(
          '${_matrixRecord([held])}$notes',
          _matrixRecordType,
          const RecordLines(rows: [added]),
        );

        expect(text, '${_matrixRecord([held, added])}$notes');
      });

      test('a record with no section gains it at the end, holding the '
          'rows', () {
        final text = addRecordLines(
          '---\ndraft: true\n---\n\n# R\n',
          _matrixRecordType,
          const RecordLines(rows: ['- k/a/x E01: `shows a toast`']),
        );

        expect(
          text,
          '---\ndraft: true\n---\n\n# R\n\n'
          '## Verification matrix\n\n- k/a/x E01: `shows a toast`\n',
        );
      });

      test('a record with no section gains it before a later section it '
          'holds', () {
        final type = _recordType.copyWith(
          sections: const [
            matrixSection,
            MergedSection(id: 'notes', header: 'Notes'),
          ],
        );
        final text = addRecordLines(
          '---\ndraft: true\n---\n\n# R\n\n## Notes\n\nSee rows.\n',
          type,
          const RecordLines(rows: ['- k/a/x E01: `shows a toast`']),
        );

        expect(
          text,
          '---\ndraft: true\n---\n\n# R\n\n'
          '## Verification matrix\n\n- k/a/x E01: `shows a toast`\n\n'
          '## Notes\n\nSee rows.\n',
        );
      });

      test('rows with no matrix section on the doc type add nothing', () {
        expect(
          addRecordLines(
            _matrixRecord(const []),
            _recordType,
            const RecordLines(rows: ['- k/a/x E01: `shows a toast`']),
          ),
          isNull,
        );
      });
    });
  });

  group('a record field block that is not valid YAML', () {
    const broken =
        '---\nstatuses:\n  - c:planned\n'
        "implements:\n  - 'c:lib/c.dart\n  - c:lib/form.dart\n"
        '---\n\n# R\n';
    final unreadable = throwsA(
      isA<RecordFieldUnreadable>().having(
        (e) => e.field,
        'field',
        'implements',
      ),
    );

    test(
      'E19: addRecordLines refuses rather than drop the lines held there',
      () {
        expect(
          () => addRecordLines(
            broken,
            _recordType,
            const RecordLines(code: ['k/a:lib/a.dart']),
          ),
          unreadable,
        );
      },
    );

    test('E19: addRecordLines adds to a readable field beside it', () {
      expect(
        addRecordLines(
          broken,
          _recordType,
          const RecordLines(statuses: ['k/a:planned']),
        ),
        contains('  - k/a:planned\n'),
      );
    });

    test('E19: rewriteRecordItems refuses, as the block may hold a line it '
        'must change', () {
      expect(
        () => rewriteRecordItems(broken, _recordType, (_) => null),
        unreadable,
      );
    });

    test('E19: recordLinesCarried refuses, as the block may hold a line it '
        'must carry', () {
      expect(
        () => recordLinesCarried(broken, _recordType, (_) => 'k'),
        unreadable,
      );
    });
  });
}
