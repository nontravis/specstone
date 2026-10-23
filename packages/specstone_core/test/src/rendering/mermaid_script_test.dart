import 'dart:convert';

import 'package:specstone_core/src/rendering/mermaid_script.dart';
import 'package:test/test.dart';

void main() {
  test('f05/us02/fr02/e03, s03/inv13: the embedded script is the pinned '
      'mermaid 11.17.2 build and is safe to inline', () {
    expect(utf8.encode(mermaidScript).length, 3572661);
    expect(mermaidScript, startsWith('"use strict";'));
    expect(mermaidScript.toLowerCase(), isNot(contains('</script')));
  });

  test('the embedded license is the MIT notice', () {
    expect(mermaidLicense, startsWith('The MIT License (MIT)'));
  });
}
