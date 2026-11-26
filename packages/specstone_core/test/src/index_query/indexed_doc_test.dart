import 'dart:convert';

import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/line_facts.dart';
import 'package:specstone_core/src/index_query/models/link_place.dart';
import 'package:specstone_core/src/index_query/models/link_places.dart';
import 'package:specstone_core/src/index_query/models/link_text.dart';
import 'package:specstone_core/src/index_query/models/section_counts.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:test/test.dart';

import '../../helpers/plain_items.dart';
import '../../helpers/record_doc_type.dart';
import '../../helpers/software_tech.dart';

MergedDocType nestedType(
  String id,
  String path, {
  String? parent,
  int? maxDepth,
}) => MergedDocType(
  id: id,
  path: path,
  parent: parent,
  maxDepth: maxDepth,
  fields: const [],
  sections: const [],
  lint: const MergedLint(),
  files: const [],
);

void main() {
  late DocTypeMatcher matcher;

  setUpAll(() async {
    matcher = DocTypeMatcher(
      await resolveSoftwareTech(),
      targetNames: const [],
    );
  });

  ParsedDoc parse(String path, String text) => parseIndexedDoc(
    docPath: path,
    bytes: utf8.encode(text),
    match: matcher.match(path),
  );

  group('runeCountOf counts what runes counts', () {
    for (final (name, text) in [
      ('an empty text', ''),
      ('ASCII', 'plain text\n'),
      ('BMP letters', 'ไทย ü \u{FF01}'),
      ('a surrogate pair', 'a\u{1F600}b'),
      ('a lone high surrogate', 'a\uD83D'),
      ('a lone low surrogate', '\uDE00a'),
      ('a low surrogate before a high one', '\uDE00\uD83D'),
    ]) {
      test(name, () => expect(runeCountOf(text), text.runes.length));
    }
  });

  test('the content hash is the bytes hash, or the one the caller holds', () {
    final bytes = utf8.encode('# Title\n');
    ParsedDoc parseWith({String? hash}) => parseIndexedDoc(
      docPath: 'notes/a.md',
      bytes: bytes,
      contentHash: hash,
      match: matcher.match('notes/a.md'),
    );

    expect(parseWith().contentHash, contentHashOf(bytes));
    expect(parseWith(hash: 'held').contentHash, 'held');
  });

  test('an FR is named by its three slugs', () {
    final doc = parse(
      'prds/features/f01_login/us02_email_login/fr01_validate_credentials.md',
      '# V\n',
    ).doc;
    expect(
      (doc.docTypeId, doc.name),
      ('fr', 'login/email_login/validate_credentials'),
    );
  });

  test('a slug-free pattern names its doc by the doc type id', () {
    for (final (path, name) in [
      ('prds/PROJECT.md', 'project'),
      ('prds/FEATURES.md', 'features'),
      ('prds/GNFR.md', 'gnfr'),
      ('specs/TECH_STACK.md', 'tech_stack'),
      ('prds/GOAL.md', 'goal'),
      ('prds/GLOSSARY.md', 'glossary'),
    ]) {
      expect(parse(path, '# T\n').doc.name, name);
    }
  });

  test('a persona and an anti-persona in one slug folder share the name', () {
    expect(parse('prds/personas/buyer/PERSONA.md', '# B\n').doc.name, 'buyer');
    expect(
      parse('prds/personas/buyer/ANTI_PERSONA.md', '# B\n').doc.name,
      'buyer',
    );
  });

  test('a spec doc carries its feature folder slug as name', () {
    final doc = parse('specs/f01_login/ARCHITECTURE.md', '# A\n').doc;
    expect((doc.docTypeId, doc.name), ('architecture', 'login'));
  });

  test('a file no doc type matches is untyped and named by its DocPath', () {
    final doc = parse(
      'prds/d01_context.md',
      '# D-01\n\n## Project vision\nx\n',
    ).doc;
    expect(
      (doc.docTypeId, doc.name, doc.isTyped),
      (null, 'prds/d01_context.md', false),
    );
  });

  test(
    'a DocPath two doc types match is untyped, with a warning naming both',
    () {
      final doc = parseIndexedDoc(
        docPath: 'prds/x.md',
        bytes: utf8.encode('# X\n'),
        match: AmbiguousDocType(['fr', 'legacy_fr']),
      ).doc;
      expect(doc.docTypeId, isNull);
      expect(doc.warnings, ['prds/x.md matches two doc types: fr, legacy_fr']);
    },
  );

  test('three doc types matching one DocPath read "3" in the warning', () {
    final doc = parseIndexedDoc(
      docPath: 'prds/x.md',
      bytes: utf8.encode('# X\n'),
      match: AmbiguousDocType(['a', 'b', 'c']),
    ).doc;
    expect(doc.warnings, ['prds/x.md matches 3 doc types: a, b, c']);
  });

  test(
    'a template header takes its id, any other header its snake_case key',
    () {
      final keys = parse(
        'prds/features/f01_login/FEATURE.md',
        '# Login\n\n## Problem\nx\n\n## Open Notes\ny\n',
      ).content.sections.map((s) => s.key);
      expect(keys, ['problem', 'open_notes']);
    },
  );

  test('the head holds the title and is no section', () {
    final parsed = parse(
      'prds/features/f01_login/FEATURE.md',
      '---\nvision: [PV-01]\n---\n\n# Login\nIntro.\n\n## Problem\nx\n',
    );
    expect(parsed.doc.title, 'Login');
    expect(parsed.content.head, contains('Intro.'));
    expect(parsed.content.sections.single.key, 'problem');
    expect(parsed.content.frontmatterText, '---\nvision: [PV-01]\n---\n');
  });

  test('a file with no frontmatter has no frontmatter values', () {
    expect(
      parse('prds/features/f01_login/FEATURE.md', '# Login\n').doc.frontmatter,
      isEmpty,
    );
  });

  test('frontmatter values, slug aliases, status, and draft are read', () {
    final doc = parse(
      'prds/features/f01_login/us01_email_login/USER_STORY.md',
      '---\nstatus: planned\ndraft: true\nslug:\n  - sign-in\n'
          'goals:\n  - PG-01\n---\n\n# S\n',
    ).doc;
    expect((doc.writtenStatus, doc.isDraft), ('planned', true));
    expect(doc.valuesOf('slug'), ['sign-in']);
    expect(doc.valuesOf('goals'), ['PG-01']);
  });

  test('links keep .md targets under the docs root only', () {
    final links = parse(
      'prds/features/f01_login/us01_email_login/fr01_validate_credentials.md',
      '# V\n\n## Statement\nSee the [story](USER_STORY.md), [site](https://x.org), [schema](../../../../specs/s.dbml), '
          'and `[not](a.md)`.\n',
    ).content.links;
    expect(links, ['prds/features/f01_login/us01_email_login/USER_STORY.md']);

    final inlineAlone = parse(
      'prds/features/f01_login/us01_email_login/fr01_validate_credentials.md',
      'See [story](USER_STORY.md)',
    ).content.links;
    expect(inlineAlone, [
      'prds/features/f01_login/us01_email_login/USER_STORY.md',
    ]);
  });

  test('a reference-style link lists its target', () {
    final links = parse(
      'prds/features/f01_login/us01_email_login/fr01_validate_credentials.md',
      '# V\n\nSee the [story][s].\n\n[s]: USER_STORY.md\n',
    ).content.links;
    expect(links, ['prds/features/f01_login/us01_email_login/USER_STORY.md']);
  });

  test('bracketed text with no link lists none', () {
    final links = parse(
      'prds/features/f01_login/us01_email_login/fr01_validate_credentials.md',
      '# V\n\nA [x] note, an array a[0], and https://example.org/a.md.\n',
    ).content.links;
    expect(links, isEmpty);
  });

  test('sizes are code points divided by 4, rounded down', () {
    expect(tokenSizeOf('a' * 401), 100);
    expect(tokenSizeOf('ค้นหา' * 4), 5);
    final parsed = parse(
      'prds/features/f01_login/FEATURE.md',
      '# L\n\n## Problem\n${'x' * 40}\n',
    );
    expect(parsed.doc.tokens, tokenSizeOf('# L\n\n## Problem\n${'x' * 40}\n'));
    expect(
      parsed.content.sections.single.tokens,
      tokenSizeOf('## Problem\n${'x' * 40}'),
    );
  });

  test('a CRLF doc parses as its LF form and keeps its own text', () {
    final crlf = parse(
      'prds/features/f01_login/FEATURE.md',
      '# L\r\n\r\n## Problem\r\nx\r\n',
    );
    expect(crlf.content.sections.single.key, 'problem');
    expect(crlf.content.text, '# L\r\n\r\n## Problem\r\nx\r\n');
  });

  test('invalid UTF-8 is decoded with replacement characters '
      'and warned about', () {
    final parsed = parseIndexedDoc(
      docPath: 'README.md',
      bytes: [0x23, 0x20, 0xFF, 0x0A],
      match: const NoDocType(),
    );
    expect(parsed.content.text, '# �\n');
    expect(parsed.doc.warnings, [
      'README.md: not UTF-8 text; indexed with replacement characters',
    ]);
  });

  test('frontmatter that is not YAML leaves no values and warns', () {
    final doc = parse(
      'prds/features/f01_login/FEATURE.md',
      '---\nvision: [PV-01\n---\n\n# L\n',
    ).doc;
    expect(doc.frontmatter, isEmpty);
    expect(doc.warnings, [
      'prds/features/f01_login/FEATURE.md: frontmatter is not valid YAML; its values are not indexed',
    ]);
  });

  test('a typed doc the parser fails on keeps its title, frontmatter values, '
      'and sections', () {
    final parsed = parse(
      'prds/features/f01_login/FEATURE.md',
      '---\nvision: [PV-01]\n---\n\n# Login\n\n## Problem\n'
          'See [y](y.md).\n\n[a]:<b\\',
    );

    expect(parsed.doc.title, 'Login');
    expect(parsed.doc.valuesOf('vision'), ['PV-01']);
    expect(parsed.content.sections.map((s) => s.key), ['problem']);
    expect(parsed.content.links, isEmpty);
    expect(parsed.doc.warnings, [
      markdownUnparsedWarning('prds/features/f01_login/FEATURE.md'),
    ]);
    expect(parsed.content.itemFacts.sectionItems, hasLength(1));
  });

  test(
    'the warning of a doc names the parser failing on it, or the link '
    'scan and the parser reading its links differently, and nothing else',
    () {
      const agreeing = LinkPlaces(
        docLinks: <LinkPlace>[],
        fileLinks: <LinkPlace>[],
        selfLinks: <LinkPlace>[],
        texts: <LinkText>[],
        addressTexts: <LinkText>[],
        readersAgree: true,
      );
      final disagreeing = LinkPlaces(
        docLinks: agreeing.docLinks,
        fileLinks: agreeing.fileLinks,
        selfLinks: agreeing.selfLinks,
        texts: agreeing.texts,
        addressTexts: agreeing.addressTexts,
        readersAgree: false,
      );

      expect(
        linkWarningOf('prds/x.md', null),
        markdownUnparsedWarning('prds/x.md'),
      );
      expect(linkWarningOf('prds/x.md', agreeing), isNull);
      expect(
        linkWarningOf('prds/x.md', disagreeing),
        'prds/x.md: the link scan and the markdown parser list its links '
        'differently; a move or rename leaves its inline links as written, and '
        'check skips its see links',
      );
    },
  );

  test('a doc with footnotes and folded labels is indexed with no link '
      'warning', () {
    final parsed = parseIndexedDoc(
      docPath: 'prds/x.md',
      bytes: utf8.encode(
        '# X\n\n## A\n[^1]: Also [b](b.md).\nSee [y](y.md), [q][ẞ], '
        'and [s [^1]](s.md).\n\n[ss]: z.md\n[^2]: [c](c.md)\n',
      ),
      match: const NoDocType(),
    );

    expect(parsed.doc.warnings, isEmpty);
    expect(parsed.content.links, ['prds/b.md', 'prds/y.md', 'prds/z.md']);
  });

  test('an undeclared header keys as lowercase words joined by _', () {
    expect(sectionKeyOf('Project vision'), 'project_vision');
    expect(
      sectionKeyOf('Assumptions & rabbit holes'),
      'assumptions_rabbit_holes',
    );
    expect(sectionKeyOf('Root-schema'), 'root_schema');
    expect(sectionKeyOf('ค้นหา เอกสาร'), 'ค้นหา_เอกสาร');
    expect(sectionKeyOf('_Lead_'), 'lead');
    expect(sectionKeyOf('---'), '');
    expect(sectionKeyOf('_'), '');
  });

  test('the reserved lead key is _lead', () {
    expect(leadKey, '_lead');
  });

  test('a nested story is named shop/cart/add_item', () {
    const storyPath =
        'prds/features/f01_shop/f01_cart/us01_add_item/USER_STORY.md';
    const domainPath = 'specs/f01_shop/f01_cart/DOMAIN.md';
    final nested = DocTypeMatcher(
      MergedSet(
        docTypes: [
          nestedType(
            'feature',
            'prds/features/f{nn}_{slug}/FEATURE.md',
            maxDepth: 1,
          ),
          nestedType(
            'user_story',
            'prds/features/f{nn}_{slug}/us{nn}_{slug}/USER_STORY.md',
            parent: 'feature',
          ),
          nestedType(
            'rulebook',
            'specs/f{nn}_{slug}/DOMAIN.md',
            parent: 'feature',
          ),
        ],
      ),
      targetNames: const [],
    );

    String nameOf(String path) => parseIndexedDoc(
      docPath: path,
      bytes: utf8.encode('# T\n'),
      match: nested.match(path),
    ).doc.name;

    expect(nameOf(storyPath), 'shop/cart/add_item');
    expect(nameOf(domainPath), 'shop/cart');
  });

  test(
    'both target twins index with their own target and one target-free name',
    () {
      for (final (pattern, twins) in [
        (
          'specs/f{nn}_{slug}/f{nn}_{slug}/ARCHITECTURE.md',
          [
            (
              'specs/jaspr/f02_feedback/f03_toast/ARCHITECTURE.md',
              'jaspr',
              'feedback/toast',
            ),
            (
              'specs/flutter/f02_feedback/f03_toast/ARCHITECTURE.md',
              'flutter',
              'feedback/toast',
            ),
          ],
        ),
        (
          'specs/f{nn}_{slug}/ARCHITECTURE.md',
          [
            ('specs/flutter/f01_login/ARCHITECTURE.md', 'flutter', 'login'),
            ('specs/jaspr/f01_login/ARCHITECTURE.md', 'jaspr', 'login'),
          ],
        ),
      ]) {
        final targeted = DocTypeMatcher(
          MergedSet(
            docTypes: [
              nestedType('architecture', pattern).copyWith(isPerTarget: true),
            ],
          ),
          targetNames: const ['flutter', 'jaspr'],
        );

        for (final (path, target, name) in twins) {
          final doc = parseIndexedDoc(
            docPath: path,
            bytes: utf8.encode('# T\n'),
            match: targeted.match(path),
          ).doc;
          expect((doc.target, doc.name), (target, name), reason: path);
        }
      }
    },
  );

  test('with two targets a '
      'target-free spec path and an unknown target folder index untyped', () {
    final targeted = DocTypeMatcher(
      MergedSet(
        docTypes: [
          nestedType(
            'architecture',
            'specs/f{nn}_{slug}/ARCHITECTURE.md',
          ).copyWith(isPerTarget: true),
        ],
      ),
      targetNames: const ['flutter', 'jaspr'],
    );

    for (final path in [
      'specs/f02_feedback/ARCHITECTURE.md',
      'specs/web/f02_feedback/ARCHITECTURE.md',
    ]) {
      final doc = parseIndexedDoc(
        docPath: path,
        bytes: utf8.encode('# T\n'),
        match: targeted.match(path),
      ).doc;
      expect((doc.isTyped, doc.target), (false, null), reason: path);
      expect(doc.name, path);
    }
  });

  test('one target, named '
      'or not, gives a per-target doc that target and a PRD doc none', () {
    final oneNamed = DocTypeMatcher(
      MergedSet(
        docTypes: [
          nestedType('feature', 'prds/features/f{nn}_{slug}/FEATURE.md'),
          nestedType(
            'architecture',
            'specs/f{nn}_{slug}/ARCHITECTURE.md',
          ).copyWith(isPerTarget: true),
        ],
      ),
      targetNames: const ['flutter'],
    );

    (bool, String?) indexed(String path, {String? codeTarget}) {
      final doc = parseIndexedDoc(
        docPath: path,
        bytes: utf8.encode('# T\n'),
        match: oneNamed.match(path),
        codeTarget: codeTarget,
      ).doc;
      return (doc.isTyped, doc.target);
    }

    expect(indexed('specs/f01_login/ARCHITECTURE.md', codeTarget: 'flutter'), (
      true,
      'flutter',
    ));
    // One unnamed target (`code_root:` alone or no code root): the doc takes
    // that target, which has no name to store.
    expect(indexed('specs/f01_login/ARCHITECTURE.md'), (true, null));
    expect(
      indexed('prds/features/f01_login/FEATURE.md', codeTarget: 'flutter'),
      (true, null),
      reason: 'every PRD doc is shared',
    );
  });

  test('a per-target doc of a pattern with no folder drops '
      'its target folder at the front, so twins share the name', () {
    final notes = nestedType('note', '{slug}.md').copyWith(isPerTarget: true);

    expect(docNameOf('flutter/notes.md', notes, target: 'flutter'), 'notes');
    expect(docNameOf('jaspr/notes.md', notes, target: 'jaspr'), 'notes');
    expect(docNameOf('notes.md', notes), 'notes');
  });

  group('formatted and laid-out counts', () {
    const featurePath = 'prds/features/f01_login/FEATURE.md';
    const padded =
        '# F\n\n## Problem\n### Sub\ntext\n\n'
        '| a   | b    |\n|-----|------|\n| 1   | 22   |\n';
    const laidOut =
        '# F\n\n## Problem\n\n### Sub\n\ntext\n\n'
        '| a | b |\n|---|---|\n| 1 | 22 |\n';
    const problemBody = '\n### Sub\n\ntext\n\n| a | b |\n|---|---|\n| 1 | 22 |';

    test('a doc that differs '
        'from its layout is not formatted and counts the laid-out text', () {
      final facts = parse(featurePath, padded);
      expect(facts.doc.formatted, isFalse);
      final counts = facts.content.lineFacts;
      expect(counts.lineCount, nonBlankLinesOf(laidOut));
      expect(counts.charCount, laidOut.length);
      expect(counts.sectionCounts, [
        SectionCounts(
          lines: nonBlankLinesOf(problemBody),
          chars: problemBody.length,
        ),
      ]);
      expect(counts.sectionLines, [3]);
      final after = parse(featurePath, laidOut);
      expect(after.doc.formatted, isTrue);
      expect(after.content.lineFacts.charCount, laidOut.length);
      expect(after.content.lineFacts.sectionCounts, counts.sectionCounts);
    });

    test('a refused doc has no formatted value and counts '
        'its text on disk', () {
      for (final text in [
        '# F\n\n## Bogus\nx  y\n',
        '# F\n\n## Problem\n```\nopen  \n',
      ]) {
        final parsed = parse(featurePath, text);
        expect(parsed.doc.formatted, isNull, reason: text);
        expect(parsed.content.lineFacts.charCount, text.length);
        expect(parsed.content.lineFacts.lineCount, nonBlankLinesOf(text));
      }
    });

    test(
      'a fence nested in a list item is code to the index and the layout alike',
      () {
        const nested =
            '# F\n\n## Problem\n\n1. Run:\n\n    ```sh\n    echo "a  b"   \n'
            '    ## not a section\n    ```\n';
        final parsed = parse(featurePath, nested);
        expect(parsed.doc.formatted, isTrue);
        expect([for (final s in parsed.content.sections) s.key], ['problem']);
      },
    );

    test('a doc with an open generated block has no formatted value', () {
      final open = generatedOpenMarker('journey_flow');
      for (final end in ['', '$generatedEndMarker  \n']) {
        final disk = '# J\n\n## Flow\n\n$open\n| a     | b |\n|---|---|\n$end';
        final parsed = parse('prds/journeys/buy/JOURNEY.md', disk);
        expect(parsed.doc.formatted, isNull, reason: disk);
        expect(parsed.content.lineFacts.charCount, disk.length);
      }
    });

    test('a doc that is not UTF-8, which format skips, has no formatted value '
        'and counts its text as read', () {
      const invalidByte = 0xFF;
      final bytes = [...utf8.encode(padded), invalidByte, ...utf8.encode('\n')];
      final parsed = parseIndexedDoc(
        docPath: featurePath,
        bytes: bytes,
        match: matcher.match(featurePath),
      );
      final read = utf8.decode(bytes, allowMalformed: true);
      expect(parsed.doc.formatted, isNull);
      expect(parsed.content.lineFacts.charCount, read.length);
    });

    test('an untyped doc has no formatted value', () {
      expect(parse('notes/a.md', '# A\n').doc.formatted, isNull);
    });

    test('CRLF line ends alone leave a doc formatted', () {
      final parsed = parse(featurePath, laidOut.replaceAll('\n', '\r\n'));
      expect(parsed.doc.formatted, isTrue);
    });

    test('a generated block counts as on disk while '
        'padding outside it is laid out', () {
      final open = generatedOpenMarker('journey_flow');
      const block = '| a   | b |\n|-----|---|';
      final disk =
          '# J\n\n## Goal\n\n| x   | y |\n|-----|---|\n\n'
          '## Flow\n\n$open\n$block\n$generatedEndMarker\n';
      final parsed = parse('prds/journeys/buy/JOURNEY.md', disk);
      expect(parsed.doc.formatted, isFalse);
      const goal = '\n| x | y |\n|---|---|';
      final flow = '\n$open\n$block\n$generatedEndMarker';
      expect(parsed.content.lineFacts.sectionCounts, [
        SectionCounts(lines: nonBlankLinesOf(goal), chars: goal.length),
        SectionCounts(lines: nonBlankLinesOf(flow), chars: flow.length),
      ]);
    });
  });

  group("a record's size counts", () {
    const recordPath = 'specs/f02_feedback/IMPLEMENTATION.md';
    const notes = MergedSection(id: 'notes', header: 'Notes');
    const questions = MergedSection(id: 'questions', header: 'Questions');
    final withMatrix = recordDocType(
      sections: [notes, matrixSection, questions],
    );

    ParsedDoc parseRecord(
      String text, {
      MergedDocType? type,
      bool crlf = false,
    }) => parseIndexedDoc(
      docPath: recordPath,
      bytes: utf8.encode(crlf ? text.replaceAll('\n', '\r\n') : text),
      match: DocTypeMatcher(
        MergedSet(docTypes: [type ?? withMatrix]),
        targetNames: const [],
      ).match(recordPath),
    );

    const head = '---\nkey: value\n---\n\n# Feedback implementation\n';
    const notesBody = '\n## Notes\n\nfirst\n';
    const questionsBody = '\n## Questions\n\nlast\n';
    const rows =
        '- a/b E01: `one`\n'
        '- a/b E02: `emoji \u{1F600} case`\n'
        '- a/b E03 skipped: no test can prove it\n';
    const matrixBody = '\n## Verification matrix\n\n$rows';

    void expectCountsLeaveOut(String withSection, String without) {
      final facts = parseRecord(withSection).content.lineFacts;
      final plain = parseRecord(without).content.lineFacts;
      expect(facts.lineCount, plain.lineCount);
      expect(facts.charCount, plain.charCount);
    }

    test('leave out its matrix section, whichever section follows it', () {
      expectCountsLeaveOut(
        '$head$notesBody$matrixBody$questionsBody',
        '$head$notesBody$questionsBody',
      );
      expectCountsLeaveOut('$head$notesBody$matrixBody', '$head$notesBody');
      expectCountsLeaveOut('$head$matrixBody', head);
    });

    test('leave out its matrix section from the laid-out text', () {
      const padded =
          '\n## Notes\n\n| a   | b    |\n|-----|------|\n| 1   | 22   |\n';
      const laidOut = '\n## Notes\n\n| a | b |\n|---|---|\n| 1 | 22 |\n';
      final parsed = parseRecord('$head$padded$matrixBody$questionsBody');
      expect(parsed.doc.formatted, isFalse);
      const expected = '$head$laidOut$questionsBody';
      final facts = parsed.content.lineFacts;
      expect(facts.charCount, expected.length);
      expect(
        facts.lineCount,
        nonBlankLinesOf('# Feedback implementation\n$laidOut$questionsBody'),
      );
    });

    test('leave out a matrix section with no rows', () {
      expectCountsLeaveOut(
        '$head$notesBody\n## Verification matrix\n$questionsBody',
        '$head$notesBody$questionsBody',
      );
    });

    test('count a record with no matrix section as laid out', () {
      final facts = parseRecord('$head$notesBody').content.lineFacts;
      expect(
        facts.lineCount,
        nonBlankLinesOf('# Feedback implementation\n$notesBody'),
      );
      expect(facts.charCount, '$head$notesBody'.length);
    });

    test('leave out its matrix section when the doc is not laid out', () {
      const bogus = '\n## Bogus\n\nx  y\n';
      final parsed = parseRecord('$head$bogus$matrixBody');
      expect(parsed.doc.formatted, isNull);
      final plain = parseRecord(
        '$head$bogus',
        type: withMatrix,
      ).content.lineFacts;
      expect(parsed.content.lineFacts.lineCount, plain.lineCount);
      expect(parsed.content.lineFacts.charCount, plain.charCount);
    });

    test('leave out its matrix section when the doc has CRLF line ends', () {
      const text = '$head$notesBody$matrixBody$questionsBody';
      final crlf = parseRecord(text, crlf: true).content.lineFacts;
      final lf = parseRecord(text).content.lineFacts;
      expect(crlf.lineCount, lf.lineCount);
      expect(crlf.charCount, lf.charCount);
    });

    test('name one section the matrix for its rows, counts, and approval hash '
        'whatever its header spelling', () {
      const spelled = '\n##  VERIFICATION   Matrix\n\n$rows';
      final parsed = parseRecord('$head$notesBody$spelled$questionsBody');
      final plain = parseRecord('$head$notesBody$questionsBody');
      expect(parsed.doc.matrixLines, hasLength(3));
      expect(parsed.doc.approvalHash, plain.doc.approvalHash);
      expect(
        parsed.content.lineFacts.lineCount,
        plain.content.lineFacts.lineCount,
      );
      expect(
        parsed.content.lineFacts.charCount,
        plain.content.lineFacts.charCount,
      );
    });

    test("keep the matrix section's own counts", () {
      const section = '\n$rows';
      final facts = parseRecord('$head$notesBody$matrixBody$questionsBody')
          .content
          .lineFacts;
      expect(
        facts.sectionCounts[1],
        SectionCounts(
          lines: nonBlankLinesOf(section),
          chars: section.trimRight().runes.length,
        ),
      );
    });

    test(
      'count a section of that name in a doc type with no matrix section',
      () {
        final plain = recordDocType(sections: [notes, questions]);
        const text = '$head$notesBody$matrixBody$questionsBody';
        final facts = parseRecord(text, type: plain).content.lineFacts;
        expect(facts.charCount, text.runes.length);
        expect(
          facts.lineCount,
          nonBlankLinesOf(
            '# Feedback implementation\n$notesBody$matrixBody$questionsBody',
          ),
        );
      },
    );
  });

  group('mermaid blocks', () {
    const frPath =
        'prds/features/f01_login/us01_email_login/fr01_validate_credentials.md';
    const text =
        '# T\n\n```mermaid\npie\n```\n\n```mermaid\nflowchart TD\n```\n';

    test('a typed doc stores one block per mermaid fence', () {
      final blocks = parse(frPath, text).content.lineFacts.mermaidBlocks;

      expect([for (final b in blocks) b.fenceLine], [3, 7]);
      expect(blocks[0].hash, isNot(blocks[1].hash));
    });

    test('an untyped doc stores no block', () {
      expect(
        parse('notes/a.md', text).content.lineFacts.mermaidBlocks,
        isEmpty,
      );
    });
  });

  group('item facts', () {
    const frPath =
        'prds/features/f01_login/us01_email_login/fr01_validate_credentials.md';
    const drifted =
        '# Validate credentials\n\nLead.\n\n## Edge cases\n'
        '1. E01 — A wrong password → refused\n\n'
        '## Statement\nThe system shall check it.\n';

    test('docStructureOf gives '
        'item facts that count its own text with no layout', () {
      final type = (matcher.match(frPath) as MatchedDocType).docType;
      final facts = docStructureOf(drifted, type).itemFacts;

      expect(facts.lead, const SectionCounts(lines: 1, chars: 5));
      expect(plainSections(facts), [
        [(id: 'E01', line: 6, chars: 35)],
        [(id: null, line: 9, chars: 26)],
      ]);
    });

    test('docStructureOf with '
        'no doc type gives items with no ID', () {
      final facts = docStructureOf(
        '# T\n\n## Notes\n1. E01 — a\n',
        null,
      ).itemFacts;

      expect(facts.sectionItems.single.single.id, isNull);
    });
  });
}

/// The non-blank lines of [text], the expected line counts.
int nonBlankLinesOf(String text) =>
    text.split('\n').where((line) => line.trim().isNotEmpty).length;
