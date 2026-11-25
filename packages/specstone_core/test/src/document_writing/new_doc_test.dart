// Test names carry the story, FR, and edge-case IDs on one line.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:specstone_core/src/document_writing/move_journal.dart'
    show WriteStep, textHashOf;
import 'package:specstone_core/src/document_writing/new_doc.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/doc_type_merger.dart';
import 'package:specstone_core/src/templates/layer.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/fixed_numbers_fixture.dart'
    show decisionLayer, decisionLayerFile;
import '../../helpers/forwarding_entities.dart';
import '../../helpers/nested_fixture.dart';
import '../../helpers/posix_modes.dart';
import '../../helpers/record_fixture.dart';
import '../../helpers/shipped_pins.dart' show shippedPinsConfig;
import '../../helpers/target_fixture.dart'
    show flutterArchitecture, jasprArchitecture, writeTwinProject;
import '../../helpers/write_fixture.dart';

Matcher indexFault(IndexFaultCode code, String message) => isA<IndexFault>()
    .having((f) => f.code, 'code', code)
    .having((f) => f.message, 'message', message);

/// Runs `onCreate` with the path of each `File` the code under test makes.
///
/// A `File` made inside `onCreate` reaches the real file system: the hook is
/// off while it runs.
final class _CreateFileHook extends IOOverrides {
  new(this._onCreate);

  final void Function(String path) _onCreate;
  var _inside = false;

  @override
  File createFile(String path) {
    if (!_inside) {
      _inside = true;
      try {
        _onCreate(path);
      } finally {
        _inside = false;
      }
    }
    return super.createFile(path);
  }
}

void main() {
  test('a story with no text is the skeleton at the next number', () async {
    final root = await writeWriteProject();
    const path = 'prds/features/f01_login/us04_forgot_email/USER_STORY.md';
    final answer = writeIn(
      root,
      (s) => answerNew(
        s,
        docTypeId: 'user_story',
        parent: 'login',
        slug: 'forgot_email',
      ),
    );
    expect(answer.text, '==> login/forgot_email (user_story) · $path <==\n');
  });

  test(
    'a slug a sibling carries is doc_exists naming it, and no file is created',
    () async {
      final root = await writeWriteProject();
      expect(
        () => writeIn(
          root,
          (s) => answerNew(
            s,
            docTypeId: 'user_story',
            parent: 'login',
            slug: 'email_login',
          ),
        ),
        throwsA(
          isA<WriteFault>()
              .having((f) => f.code, 'code', WriteFaultCode.docExists)
              .having(
                (f) => f.message,
                'message',
                'a user_story named login/email_login exists',
              )
              .having((f) => f.file, 'file', story1),
        ),
      );
      expect(
        Directory('${root.path}/docs/prds/features/f01_login/us04_email_login')
            .existsSync(),
        isFalse,
      );
    },
  );

  test(
    'a missing --parent is argument_missing with the sidecar message',
    () async {
      final root = await writeWriteProject();
      expect(
        () => writeIn(
          root,
          (s) => answerNew(s, docTypeId: 'user_story', slug: 'x'),
        ),
        throwsA(
          indexFault(
            IndexFaultCode.argumentMissing,
            'user_story needs --parent: a feature named by <doc type>:<name>, a bare name, or a path',
          ),
        ),
      );
    },
  );

  test('given text keeps its blocks and is forced to draft: true', () async {
    final root = await writeWriteProject();
    writeIn(
      root,
      (s) => answerNew(
        s,
        docTypeId: 'user_story',
        parent: 'login',
        slug: 'a',
        text: '---\ndraft: false\nvision:\n  - PV-01\n---\n\n# Mine\n',
      ),
    );
    expect(
      readDoc(root, 'prds/features/f01_login/us04_a/USER_STORY.md'),
      '---\ndraft: true\nvision:\n  - PV-01\n---\n\n# Mine\n',
    );
    writeIn(
      root,
      (s) => answerNew(
        s,
        docTypeId: 'user_story',
        parent: 'login',
        slug: 'b',
        text: '# Mine\n',
      ),
    );
    expect(
      readDoc(root, 'prds/features/f01_login/us05_b/USER_STORY.md'),
      '---\ndraft: true\n---\n\n# Mine\n',
    );
    writeIn(
      root,
      (s) => answerNew(
        s,
        docTypeId: 'user_story',
        parent: 'login',
        slug: 'plain',
        text: '# Plain\n\nJust prose.\n',
      ),
    );
    expect(
      readDoc(root, 'prds/features/f01_login/us06_plain/USER_STORY.md'),
      '---\ndraft: true\n---\n\n# Plain\n\nJust prose.\n',
    );
  });

  test('after a gap the new doc takes the highest number plus one', () async {
    final root = await writeWriteProject(
      extra: {
        'docs/prds/features/f01_login/us06_audit/USER_STORY.md': '# Audit\n',
      },
    );
    writeIn(
      root,
      (s) =>
          answerNew(s, docTypeId: 'user_story', parent: 'login', slug: 'next'),
    );
    expect(
      hasDoc(root, 'prds/features/f01_login/us07_next/USER_STORY.md'),
      isTrue,
    );
  });

  test('two new calls under one parent at once take two numbers', () async {
    final root = await writeWriteProject();
    final path = root.path;
    String create(String slug) => WriteSession.run(
      (s) => answerNew(
        s,
        docTypeId: 'user_story',
        parent: 'login',
        slug: slug,
      ).text,
      templates: TemplateResolver(),
      workingDirectory: Directory(path),
      homeDirectory: null,
    );
    await Future.wait([
      Isolate.run(() => create('a')),
      Isolate.run(() => create('b')),
    ]);
    expect(
      hasDoc(root, 'prds/features/f01_login/us04_a/USER_STORY.md') &&
              hasDoc(root, 'prds/features/f01_login/us05_b/USER_STORY.md') ||
          hasDoc(root, 'prds/features/f01_login/us04_b/USER_STORY.md') &&
              hasDoc(root, 'prds/features/f01_login/us05_a/USER_STORY.md'),
      isTrue,
    );
  });

  test(
    'a spec doc lands in the feature spec folder titled with its slug',
    () async {
      final root = await writeWriteProject();
      final answer = writeIn(
        root,
        (s) => answerNew(s, docTypeId: 'api', parent: 'login'),
      );
      expect(docOf(answer)['path'], 'specs/f01_login/API.md');
      expect(
        readDoc(root, 'specs/f01_login/API.md'),
        contains('\n\n# login\n'),
      );
    },
  );

  test('a doc type that sets a title is created under that title, not its '
      'id', () async {
    final root = await writeWriteProject(
      extra: {'.specstone/templates/project.yaml': 'title: Project brief\n'},
    );
    writeIn(root, (s) => answerNew(s, docTypeId: 'project'));
    expect(
      readDoc(root, 'prds/PROJECT.md'),
      contains('\n---\n\n# Project brief\n'),
    );
  });

  test('a feature takes the next feature number', () async {
    final root = await writeWriteProject();
    writeIn(root, (s) => answerNew(s, docTypeId: 'feature', slug: 'billing'));
    expect(hasDoc(root, 'prds/features/f03_billing/FEATURE.md'), isTrue);
  });

  test(
    'a doc type with no placeholder is created once, then doc_exists',
    () async {
      final root = await writeWriteProject();
      writeIn(root, (s) => answerNew(s, docTypeId: 'project'));
      expect(
        readDoc(root, 'prds/PROJECT.md'),
        contains('\n\n# Project context\n'),
      );
      expect(
        () => writeIn(root, (s) => answerNew(s, docTypeId: 'project')),
        throwsA(
          isA<WriteFault>()
              .having((f) => f.code, 'code', WriteFaultCode.docExists)
              .having((f) => f.file, 'file', 'prds/PROJECT.md'),
        ),
      );
    },
  );

  test('another doc type in the same folder is no clash', () async {
    final root = await writeWriteProject(
      extra: {'docs/prds/personas/seller/PERSONA.md': '# Seller\n'},
    );
    writeIn(
      root,
      (s) => answerNew(s, docTypeId: 'anti_persona', slug: 'seller'),
    );
    expect(hasDoc(root, 'prds/personas/seller/ANTI_PERSONA.md'), isTrue);
  });

  test('a parent no doc carries is doc_not_found', () async {
    final root = await writeWriteProject();
    expect(
      () => writeIn(
        root,
        (s) =>
            answerNew(s, docTypeId: 'user_story', parent: 'nobody', slug: 'x'),
      ),
      throwsA(
        isA<IndexFault>().having(
          (f) => f.code,
          'code',
          IndexFaultCode.docNotFound,
        ),
      ),
    );
  });

  test('a --parent that names no doc of the parent doc type is doc_not_found naming the value, and no file is created', () async {
    final root = await writeWriteProject();
    for (final parent in ['architecture:login', 'user_story:login']) {
      expect(
        () => writeIn(
          root,
          (s) =>
              answerNew(s, docTypeId: 'user_story', parent: parent, slug: 'x'),
        ),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.docNotFound)
              .having((f) => f.message, 'message', contains(parent)),
        ),
        reason: parent,
      );
    }
    expect(
      hasDoc(root, 'prds/features/f01_login/us04_x/USER_STORY.md'),
      isFalse,
    );
  });

  test(
    '--parent feature:login and a path name the parent as a bare name does',
    () async {
      final root = await writeWriteProject();
      for (final (parent, slug) in [
        ('feature:login', 'by_type'),
        ('prds/features/f01_login/FEATURE.md', 'by_path'),
        ('login', 'by_name'),
      ]) {
        final answer = writeIn(
          root,
          (s) =>
              answerNew(s, docTypeId: 'user_story', parent: parent, slug: slug),
        );
        expect(docOf(answer)['name'], 'login/$slug', reason: parent);
      }
    },
  );

  test('a --parent that names 2 or more docs of the parent doc type is argument_invalid listing each as <doc type>:<name>, and no file is created', () async {
    final root = await writeWriteProject(
      extra: {'docs/prds/features/f03_login/FEATURE.md': '# Login\n'},
    );
    expect(
      () => writeIn(
        root,
        (s) =>
            answerNew(s, docTypeId: 'user_story', parent: 'login', slug: 'x'),
      ),
      throwsA(
        isA<IndexFault>()
            .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
            .having(
              (f) => f.message,
              'message',
              allOf(
                contains(loginFeature),
                contains('prds/features/f03_login/FEATURE.md'),
              ),
            ),
      ),
    );
    expect(
      hasDoc(root, 'prds/features/f01_login/us04_x/USER_STORY.md'),
      isFalse,
    );
  });

  test('a missing --slug, a --parent or --slug the type takes no value for, or a bad slug is refused', () async {
    final root = await writeWriteProject();
    void refuses(
      IndexFaultCode code,
      String message, {
      required String type,
      String? parent,
      String? slug,
    }) => expect(
      () => writeIn(
        root,
        (s) => answerNew(s, docTypeId: type, parent: parent, slug: slug),
      ),
      throwsA(indexFault(code, message)),
    );
    refuses(
      IndexFaultCode.argumentMissing,
      'user_story needs --slug, lowercase letters, digits, and _',
      type: 'user_story',
      parent: 'login',
    );
    refuses(
      IndexFaultCode.argumentInvalid,
      'api takes no --slug',
      type: 'api',
      parent: 'login',
      slug: 'x',
    );
    refuses(
      IndexFaultCode.argumentInvalid,
      'Bad is no slug: use lowercase letters, digits, and _',
      type: 'feature',
      slug: 'Bad',
    );
  });

  group('sub-feature: nested docs', () {
    String pathOf(Directory root, String type, String parent, String slug) =>
        docOf(
              writeIn(
                root,
                (s) =>
                    answerNew(s, docTypeId: type, parent: parent, slug: slug),
              ),
            )['path']!
            as String;

    test(
      'a story under a sub-feature takes the next story number in its folder',
      () async {
        final root = await writeNestedProject();
        final answer = writeIn(
          root,
          (s) => answerNew(
            s,
            docTypeId: 'user_story',
            parent: 'shop/cart',
            slug: 'wish',
          ),
        );
        expect(
          docOf(answer)['path'],
          'prds/features/f02_shop/f01_cart/us03_wish/USER_STORY.md',
        );
        expect(docOf(answer)['name'], 'shop/cart/wish');
      },
    );

    test('a feature with --parent lands in that feature at the next feature number', () async {
      final root = await writeNestedProject();
      expect(
        pathOf(root, 'feature', 'shop', 'ship'),
        'prds/features/f02_shop/f03_ship/FEATURE.md',
      );
    });

    test(
      'a parent holding stories takes a sub-feature, numbered from 01',
      () async {
        final root = await writeNestedProject();
        expect(
          pathOf(root, 'feature', 'shop/cart', 'gift'),
          'prds/features/f02_shop/f01_cart/f01_gift/FEATURE.md',
        );
      },
    );

    test(
      'a domain under a sub-feature lands in the sub-feature spec folder',
      () async {
        final root = await writeNestedProject(without: {'docs/$cartDomain'});
        final answer = writeIn(
          root,
          (s) => answerNew(s, docTypeId: 'rulebook', parent: 'shop/cart'),
        );
        expect(docOf(answer)['path'], cartDomain);
      },
    );

    test(
      'a parent at the limit refuses a sub-feature and writes nothing',
      () async {
        const deep = 'prds/features/f02_shop/f01_cart/f01_deep';
        final root = await writeNestedProject(
          extra: {
            'docs/$deep/FEATURE.md': '# Deep\n',
            'docs/$deep/f01_deeper/FEATURE.md': '# Deeper\n',
          },
        );
        expect(
          () => writeIn(
            root,
            (s) => answerNew(
              s,
              docTypeId: 'feature',
              parent: 'shop/cart/deep/deeper',
              slug: 'x',
            ),
          ),
          throwsA(
            allOf(
              indexFault(
                IndexFaultCode.argumentInvalid,
                'shop/cart/deep/deeper (feature) sits 3 levels deep, the '
                'limit, so it takes no sub-feature',
              ),
              isA<IndexFault>().having((f) => f.exitStatus, 'exit', 64),
            ),
          ),
        );
        expect(
          Directory('${root.path}/docs/$deep/f01_deeper/f01_x').existsSync(),
          isFalse,
        );
      },
    );

    test('a flat set keeps feature takes no --parent', () async {
      final root = await writeWriteProject(
        extra: {'.specstone/templates/feature.yaml': 'max_depth: 0\n'},
      );
      expect(
        () => writeIn(
          root,
          (s) => answerNew(s, docTypeId: 'feature', parent: 'login', slug: 'x'),
        ),
        throwsA(
          allOf(
            indexFault(
              IndexFaultCode.argumentInvalid,
              'feature takes no --parent',
            ),
            isA<IndexFault>().having((f) => f.exitStatus, 'exit', 64),
          ),
        ),
      );
      expect(
        Directory('${root.path}/docs/prds/features/f01_login/f01_x')
            .existsSync(),
        isFalse,
      );
    });

    test(
      'a feature type with max_depth unset takes no --parent either',
      () async {
        final root = await writeWriteProject();
        final files = {...shippedPackFiles};
        final feature = utf8.decode(files['prd-core/feature.yaml']!);
        final unset = feature.replaceFirst(
          RegExp(r'^max_depth: .*\n', multiLine: true),
          '',
        );
        expect(unset, isNot(feature), reason: 'the shipped feature sets it');
        files['prd-core/feature.yaml'] = Uint8List.fromList(utf8.encode(unset));
        expect(
          () => writeIn(
            root,
            (s) =>
                answerNew(s, docTypeId: 'feature', parent: 'login', slug: 'x'),
            templates: TemplateResolver(shippedFiles: files),
          ),
          throwsA(
            isA<IndexFault>()
                .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
                .having((f) => f.exitStatus, 'exit', 64)
                .having(
                  (f) => f.message,
                  'message',
                  'feature takes no --parent',
                ),
          ),
        );
        expect(
          Directory('${root.path}/docs/prds/features/f01_login/f01_x')
              .existsSync(),
          isFalse,
        );
      },
    );
  });

  test('an unknown doc type is doc_type_unknown', () async {
    final root = await writeWriteProject();
    expect(
      () => writeIn(root, (s) => answerNew(s, docTypeId: 'runbook')),
      throwsA(
        isA<TemplateFault>()
            .having((f) => f.code, 'code', FaultCode.docTypeUnknown)
            .having(
              (f) => f.message,
              'message',
              'Could not find a doc type named "runbook".',
            ),
      ),
    );
  });

  test('the 100th story takes three digits', () async {
    final root = await writeWriteProject(
      extra: {
        'docs/prds/features/f01_login/us99_last/USER_STORY.md': '# Last\n',
      },
    );
    writeIn(
      root,
      (s) =>
          answerNew(s, docTypeId: 'user_story', parent: 'login', slug: 'next'),
    );
    expect(
      hasDoc(root, 'prds/features/f01_login/us100_next/USER_STORY.md'),
      isTrue,
    );
  });

  test('an unwritable feature folder is output_not_writable and leaves nothing behind', () async {
    final root = await writeWriteProject();
    final folder = Directory('${root.path}/docs/prds/features/f01_login');
    Process.runSync('chmod', ['555', folder.path]);
    addTearDown(() => Process.runSync('chmod', ['755', folder.path]));
    expect(
      () => writeIn(
        root,
        (s) =>
            answerNew(s, docTypeId: 'user_story', parent: 'login', slug: 'x'),
      ),
      throwsA(
        isA<RenderFault>()
            .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
            .having((f) => f.exitStatus, 'exit', 73)
            .having(
              (f) => f.message,
              'message',
              startsWith(
                'cannot write prds/features/f01_login/us04_x/USER_STORY.md: ',
              ),
            ),
      ),
    );
    expect(
      folder
          .listSync()
          .map((e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last)
          .toSet(),
      {
        'FEATURE.md',
        'us01_email_login',
        'us02_sign_out',
        'us03_reset_password',
      },
    );
  }, skip: unreadablePathSkipReason() ?? false);

  test('a write that fails after the claim removes the claimed file and the folders new made', () async {
    final root = await writeWriteProject();
    final storyFolder = Directory(
      '${root.path}/docs/prds/features/f01_login/us04_x',
    );
    expect(
      () => IOOverrides.runWithIOOverrides(
        () => writeIn(
          root,
          (s) =>
              answerNew(s, docTypeId: 'user_story', parent: 'login', slug: 'x'),
        ),
        _CreateFileHook((path) {
          final name = path.split(Platform.pathSeparator).last;
          if (name.startsWith('.USER_STORY.md.') &&
              name.endsWith('.specstone.tmp')) {
            throw FileSystemException('the temp name is taken', path);
          }
        }),
      ),
      throwsA(isA<RenderFault>()),
    );
    expect(storyFolder.existsSync(), isFalse);
  });

  test('a path taken between the sibling count and the claim moves the new doc to the next number', () async {
    final root = await writeWriteProject();
    final taken = 'f01_login/us04_x/USER_STORY.md'.replaceAll(
      '/',
      Platform.pathSeparator,
    );
    var raced = false;
    final answer = IOOverrides.runWithIOOverrides(
      () => writeIn(
        root,
        (s) =>
            answerNew(s, docTypeId: 'user_story', parent: 'login', slug: 'x'),
      ),
      _CreateFileHook((path) {
        if (!raced && path.endsWith(taken)) {
          raced = true;
          File(path).createSync(recursive: true);
        }
      }),
    );
    expect(raced, isTrue);
    expect(
      answer.text,
      startsWith('==> login/x (user_story) · prds/features/f01_login/us05_x/'),
    );
    expect(
      hasDoc(root, 'prds/features/f01_login/us05_x/USER_STORY.md'),
      isTrue,
    );
  });

  test('an fr skeleton writes its required fields empty', () async {
    final root = await writeWriteProject();
    writeIn(
      root,
      (s) => answerNew(
        s,
        docTypeId: 'fr',
        parent: 'login/reset_password',
        slug: 'notify',
      ),
    );
    expect(
      readDoc(
        root,
        'prds/features/f01_login/us03_reset_password/fr03_notify.md',
      ),
      startsWith('---\ndraft: true\ntraced_from:\nverify_method:\n---\n'),
    );
  });

  test(
    'stdin holding an approved key refuses before any path is claimed',
    () async {
      final root = await writeWriteProject();
      for (final value in ['true', 'false']) {
        expect(
          () => writeIn(
            root,
            (s) => answerNew(
              s,
              docTypeId: 'user_story',
              parent: 'login',
              slug: 'sneaky',
              text: '---\napproved: $value\n---\n\n# Mine\n',
            ),
          ),
          throwsA(
            isA<WriteFault>()
                .having((f) => f.code, 'code', WriteFaultCode.fieldNotWritable)
                .having(
                  (f) => f.message,
                  'message',
                  'approved is written only by specstone approve and the hash stamps',
                )
                .having((f) => f.key, 'key', 'approved'),
          ),
        );
      }
      expect(
        Directory('${root.path}/docs/prds/features/f01_login/us04_sneaky')
            .existsSync(),
        isFalse,
      );
    },
  );

  test('empty text gives the skeleton', () async {
    final root = await writeWriteProject();
    writeIn(
      root,
      (s) => answerNew(s, docTypeId: 'feature', slug: 'billing', text: ''),
    );
    expect(
      readDoc(root, 'prds/features/f03_billing/FEATURE.md'),
      startsWith('---\ndraft: true\nsummary:\n---\n\n# billing\n\n## '),
    );
  });

  test(
    'new replies with one docs element holding base and bases without doc',
    () async {
      final root = await writeWriteProject();
      final answer = writeIn(
        root,
        (s) => answerNew(
          s,
          docTypeId: 'user_story',
          parent: 'login',
          slug: 'forgot_email',
        ),
      );
      expect(answer.json.keys, {'docs'});
      final docs = answer.json['docs']! as List;
      expect(docs, hasLength(1));
      final element = docs.single as Map<String, Object?>;
      final got = getDoc(root, 'user_story:login/forgot_email');
      expect(element, {
        'name': 'login/forgot_email',
        'docType': 'user_story',
        'path': 'prds/features/f01_login/us04_forgot_email/USER_STORY.md',
        'base': got['base'],
        'bases': got['bases'],
      });
      expect((element['bases']! as Map).containsKey('doc'), isFalse);
    },
  );

  test('skeletonOf writes draft true, each required field '
      'empty, the title, and each required section', () {
    final set = TemplateResolver().resolveCarried(
      packNames: ['prd-core', 'software-tech'],
      homeDirectory: null,
    );
    final techStack = set.lookup('tech_stack')!;
    final project = set.lookup('project')!;

    final text = skeletonOf(techStack, 'tech_stack');
    final headers = [
      for (final s in techStack.sections)
        if (s.required) '## ${s.header}',
    ];

    expect(text, startsWith('---\ndraft: true\n'));
    expect(text, contains('\n# Tech stack\n'));
    expect(headers, isNotEmpty);
    var from = 0;
    for (final header in headers) {
      final at = text.indexOf(header, from);
      expect(at, greaterThanOrEqualTo(0), reason: header);
      from = at + header.length;
    }
    final projectText = skeletonOf(project, 'project');
    for (final field in project.fields.where((f) => f.required)) {
      expect(projectText, contains('\n${field.id}:\n'));
    }
  });

  test('a skeleton section prints its header with no body', () {
    const merger = DocTypeMerger();
    final docType = merger.apply(
      merger.builtInBase('note'),
      DocTypeLayer.parse(
        r'''
description: A note.
path: prds/NOTE.md
sections:
  - id: a
    header: A
    required: true
    template: "Say it.\n"
  - id: b
    header: B
    skeleton: true
  - id: c
    header: C
  - id: d
    header: D
    required: true
    template: "Then this.\n"
''',
        file: 'packs/prd-core/note.yaml',
        docTypeId: 'note',
        kind: LayerKind.shipped,
        files: const _NoFiles(),
      ),
    );

    expect(
      skeletonOf(docType, 'note'),
      '---\ndraft: true\n---\n\n# note\n\n## A\n\nSay it.\n\n## B\n'
      '\n## D\n\nThen this.\n',
    );
  });

  test('keys reordered, text laid out, draft at its field slot', () async {
    final root = await writeWriteProject();
    writeIn(
      root,
      (s) => answerNew(
        s,
        docTypeId: 'user_story',
        parent: 'login',
        slug: 'a',
        text: '---\nvision:\n  - PV-01\n---\n\n# Mine\n',
      ),
    );
    expect(
      readDoc(root, 'prds/features/f01_login/us04_a/USER_STORY.md'),
      '---\ndraft: true\nvision:\n  - PV-01\n---\n\n# Mine\n',
    );
    writeIn(
      root,
      (s) => answerNew(
        s,
        docTypeId: 'user_story',
        parent: 'login',
        slug: 'b',
        text: '---\npersona:\n  - owner\nvision:\n  - PV-01\n---\n\n# Mine\n',
      ),
    );
    expect(
      readDoc(root, 'prds/features/f01_login/us05_b/USER_STORY.md'),
      '---\ndraft: true\nvision:\n  - PV-01\n'
      'persona:\n  - owner\n---\n\n# Mine\n',
    );
  });

  test('stdin that lacks a required section is written without it, an undeclared key kept after the declared ones', () async {
    final root = await writeWriteProject();
    writeIn(
      root,
      (s) => answerNew(
        s,
        docTypeId: 'user_story',
        parent: 'login',
        slug: 'a',
        text: '---\nzzz: 1\nvision:\n  - PV-01\n---\n\n# Mine\n\n## Use Case\nSign in.\n',
      ),
    );
    expect(
      readDoc(root, 'prds/features/f01_login/us04_a/USER_STORY.md'),
      '---\ndraft: true\nvision:\n  - PV-01\nzzz: 1\n---\n\n# Mine\n\n'
      '## Use Case\n\nSign in.\n',
    );
  });

  test('stdin with text right under a heading is written laid out', () async {
    final root = await writeWriteProject();
    final answer = writeIn(
      root,
      (s) => answerNew(
        s,
        docTypeId: 'user_story',
        parent: 'login',
        slug: 'a',
        text: '---\nvision:\n  - PV-01\n---\n\n# Mine\n\n## Use Case\nSign in.\n\n## Acceptance Criteria\n- **Given** x\n',
      ),
    );
    const path = 'prds/features/f01_login/us04_a/USER_STORY.md';
    expect(
      readDoc(root, path),
      '---\ndraft: true\nvision:\n  - PV-01\n---\n\n# Mine\n\n'
      '## Use Case\n\nSign in.\n\n## Acceptance Criteria\n\n- **Given** x\n',
    );
    expect(docOf(answer)['path'], path);
  });

  test(
    'stdin that starts with a blank line gets no second blank line after draft',
    () async {
      final root = await writeWriteProject();
      writeIn(
        root,
        (s) => answerNew(
          s,
          docTypeId: 'user_story',
          parent: 'login',
          slug: 'a',
          text: '\n# Mine\n\nJust prose.\n',
        ),
      );
      expect(
        readDoc(root, 'prds/features/f01_login/us04_a/USER_STORY.md'),
        '---\ndraft: true\n---\n\n# Mine\n\nJust prose.\n',
      );
    },
  );

  test('stdin with its sections out of order and a padded table is written laid out', () async {
    final root = await writeWriteProject();
    writeIn(
      root,
      (s) => answerNew(
        s,
        docTypeId: 'user_story',
        parent: 'login',
        slug: 'a',
        text:
            '---\nvision:\n  - PV-01\n---\n\n# Mine\n\n'
            '## Acceptance Criteria\n\n- **Given** x\n\n'
            '## Use Case\n\n| Role   | Goal    |\n|---|---|\n| Agent  | Sign in |\n',
      ),
    );
    expect(
      readDoc(root, 'prds/features/f01_login/us04_a/USER_STORY.md'),
      '---\ndraft: true\nvision:\n  - PV-01\n---\n\n# Mine\n\n'
      '## Use Case\n\n| Role | Goal |\n|---|---|\n| Agent | Sign in |\n\n'
      '## Acceptance Criteria\n\n- **Given** x\n',
    );
  });

  test(
    'stdin the format command refuses is written as given, draft aside',
    () async {
      final root = await writeWriteProject();
      const given =
          '---\nvision:\n  - PV-01\n---\n\n# Mine\n\n## Not a section\nx\n';
      writeIn(
        root,
        (s) => answerNew(
          s,
          docTypeId: 'user_story',
          parent: 'login',
          slug: 'a',
          text: given,
        ),
      );
      expect(
        readDoc(root, 'prds/features/f01_login/us04_a/USER_STORY.md'),
        given.replaceFirst('---\nvision', '---\ndraft: true\nvision'),
      );
    },
  );

  test('a text holding a column-0 naming line outside a fence is refused and nothing is created', () async {
    final root = await writeWriteProject();
    const naming =
        '==> other (feature) · prds/features/f01_other/FEATURE.md#problem · base 55884d229b07 <==';
    for (final text in [
      '# Mine\n\nExample:\n$naming\nbody\n',
      '---\nvision:\n  - PV-01\n---\n\n# Mine\n\n$naming\n',
    ]) {
      expect(
        () => writeIn(
          root,
          (s) => answerNew(
            s,
            docTypeId: 'user_story',
            parent: 'login',
            slug: 'quoted',
            text: text,
          ),
        ),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
              .having((f) => f.message, 'message', contains('"$naming"')),
        ),
        reason: text,
      );
    }
    expect(
      Directory('${root.path}/docs/prds/features/f01_login/us04_quoted')
          .existsSync(),
      isFalse,
    );
  });

  test('a naming line inside a fence or indented is written as text', () async {
    final root = await writeWriteProject();
    const naming =
        '==> other (feature) · prds/features/f01_other/FEATURE.md#problem · base 55884d229b07 <==';
    writeIn(
      root,
      (s) => answerNew(
        s,
        docTypeId: 'user_story',
        parent: 'login',
        slug: 'quoted',
        text: '# Mine\n\n```text\n$naming\n```\n\n    $naming\n',
      ),
    );
    expect(
      readDoc(root, 'prds/features/f01_login/us04_quoted/USER_STORY.md'),
      contains('```text\n$naming\n```\n\n    $naming\n'),
    );
  });

  group('with code targets', () {
    const feedback = 'prds/features/f02_feedback/FEATURE.md';
    const toast = 'prds/features/f02_feedback/f03_toast/FEATURE.md';

    Future<Directory> twinWithToast({Set<String> without = const {}}) =>
        writeTwinProject(
          without: without,
          extra: {
            '.specstone/templates/feature.yaml': 'max_depth: 3\n',
            'docs/$feedback': '---\ndraft: true\n---\n\n# Feedback\n',
            'docs/$toast': '---\ndraft: true\n---\n\n# Toast\n',
          },
        );

    List<String> docFiles(Directory root) => [
      for (final entity in Directory(
        '${root.path}/docs',
      ).listSync(recursive: true))
        if (entity is File) entity.path,
    ]..sort();

    test('--target jaspr places the doc in the jaspr spec folder under the shared feature', () async {
      for (final (target, other) in [
        ('jaspr', 'flutter'),
        ('flutter', 'jaspr'),
      ]) {
        final root = await twinWithToast(
          without: {'docs/$flutterArchitecture', 'docs/$jasprArchitecture'},
        );
        final path = 'specs/$target/f02_feedback/f03_toast/ARCHITECTURE.md';
        final answer = writeIn(
          root,
          (s) => answerNew(
            s,
            docTypeId: 'architecture',
            parent: 'feedback/toast',
            codeTarget: target,
          ),
        );
        expect(
          answer.text,
          '==> feedback/toast (architecture) · $path <==\n',
          reason: target,
        );
        expect(docOf(answer)['path'], path, reason: target);
        expect(hasDoc(root, path), isTrue, reason: target);
        expect(
          hasDoc(root, 'specs/$other/f02_feedback/f03_toast/ARCHITECTURE.md'),
          isFalse,
          reason: target,
        );
      }
    });

    test('a per-target doc type with two targets and no --target is argument_missing naming the targets, and creates nothing', () async {
      final root = await twinWithToast();
      final before = docFiles(root);
      expect(
        () => writeIn(
          root,
          (s) => answerNew(
            s,
            docTypeId: 'implementation',
            parent: 'feedback/toast',
          ),
        ),
        throwsA(
          indexFault(
            IndexFaultCode.argumentMissing,
            'implementation needs --target: the code targets are flutter, jaspr',
          ),
        ),
      );
      expect(docFiles(root), before);
    });

    test('a --target the project does not name is argument_invalid, and creates nothing', () async {
      final root = await twinWithToast();
      final before = docFiles(root);
      expect(
        () => writeIn(
          root,
          (s) => answerNew(
            s,
            docTypeId: 'implementation',
            parent: 'feedback/toast',
            codeTarget: 'dart',
          ),
        ),
        throwsA(
          indexFault(
            IndexFaultCode.argumentInvalid,
            '--target dart: the code targets are flutter, jaspr',
          ),
        ),
      );
      expect(docFiles(root), before);
    });

    for (final codeTarget in <String?>[null, 'flutter']) {
      test(
        'one target, ${codeTarget == null ? 'unnamed on the command line' : 'named'}, places a per-target doc at its one-target path',
        () async {
          final root = await writeTwinProject(
            without: {'docs/$flutterArchitecture', 'docs/$jasprArchitecture'},
            extra: {
              '.specstone/config.yaml':
                  '${shippedPinsConfig()}targets:\n'
                  '  flutter:\n    code_root: flutter_ws\n',
            },
          );
          const path = 'specs/f01_login/ARCHITECTURE.md';
          final answer = writeIn(
            root,
            (s) => answerNew(
              s,
              docTypeId: 'architecture',
              parent: 'login',
              codeTarget: codeTarget,
            ),
          );
          expect(docOf(answer)['path'], path);
          expect(hasDoc(root, path), isTrue);
        },
      );
    }

    test('a decision type with no per_target key takes d01 then d02 in one folder with two targets and no --target', () async {
      final root = await writeTwinProject(
        extra: {decisionLayerFile: decisionLayer},
      );
      for (final (slug, path) in [
        ('adopt_sqlite', 'specs/decisions/d01_adopt_sqlite.md'),
        ('use_wal', 'specs/decisions/d02_use_wal.md'),
      ]) {
        final answer = writeIn(
          root,
          (s) => answerNew(s, docTypeId: 'decision', slug: slug),
        );
        expect(docOf(answer)['path'], path);
        expect(hasDoc(root, path), isTrue);
      }
      expect(
        Directory('${root.path}/docs/specs/decisions').listSync(),
        hasLength(2),
      );
    });

    test('a twin already there is doc_exists naming the doc, not its target folder', () async {
      final root = await writeTwinProject();
      expect(
        () => writeIn(
          root,
          (s) => answerNew(
            s,
            docTypeId: 'architecture',
            parent: 'login',
            codeTarget: 'jaspr',
          ),
        ),
        throwsA(
          isA<WriteFault>()
              .having((f) => f.code, 'code', WriteFaultCode.docExists)
              .having(
                (f) => f.message,
                'message',
                'a architecture named login exists',
              )
              .having((f) => f.file, 'file', jasprArchitecture),
        ),
      );
    });
  });

  group('the planned record line', () {
    const record = '.specstone/records/f01_login/IMPLEMENTATION.md';
    const flutterRecord =
        '.specstone/records/flutter/f01_login/IMPLEMENTATION.md';
    const jasprRecord = '.specstone/records/jaspr/f01_login/IMPLEMENTATION.md';

    Future<Directory> withRecord(String text) =>
        writeWriteProject(extra: {...recordsRootTemplates, record: text});

    List<String> statusesIn(Directory root, String docPath) {
      final lines = readDoc(root, docPath).split('\n');
      final start = lines.indexOf('statuses:');
      return [
        for (final line
            in lines.skip(start + 1).takeWhile((l) => l.startsWith('  - ')))
          line.substring(4).replaceAll("'", ''),
      ];
    }

    test('new user_story adds its planned line to each record of the feature between its siblings', () async {
      for (final text in ['', '# Forgot email\n']) {
        final root = await writeTwinProject(
          extra: {
            flutterRecord: recordText(
              statuses: [
                'email_login:implemented',
                'email_login/check_password:implemented',
              ],
            ),
            jasprRecord: recordText(statuses: ['email_login:planned']),
          },
        );
        writeIn(
          root,
          (s) => answerNew(
            s,
            docTypeId: 'user_story',
            parent: 'login',
            slug: 'forgot_email',
            text: text,
          ),
        );
        expect(statusesIn(root, flutterRecord), [
          'email_login:implemented',
          'email_login/check_password:implemented',
          'forgot_email:planned',
        ], reason: text);
        expect(statusesIn(root, jasprRecord), [
          'email_login:planned',
          'forgot_email:planned',
        ], reason: text);
      }
    });

    test(
      "new fr adds its planned line to each record of its story's feature",
      () async {
        final root = await withRecord(
          recordText(
            statuses: [
              'email_login:implemented',
              'email_login/validate_credentials:implemented',
              'email_login/lock_after_failures:planned',
              'reset_password:planned',
            ],
          ),
        );
        writeIn(
          root,
          (s) => answerNew(
            s,
            docTypeId: 'fr',
            parent: 'login/email_login',
            slug: 'audit_log',
          ),
        );
        expect(statusesIn(root, record), [
          'email_login:implemented',
          'email_login/validate_credentials:implemented',
          'email_login/lock_after_failures:planned',
          'email_login/audit_log:planned',
          'reset_password:planned',
        ]);
      },
    );

    test(
      'new user_story adds no planned line to a record that skips its feature',
      () async {
        final root = await withRecord(
          recordText(statuses: [':skipped:no web view', 'email_login:planned']),
        );
        writeIn(
          root,
          (s) => answerNew(
            s,
            docTypeId: 'user_story',
            parent: 'login',
            slug: 'forgot_email',
          ),
        );
        expect(statusesIn(root, record), [
          ':skipped:no web view',
          'email_login:planned',
        ]);
      },
    );

    test(
      'new fr adds no planned line to a record that skips its story',
      () async {
        final root = await withRecord(
          recordText(statuses: ['email_login:skipped:no web view']),
        );
        writeIn(
          root,
          (s) => answerNew(
            s,
            docTypeId: 'fr',
            parent: 'login/email_login',
            slug: 'audit_log',
          ),
        );
        expect(statusesIn(root, record), ['email_login:skipped:no web view']);
      },
    );

    test('new user_story adds no planned line under a skip in a record of a feature above', () async {
      const shopRecord = '.specstone/records/f02_shop/IMPLEMENTATION.md';
      final root = await writeNestedProject(
        extra: {
          ...nestedRecords(),
          shopRecord: recordText(statuses: ['cart:skipped:no cart yet']),
        },
      );
      writeIn(
        root,
        (s) => answerNew(
          s,
          docTypeId: 'user_story',
          parent: 'shop/cart',
          slug: 'wish',
        ),
      );
      expect(statusesIn(root, cartRecord), [
        'add_item:implemented',
        'add_item/check_stock:implemented',
        'drop_item:implemented',
      ]);
    });

    test('a recordless feature gets no line and no record file', () async {
      final root = await writeWriteProject(extra: recordsRootTemplates);
      writeIn(
        root,
        (s) => answerNew(
          s,
          docTypeId: 'user_story',
          parent: 'login',
          slug: 'forgot_email',
        ),
      );
      expect(
        hasDoc(root, 'prds/features/f01_login/us04_forgot_email/USER_STORY.md'),
        isTrue,
      );
      expect(
        Directory('${root.path}/.specstone/records').existsSync(),
        isFalse,
      );
    });

    test(
      'a record the disk refuses leaves neither the doc nor any record written',
      () async {
        final root = await withRecord(
          recordText(statuses: ['email_login:implemented']),
        );
        final file = docFile(root, record);
        final before = file.readAsStringSync();
        expect(Process.runSync('chmod', ['444', file.path]).exitCode, 0);
        addTearDown(() => Process.runSync('chmod', ['644', file.path]));
        expect(
          () => writeIn(
            root,
            (s) => answerNew(
              s,
              docTypeId: 'user_story',
              parent: 'login',
              slug: 'forgot_email',
            ),
          ),
          throwsA(
            isA<RenderFault>()
                .having(
                  (f) => f.code,
                  'code',
                  RenderFaultCode.outputNotWritable,
                )
                .having((f) => f.message, 'message', contains(record)),
          ),
        );
        expect(file.readAsStringSync(), before);
        expect(
          Directory(
            '${root.path}/docs/prds/features/f01_login/us04_forgot_email',
          ).existsSync(),
          isFalse,
        );
      },
      skip: unreadablePathSkipReason() ?? false,
    );

    test('a planned line leaves an approved record approved', () async {
      final root = await withRecord(
        recordText(statuses: ['email_login:implemented']),
      );
      stampApproved(root, record);
      expect(holdsApproval(root, record), isTrue);
      writeIn(
        root,
        (s) => answerNew(
          s,
          docTypeId: 'user_story',
          parent: 'login',
          slug: 'forgot_email',
        ),
      );
      expect(statusesIn(root, record), [
        'email_login:implemented',
        'forgot_email:planned',
      ]);
      expect(holdsApproval(root, record), isTrue);
    });

    test('a record step that fails after the journal is saved leaves the doc and finishes every record on the next write', () async {
      final root = await writeTwinProject(
        extra: {
          flutterRecord: recordText(statuses: ['email_login:implemented']),
          jasprRecord: recordText(statuses: ['email_login:planned']),
        },
      );
      final folder = Directory(
        '${root.path}/.specstone/records/jaspr/f01_login',
      );
      expect(Process.runSync('chmod', ['555', folder.path]).exitCode, 0);
      addTearDown(() => Process.runSync('chmod', ['755', folder.path]));
      expect(
        () => writeIn(
          root,
          (s) => answerNew(
            s,
            docTypeId: 'user_story',
            parent: 'login',
            slug: 'forgot_email',
          ),
        ),
        throwsA(isA<RenderFault>()),
      );
      Process.runSync('chmod', ['755', folder.path]);
      writeIn(root, (s) => s.index.docs.length);
      expect(
        hasDoc(root, 'prds/features/f01_login/us02_forgot_email/USER_STORY.md'),
        isTrue,
      );
      for (final path in [flutterRecord, jasprRecord]) {
        expect(statusesIn(root, path), contains('forgot_email:planned'));
      }
    }, skip: unreadablePathSkipReason() ?? false);

    test('a fault after the journal is deleted keeps the doc and every record line', () async {
      final root = await withRecord(
        recordText(statuses: ['email_login:implemented']),
      );
      expect(
        () => IOOverrides.runWithIOOverrides(
          () => writeIn(
            root,
            (s) => answerNew(
              s,
              docTypeId: 'user_story',
              parent: 'login',
              slug: 'forgot_email',
            ),
          ),
          _FailingDeleteHook('.specstone/trash/journal.cursor'),
        ),
        throwsA(isA<RenderFault>()),
      );
      expect(
        hasDoc(root, 'prds/features/f01_login/us04_forgot_email/USER_STORY.md'),
        isTrue,
      );
      expect(statusesIn(root, record), contains('forgot_email:planned'));
    });

    test('a fault before the journal is saved removes the claimed doc while a foreign journal file exists', () async {
      final root = await withRecord(
        recordText(statuses: ['email_login:implemented']),
      );
      expect(
        () => writeInNoHome(root, (s) {
          // Another writer's journal appears once this session is open.
          writeJournal(root, [
            WriteStep(
              'docs/prds/personas/buyer/PERSONA.md',
              'x',
              before: textHashOf(''),
            ),
          ], recorded: false);
          return answerNew(
            s,
            docTypeId: 'user_story',
            parent: 'login',
            slug: 'forgot_email',
          );
        }),
        throwsA(isA<RenderFault>()),
      );
      expect(
        Directory('${root.path}/docs/prds/features/f01_login/us04_forgot_email')
            .existsSync(),
        isFalse,
      );
    });
  });
}

/// Makes `deleteSync` throw for the one file whose path ends with the path
/// given, as a disk that refuses that one delete does.
final class _FailingDeleteHook extends IOOverrides {
  new(this._pathEnd);

  final String _pathEnd;

  @override
  File createFile(String path) => path.replaceAll(r'\', '/').endsWith(_pathEnd)
      ? _FailingDeleteFile(super.createFile(path))
      : super.createFile(path);
}

final class _FailingDeleteFile extends ForwardingFile {
  const new(super.inner);

  @override
  void deleteSync({bool recursive = false}) =>
      throw FileSystemException('Permission denied', path);
}

final class _NoFiles implements LayerFiles {
  const new();

  @override
  bool exists(String layerRelativePath) => false;
}
