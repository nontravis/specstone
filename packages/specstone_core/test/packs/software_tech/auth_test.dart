import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';
import '../../helpers/software_tech.dart';

const _says = <String, List<String>>{
  'scopes': ['<resource>:<action>', 'default scope'],
  'resource_matrix': [
    'resource',
    'operation',
    'role',
    'Default: deny',
    'blank cell',
  ],
  'conditions': ['attribute', 'relationship'],
  'field_rules': ['Field', 'Read', 'Write'],
  'authentication_and_sessions': [
    'idle timeout',
    'absolute lifetime',
    'concurrent sessions',
    'pathways',
    'anti-automation',
  ],
  'enforcement': ['layer'],
  'audit': ['one vocabulary', 'when, where, who, what', 'tokens', 'passwords'],
};

void main() {
  late MergedDocType auth;
  setUpAll(() async {
    auth = prdCoreDocType(await resolveSoftwareTech(), 'auth');
  });

  test('f03/us07/fr01, f03/us07/fr01/e06: auth sits under '
      'specs/f{nn}_{slug}/ with parent feature, no own field, and eight '
      'sections', () {
    expect(auth.path, 'specs/f{nn}_{slug}/AUTH.md');
    expect(auth.parent, 'feature');
    expectOwnFields(auth, const []);
    expectSections(auth, const [
      SectionSpec('roles', 'Roles', required: true),
      SectionSpec('scopes', 'Scopes', required: true),
      SectionSpec('resource_matrix', 'Resource matrix', required: true),
      SectionSpec('conditions', 'Conditions'),
      SectionSpec('field_rules', 'Field rules'),
      SectionSpec('authentication_and_sessions', 'Authentication and sessions'),
      SectionSpec('enforcement', 'Enforcement', required: true),
      SectionSpec('audit', 'Audit', required: true),
    ]);
  });

  test('f03/us07/fr02, f03/us07/fr02/e01, f03/us07/fr02/e03, '
      'f03/us07/fr02/e04, f03/us07/fr02/e07: the auth guide', () {
    expectSpecGuide(
      auth,
      title: '# <Feature name> auth',
      says: ['only when the feature has access rules'],
    );
    expectSectionsSay(auth, _says);
  });

  test('f03/us07/fr03: auth caps 400 lines, bans no word, and cites its four '
      'sources', () {
    expectSpecLint(auth);
  });
}
