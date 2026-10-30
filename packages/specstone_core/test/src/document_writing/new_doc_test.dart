import 'dart:io';
import 'dart:isolate';

import 'package:specstone_core/src/document_writing/new_doc.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/posix_modes.dart';
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
  test('f02/us02/s1, f02/us02/fr01, f02/us02/fr01/e01, f02/us02/fr02, f02/us02/fr02/e01, dw-s03/inv6: a story with no text is the skeleton at the next number', () async {
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
    final text = readDoc(root, path);
    expect(
      text,
      '---\ndraft: true\n---\n\n# forgot_email\n\n'
      '## Use Case\n'
      '- **As a** <Role> [who <situation>]\n'
      '- **I want to** <action>\n'
      '- **so that** <benefit>\n\n'
      '## Acceptance Criteria\n'
      '### Scenario 1 — [happy] <what differs>\n'
      '- **Given** <only the state the scenario needs>\n'
      '- **When** <one trigger>\n'
      '- **Then** <observed outcome>\n\n'
      '### Scenario 2 — [error] <what differs> (BR-01)\n'
      '- **Given** <only the state the scenario needs>\n'
      '- **When** <one trigger>\n'
      '- **Then** <what the person sees or what the system refuses>\n',
    );
  });

  test('f02/us02/s6, f02/us02/fr01/e08: a slug a sibling carries is doc_exists naming it, and no file is created', () async {
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
  });

  test('f02/us02/fr01/e10: a missing --parent is argument_missing with the sidecar message', () async {
    final root = await writeWriteProject();
    expect(
      () => writeIn(
        root,
        (s) => answerNew(s, docTypeId: 'user_story', slug: 'x'),
      ),
      throwsA(
        indexFault(
          IndexFaultCode.argumentMissing,
          'user_story needs --parent, the name of a feature',
        ),
      ),
    );
  });

  test('f02/us02/s2, f02/us02/fr02/e03, f02/us02/fr02/e04: given text keeps its blocks and is forced to draft: true', () async {
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
      '---\ndraft: true\n---\n# Mine\n',
    );
  });

  test('f02/us02/s3, f02/us02/fr01/e02: after a gap the new doc takes the highest number plus one', () async {
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

  test('f02/us02/s4, f02/us02/fr01/e03: two new calls under one parent at once take two numbers', () async {
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

  test('f02/us02/s5, f02/us02/fr01/e04, f02/us02/fr02/e07: a spec doc lands in the feature spec folder titled with its slug', () async {
    final root = await writeWriteProject();
    final answer = writeIn(
      root,
      (s) => answerNew(s, docTypeId: 'api', parent: 'login'),
    );
    expect(answer.json['path'], 'specs/f01_login/API.md');
    expect(readDoc(root, 'specs/f01_login/API.md'), contains('\n\n# login\n'));
  });

  test('f02/us02/fr01/e05: a feature takes the next feature number', () async {
    final root = await writeWriteProject();
    writeIn(root, (s) => answerNew(s, docTypeId: 'feature', slug: 'billing'));
    expect(hasDoc(root, 'prds/features/f03_billing/FEATURE.md'), isTrue);
  });

  test('f02/us02/fr01/e06: a doc type with no placeholder is created once, then doc_exists', () async {
    final root = await writeWriteProject();
    writeIn(root, (s) => answerNew(s, docTypeId: 'project'));
    expect(readDoc(root, 'prds/PROJECT.md'), contains('\n\n# project\n'));
    expect(
      () => writeIn(root, (s) => answerNew(s, docTypeId: 'project')),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.code, 'code', WriteFaultCode.docExists)
            .having((f) => f.file, 'file', 'prds/PROJECT.md'),
      ),
    );
  });

  test(
    'f02/us02/fr01/e07: another doc type in the same folder is no clash',
    () async {
      final root = await writeWriteProject(
        extra: {'docs/prds/personas/seller/PERSONA.md': '# Seller\n'},
      );
      writeIn(
        root,
        (s) => answerNew(s, docTypeId: 'anti_persona', slug: 'seller'),
      );
      expect(hasDoc(root, 'prds/personas/seller/ANTI_PERSONA.md'), isTrue);
    },
  );

  test(
    'f02/us02/s7, f02/us02/fr01/e09: a parent no doc carries is doc_not_found',
    () async {
      final root = await writeWriteProject();
      expect(
        () => writeIn(
          root,
          (s) => answerNew(
            s,
            docTypeId: 'user_story',
            parent: 'nobody',
            slug: 'x',
          ),
        ),
        throwsA(
          isA<IndexFault>().having(
            (f) => f.code,
            'code',
            IndexFaultCode.docNotFound,
          ),
        ),
      );
    },
  );

  test('f02/us02/fr01/e10: a missing --slug, a --parent or --slug the type takes no value for, or a bad slug is refused', () async {
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
      'feature takes no --parent',
      type: 'feature',
      parent: 'login',
      slug: 'x',
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

  test('f02/us02/fr01/e11: an unknown doc type is doc_type_unknown', () async {
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

  test('f02/us02/fr01/e12: the 100th story takes three digits', () async {
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

  test('f02/us02/fr01/e13, nfr-di01: an unwritable feature folder is output_not_writable and leaves nothing behind', () async {
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

  test('f02/us02/fr01/e13, nfr-di01: a write that fails after the claim removes the claimed file and the folders new made', () async {
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

  test('f02/us02/fr01/e03, PD18: a path taken between the sibling count and the claim moves the new doc to the next number', () async {
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

  test(
    'f02/us02/fr02/e02: an fr skeleton writes its required fields empty',
    () async {
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
    },
  );

  test(
    'f02/us02/fr02/e05: text that lacks a required section is written as given',
    () async {
      final root = await writeWriteProject();
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
        readDoc(root, 'prds/features/f01_login/us04_plain/USER_STORY.md'),
        '---\ndraft: true\n---\n# Plain\n\nJust prose.\n',
      );
    },
  );

  test('f02/us02/fr02/e01, final Minor 5: stdin holding an approved key refuses before any path is claimed', () async {
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
                'approved is written only by specstone approve',
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
  });

  test('f02/us02/fr02/e06: empty text gives the skeleton', () async {
    final root = await writeWriteProject();
    writeIn(
      root,
      (s) => answerNew(s, docTypeId: 'feature', slug: 'billing', text: ''),
    );
    expect(
      readDoc(root, 'prds/features/f03_billing/FEATURE.md'),
      startsWith('---\ndraft: true\n---\n\n# billing\n\n## '),
    );
  });

  test('f02/us02/fr01: --json gives name, docType, path, and the bases get --json gives', () async {
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
    expect(answer.json['name'], 'login/forgot_email');
    expect(answer.json['docType'], 'user_story');
    expect(
      answer.json['path'],
      'prds/features/f01_login/us04_forgot_email/USER_STORY.md',
    );
    expect(
      answer.json['bases'],
      getDoc(root, 'user_story:login/forgot_email')['bases'],
    );
  });

  test('f06/us03/fr02: skeletonOf writes draft true, each required field '
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
    expect(text, contains('\n# tech_stack\n'));
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

  test('f02/us02/fr02, f02/us02/fr02/e03: given text stays verbatim and draft lands at its field slot', () async {
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
      '---\ndraft: true\npersona:\n  - owner\n'
      'vision:\n  - PV-01\n---\n\n# Mine\n',
    );
  });
}
