import 'package:specstone_core/src/consistency_check/implements_entry.dart';
import 'package:specstone_core/src/index_query/record_entries.dart';
import 'package:specstone_core/src/path_tail.dart';
import 'package:test/test.dart';

void main() {
  test('a tail keeps its colons and spaces whole', () {
    final split = splitPathTail('test/a_test.dart:rejects: a wrong #2');

    expect(split.path, 'test/a_test.dart');
    expect(split.tail, 'rejects: a wrong #2');
  });

  test('a text with no colon has no tail, and an empty tail stays empty', () {
    expect(splitPathTail('test/a_test.dart'), (
      path: 'test/a_test.dart',
      tail: null,
    ));
    expect(splitPathTail('test/a_test.dart:').tail, '');
  });

  test('the index and the entry read one line to the same path and name', () {
    const rest = 'test/a_test.dart:rejects: a wrong #2';

    expect(
      recordTestLineOf('show:$rest')?.path,
      const ImplementsEntry(rest).path,
    );
    expect(const ImplementsEntry(rest).testName, 'rejects: a wrong #2');
  });
}
