import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:test/test.dart';

void main() {
  test('s05: the eleven F-01 codes in catalog order, with their exits', () {
    expect(
      [for (final c in IndexFaultCode.values) (c.wire, c.exitStatus)],
      [
        ('argument_missing', 64),
        ('argument_conflict', 64),
        ('argument_invalid', 64),
        ('doc_not_found', 64),
        ('section_not_found', 64),
        ('untyped_target', 64),
        ('code_path_not_found', 64),
        ('code_path_outside_project', 64),
        ('query_too_short', 64),
        ('index_not_writable', 73),
        ('index_busy', 75),
      ],
    );
  });

  test('s05: an F-01 fault carries code and message only', () {
    final fault = IndexFault(
      IndexFaultCode.docNotFound,
      'no doc carries the name logn',
    );
    expect(fault.toJson(), {
      'error': {
        'code': 'doc_not_found',
        'message': 'no doc carries the name logn',
      },
    });
    expect(fault.toText(), 'no doc carries the name logn');
  });

  group('E17: IndexFaults', () {
    final faults = IndexFaults([
      IndexFault(IndexFaultCode.docNotFound, 'no doc carries the name logn'),
      IndexFault(
        IndexFaultCode.sectionNotFound,
        'no doc named login holds a section with the key acceptance',
      ),
    ]);

    test('prints one line per fault, in order', () {
      expect(
        faults.toText(),
        'no doc carries the name logn\n'
        'no doc named login holds a section with the key acceptance',
      );
    });

    test("the envelope and the exit status are the first fault's", () {
      expect(faults.toJson(), {
        'error': {
          'code': 'doc_not_found',
          'message': 'no doc carries the name logn',
        },
      });
      expect(faults.exitStatus, 64);
      expect(
        IndexFaults([
          IndexFault(IndexFaultCode.indexBusy, 'busy'),
          IndexFault(IndexFaultCode.docNotFound, 'x'),
        ]).exitStatus,
        75,
      );
    });
  });
}
