import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/parents.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:test/test.dart';

import '../../helpers/software_tech.dart';

void main() {
  late MergedSet set;
  setUpAll(() async => set = await resolveSoftwareTech());
  IndexedDoc doc(String path, String type, String name) => IndexedDoc(
    docPath: path,
    docTypeId: type,
    name: name,
    frontmatter: const {},
    tokens: 0,
  );

  group('resolveParents', () {
    test('f01/us01/fr03/e01, s03/inv7: an FR has its story as parent, a story its feature', () {
      final result = resolveParents([
        doc('prds/features/f01_login/FEATURE.md', 'feature', 'login'),
        doc(
          'prds/features/f01_login/us02_email_login/USER_STORY.md',
          'user_story',
          'login/email_login',
        ),
        doc(
          'prds/features/f01_login/us02_email_login/fr01_validate_credentials.md',
          'fr',
          'login/email_login/validate_credentials',
        ),
      ], set);
      expect(result.parents, {
        'prds/features/f01_login/us02_email_login/USER_STORY.md':
            'prds/features/f01_login/FEATURE.md',
        'prds/features/f01_login/us02_email_login/fr01_validate_credentials.md':
            'prds/features/f01_login/us02_email_login/USER_STORY.md',
      });
      expect(result.warnings, isEmpty);
    });
    test('f01/us01/fr03/e04, f01/us01/fr03/e11, s03/inv7: spec docs of f01_login and f02_login take the feature login', () {
      final result = resolveParents([
        doc('prds/features/f01_login/FEATURE.md', 'feature', 'login'),
        doc('specs/f01_login/ARCHITECTURE.md', 'architecture', 'login'),
        doc('specs/f02_login/API.md', 'api', 'login'),
      ], set);
      expect(result.parents, {
        'specs/f01_login/ARCHITECTURE.md': 'prds/features/f01_login/FEATURE.md',
        'specs/f02_login/API.md': 'prds/features/f01_login/FEATURE.md',
      });
    });
    test('f01/us01/fr03/e10, s03/inv7: two candidate parents give no parent and a warning naming both', () {
      const story = 'prds/features/f01_login/us02_email_login/USER_STORY.md';
      final result = resolveParents([
        doc('prds/features/f01_login/FEATURE.md', 'feature', 'login'),
        doc('prds/features/f03_login/FEATURE.md', 'feature', 'login'),
        doc(story, 'user_story', 'login/email_login'),
      ], set);
      expect(result.parents, isEmpty);
      expect(result.warnings, {
        story:
            '$story has two candidate parent docs: prds/features/f01_login/FEATURE.md, '
            'prds/features/f03_login/FEATURE.md; it has no parent doc',
      });
    });
    test('f01/us01/fr02/e01, s03/inv7: the candidates are listed in DocPath order whatever the order of the docs', () {
      const story = 'prds/features/f01_login/us02_email_login/USER_STORY.md';
      final result = resolveParents([
        doc('prds/features/f03_login/FEATURE.md', 'feature', 'login'),
        doc('prds/features/f01_login/FEATURE.md', 'feature', 'login'),
        doc(story, 'user_story', 'login/email_login'),
      ], set);
      expect(result.warnings, {
        story:
            '$story has two candidate parent docs: prds/features/f01_login/FEATURE.md, '
            'prds/features/f03_login/FEATURE.md; it has no parent doc',
      });
    });
    test('s03/inv7: a slug-free parent type, a top-level type, and an untyped doc give no parent', () {
      final custom = MergedSet(
        docTypes: const [
          MergedDocType(
            id: 'project',
            path: 'prds/PROJECT.md',
            fields: [],
            sections: [],
            lint: MergedLint(),
            files: [],
          ),
          MergedDocType(
            id: 'note',
            parent: 'project',
            path: 'prds/notes/{slug}.md',
            fields: [],
            sections: [],
            lint: MergedLint(),
            files: [],
          ),
        ],
      );
      final result = resolveParents([
        doc('prds/PROJECT.md', 'project', 'project'),
        doc('prds/notes/x.md', 'note', 'x'),
        const IndexedDoc(
          docPath: 'README.md',
          name: 'README.md',
          frontmatter: {},
          tokens: 0,
        ),
      ], custom);
      expect(result.parents, isEmpty);
      expect(result.warnings, isEmpty);
    });
  });
}
