import 'package:test/test.dart';

import 'link_bodies.dart';

void main() {
  test(
    'f04/us02/fr04, LA5: the scan reads the links markdown reads on 9,000 '
    'inline bodies',
    () => expectReadersAgree(inlineGrammar),
  );

  test(
    'f04/us02/fr04, LA5: the scan reads the links markdown reads on 9,000 '
    'bodies with code spans, autolinks, and raw HTML',
    () => expectReadersAgree(atomGrammar),
  );

  test(
    'f04/us02/fr04, LA5: the scan reads the links markdown reads on 9,000 '
    'bodies of top-level blocks',
    () => expectReadersAgree(topBlockGrammar),
  );

  test(
    'f04/us02/fr04, LA5: the scan reads the links markdown reads on 9,000 '
    'bodies with blockquotes and lists',
    () => expectReadersAgree(containerGrammar),
  );
}
