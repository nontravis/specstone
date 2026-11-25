import 'package:test/test.dart';

import 'link_bodies.dart';

void main() {
  test(
    'the scan reads the links markdown reads on 9,000 '
    'inline bodies',
    () => expectReadersAgree(inlineGrammar),
  );

  test(
    'the scan reads the links markdown reads on 9,000 '
    'bodies with code spans, autolinks, and raw HTML',
    () => expectReadersAgree(atomGrammar),
  );

  test(
    'the scan reads the links markdown reads on 9,000 '
    'bodies of top-level blocks',
    () => expectReadersAgree(topBlockGrammar),
  );

  test(
    'the scan reads the links markdown reads on 9,000 '
    'bodies with blockquotes and lists',
    () => expectReadersAgree(containerGrammar),
  );
}
