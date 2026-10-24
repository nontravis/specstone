import 'dart:convert';

import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:test/test.dart';

import '../../helpers/software_tech.dart';

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

  test('f01/us01/fr03/e07, s03/inv4: a template header takes its id, any other header its heading slug', () {
    final keys = parse(
      'prds/features/f01_login/FEATURE.md',
      '# Login\n\n## Problem\nx\n\n## Open Notes\ny\n',
    ).content.sections.map((s) => s.key);
    expect(keys, ['problem', 'open-notes']);
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

  test('s03/inv4: heading slugs lowercase, drop punctuation, and turn spaces into hyphens', () {
    expect(headingSlug('Project vision'), 'project-vision');
    expect(
      headingSlug('Assumptions & rabbit holes'),
      'assumptions--rabbit-holes',
    );
    expect(headingSlug('ค้นหา เอกสาร'), 'ค้นหา-เอกสาร');
  });
}
