import 'package:specstone_core/src/doc_model/doc_path_shape.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:test/test.dart';

import '../../helpers/write_fixture.dart';

void main() {
  late MergedSet set;

  setUpAll(() async {
    set = openProject(await writeWriteProject()).set;
  });

  DocPathShape shape(String id) => DocPathShape.of(set.lookup(id)!, set)!;

  test('dw-s03/inv8, F2-D36, F2-D37: the movable doc types come from the templates', () {
    final shapes = {
      for (final t in set.docTypes) t.id: DocPathShape.of(t, set),
    };
    expect(
      {
        for (final MapEntry(:key, :value) in shapes.entries)
          if (value?.numbered ?? false) key,
      },
      {'feature', 'user_story', 'fr', 'nf'},
    );
    expect(
      {
        for (final MapEntry(:key, :value) in shapes.entries)
          if (value?.slugged ?? false) key,
      },
      {
        'feature',
        'user_story',
        'fr',
        'nf',
        'persona',
        'anti_persona',
        'reference',
        'journey',
        'topic',
      },
    );
  });

  test('dw-s03/inv6: the own segment is a folder or the file', () {
    expect(
      shape('feature').ownPathOf(loginFeature),
      'prds/features/f01_login/',
    );
    expect(
      shape('user_story').ownPathOf(story1),
      'prds/features/f01_login/us01_email_login/',
    );
    expect(shape('fr').ownPathOf(fr11), fr11);
    expect(shape('architecture').ownPathOf(loginArch), loginArch);
    expect(shape('persona').ownPathOf(persona), 'prds/personas/buyer/');
    expect(shape('user_story').valuesOf(story1), [
      '01',
      'login',
      '01',
      'email_login',
    ]);
    expect(
      shape('user_story').containerOf(['01', 'login']),
      'prds/features/f01_login/',
    );
    expect(specFoldersOf(set, set.lookup('feature')!, ['01', 'login']), [
      'specs/f01_login/',
    ]);
  });

  test('dw-s03/inv6: the own segment index and the parent count', () {
    expect(
      [
        for (final id in ['feature', 'user_story', 'fr', 'architecture'])
          (shape(id).parentCount, shape(id).ownIndex, shape(id).ownIsFile),
      ],
      [(0, 2, false), (2, 3, false), (4, 4, true), (2, 2, true)],
    );
    expect(shape('project').containerOf([]), 'prds/');
    expect(shape('feature').containerOf([]), 'prds/features/');
  });

  test('dw-s03/inv6: valuesOf is null on a path the doc type does not match, and build is its inverse', () {
    expect(shape('feature').valuesOf(story1), isNull);
    expect(
      shape('user_story').valuesOf('prds/features/x/USER_STORY.md'),
      isNull,
    );
    expect(
      shape('user_story').build(['01', 'login', '01', 'email_login']),
      story1,
    );
    expect(shape('project').valuesOf('prds/PROJECT.md'), <String>[]);
  });

  test('dw-s03/inv6: ownValues fills the own segment placeholders in pattern order', () {
    expect(shape('user_story').ownValues(number: '04', slug: 'a'), ['04', 'a']);
    expect(shape('persona').ownValues(slug: 'seller'), ['seller']);
    expect(shape('architecture').ownValues(), <String>[]);
  });

  test('f03/unit-roots: unitRootsOf gives the own folder then the spec folders, or the one file', () {
    expect(unitRootsOf(set, set.lookup('feature')!, loginFeature), [
      'prds/features/f01_login/',
      'specs/f01_login/',
    ]);
    expect(unitRootsOf(set, set.lookup('architecture')!, loginArch), [
      loginArch,
    ]);
    expect(unitRootsOf(set, set.lookup('feature')!, story1), isNull);
  });
}
