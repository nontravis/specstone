import 'dart:convert';

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

  test('a record with no fields written holds no entries', () {
    final doc = _record(
      'specs/jaspr/f02_feedback/IMPLEMENTATION.md',
      '# Feedback implementation\n',
    );

    expect(recordEntriesOf(doc, _recordType), isEmpty);
  });
}
