import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/index_query/mermaid_blocks.dart';
import 'package:test/test.dart';

List<MermaidSource> _sourcesOf(String text) =>
    mermaidSourcesOf(Doc.parse(text), text);

void main() {
  group('mermaidSourcesOf', () {
    test('a backtick fence gives its text at the fence line', () {
      final sources = _sourcesOf(
        '# T\n\n```mermaid\nflowchart TD\n  A --> B\n```\n',
      );

      expect(sources, hasLength(1));
      expect(sources.single.fenceLine, 3);
      expect(sources.single.text, 'flowchart TD\n  A --> B');
    });

    test('a tilde fence is read as a backtick one', () {
      final sources = _sourcesOf('# T\n\n~~~mermaid\npie\n"a" : 1\n~~~\n');

      expect(sources.single.fenceLine, 3);
      expect(sources.single.text, 'pie\n"a" : 1');
    });

    test('frontmatter lines count toward the fence line', () {
      final sources = _sourcesOf(
        '---\nstatus: planned\n---\n\n## Rationale\n\n```mermaid\npie\n```\n',
      );

      expect(sources.single.fenceLine, 7);
    });

    test('more words after mermaid in the info string still count', () {
      final sources = _sourcesOf('```mermaid title="x" {1}\npie\n```\n');

      expect(sources.single.fenceLine, 1);
      expect(sources.single.text, 'pie');
    });

    test('a fence whose first word is not mermaid gives none', () {
      expect(_sourcesOf('```dart\nvar a;\n```\n\n```\nplain\n```\n'), isEmpty);
      expect(_sourcesOf('```mermaidish\npie\n```\n'), isEmpty);
    });

    test('a fence inside a list item gives the text with its marks '
        'stripped', () {
      final sources = _sourcesOf(
        '# T\n\n- item\n\n  ```mermaid\n  flowchart TD\n    A --> B\n  ```\n',
      );

      expect(sources.single.fenceLine, 5);
      expect(sources.single.text, 'flowchart TD\n  A --> B');
    });

    test('each block of a doc is one source, in file order', () {
      final sources = _sourcesOf(
        '```mermaid\npie\n```\n\ntext\n\n```mermaid\npie\n```\n',
      );

      expect([for (final s in sources) s.fenceLine], [1, 7]);
    });

    test('equal text gives equal hashes at different fence lines', () {
      final sources = _sourcesOf(
        '```mermaid\npie\n```\n\n```mermaid\npie\n```\n',
      );

      expect(sources[0].hash, sources[1].hash);
      expect(sources[0].fenceLine, isNot(sources[1].fenceLine));
    });

    test('the hash is the full sha256 hex of the text', () {
      final source = _sourcesOf('```mermaid\npie\n```\n').single;

      expect(source.hash, sha256.convert(utf8.encode('pie')).toString());
      expect(source.hash, hasLength(64));
    });

    test('different text gives different hashes', () {
      final sources = _sourcesOf(
        '```mermaid\npie\n```\n\n```mermaid\nflowchart TD\n```\n',
      );

      expect(sources[0].hash, isNot(sources[1].hash));
    });

    test('an unclosed fence runs to the end of the doc', () {
      final sources = _sourcesOf('# T\n\n```mermaid\npie\n"a" : 1\n');

      expect(sources.single.fenceLine, 3);
      expect(sources.single.text, 'pie\n"a" : 1');
    });

    test('an empty block gives the empty text', () {
      final sources = _sourcesOf('```mermaid\n```\n');

      expect(sources.single.text, '');
    });

    test('a doc with no fence gives none', () {
      expect(_sourcesOf('# T\n\nBody.\n'), isEmpty);
    });

    test('block carries the fence line and the hash', () {
      final source = _sourcesOf('# T\n\n```mermaid\npie\n```\n').single;

      expect(source.block.fenceLine, 3);
      expect(source.block.hash, source.hash);
    });
  });
}
