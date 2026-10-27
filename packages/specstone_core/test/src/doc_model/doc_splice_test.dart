import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:test/test.dart';

void main() {
  test('dw-s03/inv1: a base is the first 12 hex characters of the SHA-256 of the UTF-8 text', () {
    expect(baseHashOf(''), 'e3b0c44298fc');
    expect(emptyBaseHash, baseHashOf(''));
    expect(baseHashOf('abc'), 'ba7816bf8f01');
    expect(baseHashOf('ค้นหา\n'), 'caa1446653a9');
  });
}
