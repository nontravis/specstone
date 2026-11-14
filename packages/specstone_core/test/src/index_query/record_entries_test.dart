import 'dart:convert';

import 'package:specstone_core/src/consistency_check/implements_entry.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/record_entries.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:test/test.dart';

/// The record doc type `domain:template_packs` INV-31 gives: found by its
/// `record_status` field, per-target.
const _recordType = MergedDocType(
  id: 'implementation',
  path: 'specs/f{nn}_{slug}/IMPLEMENTATION.md',
  isPerTarget: true,
  fields: [
    MergedField(id: 'statuses', type: FieldType.recordStatus, list: true),
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
  sections: [],
  lint: MergedLint(),
  files: [],
);

/// Parses the record at [path] with [text] under a two-target project.
IndexedDoc _record(String path, String text) => parseIndexedDoc(
  docPath: path,
  bytes: utf8.encode(text),
  match: DocTypeMatcher(
    MergedSet(docTypes: [_recordType]),
    targetNames: const ['flutter', 'jaspr'],
  ).match(path),
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
          "  - 'show_toast:implemented'\n"
          "  - ':skipped:no web view on the web'\n"
          'implements:\n'
          "  - 'show_toast:lib/toast.dart:showToast'\n"
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
      expect(text, contains("  - 'toast:lib/toast.dart:showToast'\n"));
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
        "  - 'toast:test/toast_test.dart:shows a toast'\n"
        "  - 'show_toast/queue_toasts:test/queue_test.dart'\n"
        "  - 'lib_only'\n"
        '---\n\n# R\n',
      );
      expect(
        dropped,
        '---\n'
        'tests:\n'
        "  - 'show_toast:test/toast_test.dart:shows a toast'\n"
        "  - 'lib_only'\n"
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
          '  - {"lib/toast.dart":{"item":"show_toast"}}\n'
          "  - 'no_colon_here'\n"
          '---\n\n# R\n',
        );
      },
    );

    test('a quote inside a reason is doubled', () {
      final text = rewriteRecordItems(
        '---\nstatuses:\n  - "a:skipped:it\'s out"\n  - b:planned\n'
        '---\n\n# R\n',
        _recordType,
        (item) => item == 'b' ? null : item,
      );

      expect(text, "---\nstatuses:\n  - 'a:skipped:it''s out'\n---\n\n# R\n");
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
      expect(text, "---\nimplements:\n  - ':lib/a.dart'\n---\n\n# R\n");
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
        'list of quoted lines', () {
      final text = addRecordLines(
        '---\nstatuses:\n  - c:planned\n---\n\n# R\n',
        _recordType,
        (
          statuses: ['k/a:implemented'],
          code: ['k/a:lib/a.dart:A'],
          tests: ['k/a:test/a_test.dart:holds'],
        ),
      );

      expect(
        text,
        "---\nstatuses:\n  - 'c:planned'\n  - 'k/a:implemented'\n"
        "implements:\n  - 'k/a:lib/a.dart:A'\n"
        "tests:\n  - 'k/a:test/a_test.dart:holds'\n---\n\n# R\n",
      );
    });

    test('E20: a skeleton key with no value takes the lines', () {
      final text = addRecordLines(
        '---\ndraft: true\nstatuses:\n---\n\n# R\n',
        _recordType,
        (statuses: ['k/a:implemented'], code: const [], tests: const []),
      );

      expect(
        text,
        "---\ndraft: true\nstatuses:\n  - 'k/a:implemented'\n---\n\n# R\n",
      );
    });

    test('E20: no line to add leaves the text and returns null', () {
      expect(
        addRecordLines(record, _recordType, (
          statuses: const [],
          code: const [],
          tests: const [],
        )),
        isNull,
      );
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
          () => addRecordLines(broken, _recordType, (
            statuses: const [],
            code: const ['k/a:lib/a.dart'],
            tests: const [],
          )),
          unreadable,
        );
      },
    );

    test('E19: addRecordLines adds to a readable field beside it', () {
      expect(
        addRecordLines(broken, _recordType, (
          statuses: const ['k/a:planned'],
          code: const [],
          tests: const [],
        )),
        contains("  - 'k/a:planned'\n"),
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
