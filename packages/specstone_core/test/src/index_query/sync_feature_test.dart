import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/sync_feature.dart';
import 'package:test/test.dart';

import '../../helpers/nested_fixture.dart';

void main() {
  test('a top-level feature is the one the name picks', () async {
    final index = await nestedIndexWith();
    expect(syncFeatureOf(index, 'shop').docPath, shopFeature);
  });

  for (final target in ['shop/cart', 'shop/cart/add_item']) {
    test('$target is no top-level feature', () async {
      final index = await nestedIndexWith();
      expect(
        () => syncFeatureOf(index, target),
        throwsA(
          isA<IndexFault>()
              .having((x) => x.code, 'code', IndexFaultCode.argumentInvalid)
              .having(
                (x) => x.message,
                'message',
                '--for sync takes a top-level feature, not $target',
              ),
        ),
      );
    });
  }
}
