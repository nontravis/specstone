// The plan's test literals are kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';
import 'dart:isolate';

import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/document_writing/set_doc.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/posix_modes.dart';
import '../../helpers/write_fixture.dart';

SetRequest req(String target, String base) =>
    SetRequest.parse(target, base: base);

String sectionBase(Directory root, String target) =>
    getDoc(root, target)['base']! as String;

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
}
