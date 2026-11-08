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
import 'package:specstone_core/src/rendering/format_run.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/doc_type_merger.dart';
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
  test('f01/us04/fr01/e14: set reads the address through the reference grammar and keeps gnfr# as no section key', () {
    final request = fieldReq('gnfr#', 'status', 'abc');
    expect(request.address, 'gnfr');
    expect(request.target, isA<FieldTarget>());
    final typed = req('feature:login#problem', 'abc');
    expect(typed.address, 'feature:login');
    expect(typed.target, isA<SectionTarget>());
  });

  test('index_query/read_doc_section/resolve_doc_name E13 (W8): a path holding # is the whole address, so set takes --field for it and splits no section key off it', () async {
    final root = await writeWriteProject(
      extra: {'docs/prds/notes#draft.md': '# Draft\n'},
    );
    writeIn(root, (s) {
      final whole = SetRequest.parse(
        'prds/notes#draft.md',
        field: 'status',
        base: 'abc',
        index: s.index,
      );
      expect(whole.address, 'prds/notes#draft.md');
      expect(whole.target, isA<FieldTarget>());
      expect(
        () => SetRequest.parse(
          'prds/notes#draft.md',
          base: 'abc',
          index: s.index,
        ),
        throwsA(
          isA<IndexFault>().having(
            (f) => f.code,
            'code',
            IndexFaultCode.argumentMissing,
          ),
        ),
      );
      expect(
        () => answerSet(s, whole, 'x\n'),
        throwsA(
          isA<IndexFault>().having(
            (f) => f.code,
            'code',
            IndexFaultCode.untypedTarget,
          ),
        ),
      );
      final split = SetRequest.parse(
        'prds/notes#draft',
        base: 'abc',
        index: s.index,
      );
      expect(split.address, 'prds/notes');
    });
  });

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

  test('dw-s03/inv4: markDraft leaves a draft alone and marks any other doc at the field-order slot', () {
    final builtIns = const DocTypeMerger().builtInBase('t');
    expect(
      markDraft('---\ndraft: true\n---\n# T\n', builtIns),
      '---\ndraft: true\n---\n# T\n',
    );
    expect(
      markDraft('---\nstatus: planned\n---\n# T\n', builtIns),
      '---\nstatus: planned\ndraft: true\n---\n# T\n',
    );
    expect(
      markDraft('---\napproved: true\nsize: 1\n---\n# T\n', builtIns),
      '---\ndraft: true\napproved: true\nsize: 1\n---\n# T\n',
    );
    expect(markDraft('# T\n', builtIns), '---\ndraft: true\n---\n\n# T\n');
  });

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
    final written = baseHashOf(
      '\n### Scenario 1 — [happy] Sign in\n\n- **Given** a registered email and its password\n',
    );
    expect(
      answer.text,
      '==> login/email_login (user_story) · $story1 · base $written <==\n',
    );
    expect(answer.json, {
      'name': 'login/email_login',
      'docType': 'user_story',
      'path': story1,
      'base': written,
      'draft': true,
    });
    expect(sectionBase(root, target), written);
  });

  group(
    'f02/us01/fr01/e01, doc-model/inv5: a get-then-set round trip of a section',
    () {
      const target = 'user_story:login/email_login#acceptance_criteria';

      // The body `get --json` gives, its `## ` line cut off as `set` asks.
      String bodyFromGet(Directory root) {
        final text = getDoc(root, target)['text']! as String;
        return text.substring(text.indexOf('\n') + 1);
      }

      test('of unchanged text leaves every byte as it was', () async {
        final root = await writeWriteProject();
        final before = readDoc(root, story1);

        writeIn(
          root,
          (s) => answerSet(
            s,
            req(target, sectionBase(root, target)),
            bodyFromGet(root),
          ),
        );

        expect(readDoc(root, story1), before);
      });

      test(
        'with one word changed keeps the blank line under the header',
        () async {
          final root = await writeWriteProject();
          final before = readDoc(root, story1);

          writeIn(
            root,
            (s) => answerSet(
              s,
              req(target, sectionBase(root, target)),
              bodyFromGet(root).replaceFirst('registered', 'verified'),
            ),
          );

          expect(
            readDoc(root, story1),
            before.replaceFirst('a registered email', 'a verified email'),
          );
          expect(
            readDoc(root, story1),
            contains('## Acceptance Criteria\n\n### Scenario 1'),
          );
        },
      );
    },
  );

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
        contains('## Use Case\n\nSign in with a passkey.\n'),
        contains('## Acceptance Criteria\n\n- **Given** a passkey\n'),
      ),
    );
  });

  test('f02/us01/s8, f02/us01/fr02, f02/us01/fr02/e01, f02/us01/fr01/e02, f02/us01/fr05/e02, nfr-di01: a stale base is refused with the current section, the file untouched', () async {
    final root = await writeWriteProject();
    const target = 'user_story:login/email_login#use_case';
    final base = sectionBase(root, target);
    writeIn(root, (s) => answerSet(s, req(target, base), 'First writer.\n'));
    final before = readDoc(root, story1);
    final current = sectionBase(root, target);
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
              '## Use Case\n\nFirst writer.\n',
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
        'Sign in with an email.\n\n## Rules\n\n- BR-01 One account per email.\n\n## Acceptance Criteria\n',
      ),
    );
  });

  group('f02/us01/fr01, doc-model/inv5: a section body is written laid out, whatever blank lines stdin gives it,', () {
    const target = 'user_story:login/email_login#use_case';

    for (final (count, lead) in [(0, ''), (1, '\n'), (2, '\n \n')]) {
      test(
        'here $count, its trailing blank line dropped, and a format run changes nothing',
        () async {
          final root = await writeWriteProject();
          final project = openProject(root);
          final formatTarget = project.resolveTarget(
            'docs/$story1',
            workingDirectory: root,
            defaultsToDocsRoot: true,
          );
          runFormat<void>(project, formatTarget, check: false);

          final answer = writeIn(
            root,
            (s) => answerSet(
              s,
              req(target, sectionBase(root, target)),
              '${lead}Sign in with an email and a password.\n\n',
            ),
          );

          const laidOut = '\nSign in with an email and a password.\n';
          expect(
            readDoc(root, story1),
            contains('## Use Case\n$laidOut\n## Acceptance Criteria\n'),
          );
          expect(answer.json['base'], baseHashOf(laidOut));
          expect(sectionBase(root, target), baseHashOf(laidOut));
          expect(
            runFormat<void>(
              project,
              formatTarget,
              check: true,
            ).files.single.status,
            FileStatus.unchanged,
          );
        },
      );
    }

    test('its first text line keeping its indent, the blank lines above it laid out', () async {
      final root = await writeWriteProject();

      writeIn(
        root,
        (s) => answerSet(
          s,
          req(target, sectionBase(root, target)),
          '\n \n\t\n    sign_in(email)\n',
        ),
      );

      expect(
        readDoc(root, story1),
        contains(
          '## Use Case\n\n    sign_in(email)\n\n## Acceptance Criteria\n',
        ),
      );
    });
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

  test('f02/us01/fr01/e06: empty stdin on the last section leaves the doc ending in exactly one newline', () async {
    final original = writeProject['docs/$story1']!;
    final root = await writeWriteProject(
      extra: {
        'docs/$story1': '$original\n## Rules\n- BR-01 One account per email.\n',
      },
    );
    const target = 'user_story:login/email_login#rules';
    writeIn(
      root,
      (s) => answerSet(s, req(target, sectionBase(root, target)), ''),
    );
    expect(readDoc(root, story1), original);
  });

  test('f02/us01/fr01/e06: empty stdin on a middle section keeps the blank line before the next header', () async {
    final original = writeProject['docs/$story1']!;
    final withRules = original.replaceFirst(
      '## Acceptance Criteria',
      '## Rules\n- BR-01 One account per email.\n\n## Acceptance Criteria',
    );
    final root = await writeWriteProject(extra: {'docs/$story1': withRules});
    const target = 'user_story:login/email_login#rules';
    expect(readDoc(root, story1), withRules);
    writeIn(
      root,
      (s) => answerSet(s, req(target, sectionBase(root, target)), ''),
    );
    expect(readDoc(root, story1), original);
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

  test('f02/us01/fr01/e08, dw-s03/inv4: a doc without draft gains draft: true at its field-order slot, a doc with no frontmatter gains one', () async {
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
      matches(
        RegExp(
          r'^---\nstatus: planned\ndraft: true\napproved: "[0-9a-f]{12}"\n---\n',
        ),
      ),
    );
    expect(readDoc(root, story2), contains('## Use Case\n\nSign out now.\n'));

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
      matches(
        RegExp(
          r'^---\ndraft: true\napproved: "[0-9a-f]{12}"\n---\n\n# Feature index\n',
        ),
      ),
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
    expect(readDoc(root, story1), contains('## Use Case\n\nSign in again.\n'));
  });

  test('f02/us01/fr01/e17, I1: a body that leaves a fence open is refused and the file stays', () async {
    final root = await writeWriteProject();
    const target = 'user_story:login/email_login#use_case';
    final before = readDoc(root, story1);
    expect(
      () => writeIn(
        root,
        (s) => answerSet(
          s,
          req(target, sectionBase(root, target)),
          'See:\n\n```bash\nmake\n',
        ),
      ),
      throwsA(
        isA<IndexFault>()
            .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
            .having((f) => f.message, 'message', contains('```bash')),
      ),
    );
    expect(readDoc(root, story1), before);
  });

  test(
    'f02/us01/fr01/e15, I1: a fenced "## install" line in a body round-trips',
    () async {
      final root = await writeWriteProject();
      const target = 'user_story:login/email_login#use_case';
      const fenced = 'Run:\n\n```bash\n## install\nmake\n```\n';
      writeIn(
        root,
        (s) => answerSet(s, req(target, sectionBase(root, target)), fenced),
      );
      final text = getDoc(root, target)['text']! as String;
      expect(text, contains('## install'));
      final body = text.substring(text.indexOf('\n') + 1);
      writeIn(
        root,
        (s) => answerSet(
          s,
          req(target, sectionBase(root, target)),
          body.replaceFirst('Run', 'Go'),
        ),
      );
      expect(readDoc(root, story1), contains('Go:\n\n```bash\n## install'));
    },
  );

  test('f02/us01/fr01/e15, D12: a body opening with the held section header drops it after blank lines', () async {
    final root = await writeWriteProject();
    const target = 'user_story:login/email_login#use_case';
    writeIn(
      root,
      (s) => answerSet(
        s,
        req(target, sectionBase(root, target)),
        '\n\n## Use Case\n\nSign in again.\n',
      ),
    );
    final text = readDoc(root, story1);
    expect(text, contains('## Use Case\n\nSign in again.\n'));
    expect('## Use Case'.allMatches(text), hasLength(1));
  });

  test('f02/us01/fr01/e15, D12: a body opening with the template header drops it for a section the doc lacks', () async {
    final root = await writeWriteProject();
    const target = 'user_story:login/email_login#open_questions';
    writeIn(
      root,
      (s) => answerSet(
        s,
        req(target, emptyBaseHash),
        '## Open questions\n\nNone yet.\n',
      ),
    );
    final text = readDoc(root, story1);
    expect(text, endsWith('## Open questions\n\nNone yet.\n'));
    expect('## Open questions'.allMatches(text), hasLength(1));
  });

  test('f02/us01/fr01/e15, D12: another section header is refused naming the line and the file stays', () async {
    final root = await writeWriteProject();
    const target = 'user_story:login/email_login#use_case';
    final before = readDoc(root, story1);
    expect(
      () => writeIn(
        root,
        (s) => answerSet(
          s,
          req(target, sectionBase(root, target)),
          '## Use Case\n\nx\n\n## Sub\n',
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
    expect(
      () => writeIn(
        root,
        (s) => answerSet(
          s,
          req(target, sectionBase(root, target)),
          '## Acceptance Criteria\n\nx\n',
        ),
      ),
      throwsA(
        isA<IndexFault>().having(
          (f) => f.message,
          'message',
          contains('"## Acceptance Criteria"'),
        ),
      ),
    );
    expect(readDoc(root, story1), before);
  });

  test('f02/us01/fr01/e15, D12: the header line inside a fence is written back unchanged', () async {
    final root = await writeWriteProject();
    const target = 'user_story:login/email_login#use_case';
    const fenced = '```md\n## Use Case\n```\n';
    writeIn(
      root,
      (s) => answerSet(s, req(target, sectionBase(root, target)), fenced),
    );
    expect(
      readDoc(root, story1),
      contains('## Use Case\n\n```md\n## Use Case\n```\n'),
    );
  });

  for (final (label, key, header) in [
    ('required', 'use_case', '## Use Case'),
    ('optional', 'open_questions', '## Open questions'),
  ]) {
    test(
      'f02/us01/fr01/e15, P21: header-only stdin on an empty $label section keeps it, empty and byte-equal',
      () async {
        final root = await writeWriteProject(
          extra: {
            'docs/$story1':
                '---\nstatus: planned\ndraft: true\npersona:\n  - buyer\n---\n\n'
                '# Sign in with email\n\n## Use Case\n\n## Acceptance Criteria\n\n'
                '### Scenario 1 — [happy] Sign in\n\n- **Given** a registered email\n\n'
                '## Open questions\n',
          },
        );
        final target = 'user_story:login/email_login#$key';
        final before = readDoc(root, story1);
        writeIn(
          root,
          (s) => answerSet(
            s,
            req(target, sectionBase(root, target)),
            '\n$header\n',
          ),
        );
        expect(readDoc(root, story1), before);
      },
    );
  }

  test('f02/us01/fr01/e15, D12: a header with trailing spaces is not the own header and refuses', () async {
    final root = await writeWriteProject();
    const target = 'user_story:login/email_login#use_case';
    final before = readDoc(root, story1);
    expect(
      () => writeIn(
        root,
        (s) => answerSet(
          s,
          req(target, sectionBase(root, target)),
          '## Use Case  \n\nx\n',
        ),
      ),
      throwsA(
        isA<IndexFault>()
            .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
            .having((f) => f.message, 'message', contains('"## Use Case  "')),
      ),
    );
    expect(readDoc(root, story1), before);
  });

  test('f02/us01/fr01/e15, D12: get then set of a whole section leaves the file byte-equal', () async {
    final root = await writeWriteProject();
    const target = 'user_story:login/email_login#use_case';
    final before = readDoc(root, story1);
    final text = '${getDoc(root, target)['text']! as String}\n';
    writeIn(
      root,
      (s) => answerSet(s, req(target, sectionBase(root, target)), text),
    );
    expect(readDoc(root, story1), before);
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
      ).replaceFirst('## Use Case\n\nSign in with an email.\n\n', ''),
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
    expect(
      readDoc(root, story1),
      contains('## Use Case\r\n\r\nSign in fast.\r\n'),
    );
    expect(answer.json['base'], baseHashOf('\nSign in fast.\n'));
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
        contains('## Use Case\n\nSign in fast.\n\n## Acceptance Criteria'),
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
      matches(
        RegExp(
          r'^---\ndraft: true\napproved: "[0-9a-f]{12}"\nvision:\n  - PV-01\n---\n\n# Sign in\n\n## Problem\n\nUsers sign in with an email and a password\.\n$',
        ),
      ),
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
            .having(
              (f) => f.message,
              'message',
              'vision takes a YAML list, one `- item` line each',
            ),
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
              'verify_method takes one YAML value, not a list',
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
        '---\nstatus: planned\ndraft: true\nvision:\n  - PV-01\ngoals:\n  - PG-01\npersona:\n  - buyer\n---\n',
      ),
    );
  });
  test('f02/us01/fr03/e09, dw-s03/inv4: a field set adds to a doc with no keys lands below the draft flag, as new orders them', () async {
    const nf = 'prds/features/f01_login/us01_email_login/nf01_fast_sign_in.md';
    final root = await writeWriteProject(
      extra: {
        'docs/$nf': '---\n---\n\n# Fast sign in\n\n## Statement\nThe system shall sign in within 2 s.\n',
      },
    );
    writeIn(
      root,
      (s) => answerSet(
        s,
        fieldReq('nf:login/email_login/fast_sign_in', 'kind', emptyBaseHash),
        'relax\n',
      ),
    );
    expect(
      readDoc(root, nf),
      startsWith('---\ndraft: true\nkind: relax\n---\n'),
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
      startsWith('---\ndraft: true\nvision:\n  - PV-01\n---\n'),
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
        '---\ndraft: true\n---\n# Create an account\n\n## Problem\n\nUsers create an account.\n',
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
    expect(readDoc(root, story1), endsWith('## Open questions\n\nNone yet.\n'));
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

  group('f02/us01/fr06: set writes the lead through #_lead', () {
    const target = 'user_story:login/email_login#_lead';
    const address = 'user_story:login/email_login';
    final withLead = writeProject['docs/$story1']!.replaceFirst(
      '# Sign in with email\n',
      '# Sign in with email\n\nOld lead.\n',
    );

    Future<Directory> project() =>
        writeWriteProject(extra: {'docs/$story1': withLead});

    String leadBase(Directory root) => getDoc(root, target)['base']! as String;

    test('f02/us01/fr06/e01: #_lead parses to a LeadTarget', () {
      expect(SetRequest.parse(target, base: 'abc').target, isA<LeadTarget>());
      expect(SetRequest.parse(target, base: 'abc').address, address);
    });

    test('f02/us01/fr06/e01: the lead is replaced, the doc turns draft, and the new base prints', () async {
      final root = await project();
      final before = readDoc(root, story1);
      final answer = writeIn(
        root,
        (s) => answerSet(s, req(target, leadBase(root)), 'New lead.\n'),
      );
      expect(
        readDoc(root, story1),
        before.replaceFirst('\nOld lead.\n', '\nNew lead.\n'),
      );
      final written = baseHashOf('\nNew lead.\n');
      expect(
        answer.text,
        '==> login/email_login (user_story) · $story1 · base $written <==\n',
      );
      expect(answer.json['base'], written);
      expect(answer.json['draft'], isTrue);
      expect(leadBase(root), written);
    });

    test('f02/us01/fr06/e08, I1: a lead that leaves a fence open is refused and the file stays', () async {
      final root = await project();
      final before = readDoc(root, story1);
      expect(
        () => writeIn(
          root,
          (s) => answerSet(
            s,
            req(target, leadBase(root)),
            'See:\n\n```bash\nmake\n',
          ),
        ),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
              .having((f) => f.message, 'message', contains('```bash')),
        ),
      );
      expect(readDoc(root, story1), before);
    });

    test('f02/us01/fr06/e04, I1: a fenced "# install" line in the lead round-trips', () async {
      final root = await project();
      const fenced = 'Run:\n\n```bash\n# install\nmake\n```\n';
      writeIn(root, (s) => answerSet(s, req(target, leadBase(root)), fenced));
      expect(getDoc(root, target)['text'], '\n$fenced');
      final text = getDoc(root, target)['text']! as String;
      writeIn(
        root,
        (s) => answerSet(
          s,
          req(target, leadBase(root)),
          text.replaceFirst('Run', 'Go'),
        ),
      );
      expect(
        getDoc(root, target)['text'],
        '\n${fenced.replaceFirst('Run', 'Go')}',
      );
    });

    test('f02/us01/fr06/e04: a stdin line starting "# " or "## " refuses with argument_invalid', () async {
      for (final body in ['# X\n', '## X\n', 'fine\n# X\n']) {
        final root = await project();
        final before = readDoc(root, story1);
        expect(
          () => writeIn(
            root,
            (s) => answerSet(s, req(target, leadBase(root)), body),
          ),
          throwsA(
            isA<IndexFault>().having(
              (f) => f.code,
              'code',
              IndexFaultCode.argumentInvalid,
            ),
          ),
        );
        expect(readDoc(root, story1), before);
      }
    });

    test('f02/us01/fr06/e04: a refused last line with no final newline refuses with argument_invalid', () async {
      for (final body in ['# X', '## X', 'fine\n## X']) {
        final root = await project();
        final before = readDoc(root, story1);
        expect(
          () => writeIn(
            root,
            (s) => answerSet(s, req(target, leadBase(root)), body),
          ),
          throwsA(
            isA<IndexFault>().having(
              (f) => f.code,
              'code',
              IndexFaultCode.argumentInvalid,
            ),
          ),
        );
        expect(readDoc(root, story1), before);
      }
    });

    test('f02/us01/fr06/e04: every line Doc.parse reads as a header is refused for a lead and for a section body', () async {
      const sectionTarget = 'user_story:login/email_login#use_case';
      for (final body in ['  ## X\n', '##\n', '##', '   ##\tX\n']) {
        final root = await project();
        final before = readDoc(root, story1);
        for (final (t, base) in [
          (target, leadBase(root)),
          (sectionTarget, sectionBase(root, sectionTarget)),
        ]) {
          expect(
            () => writeIn(root, (s) => answerSet(s, req(t, base), body)),
            throwsA(
              isA<IndexFault>().having(
                (f) => f.code,
                'code',
                IndexFaultCode.argumentInvalid,
              ),
            ),
            reason: '$t <- ${body.replaceAll('\n', r'\n')}',
          );
        }
        expect(readDoc(root, story1), before);
      }
    });

    test('f02/us01/fr06/e05: empty stdin empties the lead', () async {
      final root = await project();
      final before = readDoc(root, story1);
      final answer = writeIn(
        root,
        (s) => answerSet(s, req(target, leadBase(root)), ''),
      );
      expect(readDoc(root, story1), before.replaceFirst('\nOld lead.\n', ''));
      expect(answer.json['base'], emptyBaseHash);
    });

    test(
      'f02/us01/fr06/e06: a stale base refuses with the current lead',
      () async {
        final root = await project();
        expect(
          () => writeIn(root, (s) => answerSet(s, req(target, 'abc'), 'x\n')),
          throwsA(
            isA<WriteFault>()
                .having((f) => f.code, 'code', WriteFaultCode.baseMismatch)
                .having((f) => f.current?.text, 'current', '\nOld lead.\n')
                .having(
                  (f) => f.current?.base,
                  'base',
                  baseHashOf('\nOld lead.\n'),
                ),
          ),
        );
      },
    );

    test('f02/us01/fr06/e07: a CRLF doc keeps CRLF', () async {
      final root = await project();
      docFile(
        root,
        story1,
      ).writeAsStringSync(readDoc(root, story1).replaceAll('\n', '\r\n'));
      writeIn(
        root,
        (s) => answerSet(s, req(target, leadBase(root)), 'New lead.\n'),
      );
      expect(
        readDoc(root, story1),
        contains('# Sign in with email\r\n\r\nNew lead.\r\n'),
      );
      expect(
        readDoc(root, story1).replaceAll('\r\n', ''),
        isNot(contains('\n')),
      );
    });
  });

  group('write one section, field, title, or lead lays the doc out', () {
    const padded =
        '---\ndraft: true\n---\n\n# Signup architecture\n\n## Components\n'
        '| Component   | Responsibility |\n|-------------|----------------|\n'
        '| Signup form | Collects the email |\n\n## Deployment\nNone yet.\n';
    const laidOutArch =
        '---\ndraft: true\n---\n\n# Signup architecture\n\n## Components\n\n'
        '| Component | Responsibility |\n|---|---|\n'
        '| Signup form | Collects the email |\n\n## Deployment\n\nNone yet.\n';
    const refused =
        '---\ndraft: true\n---\n\n# Signup architecture\n\n## Not a section\nx\n\n'
        '## Components\n| A   | B |\n|---|---|\n| 1 | 2 |\n';
    const arch = 'architecture:signup';

    Future<Directory> archProject(String text) =>
        writeWriteProject(extra: {'docs/$signupArch': text});

    test('document_writing/edit_one_section_or_field/write_one_section E01: the base of the laid-out body writes a body stored unlaid-out', () async {
      final root = await archProject(padded);
      const target = '$arch#deployment';
      final base = sectionBase(root, target);
      final answer = writeIn(
        root,
        (s) => answerSet(s, req(target, base), 'None at all.\n'),
      );
      expect(
        readDoc(root, signupArch),
        contains('## Deployment\n\nNone at all.\n'),
      );
      expect(answer.json['base'], baseHashOf('\nNone at all.\n'));
    });

    test('document_writing/edit_one_section_or_field/write_one_section: a header that differs from the template header in case or spacing is that section, and set prints the base the next get reads', () async {
      final root = await writeWriteProject(
        extra: {
          'docs/$persona':
              '---\ndraft: true\n---\n\n# Buyer\n\n## Snapshot\nBuys.\n\n'
              '## jobs  to be done\nOld job.\n',
        },
      );
      const target = 'persona:buyer#jobs';
      final base = sectionBase(root, target);
      final answer = writeIn(
        root,
        (s) => answerSet(s, req(target, base), 'New job.\n'),
      );
      expect(
        readDoc(root, persona),
        endsWith('## Jobs to be done\n\nNew job.\n'),
      );
      expect(answer.json['base'], baseHashOf('\nNew job.\n'));
      expect(answer.json['base'], sectionBase(root, target));
    });

    test('document_writing/edit_one_section_or_field/write_one_section E03: a write to another section leaves this base valid', () async {
      final root = await writeWriteProject();
      const useCase = 'user_story:login/email_login#use_case';
      const criteria = 'user_story:login/email_login#acceptance_criteria';
      final criteriaBase = sectionBase(root, criteria);
      writeIn(
        root,
        (s) =>
            answerSet(s, req(useCase, sectionBase(root, useCase)), 'Other.\n'),
      );
      writeIn(
        root,
        (s) => answerSet(s, req(criteria, criteriaBase), '- **Given** x\n'),
      );
      expect(
        readDoc(root, story1),
        allOf(contains('## Use Case\n\nOther.\n'), contains('- **Given** x\n')),
      );
    });

    test('document_writing/edit_one_section_or_field/write_one_section E16: a body with none, one, or several leading blank lines lands under one blank line', () async {
      const target = 'user_story:login/email_login#use_case';
      for (final lead in ['', '\n', '\n\n\n']) {
        final root = await writeWriteProject();
        writeIn(
          root,
          (s) => answerSet(
            s,
            req(target, sectionBase(root, target)),
            '${lead}Go.\n',
          ),
        );
        expect(readDoc(root, story1), contains('## Use Case\n\nGo.\n\n## Acc'));
      }
    });

    test('document_writing/edit_one_section_or_field/write_one_section E18: an unlaid-out doc is written whole laid out', () async {
      final root = await archProject(padded);
      const target = '$arch#deployment';
      writeIn(
        root,
        (s) =>
            answerSet(s, req(target, sectionBase(root, target)), 'None yet.\n'),
      );
      expect(readDoc(root, signupArch), laidOutArch);
    });

    test('document_writing/edit_one_section_or_field/write_one_section E18: a doc format refuses keeps every other byte', () async {
      final root = await archProject(refused);
      const target = '$arch#components';
      writeIn(
        root,
        (s) => answerSet(
          s,
          req(target, sectionBase(root, target)),
          '| A | B |\n|---|---|\n| 3 | 4 |\n',
        ),
      );
      expect(
        readDoc(root, signupArch),
        refused.replaceFirst(
          '| A   | B |\n|---|---|\n| 1 | 2 |\n',
          '| A | B |\n|---|---|\n| 3 | 4 |\n',
        ),
      );
    });

    test('document_writing/edit_one_section_or_field/write_one_field E14: an output_ref write on an approved doc lays it out and adds no draft', () async {
      final approved = padded.replaceFirst('draft: true', 'approved: true');
      final root = await archProject(approved);
      writeIn(
        root,
        (s) => answerSet(
          s,
          fieldReq(arch, 'covers', fieldBase(root, arch, 'covers')),
          '- app/lib/\n',
        ),
      );
      final written = readDoc(root, signupArch);
      expect(
        written,
        laidOutArch.replaceFirst(
          'draft: true\n',
          'approved: true\ncovers:\n  - app/lib/\n',
        ),
      );
      expect(written, isNot(contains('draft:')));
    });

    test('document_writing/edit_one_section_or_field/write_one_field E14: a doc format refuses keeps every other byte', () async {
      final root = await archProject(refused);
      writeIn(
        root,
        (s) => answerSet(
          s,
          fieldReq(arch, 'covers', fieldBase(root, arch, 'covers')),
          '- app/lib/\n',
        ),
      );
      expect(
        readDoc(root, signupArch),
        refused.replaceFirst(
          'draft: true\n',
          'draft: true\ncovers:\n  - app/lib/\n',
        ),
      );
    });

    test('document_writing/edit_one_section_or_field/write_the_lead E03: text before the title line stays as on disk', () async {
      const given =
          'before\n# T\nold\n\n## Use Case\n\nSign in.\n\n'
          '## Acceptance Criteria\n\n- **Given** x\n';
      final root = await writeWriteProject(
        extra: {
          'docs/$story1': writeProject['docs/$story1']!.replaceFirst(
            '# Sign in with email\n\n## Use Case\n\nSign in with an email.\n\n## Acceptance Criteria\n\n### Scenario 1 — [happy] Sign in\n\n- **Given** a registered email\n',
            given,
          ),
        },
      );
      const target = 'user_story:login/email_login#_lead';
      writeIn(
        root,
        (s) => answerSet(
          s,
          req(target, getDoc(root, target)['base']! as String),
          'New.\n',
        ),
      );
      expect(readDoc(root, story1), contains('before\n# T\n'));
    });

    test('document_writing/edit_one_section_or_field/write_one_field E09: an absent field lands at its slot in a laid-out doc', () async {
      final root = await writeWriteProject();
      const target = 'user_story:login/email_login';
      writeIn(
        root,
        (s) =>
            answerSet(s, fieldReq(target, 'goals', emptyBaseHash), '- PG-01\n'),
      );
      expect(readDoc(root, story1), contains('goals:\n  - PG-01\n'));
      expect(readDoc(root, story1), contains('## Use Case\n\nSign in'));
    });

    test('document_writing/edit_one_section_or_field/write_the_title E07: an unlaid-out doc is written whole laid out', () async {
      final root = await archProject(padded);
      final base = (getDoc(root, arch)['bases']! as Map)['title']! as String;
      writeIn(
        root,
        (s) => answerSet(
          s,
          SetRequest.parse(arch, title: true, base: base),
          'Signup architecture\n',
        ),
      );
      expect(readDoc(root, signupArch), laidOutArch);
    });

    test('document_writing/edit_one_section_or_field/write_the_title E07: a doc format refuses keeps every other byte', () async {
      final root = await archProject(refused);
      final base = (getDoc(root, arch)['bases']! as Map)['title']! as String;
      writeIn(
        root,
        (s) => answerSet(
          s,
          SetRequest.parse(arch, title: true, base: base),
          'Renamed\n',
        ),
      );
      expect(
        readDoc(root, signupArch),
        refused.replaceFirst('# Signup architecture', '# Renamed'),
      );
    });

    test('document_writing/edit_one_section_or_field/write_the_lead E09: a lead without a leading blank line keeps one under the title', () async {
      final root = await writeWriteProject();
      const target = 'user_story:login/email_login#_lead';
      writeIn(
        root,
        (s) => answerSet(
          s,
          req(target, getDoc(root, target)['base']! as String),
          'Short lead.\n',
        ),
      );
      expect(
        readDoc(root, story1),
        contains('# Sign in with email\n\nShort lead.\n\n## Use Case\n'),
      );
    });

    test('document_writing/edit_one_section_or_field/write_the_lead E10: an unlaid-out doc is written whole laid out', () async {
      final root = await archProject(padded);
      const target = '$arch#_lead';
      writeIn(
        root,
        (s) => answerSet(
          s,
          req(target, getDoc(root, target)['base']! as String),
          'Lead.\n',
        ),
      );
      expect(
        readDoc(root, signupArch),
        laidOutArch.replaceFirst(
          '# Signup architecture\n',
          '# Signup architecture\n\nLead.\n',
        ),
      );
    });

    test('document_writing/edit_one_section_or_field/write_the_lead E10: a doc format refuses keeps every other byte', () async {
      final root = await archProject(refused);
      const target = '$arch#_lead';
      writeIn(
        root,
        (s) => answerSet(
          s,
          req(target, getDoc(root, target)['base']! as String),
          'Lead.\n',
        ),
      );
      expect(
        readDoc(root, signupArch),
        refused.replaceFirst(
          '# Signup architecture\n',
          '# Signup architecture\nLead.\n',
        ),
      );
    });
  });
}
