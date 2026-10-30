// The plan's test literals are kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';
import 'dart:isolate';

import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/document_writing/set_doc.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart' show spots;
import '../../helpers/index_fixture.dart' show openSession;
import '../../helpers/posix_modes.dart';
import '../../helpers/write_fixture.dart';

SetRequest req(String target, String base) =>
    SetRequest.parse(target, base: base);

SetRequest fieldReq(String target, String id, String base) =>
    SetRequest.parse(target, field: id, base: base);

String sectionBase(Directory root, String target) =>
    getDoc(root, target)['base']! as String;

String fieldBase(Directory root, String target, String id) =>
    ((getDoc(root, target)['bases']! as Map)['fields']! as Map)[id]! as String;

void main() {
  test(
    'f02/us01/fr01/e12, f02/us01/fr04/e06: set names one target and a base',
    () {
      expect(
        () => SetRequest.parse(null, base: 'abc'),
        throwsA(
          isA<IndexFault>().having(
            (f) => f.code,
            'code',
            IndexFaultCode.argumentMissing,
          ),
        ),
      );
      expect(
        () => SetRequest.parse(
          'user_story:a/b#use_case',
          field: 'status',
          base: 'abc',
        ),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.argumentConflict)
              .having(
                (f) => f.message,
                'message',
                'set takes one target: a section key, --field, or --title',
              ),
        ),
      );
      expect(
        () => SetRequest.parse(
          'user_story:a/b',
          field: 'status',
          title: true,
          base: 'abc',
        ),
        throwsA(
          isA<IndexFault>().having(
            (f) => f.code,
            'code',
            IndexFaultCode.argumentConflict,
          ),
        ),
      );
      expect(
        () => SetRequest.parse('user_story:a/b', base: 'abc'),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.argumentMissing)
              .having(
                (f) => f.message,
                'message',
                startsWith(
                  'set needs a section key, --field, or --title, such as ',
                ),
              ),
        ),
      );
      expect(
        () => SetRequest.parse('user_story:a/b#use_case'),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.argumentMissing)
              .having(
                (f) => f.message,
                'message',
                startsWith('set needs --base, such as '),
              ),
        ),
      );
    },
  );

  test(
    'f02/us01/fr01/e12: set parses the address, the target, and the base',
    () {
      final section = SetRequest.parse(
        'user_story:login/email_login#use_case',
        base: 'abc',
      );
      expect(
        (section.address, section.base),
        ('user_story:login/email_login', 'abc'),
      );
      expect(
        section.target,
        isA<SectionTarget>().having((t) => t.key, 'key', 'use_case'),
      );
      expect(
        SetRequest.parse('user_story:a/b', field: 'status', base: 'x').target,
        isA<FieldTarget>(),
      );
      expect(
        SetRequest.parse('user_story:a/b', title: true, base: 'x').target,
        isA<TitleTarget>(),
      );
    },
  );

  test(
    'dw-s03/inv4: markDraft leaves a draft alone and marks any other doc',
    () {
      expect(
        markDraft('---\ndraft: true\n---\n# T\n'),
        '---\ndraft: true\n---\n# T\n',
      );
      expect(
        markDraft('---\nstatus: planned\n---\n# T\n'),
        '---\nstatus: planned\ndraft: true\n---\n# T\n',
      );
      expect(markDraft('# T\n'), '---\ndraft: true\n---\n# T\n');
    },
  );

  test('f02/us01/s1, f02/us01/fr01, f02/us01/fr01/e01, dw-s03/inv1, dw-s03/inv13: only the section body changes, and the new base prints', () async {
    final root = await writeWriteProject();
    final before = readDoc(root, story1);
    const target = 'user_story:login/email_login#acceptance_criteria';
    const body =
        '\n### Scenario 1 — [happy] Sign in\n- **Given** a registered email and its password\n';
    final answer = writeIn(
      root,
      (s) => answerSet(s, req(target, sectionBase(root, target)), body),
    );
    expect(
      readDoc(root, story1),
      before.replaceFirst(
        'a registered email\n',
        'a registered email and its password\n',
      ),
    );
    expect(
      answer.text,
      '==> login/email_login (user_story) · $story1 · base ${baseHashOf(body)} <==\n',
    );
    expect(answer.json, {
      'name': 'login/email_login',
      'docType': 'user_story',
      'path': story1,
      'base': baseHashOf(body),
      'draft': true,
    });
    expect(sectionBase(root, target), baseHashOf(body));
  });

  test('f02/us01/s2, f02/us01/fr05/e01, f02/us01/fr01/e03: two Agents write two sections of one doc at once and both land', () async {
    final root = await writeWriteProject();
    final path = root.path;
    final useCase = sectionBase(root, 'user_story:login/email_login#use_case');
    final criteria = sectionBase(
      root,
      'user_story:login/email_login#acceptance_criteria',
    );
    String write(String key, String base, String body) => WriteSession.run(
      (s) => answerSet(
        s,
        req('user_story:login/email_login#$key', base),
        body,
      ).text,
      templates: TemplateResolver(),
      workingDirectory: Directory(path),
      homeDirectory: null,
    );
    await Future.wait([
      Isolate.run(
        () => write('use_case', useCase, 'Sign in with a passkey.\n'),
      ),
      Isolate.run(
        () => write('acceptance_criteria', criteria, '- **Given** a passkey\n'),
      ),
    ]);
    expect(
      readDoc(root, story1),
      allOf(
        contains('## Use Case\nSign in with a passkey.\n'),
        contains('## Acceptance Criteria\n- **Given** a passkey\n'),
      ),
    );
  });

  test('f02/us01/s8, f02/us01/fr02, f02/us01/fr02/e01, f02/us01/fr01/e02, f02/us01/fr05/e02, nfr-di01: a stale base is refused with the current section, the file untouched', () async {
    final root = await writeWriteProject();
    const target = 'user_story:login/email_login#use_case';
    final base = sectionBase(root, target);
    writeIn(root, (s) => answerSet(s, req(target, base), 'First writer.\n'));
    final before = readDoc(root, story1);
    final current = baseHashOf('First writer.\n');
    expect(
      () => writeIn(
        root,
        (s) => answerSet(s, req(target, base), 'Second writer.\n'),
      ),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.code, 'code', WriteFaultCode.baseMismatch)
            .having((f) => f.exitStatus, 'exitStatus', 75)
            .having(
              (f) => f.message,
              'message',
              'the section changed since base $base',
            )
            .having((f) => (f.file, f.key), 'location', (story1, 'use_case'))
            .having(
              (f) => f.current?.text,
              'current.text',
              '## Use Case\nFirst writer.\n',
            )
            .having((f) => f.current?.base, 'current.base', current)
            .having(
              (f) => f.current?.heading,
              'heading',
              '==> login/email_login (user_story) · $story1 · base $current <==',
            ),
      ),
    );
    expect(readDoc(root, story1), before);
  });

  test('f02/us01/s6, f02/us01/fr01/e04, dw-s03/inv13: a template section the doc lacks is added at its template place', () async {
    final root = await writeWriteProject();
    writeIn(
      root,
      (s) => answerSet(
        s,
        req('user_story:login/email_login#rules', emptyBaseHash),
        '- BR-01 One account per email.\n',
      ),
    );
    expect(
      readDoc(root, story1),
      contains(
        'Sign in with an email.\n\n## Rules\n- BR-01 One account per email.\n\n## Acceptance Criteria\n',
      ),
    );
  });

  test('f02/us01/fr01/e05: a key no template defines and the doc lacks is section_not_found', () async {
    final root = await writeWriteProject();
    final before = readDoc(root, story1);
    expect(
      () => writeIn(
        root,
        (s) => answerSet(
          s,
          req('user_story:login/email_login#notes', emptyBaseHash),
          'x\n',
        ),
      ),
      throwsA(
        isA<IndexFault>()
            .having((f) => f.code, 'code', IndexFaultCode.sectionNotFound)
            .having(
              (f) => f.message,
              'message',
              'user_story:login/email_login holds no section with the key notes, and its template defines none',
            ),
      ),
    );
    expect(readDoc(root, story1), before);
  });

  test('f02/us01/s7, f02/us01/fr01/e06: empty stdin removes an optional section', () async {
    final root = await writeWriteProject(
      extra: {
        'docs/$story1':
            '${writeProject['docs/$story1']!}\n## Rules\n- BR-01 One account per email.\n',
      },
    );
    const target = 'user_story:login/email_login#rules';
    expect(readDoc(root, story1), contains('## Rules'));
    final answer = writeIn(
      root,
      (s) => answerSet(s, req(target, sectionBase(root, target)), ''),
    );
    expect(readDoc(root, story1), isNot(contains('## Rules')));
    expect(readDoc(root, story1), contains('## Acceptance Criteria'));
    expect(answer.json['base'], emptyBaseHash);
  });

  test('f02/us01/s10, f02/us01/fr01/e07: empty stdin on a required section is required_target', () async {
    final root = await writeWriteProject();
    const target = 'user_story:login/email_login#use_case';
    final before = readDoc(root, story1);
    expect(
      () => writeIn(
        root,
        (s) => answerSet(s, req(target, sectionBase(root, target)), ''),
      ),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.code, 'code', WriteFaultCode.requiredTarget)
            .having(
              (f) => f.message,
              'message',
              'user_story requires the section use_case',
            )
            .having((f) => (f.file, f.key), 'location', (story1, 'use_case')),
      ),
    );
    expect(readDoc(root, story1), before);
  });

  test('f02/us01/fr01/e08, dw-s03/inv4: a doc without draft gains draft: true after its last key block, a doc with no frontmatter gains one', () async {
    final root = await writeWriteProject();
    const useCase = 'user_story:login/sign_out#use_case';
    writeIn(
      root,
      (s) => answerSet(
        s,
        req(useCase, sectionBase(root, useCase)),
        'Sign out now.\n',
      ),
    );
    expect(
      readDoc(root, story2),
      startsWith('---\nstatus: planned\napproved: true\ndraft: true\n---\n'),
    );
    expect(readDoc(root, story2), contains('## Use Case\nSign out now.\n'));

    const systems = 'features:features#systems';
    writeIn(
      root,
      (s) => answerSet(
        s,
        req(systems, sectionBase(root, systems)),
        '- [Login](features/f01_login/FEATURE.md)\n',
      ),
    );
    expect(
      readDoc(root, 'prds/FEATURES.md'),
      startsWith('---\ndraft: true\n---\n# Feature index\n'),
    );
  });

  test(
    'f02/us01/s12, f02/us01/fr01/e10: an old-format doc is untyped_target',
    () async {
      final root = await writeWriteProject();
      final before = readDoc(root, 'prds/d01_context.md');
      expect(
        () => writeIn(
          root,
          (s) => answerSet(
            s,
            req('prds/d01_context.md#features', emptyBaseHash),
            'x\n',
          ),
        ),
        throwsA(
          isA<IndexFault>().having(
            (f) => f.code,
            'code',
            IndexFaultCode.untypedTarget,
          ),
        ),
      );
      expect(readDoc(root, 'prds/d01_context.md'), before);
    },
  );

  test('f02/us01/s13, f02/us01/fr01/e11: a doc deleted after it was read is doc_not_found, and no file is created', () async {
    final root = await writeWriteProject();
    const target = 'user_story:login/email_login#use_case';
    final base = sectionBase(root, target);
    expect(
      () => writeIn(root, (s) {
        docFile(root, story1).deleteSync();
        return answerSet(s, req(target, base), 'x\n');
      }),
      throwsA(
        isA<IndexFault>()
            .having((f) => f.code, 'code', IndexFaultCode.docNotFound)
            .having(
              (f) => f.message,
              'message',
              'no user_story doc carries the name login/email_login',
            ),
      ),
    );
    expect(hasDoc(root, story1), isFalse);
  });

  test('f02/us01/fr01/e13, nfr-di01: an unwritable folder is output_not_writable and the doc keeps its bytes', () async {
    final root = await writeWriteProject();
    const target = 'user_story:login/email_login#use_case';
    final base = sectionBase(root, target);
    final before = readDoc(root, story1);
    final folder = docFile(root, story1).parent;
    Process.runSync('chmod', ['555', folder.path]);
    addTearDown(() => Process.runSync('chmod', ['755', folder.path]));
    expect(
      () => writeIn(root, (s) => answerSet(s, req(target, base), 'x\n')),
      throwsA(
        isA<RenderFault>().having(
          (f) => f.code,
          'code',
          RenderFaultCode.outputNotWritable,
        ),
      ),
    );
    expect(readDoc(root, story1), before);
    expect(
      folder.listSync().map((e) => e.path),
      isNot(contains(contains('.specstone.tmp'))),
    );
  }, skip: unreadablePathSkipReason() ?? false);

  test('f02/us01/fr01/e07, final Important 2: a read-only doc is output_not_writable and keeps its bytes and mode', () async {
    final root = await writeWriteProject();
    const target = 'user_story:login/email_login#use_case';
    final base = sectionBase(root, target);
    final before = readDoc(root, story1);
    final file = docFile(root, story1);
    Process.runSync('chmod', ['444', file.path]);
    addTearDown(() => Process.runSync('chmod', ['644', file.path]));
    expect(
      () => writeIn(root, (s) => answerSet(s, req(target, base), 'x\n')),
      throwsA(
        isA<RenderFault>()
            .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
            .having(
              (f) => f.message,
              'message',
              'cannot write $story1: read-only',
            ),
      ),
    );
    expect(readDoc(root, story1), before);
    expect(file.statSync().mode & 0x80, 0);
  }, skip: unreadablePathSkipReason() ?? false);

  test('f02/us01/fr01/e14: a hand edit is read as it is on disk', () async {
    final root = await writeWriteProject();
    const target = 'user_story:login/email_login#use_case';
    docFile(root, story1).writeAsStringSync(
      readDoc(
        root,
        story1,
      ).replaceFirst('Sign in with an email.', 'Sign in by hand.'),
    );
    final base = sectionBase(root, target);
    writeIn(root, (s) => answerSet(s, req(target, base), 'Sign in again.\n'));
    expect(readDoc(root, story1), contains('## Use Case\nSign in again.\n'));
  });

  test(
    'f02/us01/fr01/e15: a body line starting ## is argument_invalid',
    () async {
      final root = await writeWriteProject();
      final before = readDoc(root, story1);
      expect(
        () => writeIn(
          root,
          (s) => answerSet(
            s,
            req('user_story:login/email_login#use_case', emptyBaseHash),
            '## Sub\nx\n',
          ),
        ),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
              .having(
                (f) => f.message,
                'message',
                'the body holds the header line "## Sub"; send the body only',
              ),
        ),
      );
      expect(readDoc(root, story1), before);
    },
  );

  test('f02/us01/fr02/e03: a template section removed after the read refuses with empty current text and the empty base', () async {
    final root = await writeWriteProject();
    const target = 'user_story:login/email_login#use_case';
    final base = sectionBase(root, target);
    docFile(root, story1).writeAsStringSync(
      readDoc(
        root,
        story1,
      ).replaceFirst('## Use Case\nSign in with an email.\n\n', ''),
    );
    final before = readDoc(root, story1);
    expect(
      () => writeIn(root, (s) => answerSet(s, req(target, base), 'x\n')),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.code, 'code', WriteFaultCode.baseMismatch)
            .having((f) => f.current?.text, 'current.text', '')
            .having((f) => f.current?.base, 'current.base', emptyBaseHash),
      ),
    );
    expect(readDoc(root, story1), before);
  });

  test('f02/us01/fr02/e05: a non-template section removed after the read is section_not_found', () async {
    final root = await writeWriteProject(
      extra: {
        'docs/$story1': '${writeProject['docs/$story1']!}\n## Notes\nfirst\n',
      },
    );
    const target = 'user_story:login/email_login#notes';
    final base = sectionBase(root, target);
    docFile(root, story1).writeAsStringSync(
      readDoc(root, story1).replaceFirst('\n## Notes\nfirst\n', ''),
    );
    final before = readDoc(root, story1);
    expect(
      () => writeIn(root, (s) => answerSet(s, req(target, base), 'x\n')),
      throwsA(
        isA<IndexFault>().having(
          (f) => f.code,
          'code',
          IndexFaultCode.sectionNotFound,
        ),
      ),
    );
    expect(readDoc(root, story1), before);
  });

  test('review focus 1, dw-s03/inv1: a CRLF doc keeps CRLF, and its base is its LF twin base', () async {
    final root = await writeWriteProject();
    docFile(
      root,
      story1,
    ).writeAsStringSync(readDoc(root, story1).replaceAll('\n', '\r\n'));
    const target = 'user_story:login/email_login#use_case';
    final answer = writeIn(
      root,
      (s) => answerSet(
        s,
        req(target, sectionBase(root, target)),
        'Sign in fast.\n',
      ),
    );
    expect(readDoc(root, story1).replaceAll('\r\n', ''), isNot(contains('\n')));
    expect(readDoc(root, story1), contains('## Use Case\r\nSign in fast.\r\n'));
    expect(answer.json['base'], baseHashOf('Sign in fast.\n'));
  });

  test('review focus 3, dw-s03/inv1: a body with no final newline or with trailing blank lines ends in one newline', () async {
    for (final body in ['Sign in fast.', 'Sign in fast.\n\n\n']) {
      final root = await writeWriteProject();
      const target = 'user_story:login/email_login#use_case';
      final answer = writeIn(
        root,
        (s) => answerSet(s, req(target, sectionBase(root, target)), body),
      );
      expect(
        readDoc(root, story1),
        contains('## Use Case\nSign in fast.\n\n## Acceptance Criteria'),
      );
      expect(answer.json['base'], sectionBase(root, target));
    }
  });

  test('review focus 4, PD4: two sections with one key: set writes the first', () async {
    final root = await writeWriteProject(
      extra: {
        'docs/$story1':
            '${writeProject['docs/$story1']!}\n## Notes\nfirst\n\n## Notes\nsecond\n',
      },
    );
    const target = 'user_story:login/email_login#notes';
    writeIn(
      root,
      (s) => answerSet(s, req(target, sectionBase(root, target)), 'changed\n'),
    );
    expect(
      readDoc(root, story1),
      contains('## Notes\nchanged\n\n## Notes\nsecond\n'),
    );
  });

  test('f02/us01/s3, f02/us01/fr03, f02/us01/fr03/e01, dw-s03/inv14: a field block is rewritten and every other block kept', () async {
    final root = await writeWriteProject();
    const target = 'user_story:login/email_login';
    writeIn(
      root,
      (s) => answerSet(
        s,
        fieldReq(target, 'vision', fieldBase(root, target, 'vision')),
        '- PV-02\n',
      ),
    );
    expect(
      readDoc(root, story1),
      startsWith(
        '---\nstatus: planned\ndraft: true\nvision:\n  - PV-02\npersona:\n  - buyer\n---\n',
      ),
    );
  });
  test('f02/us01/s4, f02/us01/fr03/e02, dw-s03/inv4: an implements edit leaves an approved FR approved', () async {
    final root = await writeWriteProject();
    const target = 'fr:login/email_login/validate_credentials';
    final answer = writeIn(
      root,
      (s) => answerSet(
        s,
        fieldReq(target, 'implements', fieldBase(root, target, 'implements')),
        '- app/lib/src/login/password_check.dart:checkPassword\n',
      ),
    );
    expect(readDoc(root, fr11), isNot(contains('draft:')));
    expect(
      readDoc(root, fr11),
      contains(
        'implements:\n  - app/lib/src/login/password_check.dart:checkPassword\n',
      ),
    );
    expect(answer.json['draft'], isFalse);
  });
  test(
    'f02/us01/s9, f02/us01/fr03/e04: draft and approved are field_not_writable',
    () async {
      final root = await writeWriteProject();
      expect(
        () => writeIn(
          root,
          (s) => answerSet(
            s,
            fieldReq(
              'fr:login/email_login/validate_credentials',
              'draft',
              emptyBaseHash,
            ),
            'true\n',
          ),
        ),
        throwsA(
          isA<WriteFault>()
              .having((f) => f.code, 'code', WriteFaultCode.fieldNotWritable)
              .having(
                (f) => f.message,
                'message',
                'draft is written only by specstone approve',
              )
              .having((f) => (f.file, f.key), 'location', (fr11, 'draft')),
        ),
      );
      expect(
        () => writeIn(
          root,
          (s) => answerSet(
            s,
            fieldReq(
              'fr:login/email_login/validate_credentials',
              'approved',
              emptyBaseHash,
            ),
            'true\n',
          ),
        ),
        throwsA(
          isA<WriteFault>()
              .having((f) => f.code, 'code', WriteFaultCode.fieldNotWritable)
              .having(
                (f) => f.message,
                'message',
                'approved is written only by specstone approve',
              ),
        ),
      );
    },
  );
  test('f02/us01/s5, f02/us01/fr04, f02/us01/fr04/e01, f02/us01/fr04/e05: a new title keeps the folder and the name, and marks the doc draft', () async {
    final root = await writeWriteProject();
    final base =
        (getDoc(root, 'feature:login')['bases']! as Map)['title']! as String;
    final answer = writeIn(
      root,
      (s) => answerSet(
        s,
        SetRequest.parse('feature:login', title: true, base: base),
        'Sign in\n',
      ),
    );
    expect(
      readDoc(root, loginFeature),
      '---\nvision:\n  - PV-01\ndraft: true\n---\n\n# Sign in\n\n## Problem\nUsers sign in with an email and a password.\n',
    );
    expect(
      answer.text,
      '==> login (feature) · $loginFeature · base ${baseHashOf('Sign in')} <==\n',
    );
  });

  test('f02/us01/fr03/e03: a covers edit leaves an approved architecture doc approved', () async {
    final root = await writeWriteProject();
    const target = 'architecture:login';
    final answer = writeIn(
      root,
      (s) => answerSet(
        s,
        fieldReq(target, 'covers', fieldBase(root, target, 'covers')),
        '- app/lib/src/login/\n',
      ),
    );
    expect(readDoc(root, loginArch), isNot(contains('draft')));
    expect(
      readDoc(root, loginArch),
      contains('covers:\n  - app/lib/src/login/\n'),
    );
    expect(answer.json['draft'], isFalse);
  });
  test('f02/us01/fr03/e05: status on a feature is field_not_writable; on a story it is written', () async {
    final root = await writeWriteProject();
    expect(
      () => writeIn(
        root,
        (s) => answerSet(
          s,
          fieldReq('feature:login', 'status', emptyBaseHash),
          'implemented\n',
        ),
      ),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.code, 'code', WriteFaultCode.fieldNotWritable)
            .having(
              (f) => f.message,
              'message',
              'the status of a feature is computed from its stories',
            )
            .having((f) => (f.file, f.key), 'location', (
              loginFeature,
              'status',
            )),
      ),
    );
    const story = 'user_story:login/email_login';
    final answer = writeIn(
      root,
      (s) => answerSet(
        s,
        fieldReq(story, 'status', fieldBase(root, story, 'status')),
        'implemented\n',
      ),
    );
    expect(readDoc(root, story1), startsWith('---\nstatus: implemented\n'));
    expect(answer.json['base'], baseHashOf('status: implemented\n'));
  });
  test('f02/us01/s11, f02/us01/fr03/e06: a value outside the enum is field_value_invalid', () async {
    final root = await writeWriteProject();
    const target = 'fr:login/email_login/validate_credentials';
    expect(
      () => writeIn(
        root,
        (s) => answerSet(
          s,
          fieldReq(
            target,
            'verify_method',
            fieldBase(root, target, 'verify_method'),
          ),
          'maybe\n',
        ),
      ),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.code, 'code', WriteFaultCode.fieldValueInvalid)
            .having(
              (f) => f.message,
              'message',
              'verify_method takes one of test, analysis, inspection, demonstration',
            )
            .having((f) => (f.file, f.key), 'location', (
              fr11,
              'verify_method',
            )),
      ),
    );
  });
  test('f02/us01/fr03/e07: a scalar for a list, a list for a scalar, or invalid YAML is field_value_invalid', () async {
    final root = await writeWriteProject();
    const story = 'user_story:login/email_login';
    expect(
      () => writeIn(
        root,
        (s) => answerSet(
          s,
          fieldReq(story, 'vision', fieldBase(root, story, 'vision')),
          'PV-02\n',
        ),
      ),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.code, 'code', WriteFaultCode.fieldValueInvalid)
            .having((f) => f.message, 'message', 'vision takes a list'),
      ),
    );
    const fr = 'fr:login/email_login/validate_credentials';
    expect(
      () => writeIn(
        root,
        (s) => answerSet(
          s,
          fieldReq(fr, 'verify_method', fieldBase(root, fr, 'verify_method')),
          '- test\n',
        ),
      ),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.code, 'code', WriteFaultCode.fieldValueInvalid)
            .having(
              (f) => f.message,
              'message',
              'verify_method takes one value',
            ),
      ),
    );
    expect(
      () => writeIn(
        root,
        (s) => answerSet(
          s,
          fieldReq(story, 'vision', fieldBase(root, story, 'vision')),
          '[\n',
        ),
      ),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.code, 'code', WriteFaultCode.fieldValueInvalid)
            .having((f) => f.message, 'message', 'vision takes a YAML value'),
      ),
    );
  });
  test('f02/us01/fr03/e08: empty stdin removes an optional field, and refuses a required one', () async {
    final root = await writeWriteProject();
    const story = 'user_story:login/email_login';
    writeIn(
      root,
      (s) => answerSet(
        s,
        fieldReq(story, 'persona', fieldBase(root, story, 'persona')),
        '\n',
      ),
    );
    expect(
      readDoc(root, story1),
      startsWith(
        '---\nstatus: planned\ndraft: true\nvision:\n  - PV-01\n---\n',
      ),
    );
    expect(
      () => writeIn(
        root,
        (s) => answerSet(
          s,
          fieldReq(
            'fr:login/reset_password/expire_reset_link',
            'traced_from',
            fieldBase(
              root,
              'fr:login/reset_password/expire_reset_link',
              'traced_from',
            ),
          ),
          '\n',
        ),
      ),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.code, 'code', WriteFaultCode.requiredTarget)
            .having(
              (f) => f.message,
              'message',
              'fr requires the field traced_from',
            ),
      ),
    );
  });
  test('f02/us01/fr03/e09: an absent field with the empty base is added after the last key block', () async {
    final root = await writeWriteProject();
    const target = 'user_story:login/email_login';
    writeIn(
      root,
      (s) =>
          answerSet(s, fieldReq(target, 'goals', emptyBaseHash), '- PG-01\n'),
    );
    expect(
      readDoc(root, story1),
      startsWith(
        '---\nstatus: planned\ndraft: true\nvision:\n  - PV-01\npersona:\n  - buyer\ngoals:\n  - PG-01\n---\n',
      ),
    );
  });
  test('f02/us01/fr03/e10: an undeclared id is field_unknown', () async {
    final root = await writeWriteProject();
    const target = 'user_story:login/email_login';
    expect(
      () => writeIn(
        root,
        (s) => answerSet(s, fieldReq(target, 'size', emptyBaseHash), '1\n'),
      ),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.code, 'code', WriteFaultCode.fieldUnknown)
            .having(
              (f) => f.message,
              'message',
              'user_story declares no field size',
            )
            .having((f) => (f.file, f.key), 'location', (story1, 'size')),
      ),
    );
  });
  test('f08/us05/fr01/e02, f02/us01/fr03: empty stdin removes a held field the type does not declare', () async {
    final root = await writeWriteProject(
      extra: {
        'docs/$story1':
            '---\nstatus: planned\ndraft: true\nsize: 1\nvision:\n  - PV-01\npersona:\n  - buyer\n---\n\n'
            '# Sign in with email\n\n## Use Case\nSign in with an email.\n\n'
            '## Acceptance Criteria\n\n### Scenario 1 — [happy] Sign in\n- **Given** a registered email\n',
      },
    );
    const target = 'user_story:login/email_login';
    final answer = writeIn(
      root,
      (s) => answerSet(
        s,
        fieldReq(target, 'size', fieldBase(root, target, 'size')),
        '\n',
      ),
    );
    expect(
      readDoc(root, story1),
      startsWith(
        '---\nstatus: planned\ndraft: true\nvision:\n  - PV-01\npersona:\n  - buyer\n---\n',
      ),
    );
    expect(answer.json['base'], emptyBaseHash);
    expect(answer.json['draft'], isTrue);
  });
  test("f08/us05/fr01/e01, f02/us01/fr03: empty stdin removes a feature's written status", () async {
    final root = await writeWriteProject(
      extra: {
        'docs/$loginFeature': '---\nstatus: implemented\nvision:\n  - PV-01\n---\n\n# Login\n\n## Problem\nUsers sign in with an email and a password.\n',
      },
    );
    const target = 'feature:login';
    final answer = writeIn(
      root,
      (s) => answerSet(
        s,
        fieldReq(target, 'status', fieldBase(root, target, 'status')),
        '\n',
      ),
    );
    expect(
      readDoc(root, loginFeature),
      startsWith('---\nvision:\n  - PV-01\ndraft: true\n---\n'),
    );
    expect(answer.json['base'], emptyBaseHash);
    expect(answer.json['draft'], isTrue);
  });
  test('f02/us01/fr03/e10: a value for an undeclared field still refuses field_unknown', () async {
    final root = await writeWriteProject(
      extra: {
        'docs/$story1':
            '---\nstatus: planned\ndraft: true\nsize: 1\nvision:\n  - PV-01\npersona:\n  - buyer\n---\n\n'
            '# Sign in with email\n\n## Use Case\nSign in with an email.\n\n'
            '## Acceptance Criteria\n\n### Scenario 1 — [happy] Sign in\n- **Given** a registered email\n',
      },
    );
    const target = 'user_story:login/email_login';
    expect(
      () => writeIn(
        root,
        (s) => answerSet(s, fieldReq(target, 'size', emptyBaseHash), '2\n'),
      ),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.code, 'code', WriteFaultCode.fieldUnknown)
            .having(
              (f) => f.message,
              'message',
              'user_story declares no field size',
            )
            .having((f) => (f.file, f.key), 'location', (story1, 'size')),
      ),
    );
  });
  test('f02/us01/fr03/e10: empty stdin on an undeclared field the doc does not hold refuses field_unknown', () async {
    final root = await writeWriteProject();
    const target = 'user_story:login/email_login';
    expect(
      () => writeIn(
        root,
        (s) => answerSet(s, fieldReq(target, 'size', emptyBaseHash), '\n'),
      ),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.code, 'code', WriteFaultCode.fieldUnknown)
            .having(
              (f) => f.message,
              'message',
              'user_story declares no field size',
            )
            .having((f) => (f.file, f.key), 'location', (story1, 'size')),
      ),
    );
  });
  test("f02/us01/fr03: a value for a feature's status still refuses field_not_writable", () async {
    final root = await writeWriteProject(
      extra: {
        'docs/$loginFeature': '---\nstatus: implemented\nvision:\n  - PV-01\n---\n\n# Login\n\n## Problem\nUsers sign in with an email and a password.\n',
      },
    );
    expect(
      () => writeIn(
        root,
        (s) => answerSet(
          s,
          fieldReq('feature:login', 'status', emptyBaseHash),
          'deprecated\n',
        ),
      ),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.code, 'code', WriteFaultCode.fieldNotWritable)
            .having(
              (f) => f.message,
              'message',
              'the status of a feature is computed from its stories',
            )
            .having((f) => (f.file, f.key), 'location', (
              loginFeature,
              'status',
            )),
      ),
    );
  });
  test('f08/us05/fr01/e01, f08/us05/fr01/e02: after a removal runCheck reports no finding for the key', () async {
    final root = await writeWriteProject(
      extra: {
        'docs/$story1':
            '---\nstatus: planned\ndraft: true\nsize: 1\nvision:\n  - PV-01\npersona:\n  - buyer\n---\n\n'
            '# Sign in with email\n\n## Use Case\nSign in with an email.\n\n'
            '## Acceptance Criteria\n\n### Scenario 1 — [happy] Sign in\n- **Given** a registered email\n',
        'docs/$loginFeature': '---\nstatus: implemented\nvision:\n  - PV-01\n---\n\n# Login\n\n## Problem\nUsers sign in with an email and a password.\n',
      },
    );
    writeIn(
      root,
      (s) => answerSet(
        s,
        fieldReq(
          'user_story:login/email_login',
          'size',
          fieldBase(root, 'user_story:login/email_login', 'size'),
        ),
        '\n',
      ),
    );
    writeIn(
      root,
      (s) => answerSet(
        s,
        fieldReq(
          'feature:login',
          'status',
          fieldBase(root, 'feature:login', 'status'),
        ),
        '\n',
      ),
    );
    final session = openSession(root);
    try {
      final report = runCheck(session);
      expect(
        spots(
          report,
          FindingKind.fieldUndeclared,
        ).where((s) => s.startsWith('$story1:')),
        isEmpty,
      );
      expect(
        spots(
          report,
          FindingKind.featureStatusWritten,
        ).where((s) => s.startsWith('$loginFeature:')),
        isEmpty,
      );
    } finally {
      session.close();
    }
  });
  test('f02/us01/fr03/e11, f02/us01/fr02/e02: a field changed after the read refuses with its block as current text', () async {
    final root = await writeWriteProject();
    const target = 'user_story:login/email_login';
    final base = fieldBase(root, target, 'vision');
    writeIn(
      root,
      (s) => answerSet(s, fieldReq(target, 'vision', base), '- PV-09\n'),
    );
    final before = readDoc(root, story1);
    expect(
      () => writeIn(
        root,
        (s) => answerSet(s, fieldReq(target, 'vision', base), '- PV-02\n'),
      ),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.code, 'code', WriteFaultCode.baseMismatch)
            .having(
              (f) => f.current?.text,
              'current.text',
              'vision:\n  - PV-09\n',
            )
            .having(
              (f) => f.current?.base,
              'current.base',
              baseHashOf('vision:\n  - PV-09\n'),
            ),
      ),
    );
    expect(readDoc(root, story1), before);
  });
  test(
    'f02/us01/fr04/e02: a doc with no title line gains one with the empty base',
    () async {
      final root = await writeWriteProject(
        extra: {
          'docs/$signupFeature':
              '---\ndraft: true\n---\n\n## Problem\nUsers create an account.\n',
        },
      );
      const target = 'feature:signup';
      final answer = writeIn(
        root,
        (s) => answerSet(
          s,
          SetRequest.parse(target, title: true, base: emptyBaseHash),
          'Create an account\n',
        ),
      );
      expect(
        readDoc(root, signupFeature),
        '---\ndraft: true\n---\n# Create an account\n\n## Problem\nUsers create an account.\n',
      );
      expect(answer.json['base'], baseHashOf('Create an account'));
    },
  );
  test(
    'f02/us01/fr04/e03: an empty title or two lines is argument_invalid',
    () async {
      final root = await writeWriteProject();
      expect(
        () => writeIn(
          root,
          (s) => answerSet(
            s,
            SetRequest.parse('feature:login', title: true, base: 'x'),
            '\n',
          ),
        ),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
              .having(
                (f) => f.message,
                'message',
                'a title is one line; stdin held 0 lines',
              ),
        ),
      );
      expect(
        () => writeIn(
          root,
          (s) => answerSet(
            s,
            SetRequest.parse('feature:login', title: true, base: 'x'),
            'One\nTwo\n',
          ),
        ),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
              .having(
                (f) => f.message,
                'message',
                'a title is one line; stdin held 2 lines',
              ),
        ),
      );
      final before = readDoc(root, loginFeature);
      expect(
        () => writeIn(
          root,
          (s) => answerSet(
            s,
            SetRequest.parse('feature:login', title: true, base: 'x'),
            '   \n',
          ),
        ),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
              .having(
                (f) => f.message,
                'message',
                'a title is one line; stdin held 0 lines',
              ),
        ),
      );
      expect(readDoc(root, loginFeature), before);
    },
  );
  test('f02/us01/fr04/e04, f02/us01/fr02/e04: a title changed after the read refuses with the # line as current text', () async {
    final root = await writeWriteProject();
    const target = 'feature:login';
    final base = (getDoc(root, target)['bases']! as Map)['title']! as String;
    writeIn(
      root,
      (s) => answerSet(
        s,
        SetRequest.parse(target, title: true, base: base),
        'Sign in fast\n',
      ),
    );
    final before = readDoc(root, loginFeature);
    expect(
      () => writeIn(
        root,
        (s) => answerSet(
          s,
          SetRequest.parse(target, title: true, base: base),
          'Sign in slow\n',
        ),
      ),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.code, 'code', WriteFaultCode.baseMismatch)
            .having(
              (f) => f.message,
              'message',
              'the title changed since base $base',
            )
            .having((f) => f.key, 'key', 'title')
            .having((f) => f.current?.text, 'current.text', '# Sign in fast\n')
            .having(
              (f) => f.current?.base,
              'current.base',
              baseHashOf('Sign in fast'),
            ),
      ),
    );
    expect(readDoc(root, loginFeature), before);
  });

  test(
    'PD5, f02/us01/fr01/e04: whitespace-only stdin counts as empty',
    () async {
      final root = await writeWriteProject();
      const target = 'user_story:login/email_login#acceptance_criteria';
      final before = readDoc(root, story1);
      expect(
        () => writeIn(
          root,
          (s) =>
              answerSet(s, req(target, sectionBase(root, target)), ' \n\t\n'),
        ),
        throwsA(
          isA<WriteFault>().having(
            (f) => f.code,
            'code',
            WriteFaultCode.requiredTarget,
          ),
        ),
      );
      expect(readDoc(root, story1), before);
    },
  );
  test('f02/us01/fr01/e06, PD11: a template section no later held section follows is added at the end', () async {
    final root = await writeWriteProject();
    const target = 'user_story:login/email_login#open_questions';
    writeIn(
      root,
      (s) => answerSet(s, req(target, emptyBaseHash), 'None yet.\n'),
    );
    expect(readDoc(root, story1), endsWith('## Open questions\nNone yet.\n'));
  });
  test(
    'f02/us01/fr01/e07: empty stdin on an absent optional section adds nothing',
    () async {
      final root = await writeWriteProject();
      const target = 'user_story:login/email_login#rules';
      final before = readDoc(root, story1);
      writeIn(root, (s) => answerSet(s, req(target, emptyBaseHash), '\n'));
      expect(readDoc(root, story1), before);
    },
  );
  test('PD4, f02/us01/fr03/e11: a base from get on a duplicated field key writes the first block', () async {
    final root = await writeWriteProject(
      extra: {
        'docs/$story1':
            '---\nstatus: planned\ndraft: true\nvision:\n  - PV-01\nvision:\n  - PV-09\npersona:\n  - buyer\n---\n\n'
            '# Sign in with email\n\n## Use Case\nSign in with an email.\n\n'
            '## Acceptance Criteria\n\n### Scenario 1 — [happy] Sign in\n- **Given** a registered email\n',
      },
    );
    const target = 'user_story:login/email_login';
    writeIn(
      root,
      (s) => answerSet(
        s,
        fieldReq(target, 'vision', fieldBase(root, target, 'vision')),
        '- PV-02\n',
      ),
    );
    expect(
      readDoc(root, story1),
      startsWith(
        '---\nstatus: planned\ndraft: true\nvision:\n  - PV-02\nvision:\n  - PV-09\npersona:\n  - buyer\n---\n',
      ),
    );
  });
  test(
    'f02/us01/fr03, PD4, HD4: set --field writes a field whose key is quoted',
    () async {
      final root = await writeWriteProject(
        extra: {
          'docs/$story1':
              '---\n"status": planned\ndraft: true\nvision:\n  - PV-01\npersona:\n  - buyer\n---\n\n'
              '# Sign in with email\n\n## Use Case\nSign in with an email.\n\n'
              '## Acceptance Criteria\n\n### Scenario 1 — [happy] Sign in\n- **Given** a registered email\n',
        },
      );
      const target = 'user_story:login/email_login';
      expect(
        fieldBase(root, target, 'status'),
        baseHashOf('"status": planned\n'),
      );
      writeIn(
        root,
        (s) => answerSet(
          s,
          fieldReq(target, 'status', baseHashOf('"status": planned\n')),
          'implemented\n',
        ),
      );
      expect(
        readDoc(root, story1),
        startsWith(
          '---\nstatus: implemented\ndraft: true\nvision:\n  - PV-01\npersona:\n  - buyer\n---\n',
        ),
      );
    },
  );
  test('PD6: a multi-line value keeps its interior blank lines, each indented two spaces', () async {
    final root = await writeWriteProject();
    const target = 'user_story:login/email_login';
    writeIn(
      root,
      (s) => answerSet(
        s,
        fieldReq(target, 'vision', fieldBase(root, target, 'vision')),
        '- PV-02\n\n- PV-03\n',
      ),
    );
    expect(
      readDoc(root, story1),
      contains('vision:\n  - PV-02\n\n  - PV-03\n'),
    );
  });

  test('U1, dw-s03/inv3: set refuses a doc that is not UTF-8 and leaves its bytes unchanged', () async {
    final root = await writeWriteProject();
    final base = sectionBase(root, 'feature:signup#problem');
    final bytes = [
      ...docFile(root, signupFeature).readAsBytesSync(),
      0xFF,
      0x0A,
    ];
    docFile(root, signupFeature).writeAsBytesSync(bytes);
    expect(
      () => writeIn(
        root,
        (s) => answerSet(s, req('feature:signup#problem', base), 'New.\n'),
      ),
      throwsA(
        isA<RenderFault>()
            .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
            .having(
              (f) => f.message,
              'message',
              'cannot write $signupFeature: not UTF-8 text',
            ),
      ),
    );
    expect(docFile(root, signupFeature).readAsBytesSync(), bytes);
  });
  test('U1, dw-s03/inv3: set keeps the BOM of a doc', () async {
    final root = await writeWriteProject();
    final base = sectionBase(root, 'feature:signup#problem');
    final file = docFile(root, signupFeature);
    file.writeAsBytesSync([0xEF, 0xBB, 0xBF, ...file.readAsBytesSync()]);
    writeIn(
      root,
      (s) => answerSet(s, req('feature:signup#problem', base), 'New.\n'),
    );
    final after = file.readAsBytesSync();
    expect(after.take(3), [0xEF, 0xBB, 0xBF]);
    expect(String.fromCharCodes(after.skip(3)), contains('draft: true'));
    expect(String.fromCharCodes(after.skip(3)), contains('New.'));
  });

  test('f02/us01/fr01, PD5, H24: stdin with many whitespace lines before its last character is read in linear time', () async {
    final root = await writeWriteProject();
    const target = 'user_story:login/email_login#use_case';
    final stdin = 'a${'\n ' * 20000}x';
    final answer = writeIn(
      root,
      (s) => answerSet(s, req(target, sectionBase(root, target)), stdin),
    );
    expect(answer.text, isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 5)));

  test('f02/us01/fr03, PD5, H24: a field value with many whitespace lines before its last character is read in linear time', () async {
    final root = await writeWriteProject();
    const target = 'user_story:login/email_login';
    final stdin = '- PV-01${'\n ' * 20000}\n- PV-02';
    final answer = writeIn(
      root,
      (s) => answerSet(
        s,
        fieldReq(target, 'vision', fieldBase(root, target, 'vision')),
        stdin,
      ),
    );
    expect(answer.text, isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 5)));
}
