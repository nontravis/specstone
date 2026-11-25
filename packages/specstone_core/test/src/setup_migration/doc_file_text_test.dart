import 'dart:convert';

import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/rendering/models/line_ending.dart';
import 'package:specstone_core/src/setup_migration/doc_file_text.dart';
import 'package:test/test.dart';

void main() {
  group('DocFileText read and written', () {
    test('a CRLF doc with a BOM keeps both', () {
      const lfText = '# D-01 — Context\n\nBody line.\n';
      const rewritten = '# Context\n\nBody line.\n';
      final bytes = [
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode(LineEnding.crlf.apply(lfText)),
      ];

      final original = DocFileText.read(bytes);
      final written = DocFileText.written(original, rewritten);

      expect(original.bom, isTrue);
      expect(original.ending, LineEnding.crlf);
      expect(original.lf, lfText);
      expect(written, startsWith('﻿'));
      expect(written.replaceAll('\r\n', '').contains('\n'), isFalse);
      expect(toLf(written.substring(1)), rewritten);
    });

    test('an LF doc without a BOM writes neither', () {
      final original = DocFileText.read(utf8.encode('# D-01 — x\n'));

      expect(original.bom, isFalse);
      expect(original.ending, LineEnding.lf);
      expect(DocFileText.written(original, '# x\n'), '# x\n');
    });
  });
}
