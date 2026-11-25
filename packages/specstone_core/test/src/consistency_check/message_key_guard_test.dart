import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/message_key_guard.dart';
import 'package:test/test.dart';

void main() {
  test(
    'a finding whose message names a path no key holds fails its assert',
    () {
      Finding build(Map<String, Object> keys) => Finding(
        kind: FindingKind.linkUnresolved,
        path: 'prds/A.md',
        line: 1,
        message: 'names prds/B.md',
        keys: keys,
      );

      expect(() => build({'value': 'x'}), throwsA(isA<AssertionError>()));
      expect(() => build({'targetPath': 'docs/prds/B.md'}), returnsNormally);
    },
  );

  group('unheldMessageValues', () {
    const linkMessage =
        'link target x names anchor a, which prds/A.md does not hold';

    test('a path the message names and no key holds is unheld', () {
      expect(
        unheldMessageValues(
          message: linkMessage,
          path: 'prds/B.md',
          keys: {'value': 'x'},
        ),
        ['prds/A.md'],
      );
    });

    test('a path a key holds is held', () {
      expect(
        unheldMessageValues(
          message: linkMessage,
          path: 'prds/B.md',
          keys: {'value': 'x', 'targetPath': 'docs/prds/A.md'},
        ),
        isEmpty,
      );
    });

    test('a joined item and edge case is held part by part', () {
      expect(
        unheldMessageValues(
          message: 'login/check#E01 is implemented and no matrix row names it',
          path: 'specs/S.md',
          keys: {'item': 'login/check', 'edgeCase': 'E01'},
        ),
        isEmpty,
      );
    });

    test('a joined item and edge case with one part unheld is returned', () {
      expect(
        unheldMessageValues(
          message: 'login/check#E01 is implemented and no matrix row names it',
          path: 'specs/S.md',
          keys: {'item': 'login/check'},
        ),
        isNotEmpty,
      );
    });

    test('text inside double quotes is no value', () {
      expect(
        unheldMessageValues(
          message: 'no [error] scenario and no "Error cases: N/A" line',
          path: 'specs/S.md',
          keys: {},
        ),
        isEmpty,
      );
      expect(
        unheldMessageValues(
          message: '"a/b.md" is quoted',
          path: 'specs/S.md',
          keys: {},
        ),
        isEmpty,
      );
    });

    test('a markdown link is one value held by fix', () {
      const message =
          'cite x is no link; write it as [INV-6](../s/D.md#invariants)';
      expect(
        unheldMessageValues(
          message: message,
          path: 'prds/B.md',
          keys: {'value': 'x', 'fix': '[INV-6](../s/D.md#invariants)'},
        ),
        isEmpty,
      );
      expect(
        unheldMessageValues(
          message: message,
          path: 'prds/B.md',
          keys: {'value': 'x'},
        ),
        ['[INV-6](../s/D.md#invariants)'],
      );
    });

    test('a value cut short with an ellipsis is held by its full key', () {
      final cut = 'the value is still to be resolved: ${'a/' * 40}…';
      expect(
        unheldMessageValues(
          message: cut,
          path: 'specs/S.md',
          keys: {'value': 'a/' * 50},
        ),
        isEmpty,
      );
    });

    test('a placeholder form is no value', () {
      for (final message in [
        'write it as [text](<path>)',
        'write `<feature>/<story>`',
        'write [<ID>](<doc>#<section>) instead',
      ]) {
        expect(
          unheldMessageValues(message: message, path: 'specs/S.md', keys: {}),
          isEmpty,
          reason: message,
        );
      }
    });

    test('a list key holds each element', () {
      expect(
        unheldMessageValues(
          message: 'measurement m/b.md is stale',
          path: 'specs/S.md',
          keys: {
            'measurements': ['m/a.md', 'm/b.md'],
          },
        ),
        isEmpty,
      );
    });

    test('a word with no slash and no doc or code extension is no value', () {
      expect(
        unheldMessageValues(
          message: 'item has 2 lines; the limit is 1',
          path: 'specs/S.md',
          keys: {},
        ),
        isEmpty,
      );
    });
  });
}
