import 'package:specstone_core/src/fault.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:test/test.dart';

void main() {
  group('RenderFaultCode', () {
    test('codes and exit statuses follow the s05 catalog', () {
      expect(
        {for (final code in RenderFaultCode.values) code.wire: code.exitStatus},
        {
          'project_not_found': 78,
          'target_missing': 64,
          'target_not_found': 64,
          'target_outside_docs_root': 64,
          'browser_not_found': 69,
          'browser_print_failed': 70,
          'output_not_writable': 73,
        },
      );
    });

    test('values keep the s05 catalog order', () {
      expect(
        [for (final code in RenderFaultCode.values) code.wire],
        [
          'project_not_found',
          'target_missing',
          'target_not_found',
          'target_outside_docs_root',
          'browser_not_found',
          'browser_print_failed',
          'output_not_writable',
        ],
      );
    });
  });

  group('RenderFault', () {
    test('is a SpecstoneFault whose exit status comes from its code', () {
      final fault = RenderFault(RenderFaultCode.targetMissing, 'm');

      expect(fault, isA<SpecstoneFault>());
      expect(fault.exitStatus, 64);
    });

    test('toText is the message when no file applies', () {
      final fault = RenderFault(RenderFaultCode.targetNotFound, 'gone');

      expect(fault.toText(), 'gone');
      expect(fault.toJson(), {
        'error': {'code': 'target_not_found', 'message': 'gone'},
      });
    });

    test('a file prefixes the text and appears in the json', () {
      final fault = RenderFault(
        RenderFaultCode.outputNotWritable,
        'the output path is not writable',
        file: '.specstone/build/docs.html',
      );

      expect(
        fault.toText(),
        '.specstone/build/docs.html: the output path is not writable',
      );
      expect(fault.exitStatus, 73);
      expect(fault.toJson(), {
        'error': {
          'code': 'output_not_writable',
          'message': 'the output path is not writable',
          'file': '.specstone/build/docs.html',
        },
      });
    });
  });
}
