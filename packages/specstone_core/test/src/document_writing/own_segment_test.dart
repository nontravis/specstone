import 'dart:io';

import 'package:specstone_core/src/document_writing/own_segment.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:test/test.dart';

import '../../helpers/posix_modes.dart';
import '../../helpers/prd_core.dart';
import '../../helpers/write_fixture.dart';

void main() {
  late Directory root;
  late MergedSet set;

  setUpAll(() async {
    root = await writeWriteProject();
    set = openProject(root).set;
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
    expect([padNumber(1), padNumber(99), padNumber(100)], ['01', '99', '100']);
  });

  test('dw-s03/inv7, H22: spec folder moves pair each folder with the one its child doc type holds after the move', () {
    final feature = set.lookup('feature')!;
    expect(specFolderMovesOf(set, feature, ['01', 'login'], ['02', 'login']), [
      (from: 'specs/f01_login/', to: 'specs/f02_login/'),
    ]);
    expect(
      specFolderMovesOf(set, feature, ['01', 'login'], ['01', 'login']),
      isEmpty,
    );
  });

  test('dw-s03/inv7, H22: spec folder moves pair child folders that sort differently before and after by child type', () async {
    final custom = await resolvePrdCore(
      templates: {
        'spec_a.yaml': 'id: spec_a\ndescription: Spec A\npath: specs/f{nn}_{slug}_a/A.md\nparent: feature\n',
        'spec_b.yaml': 'id: spec_b\ndescription: Spec B\npath: specs/f{nn}_b_{slug}/B.md\nparent: feature\n',
      },
    );
    final feature = custom.lookup('feature')!;
    expect(specFoldersOf(custom, feature, ['01', 'z']), [
      'specs/f01_b_z/',
      'specs/f01_z_a/',
    ]);
    expect(specFoldersOf(custom, feature, ['01', 'a']), [
      'specs/f01_a_a/',
      'specs/f01_b_a/',
    ]);
    expect(specFolderMovesOf(custom, feature, ['01', 'z'], ['01', 'a']), [
      (from: 'specs/f01_b_z/', to: 'specs/f01_b_a/'),
      (from: 'specs/f01_z_a/', to: 'specs/f01_a_a/'),
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

  test('dw-s03/inv6: siblings on disk are the matching own segments, sorted by number', () {
    expect(
      [
        for (final s in siblingsOnDisk(
          openProject(root).docsRoot,
          shape('user_story'),
          ['01', 'login'],
        ))
          (s.name, s.number, s.slug),
      ],
      [
        ('us01_email_login', 1, 'email_login'),
        ('us02_sign_out', 2, 'sign_out'),
        ('us03_reset_password', 3, 'reset_password'),
      ],
    );
    expect(
      siblingsOnDisk(openProject(root).docsRoot, shape('user_story'), [
        '09',
        'nobody',
      ]),
      isEmpty,
    );
  });

  test(
    'final Minor 1, dw-s03/inv8: a folder with no doc file is no sibling',
    () async {
      final copy = await writeWriteProject();
      Directory('${copy.path}/docs/prds/features/f01_login/us09_empty')
          .createSync();
      final names = [
        for (final s in siblingsOnDisk(
          openProject(copy).docsRoot,
          shape('user_story'),
          ['01', 'login'],
        ))
          s.name,
      ];
      expect(names, [
        'us01_email_login',
        'us02_sign_out',
        'us03_reset_password',
      ]);
    },
  );

  test('dw-s03/inv8, final Important 3: an unreadable container is output_not_writable', () async {
    final copy = await writeWriteProject();
    final container = '${copy.path}/docs/prds/features/f01_login';
    Process.runSync('chmod', ['000', container]);
    addTearDown(() => Process.runSync('chmod', ['755', container]));
    expect(
      () => siblingsOnDisk(
        Directory('${copy.path}/docs'),
        shape('user_story'),
        ['01', 'login'],
      ),
      throwsA(
        isA<RenderFault>()
            .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
            .having(
              (f) => f.message,
              'message',
              startsWith('cannot read prds/features/f01_login: '),
            ),
      ),
    );
  }, skip: unreadablePathSkipReason() ?? false);

  test('dw-s03/inv6: a file own segment lists files, not folders', () {
    final names = [
      for (final s in siblingsOnDisk(openProject(root).docsRoot, shape('fr'), [
        '01',
        'login',
        '01',
        'email_login',
      ]))
        s.name,
    ];
    expect(names, [
      'fr01_validate_credentials.md',
      'fr02_lock_after_failures.md',
    ]);
  });

  test('f02/us02/fr01/e10: checkSlug accepts lowercase letters, digits, and underscore only', () {
    checkSlug('email_2');
    for (final bad in ['', 'Email', 'a-b', 'a b', 'a\n']) {
      expect(
        () => checkSlug(bad),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
              .having(
                (f) => f.message,
                'message',
                '$bad is no slug: use lowercase letters, digits, and _',
              ),
        ),
        reason: 'slug "$bad"',
      );
    }
  });
}
