import 'dart:convert';

import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/line_facts.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:test/test.dart';

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
    matcher = DocTypeMatcher(await resolveSoftwareTech());
  });

  ParsedDoc parse(String path, String text) => parseIndexedDoc(
    docPath: path,
    bytes: utf8.encode(text),
    match: matcher.match(path),
  );

  test('f01/us01/fr03/e01, s03/inv5: an FR is named by its three slugs', () {
    final doc = parse(
      'prds/features/f01_login/us02_email_login/fr01_validate_credentials.md',
      '# V\n',
    ).doc;
    expect(
      (doc.docTypeId, doc.name),
      ('fr', 'login/email_login/validate_credentials'),
    );
  });

  test('f01/us01/fr03/e02, s03/inv5: a slug-free pattern names its doc by the doc type id', () {
    for (final (path, name) in [
      ('prds/PROJECT.md', 'project'),
      ('prds/FEATURES.md', 'features'),
      ('prds/GNFR.md', 'gnfr'),
      ('specs/TECH_STACK.md', 'tech_stack'),
    ]) {
      expect(parse(path, '# T\n').doc.name, name);
    }
  });

  test('f01/us01/fr03/e03: a persona and an anti-persona in one slug folder share the name', () {
    expect(parse('prds/personas/buyer/PERSONA.md', '# B\n').doc.name, 'buyer');
    expect(
      parse('prds/personas/buyer/ANTI_PERSONA.md', '# B\n').doc.name,
      'buyer',
    );
  });

  test(
    'f01/us01/fr03/e04: a spec doc carries its feature folder slug as name',
    () {
      final doc = parse('specs/f01_login/ARCHITECTURE.md', '# A\n').doc;
      expect((doc.docTypeId, doc.name), ('architecture', 'login'));
    },
  );

  test('f01/us01/fr03/e05, s03/inv8: a file no doc type matches is untyped and named by its DocPath', () {
    final doc = parse(
      'prds/d01_context.md',
      '# D-01\n\n## Project vision\nx\n',
    ).doc;
    expect(
      (doc.docTypeId, doc.name, doc.isTyped),
      (null, 'prds/d01_context.md', false),
    );
  });

  test('f01/us01/fr03/e06, s03/inv8: a DocPath two doc types match is untyped, with a warning naming both', () {
    final doc = parseIndexedDoc(
      docPath: 'prds/x.md',
      bytes: utf8.encode('# X\n'),
      match: AmbiguousDocType(['fr', 'legacy_fr']),
    ).doc;
    expect(doc.docTypeId, isNull);
    expect(doc.warnings, ['prds/x.md matches two doc types: fr, legacy_fr']);
  });

  test('f01/us01/fr03/e06, plan decision 7: three doc types matching one DocPath read "3" in the warning', () {
    final doc = parseIndexedDoc(
      docPath: 'prds/x.md',
      bytes: utf8.encode('# X\n'),
      match: AmbiguousDocType(['a', 'b', 'c']),
    ).doc;
    expect(doc.warnings, ['prds/x.md matches 3 doc types: a, b, c']);
  });

  test('f01/us01/fr03/e07, s03/inv4: a template header takes its id, any other header its snake_case key', () {
    final keys = parse(
      'prds/features/f01_login/FEATURE.md',
      '# Login\n\n## Problem\nx\n\n## Open Notes\ny\n',
    ).content.sections.map((s) => s.key);
    expect(keys, ['problem', 'open_notes']);
  });

  test(
    'f01/us01/fr03/e08, s03/inv4: the head holds the title and is no section',
    () {
      final parsed = parse(
        'prds/features/f01_login/FEATURE.md',
        '---\nvision: [PV-01]\n---\n\n# Login\nIntro.\n\n## Problem\nx\n',
      );
      expect(parsed.doc.title, 'Login');
      expect(parsed.content.head, contains('Intro.'));
      expect(parsed.content.sections.single.key, 'problem');
      expect(parsed.content.frontmatterText, '---\nvision: [PV-01]\n---\n');
    },
  );

  test(
    'f01/us01/fr03/e09: a file with no frontmatter has no frontmatter values',
    () {
      expect(
        parse(
          'prds/features/f01_login/FEATURE.md',
          '# Login\n',
        ).doc.frontmatter,
        isEmpty,
      );
    },
  );

  test('f01/us01/fr03: frontmatter values, slug aliases, status, and draft are read', () {
    final doc = parse(
      'prds/features/f01_login/us01_email_login/USER_STORY.md',
      '---\nstatus: planned\ndraft: true\nslug:\n  - sign-in\n'
          'goals:\n  - PG-01\n---\n\n# S\n',
    ).doc;
    expect((doc.writtenStatus, doc.isDraft), ('planned', true));
    expect(doc.valuesOf('slug'), ['sign-in']);
    expect(doc.valuesOf('goals'), ['PG-01']);
  });

  test('f01/us01/fr03: links keep .md targets under the docs root only', () {
    final links = parse(
      'prds/features/f01_login/us01_email_login/fr01_validate_credentials.md',
      '# V\n\n## Statement\nSee the [story](USER_STORY.md), [site](https://x.org), [schema](../../../../specs/s.dbml), '
          'and `[not](a.md)`.\n',
    ).content.links;
    expect(links, ['prds/features/f01_login/us01_email_login/USER_STORY.md']);
  });

  test('f01/us07/fr02, s03/inv19: a reference-style link lists its target', () {
    final links = parse(
      'prds/features/f01_login/us01_email_login/fr01_validate_credentials.md',
      '# V\n\nSee the [story][s].\n\n[s]: USER_STORY.md\n',
    ).content.links;
    expect(links, ['prds/features/f01_login/us01_email_login/USER_STORY.md']);
  });

  test('f01/us07/fr02, s03/inv19: an inline link alone lists its target', () {
    final links = parse(
      'prds/features/f01_login/us01_email_login/fr01_validate_credentials.md',
      'See [story](USER_STORY.md)',
    ).content.links;
    expect(links, ['prds/features/f01_login/us01_email_login/USER_STORY.md']);
  });

  test('f01/us07/fr02, s03/inv19: bracketed text with no link lists none', () {
    final links = parse(
      'prds/features/f01_login/us01_email_login/fr01_validate_credentials.md',
      '# V\n\nA [x] note, an array a[0], and https://example.org/a.md.\n',
    ).content.links;
    expect(links, isEmpty);
  });

  test(
    'f01/us01/fr03, s03/inv9: sizes are code points divided by 4, rounded down',
    () {
      expect(tokenSizeOf('a' * 401), 100);
      expect(tokenSizeOf('ค้นหา' * 4), 5);
      final parsed = parse(
        'prds/features/f01_login/FEATURE.md',
        '# L\n\n## Problem\n${'x' * 40}\n',
      );
      expect(
        parsed.doc.tokens,
        tokenSizeOf('# L\n\n## Problem\n${'x' * 40}\n'),
      );
      expect(
        parsed.content.sections.single.tokens,
        tokenSizeOf('## Problem\n${'x' * 40}'),
      );
    },
  );

  test(
    'review focus 5: a CRLF doc parses as its LF form and keeps its own text',
    () {
      final crlf = parse(
        'prds/features/f01_login/FEATURE.md',
        '# L\r\n\r\n## Problem\r\nx\r\n',
      );
      expect(crlf.content.sections.single.key, 'problem');
      expect(crlf.content.text, '# L\r\n\r\n## Problem\r\nx\r\n');
    },
  );

  test('review focus 2: invalid UTF-8 is decoded with replacement characters '
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

  test(
    'review focus 3: frontmatter that is not YAML leaves no values and warns',
    () {
      final doc = parse(
        'prds/features/f01_login/FEATURE.md',
        '---\nvision: [PV-01\n---\n\n# L\n',
      ).doc;
      expect(doc.frontmatter, isEmpty);
      expect(doc.warnings, [
        'prds/features/f01_login/FEATURE.md: frontmatter is not valid YAML; its values are not indexed',
      ]);
    },
  );

  test('f01/us01/fr03/e12, s03/inv24, LP3: a doc the parser fails on is indexed with no links and the warning', () {
    final parsed = parseIndexedDoc(
      docPath: 'prds/x.md',
      bytes: utf8.encode('# X\n\n## A\nSee [y](y.md).\n\n[a]:<b\\'),
      match: const NoDocType(),
    );

    expect(parsed.content.links, isEmpty);
    expect(parsed.doc.warnings, [markdownUnparsedWarning('prds/x.md')]);
    expect(parsed.content.sections.map((s) => s.key), ['a']);
  });

  test('f01/us01/fr03/e13, is-s03/inv4: an undeclared header keys as lowercase words joined by _', () {
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

  test('f01/us01/fr03/e14, is-s03/inv4: the reserved lead key is _lead', () {
    expect(leadKey, '_lead');
  });

  test(
    'f01/us01/fr03/e15, sf-r6: a nested story is named shop/cart/add_item',
    () {
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
              'domain',
              'specs/f{nn}_{slug}/DOMAIN.md',
              parent: 'feature',
            ),
          ],
        ),
      );

      String nameOf(String path) => parseIndexedDoc(
        docPath: path,
        bytes: utf8.encode('# T\n'),
        match: nested.match(path),
      ).doc.name;

      expect(nameOf(storyPath), 'shop/cart/add_item');
      expect(nameOf(domainPath), 'shop/cart');
    },
  );

  group('formatted and laid-out counts', () {
    const featurePath = 'prds/features/f01_login/FEATURE.md';
    const padded =
        '# F\n\n## Problem\n### Sub\ntext\n\n'
        '| a   | b    |\n|-----|------|\n| 1   | 22   |\n';
    const laidOut =
        '# F\n\n## Problem\n\n### Sub\n\ntext\n\n'
        '| a | b |\n|---|---|\n| 1 | 22 |\n';
    const problemText =
        '## Problem\n\n### Sub\n\ntext\n\n| a | b |\n|---|---|\n| 1 | 22 |';

    test('index_query/read_current_docs/index_each_doc E18: a doc that differs '
        'from its layout is not formatted and counts the laid-out text', () {
      final facts = parse(featurePath, padded);
      expect(facts.doc.formatted, isFalse);
      final counts = facts.content.lineFacts;
      expect(counts.lineCount, laidOut.split('\n').length - 1);
      expect(counts.charCount, laidOut.length);
      expect(counts.sectionCounts, [
        (lines: problemText.split('\n').length, chars: problemText.length),
      ]);
      expect(counts.sectionLines, [3]);
      final after = parse(featurePath, laidOut);
      expect(after.doc.formatted, isTrue);
      expect(after.content.lineFacts.charCount, laidOut.length);
      expect(after.content.lineFacts.sectionCounts, counts.sectionCounts);
    });

    test('index_query/read_current_docs/index_each_doc E19: a refused doc has no formatted value and counts '
        'its text on disk', () {
      for (final text in [
        '# F\n\n## Bogus\nx  y\n',
        '# F\n\n## Problem\n```\nopen  \n',
      ]) {
        final parsed = parse(featurePath, text);
        expect(parsed.doc.formatted, isNull, reason: text);
        expect(parsed.content.lineFacts.charCount, text.length);
        expect(parsed.content.lineFacts.lineCount, text.split('\n').length - 1);
      }
    });

    test('index_query/read_current_docs/index_each_doc: an untyped doc has no formatted value', () {
      expect(parse('notes/a.md', '# A\n').doc.formatted, isNull);
    });

    test('index_query/read_current_docs/index_each_doc: CRLF line ends alone leave a doc formatted', () {
      final parsed = parse(featurePath, laidOut.replaceAll('\n', '\r\n'));
      expect(parsed.doc.formatted, isTrue);
    });

    test('index_query/read_current_docs/index_each_doc R31: a generated block counts as on disk while '
        'padding outside it is laid out', () {
      final open = generatedOpenMarker('journey_flow');
      const block = '| a   | b |\n|-----|---|';
      final disk =
          '# J\n\n## Goal\n\n| x   | y |\n|-----|---|\n\n'
          '## Flow\n\n$open\n$block\n$generatedEndMarker\n';
      final parsed = parse('prds/journeys/buy/JOURNEY.md', disk);
      expect(parsed.doc.formatted, isFalse);
      const goal = '## Goal\n\n| x | y |\n|---|---|';
      final flow = '## Flow\n\n$open\n$block\n$generatedEndMarker';
      expect(parsed.content.lineFacts.sectionCounts, [
        (lines: goal.split('\n').length, chars: goal.length),
        (lines: flow.split('\n').length, chars: flow.length),
      ]);
    });
  });
}
