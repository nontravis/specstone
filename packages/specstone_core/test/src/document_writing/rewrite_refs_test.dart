// The test names and file literals are plan text kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/document_writing/move_doc.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/rewrite_mentions.dart'
    show rewriteNameMentions;
import 'package:specstone_core/src/document_writing/rewrite_refs.dart';
import 'package:specstone_core/src/index_query/link_places.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart' show fingerprintFor;
import '../../helpers/nested_fixture.dart';
import '../../helpers/record_fixture.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/write_fixture.dart';

void main() {
  const reorderMoves = <PathMove>[
    (
      from: 'prds/features/f01_login/us02_sign_out/',
      to: 'prds/features/f01_login/us03_sign_out/',
    ),
    (
      from: 'prds/features/f01_login/us03_reset_password/',
      to: 'prds/features/f01_login/us01_reset_password/',
    ),
  ];
  const featureSwap = <PathMove>[
    (from: 'prds/features/f01_login/', to: 'prds/features/f02_login/'),
    (from: 'prds/features/f02_signup/', to: 'prds/features/f01_signup/'),
  ];
  late Directory root;

  setUp(() async {
    root = await writeWriteProject();
  });

  List<WriteStep> plan(
    List<PathMove> moves, {
    Map<(String, String), String> renamed = const {},
  }) => writeIn(root, (s) => planRewrites(s, moves, renamed: renamed));

  test('movedPath and relativeHref', () {
    expect(
      movedPath(story3, reorderMoves),
      'prds/features/f01_login/us01_reset_password/USER_STORY.md',
    );
    expect(movedPath(story1, reorderMoves), story1);
    expect(movedPath('a/b.md', [(from: 'a/b.md', to: 'a/c.md')]), 'a/c.md');
    expect(relativeHref(fr12, story2), '../us02_sign_out/USER_STORY.md');
    expect(
      relativeHref('prds/FEATURES.md', loginFeature),
      'features/f01_login/FEATURE.md',
    );
    expect(relativeHref('a/b/c.md', 'a/d.md'), '../d.md');
    expect(relativeHref('a/b.md', 'a/b.md'), 'b.md');
  });

  test('f02/us05/fr02, f02/us05/fr02/e01, dw-s03/inv10: a link to a moved doc follows it, its fragment kept', () {
    expect(
      rewriteDocLinks(
        'See [sign out](../us02_sign_out/USER_STORY.md#acceptance-criteria).\n',
        docPath: 'prds/features/f01_login/us01_email_login/USER_STORY.md',
        moves: reorderMoves,
      ),
      'See [sign out](../us03_sign_out/USER_STORY.md#acceptance-criteria).\n',
    );
  });

  test(
    'f02/us05/fr02: rewriteDocLinksCounted counts the destinations it changes',
    () {
      final result = rewriteDocLinksCounted(
        'See [a](../us02_sign_out/USER_STORY.md) and [b](../us02_sign_out/USER_STORY.md#x) or [w](https://x.dev/a.md).\n',
        docPath: 'prds/features/f01_login/us01_email_login/USER_STORY.md',
        moves: reorderMoves,
      );

      expect(
        result?.lfText,
        'See [a](../us03_sign_out/USER_STORY.md) and [b](../us03_sign_out/USER_STORY.md#x) or [w](https://x.dev/a.md).\n',
      );
      expect(result?.count, 2);
      expect(
        rewriteDocLinksCounted(
          '[w](https://x.dev/a.md)\n',
          docPath: 'I.md',
          moves: reorderMoves,
        ),
        isNull,
      );
    },
  );

  test('f02/us05/fr02, R74: a move replaces only the path a destination is written with and keeps its ? or # part as written', () {
    const moves = <PathMove>[(from: 'specs/t_doc.md', to: 'specs/m/t_doc.md')];
    const before =
        '[a](../t_doc.md#a\\)b) [b](../t_doc.md#f\\(x) [c](../t_doc.md#a&amp;copy;)\n'
        '[d](../t_doc.md&#35;s) [e](<../t_doc.md?q=a b#x>) [f](../t\\_doc.md\\#y)\n';

    expect(
      rewriteDocLinks(before, docPath: 'specs/f01_a/DOMAIN.md', moves: moves),
      '[a](../m/t_doc.md#a\\)b) [b](../m/t_doc.md#f\\(x) [c](../m/t_doc.md#a&amp;copy;)\n'
      '[d](../m/t_doc.md&#35;s) [e](<../m/t_doc.md?q=a b#x>) [f](../m/t_doc.md\\#y)\n',
    );
  });

  test('f02/us05/fr02, R74: a move to or from a path with a paren keeps a bare inline link one link to the same file, its fragment kept', () {
    const into = <PathMove>[(from: 'specs/t.md', to: 'specs/x(y/t.md')];
    const back = <PathMove>[(from: 'specs/x(y/t.md', to: 'specs/t.md')];
    String? moved(String text, List<PathMove> moves) =>
        rewriteDocLinks(text, docPath: 'specs/d.md', moves: moves);
    List<(String, String?)>? read(String? text) => linkPlacesOf(
      text!,
      docPath: 'specs/d.md',
      firstLine: 1,
    )?.docLinks.map((link) => (link.target, link.anchor)).toList();

    final there = moved(
      'See [a](t.md#z) end. [b](<t.md#z>) [c][r]\n\n[r]: t.md#z\n',
      into,
    );
    final home = moved('See [a](x(y/t.md#z)) end.\n', back);

    expect(
      there,
      'See [a](x%28y/t.md#z) end. [b](<x(y/t.md#z>) [c][r]\n\n'
      '[r]: x%28y/t.md#z\n',
    );
    expect(read(there), [for (var i = 0; i < 3; i++) ('specs/x(y/t.md', 'z')]);
    expect(home, 'See [a](t.md#z\\)) end.\n');
    expect(read(home), [('specs/t.md', 'z)')]);
  });

  test('f02/us05/fr02, R74: a move to or from a path with a paren keeps the parens of an angle-bracketed definition as written', () {
    const into = <PathMove>[(from: 'specs/t.md', to: 'specs/x(y/t.md')];
    const back = <PathMove>[(from: 'specs/x(y/t.md', to: 'specs/t.md')];
    List<(String, String?)>? read(String? text) => linkPlacesOf(
      text!,
      docPath: 'specs/d.md',
      firstLine: 1,
    )?.docLinks.map((link) => (link.target, link.anchor)).toList();

    final there = rewriteDocLinks(
      '[c][r]\n\n[r]: <t.md#z>\n',
      docPath: 'specs/d.md',
      moves: into,
    );
    final home = rewriteDocLinks(there!, docPath: 'specs/d.md', moves: back);

    expect(there, '[c][r]\n\n[r]: <x(y/t.md#z>\n');
    expect(read(there), [('specs/x(y/t.md', 'z')]);
    expect(home, '[c][r]\n\n[r]: <t.md#z>\n');
  });

  test('f02/us05/fr02, R74: a folder move to or from a name with parens keeps a bare definition a definition to the same file', () {
    const doc = 'specs/f01_a/DOMAIN.md';
    List<String>? read(String? text) => linkPlacesOf(
      text!,
      docPath: doc,
      firstLine: 1,
    )?.fileLinks.map((link) => link.target).toList();
    String? moved(String text, String from, String to) => rewriteDocLinks(
      text,
      docPath: doc,
      moves: [(from: 'specs/$from/', to: 'specs/$to/')],
    );

    final there = moved(
      '[i][p]\n\n[p]: ../f02_b/img%281%29.png\n',
      'f02_b',
      'f03_b',
    );
    final back = moved(there!, 'f03_b', 'f02_b');

    expect(there, '[i][p]\n\n[p]: ../f03_b/img%281%29.png\n');
    expect(back, '[i][p]\n\n[p]: ../f02_b/img%281%29.png\n');
    expect(read(there), ['specs/f03_b/img(1).png']);
    expect(read(back), ['specs/f02_b/img(1).png']);
  });

  test('rewrite_links_to_moved_docs E15: a destination inside an unreferenced footnote stays as written on a move, and one inside a referenced footnote moves', () {
    const moves = <PathMove>[(from: 'specs/t_doc.md', to: 'specs/m/t_doc.md')];
    const doc = 'specs/f01_a/DOMAIN.md';

    final unreferenced = rewriteDocLinks(
      'Text.\n\n[^1]: Also [x](../t_doc.md).\n',
      docPath: doc,
      moves: moves,
    );
    final referenced = rewriteDocLinks(
      'Text[^1].\n\n[^1]: Also [x](../t_doc.md).\n',
      docPath: doc,
      moves: moves,
    );

    expect(unreferenced, isNull);
    expect(referenced, 'Text[^1].\n\n[^1]: Also [x](../m/t_doc.md).\n');
  });

  test('f02/us05/fr02, R74: a destination inside an image description is no link, so a move leaves it and moves the definition written alike', () {
    const moves = <PathMove>[(from: 'specs/t_doc.md', to: 'specs/m/t_doc.md')];

    final result = rewriteDocLinksCounted(
      '![see [x](../t_doc.md)](pic.png)\n\n[d1]: ../t_doc.md\n',
      docPath: 'specs/f01_a/DOMAIN.md',
      moves: moves,
    );

    expect(
      result?.lfText,
      '![see [x](../t_doc.md)](pic.png)\n\n[d1]: ../m/t_doc.md\n',
    );
    expect(result?.count, 1);
  });

  test('f02/us05/fr02/e02: a link between two files of one moved folder is unchanged', () {
    expect(
      rewriteDocLinks(
        'See [send](fr01_send_reset_link.md).\n',
        docPath: fr32,
        moves: reorderMoves,
      ),
      isNull,
    );
  });

  test(
    'f02/us05/fr02/e04, LP1: a move keeps a link whose escape is not UTF-8',
    () {
      expect(
        rewriteDocLinks(
          '# T\n\n[x](%DB.md) [s](../us02/USER_STORY.md)\n',
          docPath: 'prds/f/us01/fr01.md',
          moves: [(from: 'prds/f/us02/', to: 'prds/f/us03/')],
        ),
        '# T\n\n[x](%DB.md) [s](../us03/USER_STORY.md)\n',
      );
    },
  );

  test('f02/us05/fr02/e04, LP1: a move keeps the text of a link whose escape is not UTF-8, whichever side moves', () {
    expect(
      rewriteDocLinks(
        '# T\n\n[x](../other/%DB.md)\n',
        docPath: 'prds/f/us01/fr01.md',
        moves: [(from: 'prds/f/us01/', to: 'prds/g/us01/')],
      ),
      isNull,
      reason: 'the holder moves',
    );
    expect(
      rewriteDocLinks(
        '# T\n\n[x](us01/%DB.md) [s](us02/USER_STORY.md)\n',
        docPath: 'prds/f/fr.md',
        moves: [
          (from: 'prds/f/us01/', to: 'prds/f/us03/'),
          (from: 'prds/f/us02/', to: 'prds/f/us04/'),
        ],
      ),
      '# T\n\n[x](us01/%DB.md) [s](us04/USER_STORY.md)\n',
      reason: 'the target folder moves; the lossy link keeps its bytes',
    );
  });

  test('f02/us05/fr02/e04, LP1: a move still re-encodes a valid escape', () {
    expect(
      rewriteDocLinks(
        '# T\n\n[x](us01/caf%C3%A9.md)\n',
        docPath: 'prds/f/fr.md',
        moves: [(from: 'prds/f/us01/', to: 'prds/f/us03/')],
      ),
      '# T\n\n[x](us03/caf%C3%A9.md)\n',
    );
  });

  test('f02/us05/fr02/e04: web links, paths outside the docs root, and unmoved targets keep their text', () {
    expect(
      rewriteDocLinks(
        '[w](https://x.dev/a.md) [o](../../../../../x.md) [s](../us01_email_login/USER_STORY.md)\n',
        docPath: story2,
        moves: reorderMoves,
      ),
      isNull,
    );
  });

  test('f02/us05/fr02/e09, M2: a link to a non-doc file of a moved folder follows the move, its image form too', () {
    expect(
      rewriteDocLinks(
        '![flow](us02_sign_out/flow.png)\n',
        docPath: 'prds/features/f01_login/FEATURE.md',
        moves: reorderMoves,
      ),
      '![flow](us03_sign_out/flow.png)\n',
    );
  });

  test('f02/us05/fr02, M2: a link to a moved folder itself follows the move, with or without the slash', () {
    expect(
      rewriteDocLinks(
        '[a](../us02_sign_out/) [b](../us02_sign_out) [c](../us02_sign_out/#top)\n',
        docPath: story3,
        moves: reorderMoves,
      ),
      '[a](../us03_sign_out/) [b](../us03_sign_out) [c](../us03_sign_out/#top)\n',
    );
  });

  test('f02/us05/fr02, M2: a link to an unmoved file from an unmoved doc keeps every byte', () {
    expect(
      rewriteDocLinks(
        '[a](./flow.png?raw=1) [b](../us01_email_login/a%20b.png#x) [c](../../../../../lib/a.dart)\n',
        docPath: story1,
        moves: reorderMoves,
      ),
      isNull,
    );
  });

  test('f02/us05/fr02, M2: a moved doc keeps a link that leaves the docs root pointing at the same file', () {
    expect(
      rewriteDocLinks(
        '[code](../../../../lib/a.dart)\n',
        docPath: 'prds/f/FEATURE.md',
        moves: [(from: 'prds/f/FEATURE.md', to: 'prds/f/sub/FEATURE.md')],
      ),
      '[code](../../../../../lib/a.dart)\n',
    );
  });

  test('f02/us05/fr02, M2: a link to an ancestor folder of its own doc keeps every byte when that folder is renamed', () {
    expect(
      rewriteDocLinks(
        '[a](../) [b](..) [c](../#top)\n',
        docPath: 'prds/features/f01_x/us01/USER_STORY.md',
        moves: [(from: 'prds/features/f01_x/', to: 'prds/features/f02_x/')],
      ),
      isNull,
    );
  });

  test('f02/us05/fr02, M2: a link that leaves a moved ancestor and re-enters it by name follows the rename', () {
    expect(
      rewriteDocLinks(
        '[a](../../f01_x/) [b](../../f01_x/FEATURE.md#top) [c](../../f01_x)\n',
        docPath: 'prds/features/f01_x/us01/USER_STORY.md',
        moves: [(from: 'prds/features/f01_x/', to: 'prds/features/f02_x/')],
      ),
      '[a](../../f02_x/) [b](../FEATURE.md#top) [c](../../f02_x)\n',
    );
  });

  test('PD13: a swap is rewritten in one pass, and a reference definition follows too', () {
    const swap = <PathMove>[
      (from: 'a/f01_x/', to: 'a/f02_x/'),
      (from: 'a/f02_y/', to: 'a/f01_y/'),
    ];
    expect(
      rewriteDocLinks(
        '[x](a/f01_x/F.md) [y]\n\n[y]: a/f02_y/F.md\n',
        docPath: 'I.md',
        moves: swap,
      ),
      '[x](a/f02_x/F.md) [y]\n\n[y]: a/f01_y/F.md\n',
    );
  });

  test('PD13, R73: a definition destination follows its moved target by the href markdown reads, an unbalanced paren included', () {
    const moves = <PathMove>[(from: 'a/f01_x/', to: 'a/f02_x/')];
    expect(
      rewriteDocLinks(
        '[x][m] [y][n]\n\n[m]: a/f01_x/a(b.md\n[n]: a/f01\\_x/F.md\n',
        docPath: 'I.md',
        moves: moves,
      ),
      '[x][m] [y][n]\n\n[m]: a/f02_x/a%28b.md\n[n]: a/f02_x/F.md\n',
    );
  });

  test('f02/us05/fr02, PD13: a link-shaped href in a fenced block or a code span keeps every byte', () {
    const moves = <PathMove>[(from: 'a/f01_x/', to: 'a/f02_x/')];
    expect(
      rewriteDocLinks(
        '[x](a/f01_x/F.md)\n\n```\n[x](a/f01_x/F.md)\n```\n\nUse `[x](a/f01_x/F.md)` here.\n',
        docPath: 'I.md',
        moves: moves,
      ),
      '[x](a/f02_x/F.md)\n\n```\n[x](a/f01_x/F.md)\n```\n\nUse `[x](a/f01_x/F.md)` here.\n',
    );
    expect(
      rewriteDocLinks(
        '```\n[x](a/f01_x/F.md)\n```\n',
        docPath: 'I.md',
        moves: moves,
      ),
      isNull,
    );
  });

  test('f02/us05/fr02: an angle-bracket href and an href with a query are rewritten, a folder sharing the prefix of a moved one is not', () {
    const moves = <PathMove>[(from: 'a/f01_x/', to: 'a/f02_x/')];
    expect(
      rewriteDocLinks(
        '[x](<a/f01_x/F.md>) [q](a/f01_x/F.md?v=1) [l](a/f01_xy/F.md)\n',
        docPath: 'I.md',
        moves: moves,
      ),
      '[x](<a/f02_x/F.md>) [q](a/f02_x/F.md?v=1) [l](a/f01_xy/F.md)\n',
    );
  });

  test('f02/us05/fr02: a query and a fragment stay as written; a scheme href and a bare fragment are left alone', () {
    const moves = <PathMove>[(from: 'a/f01_x/', to: 'a/f02_x/')];
    expect(
      rewriteDocLinks(
        '[a](a/f01_x/F.md?v=1#top) [b](a/f01_x/F.md#a?b) [c](mailto:a/f01_x/F.md#x) [d](#a/f01_x/F.md)\n',
        docPath: 'I.md',
        moves: moves,
      ),
      '[a](a/f02_x/F.md?v=1#top) [b](a/f02_x/F.md#a?b) [c](mailto:a/f01_x/F.md#x) [d](#a/f01_x/F.md)\n',
    );
  });

  test('f02/us06/fr02, f02/us06/fr02/e01, f02/us06/fr02/e03, f02/us06/fr02/e06: doc_ref values follow a rename, prose and other values stay', () {
    const persona = MergedField(
      id: 'persona',
      type: FieldType.docRef,
      list: true,
      docTypes: ['persona'],
    );
    expect(
      rewriteDocRefs(
        '---\npersona:\n  - buyer\n  - seller\n---\n\n# S\n\nThe buyer pays.\n',
        fields: [persona],
        renamed: {('persona', 'buyer'): 'shopper'},
      ),
      '---\npersona:\n  - shopper\n  - seller\n---\n\n# S\n\nThe buyer pays.\n',
    );
    expect(
      rewriteDocRefs(
        '---\npersona: [buyer, seller]\n---\n',
        fields: [persona],
        renamed: {('persona', 'buyer'): 'shopper'},
      ),
      '---\npersona: [shopper, seller]\n---\n',
    );
    expect(
      rewriteDocRefs(
        '---\npersona:\n  - buyer\n---\n',
        fields: [persona],
        renamed: {('feature', 'buyer'): 'x'},
      ),
      isNull,
    );
  });

  test('f02/us06/fr02/e01: an inline scalar, a quoted value, and a comment line follow the rule; another field keeps its text', () {
    const anyType = MergedField(id: 'reference', type: FieldType.docRef);
    const other = MergedField(id: 'note', type: FieldType.string);
    expect(
      rewriteDocRefs(
        '---\nreference: "buyer" # who\nnote: buyer\n---\n',
        fields: [anyType, other],
        renamed: {('persona', 'buyer'): 'shopper'},
      ),
      '---\nreference: "shopper" # who\nnote: buyer\n---\n',
    );
    expect(
      rewriteDocRefs(
        "---\nreference:\n  # buyer\n  - 'buyer'\n  - buyers\n---\n",
        fields: [anyType],
        renamed: {('persona', 'buyer'): 'shopper'},
      ),
      "---\nreference:\n  # buyer\n  - 'shopper'\n  - buyers\n---\n",
    );
    expect(
      rewriteDocRefs(
        '# No frontmatter\n',
        fields: [anyType],
        renamed: {('persona', 'buyer'): 'shopper'},
      ),
      isNull,
    );
  });

  test('f02/us06/fr02, HD4: a quoted "reference": key follows the rename', () {
    const anyType = MergedField(id: 'reference', type: FieldType.docRef);
    expect(
      rewriteDocRefs(
        '---\n"reference": "buyer" # who\nnote: buyer\n---\n',
        fields: [anyType],
        renamed: {('persona', 'buyer'): 'shopper'},
      ),
      '---\n"reference": "shopper" # who\nnote: buyer\n---\n',
    );
    expect(
      rewriteDocRefs(
        "---\n'reference':\n  - buyer\n---\n",
        fields: [anyType],
        renamed: {('persona', 'buyer'): 'shopper'},
      ),
      "---\n'reference':\n  - shopper\n---\n",
    );
  });

  test('dw-s03/inv6, f02/us06/fr02: of two blocks with one name only the first counts, whatever the spelling', () {
    const anyType = MergedField(id: 'reference', type: FieldType.docRef);
    const renamed = {('persona', 'buyer'): 'shopper'};
    expect(
      rewriteDocRefs(
        '---\nreference: keep\n"reference": buyer\n---\n',
        fields: [anyType],
        renamed: renamed,
      ),
      isNull,
    );
    expect(
      rewriteDocRefs(
        '---\nreference: buyer\n"reference": buyer\n---\n',
        fields: [anyType],
        renamed: renamed,
      ),
      '---\nreference: shopper\n"reference": buyer\n---\n',
    );
    expect(
      rewriteDocRefs(
        '---\nreference: keep\nreference: buyer\n---\n',
        fields: [anyType],
        renamed: renamed,
      ),
      isNull,
    );
  });

  test('f02/us05/fr02, dw-s03/inv10, H14: a link-shaped frontmatter value keeps its text; the same link in the body follows', () {
    const link = '[sign out](../us02_sign_out/USER_STORY.md)';
    expect(
      rewriteDocLinks(
        '---\nsee: $link\n---\n\nSee $link.\n',
        docPath: 'prds/features/f01_login/us01_email_login/USER_STORY.md',
        moves: reorderMoves,
      ),
      '---\nsee: $link\n---\n\n'
      'See [sign out](../us03_sign_out/USER_STORY.md).\n',
    );
  });

  test('f02/us05/fr02, dw-s03/inv10, H17: an href with a backslash escape follows the move', () {
    expect(
      rewriteDocLinks(
        r'See [reset](../us03\_reset\_password/USER_STORY.md) and '
        '[again](../us03_reset_password/USER_STORY.md).\n',
        docPath: 'prds/features/f01_login/us01_email_login/USER_STORY.md',
        moves: reorderMoves,
      ),
      'See [reset](../us01_reset_password/USER_STORY.md) and '
      '[again](../us01_reset_password/USER_STORY.md).\n',
    );
  });

  test('f02/us05/fr02, dw-s03/inv10, H17: an href with an entity spelling follows the move', () {
    expect(
      rewriteDocLinks(
        'See [reset](../us03&#95;reset&#95;password/USER_STORY.md).\n',
        docPath: 'prds/features/f01_login/us01_email_login/USER_STORY.md',
        moves: reorderMoves,
      ),
      'See [reset](../us01_reset_password/USER_STORY.md).\n',
    );
  });

  test('f02/us05/fr02/e08, dw-s03/inv10, LP3: a doc the parser fails on keeps its links in a move', () {
    expect(
      rewriteDocLinks(
        '# T\n\n[s](../us02/USER_STORY.md)\n\n[a]:<b\\',
        docPath: 'prds/f/us01/fr01.md',
        moves: [(from: 'prds/f/us02/', to: 'prds/f/us03/')],
      ),
      isNull,
    );
  });

  test('f02/us06/fr02, H15: a flow list followed by a comment holding brackets renames its item', () {
    const reference = MergedField(
      id: 'reference',
      type: FieldType.docRef,
      list: true,
    );
    expect(
      rewriteDocRefs(
        '---\nreference: [a, buyer] # see [x]\n---\n',
        fields: [reference],
        renamed: {('persona', 'buyer'): 'shopper'},
      ),
      '---\nreference: [a, shopper] # see [x]\n---\n',
    );
  });

  test('f02/us06/fr02, dw-s03/inv10, HD3: with no docTypes, a value two renamed docs take to different names keeps its text, and one they agree on follows', () {
    const reference = MergedField(id: 'reference', type: FieldType.docRef);
    const text = '---\nreference: buyer\n---\n';
    expect(
      rewriteDocRefs(
        text,
        fields: [reference],
        renamed: {
          ('persona', 'buyer'): 'shopper',
          ('actor', 'buyer'): 'customer',
        },
      ),
      isNull,
    );
    expect(
      rewriteDocRefs(
        text,
        fields: [reference],
        renamed: {
          ('persona', 'buyer'): 'shopper',
          ('actor', 'buyer'): 'shopper',
        },
      ),
      '---\nreference: shopper\n---\n',
    );
  });

  test('f02/us05/fr02/e03, f02/us05/fr02/e06, f02/us05/fr02/e07, f02/us06/fr02/e04, f02/us06/fr02/e05: planRewrites reaches untyped referrers, never code, and keeps the marks', () async {
    root = await writeWriteProject(
      extra: {
        'docs/prds/FEATURES.md': '---\napproved: true\n---\n\n# Feature index\n\n## Systems\n- [Login](features/f01_login/FEATURE.md)\n- [Signup](features/f02_signup/FEATURE.md)\n',
      },
    );
    final steps = plan(featureSwap);
    expect(
      [for (final step in steps) step.path],
      ['docs/prds/FEATURES.md', 'docs/prds/d01_context.md'],
    );
    expect(
      steps.first.text,
      '---\napproved: true\n---\n\n# Feature index\n\n## Systems\n\n- [Login](features/f02_login/FEATURE.md)\n- [Signup](features/f01_signup/FEATURE.md)\n',
    );
    expect(steps.last.text, contains('(features/f01_signup/FEATURE.md)'));
    expect(
      steps.every(
        (step) => step.path.startsWith('docs/') && step.path.endsWith('.md'),
      ),
      isTrue,
    );
  });

  test('document_writing/move_story/rewrite_moved_story_references E10, E07: a record edit is a rewrite of its doc, which joins the link rewrites of one step and makes a record with no link a candidate', () async {
    const linked = 'specs/f01_login/IMPLEMENTATION.md';
    const alone = 'specs/f02_signup/IMPLEMENTATION.md';
    root = await writeWriteProject(
      extra: {
        '.specstone/templates/implementation.yaml': recordLayer,
        'docs/$linked': recordText(
          statuses: ['a:planned'],
        ).replaceFirst('# Record\n', '# Record\n\nSee [it](../../$story3).\n'),
        'docs/$alone': recordText(statuses: ['a:planned']),
      },
    );
    String? rename(String text) => text.contains('a:planned')
        ? text.replaceFirst('a:planned', 'b:planned')
        : null;
    final steps = writeIn(
      root,
      (s) => planRewrites(
        s,
        reorderMoves,
        recordEdits: {linked: rename, alone: rename},
      ),
    );
    final byPath = {for (final step in steps) step.path: step.text};
    expect(byPath['docs/$linked'], contains("'b:planned'"));
    expect(
      byPath['docs/$linked'],
      contains('../../prds/features/f01_login/us01_reset_password/'),
    );
    expect(byPath['docs/$alone'], contains("'b:planned'"));
    expect(steps.where((step) => step.path == 'docs/$linked'), hasLength(1));
  });

  test('f02/us05/fr02/e09, M2: planRewrites reaches a doc that links only to a moved non-doc file', () async {
    root = await writeWriteProject(
      extra: {
        'docs/prds/d02_notes.md':
            '# Notes\n\n![flow](features/f01_login/us02_sign_out/flow.png)\n',
      },
    );
    final step = plan(reorderMoves)
        .singleWhere((step) => step.path == 'docs/prds/d02_notes.md');
    expect(
      step.text,
      '# Notes\n\n![flow](features/f01_login/us03_sign_out/flow.png)\n',
    );
  });

  test('f02/us05/fr02, M2: planRewrites reaches a doc whose only link is a folder link with no trailing slash', () async {
    root = await writeWriteProject(
      extra: {
        'docs/prds/d02_notes.md':
            '# Notes\n\n[a](features/f01_login/us02_sign_out)\n',
      },
    );
    final step = plan(reorderMoves)
        .singleWhere((step) => step.path == 'docs/prds/d02_notes.md');
    expect(step.text, '# Notes\n\n[a](features/f01_login/us03_sign_out)\n');
  });

  test('f02/us05/fr02: a step is written to the path after the moves, in the file line ends', () async {
    root = await writeWriteProject(
      extra: {
        'docs/prds/features/f01_login/us03_reset_password/USER_STORY.md': '---\r\nstatus: planned\r\n---\r\n\r\n# Reset\r\n\r\nSee [sign out](../us02_sign_out/USER_STORY.md).\r\n',
      },
    );
    final step = plan(reorderMoves)
        .singleWhere((step) => step.path.contains('us01_reset_password'));
    expect(
      step.text,
      '---\r\nstatus: planned\r\n---\r\n\r\n# Reset\r\n\r\nSee [sign out](../us03_sign_out/USER_STORY.md).\r\n',
    );
  });

  test('f02/us05/fr02, U1: a leading BOM is kept and bytes that are not UTF-8 refuse', () async {
    final index = File('${root.path}/docs/prds/FEATURES.md')
      ..writeAsBytesSync([
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('# Index\n\n- [Login](features/f01_login/FEATURE.md)\n'),
      ]);
    final step = plan(featureSwap).first;
    expect(
      step.text,
      '${String.fromCharCode(0xFEFF)}# Index\n\n- [Login](features/f02_login/FEATURE.md)\n',
    );
    expect(
      () => writeIn(root, (s) {
        index.writeAsBytesSync([0xFF, 0xFE, 0x5D, 0x28]);
        return planRewrites(s, featureSwap);
      }),
      throwsA(
        isA<RenderFault>()
            .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
            .having((f) => f.message, 'message', contains('not UTF-8 text')),
      ),
    );
  });

  test(
    'f02/us05/fr02/e05: a doc_ref value is untouched when only paths move',
    () {
      final steps = plan(featureSwap);
      expect(steps.where((step) => step.path.contains('PERSONA')), isEmpty);
      expect(
        readDoc(root, 'prds/personas/buyer/PERSONA.md'),
        contains('login/email_login'),
      );
    },
  );

  test(
    'f02/us06/fr02/e02: a rename reaches doc_ref values naming every moved doc',
    () {
      final steps = plan(
        const [
          (from: 'prds/features/f01_login/', to: 'prds/features/f01_signin/'),
        ],
        renamed: {('user_story', 'login/email_login'): 'signin/email_login'},
      );
      final persona = steps.singleWhere(
        (step) => step.path == 'docs/prds/personas/buyer/PERSONA.md',
      );
      expect(persona.text, contains('  - signin/email_login\n'));
      expect(persona.text, contains('draft: true\n'));
    },
  );

  test('f02/us05/fr02/e10: a doc that only mentions a moved file is rewritten, a mention of nothing stays', () async {
    final mentioning = await writeWriteProject(
      extra: {
        'docs/prds/NOTES.md': '# Notes\n\nSee `features/f01_login/us02_sign_out/USER_STORY.md` and prds/x.md or and/or.\n',
      },
    );

    final steps = writeIn(mentioning, (s) => planRewrites(s, reorderMoves));
    final notes = steps.singleWhere(
      (step) => step.path == 'docs/prds/NOTES.md',
    );

    expect(
      notes.text,
      '# Notes\n\nSee `features/f01_login/us03_sign_out/USER_STORY.md` and prds/x.md or and/or.\n',
    );
  });

  test('f02/us05/fr02/e10: a mention of a file on disk that no doc indexes follows its folder', () async {
    final mentioning = await writeWriteProject(
      extra: {
        'docs/prds/features/f01_login/us02_sign_out/flow.png': 'png',
        'docs/prds/NOTES.md': '# Notes\n\nDiagram: features/f01_login/us02_sign_out/flow.png:3, ghost: features/f01_login/us02_sign_out/ghost.png\n',
      },
    );

    final steps = writeIn(mentioning, (s) => planRewrites(s, reorderMoves));
    final notes = steps.singleWhere(
      (step) => step.path == 'docs/prds/NOTES.md',
    );

    expect(
      notes.text,
      '# Notes\n\nDiagram: features/f01_login/us03_sign_out/flow.png:3, ghost: features/f01_login/us02_sign_out/ghost.png\n',
    );
  });

  test('f02/us05/fr02/e04, review 3: a leading ./ stays on a link', () {
    expect(
      rewriteDocLinks(
        '[b](./b.md#x) [c](./c.md)\n',
        docPath: 'a/x.md',
        moves: [(from: 'a/b.md', to: 'a/d.md')],
      ),
      '[b](./d.md#x) [c](./c.md)\n',
    );
  });

  test('f02/us06/fr03/e10: a sub-feature rename lists the parent api among the rewrites and sets its confirmed label', () async {
    final nested = await writeNestedProject();
    final answer = writeIn(
      nested,
      (s) => answerRename(s, 'feature:shop/cart', slug: 'basket'),
    );
    expect(answer.json['rewritten'], contains(shopApi));
    final stock = fingerprintFor(checkStockStatement);
    expect(
      readDoc(nested, shopApi),
      contains('  - basket/add_item/check_stock $stock\n'),
    );
  });

  group('laid-out rewrites', () {
    const looseLink =
        'The system shall lock the account. See [reset](../us03_reset_password/USER_STORY.md#use-case).\n';
    const loose =
        '---\ndraft: true\ntraced_from: US-01\nverify_method: test\n---\n\n# Lock after failures\n\n## Statement\n\n\n\n$looseLink\n\n';

    String stepText(List<WriteStep> steps, String docPath) =>
        steps.singleWhere((step) => step.path == 'docs/$docPath').text;

    test('document_writing/reorder_doc/rewrite_links_to_moved_docs E13: a typed doc whose link changes is written laid out, still draft', () async {
      final project = await writeWriteProject(extra: {'docs/$fr12': loose});
      final text = stepText(
        writeIn(project, (s) => planRewrites(s, reorderMoves)),
        fr12,
      );
      expect(text, contains('us01_reset_password/USER_STORY.md#use-case'));
      expect(text, isNot(contains('\n\n\n')));
      expect(text, contains('draft: true\n'));
    });

    test('document_writing/reorder_doc/rewrite_links_to_moved_docs E13: an untyped doc keeps every byte the rewrite leaves', () async {
      final project = await writeWriteProject(
        extra: {
          'docs/prds/d01_context.md': '# Context\n\n\n\n## Features\nSee [signup](features/f02_signup/FEATURE.md).\n\n\n',
        },
      );
      final text = stepText(
        writeIn(project, (s) => planRewrites(s, featureSwap)),
        'prds/d01_context.md',
      );
      expect(text, contains('features/f01_signup/FEATURE.md'));
      expect(text, contains('\n\n\n\n## Features'));
      expect(text, endsWith(').\n\n\n'));
    });

    test('document_writing/reorder_doc/rewrite_links_to_moved_docs E13: a doc the formatter refuses keeps every byte the rewrite leaves', () async {
      final refused = loose.replaceFirst('## Statement', '## Bogus');
      final project = await writeWriteProject(extra: {'docs/$fr12': refused});
      final text = stepText(
        writeIn(project, (s) => planRewrites(s, reorderMoves)),
        fr12,
      );
      expect(text, contains('\n\n\n\nThe system'));
      expect(text, contains('us01_reset_password/USER_STORY.md#use-case'));
    });

    test('document_writing/reorder_doc/rewrite_links_to_moved_docs E13: a doc the rewrite does not change gets no step', () async {
      final project = await writeWriteProject(
        extra: {
          'docs/$fr11': '---\nstatus: implemented\n---\n\n# Validate\n\n\n\n## Statement\n\nText.\n',
        },
      );
      final steps = writeIn(project, (s) => planRewrites(s, reorderMoves));
      expect(steps.where((step) => step.path == 'docs/$fr11'), isEmpty);
    });

    test('document_writing/move_story/move_story_folder E11: the type of the path a moved doc lands on decides the layout', () async {
      const to = 'prds/features/f01_login/us01_email_login/fr09_context.md';
      final project = await writeWriteProject(
        extra: {
          'docs/prds/d01_context.md': '# Context\n\n## Statement\n\n\n\nSee [signup](features/f02_signup/FEATURE.md).\n',
        },
      );
      final steps = writeIn(
        project,
        (s) => planRewrites(s, [(from: 'prds/d01_context.md', to: to)]),
      );
      final step = steps.singleWhere((step) => step.path == 'docs/$to');
      expect(step.text, contains('../../f02_signup/FEATURE.md'));
      expect(step.text, isNot(contains('\n\n\n')));
    });

    test('document_writing/reorder_doc/rewrite_links_to_moved_docs E13: a CRLF doc with a BOM is written laid out with both kept', () async {
      final project = await writeWriteProject(
        extra: {'docs/$fr12': '\uFEFF${loose.replaceAll('\n', '\r\n')}'},
      );
      final text = stepText(
        writeIn(project, (s) => planRewrites(s, reorderMoves)),
        fr12,
      );
      expect(text, startsWith('\uFEFF---\r\n'));
      expect(text, contains('us01_reset_password/USER_STORY.md#use-case'));
      expect(text.replaceAll('\r\n', ''), isNot(contains('\n')));
      expect(text, isNot(contains('\r\n\r\n\r\n')));
    });

    test('document_writing/rename_doc/rewrite_name_references E07: a renamed doc_ref referrer with keys out of field order is written in order', () async {
      final project = await writeWriteProject(
        extra: {
          'docs/$story1': '---\npersona:\n  - buyer\nstatus: planned\ndraft: true\n---\n\n# Sign in with email\n',
        },
      );
      final text = stepText(
        writeIn(
          project,
          (s) => planRewrites(
            s,
            const [],
            renamed: {('persona', 'buyer'): 'shopper'},
          ),
        ),
        story1,
      );
      expect(text, contains('  - shopper\n'));
      expect(
        text.indexOf('status: planned'),
        lessThan(text.indexOf('persona:')),
      );
    });

    test('document_writing/rename_doc/rewrite_link_labels E14: a rewritten api doc with padded table cells is written compact', () async {
      final nested = await writeNestedProject();
      final file = docFile(nested, shopApi);
      file.writeAsStringSync(
        file.readAsStringSync().replaceAll(
          '| FR | Operation |\n|----|-----------|\n| cart/add_item/check_stock | `addItem` |',
          '| FR                        | Operation |\n|---------------------------|-----------|\n| cart/add_item/check_stock | `addItem` |',
        ),
      );
      writeIn(
        nested,
        (s) => answerRename(s, 'feature:shop/cart', slug: 'basket'),
      );
      final text = readDoc(nested, shopApi);
      expect(text, contains('| basket/add_item/check_stock | `addItem` |'));
      expect(text, isNot(contains('| FR                        |')));
    });
  });
  group('rewriteNameMentions', () {
    const renamed = {
      ('feature', 'login'): 'signin',
      ('user_story', 'login/email_login'): 'signin/email_login',
      ('persona', 'buyer'): 'shopper',
    };

    test('document_writing/rename_doc/rewrite_name_references E03: the Name changes, the type prefix and section key stay', () {
      expect(
        rewriteNameMentions(
          '`login/email_login`, `user_story:login/email_login#goal`, '
              '`feature:login#problem`\n',
          '.md',
          renamed,
        ),
        '`signin/email_login`, `user_story:signin/email_login#goal`, '
        '`feature:signin#problem`\n',
      );
    });

    test('document_writing/rename_doc/rewrite_name_references E03: a typed mention of another type, a one-slug bare name, and plain text stay', () {
      expect(
        rewriteNameMentions(
          '`fr:login/email_login` `login` login/email_login `persona:login`\n',
          '.md',
          renamed,
        ),
        isNull,
      );
    });

    test('document_writing/rename_doc/rewrite_name_references E03: a bare name two renamed docs call differently stays', () {
      expect(
        rewriteNameMentions('`shop/cart`\n', '.md', {
          ('feature', 'shop/cart'): 'shop/basket',
          ('user_story', 'shop/cart'): 'shop/trolley',
        }),
        isNull,
      );
    });

    test('document_writing/rename_doc/rewrite_name_references E04: a code file changes on its comment lines only', () {
      expect(
        rewriteNameMentions(
          '// `login/email_login`\nx = `login/email_login`;\n',
          '.dart',
          renamed,
        ),
        '// `signin/email_login`\nx = `login/email_login`;\n',
      );
      expect(
        rewriteNameMentions('// `login/email_login`\n', '.txt', renamed),
        isNull,
      );
    });

    test('document_writing/rename_doc/rewrite_name_references E04: two mentions on one line both change, each at its own column', () {
      expect(
        rewriteNameMentions(
          '// `login/email_login` and `feature:login`\r\n',
          '.dart',
          renamed,
        ),
        '// `signin/email_login` and `feature:signin`\r\n',
      );
    });

    test('document_writing/rename_doc/rewrite_name_references: no rename changes nothing', () {
      expect(rewriteNameMentions('`login/email_login`\n', '.md', {}), isNull);
    });
  });

  group('planRewrites code files', () {
    const entry = 'app/lib/doc.dart';
    const rename = {('user_story', 'login/email_login'): 'signin/email_login'};
    const noMoves = <PathMove>[];

    Future<Directory> withCode(String text) => writeWriteProject(
      extra: {
        'docs/specs/TECH_STACK.md':
            '---\ncode:\n  - app/lib/\n---\n\n# Tech stack\n\n## Stack\n\n'
            '| Slot | Choice |\n|---|---|\n| Language | Dart |\n\n'
            '## Naming\n\n- snake_case file names\n',
        entry: text,
      },
    );

    test('document_writing/rename_doc/rewrite_name_references E04: a code file step is listed by its project path with its rewritten text, never stamped', () async {
      root = await withCode('// `login/email_login`\n');
      final step = plan(
        noMoves,
        renamed: rename,
      ).singleWhere((s) => s.path == entry);
      expect(step.text, '// `signin/email_login`\n');
    });

    test('document_writing/rename_doc/rewrite_name_references E04: with two targets each code root is walked, and a file under a nested target root gets one step', () async {
      const mention = '// `login/email_login`\n';
      const techStack =
          '---\ncode:\n  - ./\n---\n\n# Tech stack\n\n## Stack\n\n'
          '| Slot | Choice |\n|---|---|\n| Language | Dart |\n\n'
          '## Naming\n\n- snake_case file names\n';
      root = await writeWriteProject(
        without: {'docs/$loginArch', 'docs/$signupArch'},
        extra: {
          '.specstone/config.yaml':
              '${shippedPinsConfig()}targets:\n'
              '  outer:\n    code_root: ws\n'
              '  inner:\n    code_root: ws/inner\n'
              '  apart:\n    code_root: other\n',
          'docs/specs/outer/TECH_STACK.md': techStack,
          'docs/specs/inner/TECH_STACK.md': techStack,
          'docs/specs/apart/TECH_STACK.md': techStack,
          'ws/a.dart': mention,
          'ws/inner/b.dart': mention,
          'other/c.dart': mention,
        },
      );

      final paths = plan(noMoves, renamed: rename).map((s) => s.path).toList();

      expect(paths.where((p) => p.endsWith('.dart')), [
        'other/c.dart',
        'ws/a.dart',
        'ws/inner/b.dart',
      ]);
    });

    test('document_writing/rename_doc/rewrite_name_references E04: a code file with no mention of a renamed doc gets no step, and no rename reads no code file', () async {
      root = await withCode('// `login/email_login`\n');
      expect(plan(noMoves).map((s) => s.path), isNot(contains(entry)));
      root = await withCode('// `other/name`\n');
      expect(
        plan(noMoves, renamed: rename).map((s) => s.path),
        isNot(contains(entry)),
      );
    });
  });
}
