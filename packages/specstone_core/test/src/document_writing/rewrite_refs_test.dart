// The test names and file literals are plan text kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/rewrite_refs.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

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

  test('f02/us05/fr02: an angle-bracket href and an href with a query are rewritten, a longer href sharing its prefix is not', () {
    const moves = <PathMove>[(from: 'a/f01_x/', to: 'a/f02_x/')];
    expect(
      rewriteDocLinks(
        '[x](<a/f01_x/F.md>) [q](a/f01_x/F.md?v=1) [l](a/f01_x/F.md.bak)\n',
        docPath: 'I.md',
        moves: moves,
      ),
      '[x](<a/f02_x/F.md>) [q](a/f02_x/F.md?v=1) [l](a/f01_x/F.md.bak)\n',
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
      '---\napproved: true\n---\n\n# Feature index\n\n## Systems\n- [Login](features/f02_login/FEATURE.md)\n- [Signup](features/f01_signup/FEATURE.md)\n',
    );
    expect(steps.last.text, contains('(features/f01_signup/FEATURE.md)'));
    expect(
      steps.every(
        (step) => step.path.startsWith('docs/') && step.path.endsWith('.md'),
      ),
      isTrue,
    );
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
}
