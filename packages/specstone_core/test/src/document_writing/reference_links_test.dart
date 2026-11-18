import 'package:specstone_core/src/document_writing/reference_links.dart';
import 'package:specstone_core/src/rendering/skill_references.dart';
import 'package:test/test.dart';

const _front = '---\nlifecycle: stable\n---\n\n';

/// Returns [body] under [_front], rewritten with [action] for `a.md`.
String _rewritten(String body, LinkAction action) => rewriteReferenceLinks(
  '$_front$body',
  (href) => href.startsWith('a.md') ? action : const KeepLink(),
);

void main() {
  group('rewriteReferenceLinks', () {
    const retarget = RetargetLink('../b/c.md');
    const asText = LinkAsText('specs/a.md');
    const rows = [
      (
        'keeps an inline link',
        KeepLink(),
        'See [A](a.md#x).\n',
        'See [A](a.md#x).\n',
      ),
      (
        'keeps a reference-style link',
        KeepLink(),
        'See [A][a].\n\n[a]: a.md#x\n',
        'See [A][a].\n\n[a]: a.md#x\n',
      ),
      (
        'sets the path of an inline link and keeps its anchor',
        retarget,
        'See [A](a.md#x "title").\n',
        'See [A](../b/c.md#x "title").\n',
      ),
      (
        'sets the path of an angle-bracketed link',
        retarget,
        'See [A](<a.md#x>).\n',
        'See [A](<../b/c.md#x>).\n',
      ),
      (
        "sets the path of a reference-style link's definition",
        retarget,
        'See [A][a].\n\n[a]: a.md#x\n',
        'See [A][a].\n\n[a]: ../b/c.md#x\n',
      ),
      (
        'writes an inline link as its text and its path in a code span',
        asText,
        'See [*A*](a.md#x).\n',
        'See *A* (`specs/a.md`).\n',
      ),
      (
        'writes a reference-style link as its text and its path',
        asText,
        'See [A][a].\n\n[a]: a.md\n',
        'See A (`specs/a.md`).\n\n[a]: a.md\n',
      ),
      (
        'writes an image as its description and its path',
        asText,
        'See ![A](a.md).\n',
        'See A (`specs/a.md`).\n',
      ),
    ];
    for (final (name, action, body, expected) in rows) {
      test(name, () {
        expect(_rewritten(body, action), '$_front$expected');
      });
    }

    for (final action in const <LinkAction>[retarget, asText]) {
      test('leaves a link in a code span or a fenced block as written for '
          '${action.runtimeType}', () {
        const body = 'See `[A](a.md)`.\n\n```\n[A](a.md)\n```\n';

        expect(_rewritten(body, action), '$_front$body');
      });
    }

    test('writes a link around an image as text with the image as text '
        'inside', () {
      final rewritten = rewriteReferenceLinks(
        '$_front[![B](b.png)](a.md)\n',
        (href) => LinkAsText(href == 'a.md' ? 'specs/a.md' : 'specs/b.png'),
      );

      expect(rewritten, '${_front}B (`specs/b.png`) (`specs/a.md`)\n');
    });

    test('shows a path holding a backtick in a longer code span', () {
      final rewritten = rewriteReferenceLinks(
        '$_front[A](a.md)\n',
        (href) => const LinkAsText('specs/a`b.md'),
      );

      expect(rewritten, '${_front}A (``specs/a`b.md``)\n');
    });

    test('never reads the frontmatter as links', () {
      const text = '---\nnote: "[A](a.md)"\n---\n\nNo links.\n';

      expect(rewriteReferenceLinks(text, (href) => asText), text);
    });
  });
}
