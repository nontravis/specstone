// Test names carry the long FR/INV tags the plan gives them.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:test/test.dart';

import '../../helpers/write_fixture.dart';

void main() {
  test('dw-s05: base_mismatch carries file, key, and current; the text form names file and key', () {
    final fault = WriteFault(
      WriteFaultCode.baseMismatch,
      'the section changed since base 3f9a1c0b7e21',
      file: story1,
      key: 'acceptance_criteria',
      current: const CurrentTarget(
        heading: '==> x <==',
        text: '## Acceptance Criteria\n',
        base: 'a07c55e19d42',
      ),
    );
    expect(fault.exitStatus, 75);
    expect(fault.toJson(), {
      'error': {
        'code': 'base_mismatch',
        'message': 'the section changed since base 3f9a1c0b7e21',
        'file': story1,
        'key': 'acceptance_criteria',
        'current': {'text': '## Acceptance Criteria\n', 'base': 'a07c55e19d42'},
      },
    });
    expect(
      fault.toText(),
      '$story1: acceptance_criteria: the section changed since base 3f9a1c0b7e21',
    );
  });

  test('dw-s05: doc_referenced lists relatedFiles after "; also"; owner_terminal_required exits 77 with no file', () {
    final fault = WriteFault(
      WriteFaultCode.docReferenced,
      'docs outside user_story:login/reset_password link into it',
      file: story3,
      relatedFiles: [fr12],
    );
    expect(
      fault.toText(),
      '$story3: docs outside user_story:login/reset_password link into it; also $fr12',
    );
    expect(fault.toJson(), {
      'error': {
        'code': 'doc_referenced',
        'message': 'docs outside user_story:login/reset_password link into it',
        'file': story3,
        'relatedFiles': [fr12],
      },
    });
    final owner = WriteFault(WriteFaultCode.ownerTerminalRequired, 'm');
    expect(owner.exitStatus, 77);
    expect(owner.toJson(), {
      'error': {'code': 'owner_terminal_required', 'message': 'm'},
    });
    expect(owner.toText(), 'm');
  });

  test(
    'dw-s05: the codes keep the catalog order, wire names, and exit statuses',
    () {
      expect(
        [
          for (final code in WriteFaultCode.values)
            (code.wire, code.exitStatus),
        ],
        [
          ('base_mismatch', 75),
          ('field_unknown', 64),
          ('field_value_invalid', 64),
          ('field_not_writable', 64),
          ('required_target', 64),
          ('doc_exists', 64),
          ('doc_referenced', 64),
          ('position_out_of_range', 64),
          ('doc_type_not_movable', 64),
          ('owner_terminal_required', 77),
          ('migrate_pending', 75),
        ],
      );
    },
  );

  test('f06/us01/fr07/e06: migrate_pending exits 75', () {
    expect(WriteFaultCode.migratePending.wire, 'migrate_pending');
    expect(WriteFaultCode.migratePending.exitStatus, 75);
  });

  test(
    'dw-s05: a text form with several relatedFiles joins them with commas',
    () {
      final fault = WriteFault(
        WriteFaultCode.docReferenced,
        'linked',
        file: story3,
        relatedFiles: [fr12, fr32],
      );
      expect(fault.toText(), '$story3: linked; also $fr12, $fr32');
    },
  );
}
