import 'package:test/test.dart';

import 'link_bodies.dart';

void main() {
  test(
    'f04/us02/fr04, LA5: the scan reads the links markdown reads on 9,000 '
    'inline bodies',
    () => expectReadersAgree(inlineGrammar),
  );
}
