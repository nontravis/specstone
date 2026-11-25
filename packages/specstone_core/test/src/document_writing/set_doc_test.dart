// The plan's test literals are kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';
import 'dart:isolate';

import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/document_writing/approval.dart'
    show withApprovalHash;
import 'package:specstone_core/src/document_writing/batch_file.dart'
    show parseBatchFile;
import 'package:specstone_core/src/document_writing/models/spliced_doc.dart';
import 'package:specstone_core/src/document_writing/new_doc.dart'
    show answerNew;
import 'package:specstone_core/src/document_writing/set_batch.dart'
    show answerSetBatch;
import 'package:specstone_core/src/document_writing/set_doc.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/get_docs.dart' show answerGet;
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/rendering/format_run.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/rendering/models/line_ending.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/doc_type_merger.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart' show checkOf, loginRecord, spots;
import '../../helpers/index_fixture.dart' show openSession;
import '../../helpers/matrix_record_fixture.dart';
import '../../helpers/posix_modes.dart';
import '../../helpers/shipped_pins.dart'
    show pinStatusesBelow, statusesBelowResolver;
import '../../helpers/target_fixture.dart'
    show flutterArchitecture, jasprArchitecture, writeTwinProject;
import '../../helpers/write_fixture.dart';

SetRequest req(String target, String base) =>
    SetRequest.parse(target, base: base);

SetRequest fieldReq(String target, String id, String base) =>
    SetRequest.parse(target, field: id, base: base);

String sectionBase(Directory root, String target) =>
    getDoc(root, target)['base']! as String;

String fieldBase(Directory root, String target, String id) =>
    ((getDoc(root, target)['bases']! as Map)['fields']! as Map)[id]! as String;

/// Runs [splicePart] for [request] against the doc as it stands on disk, with
/// the arguments `answerSet` gives it under the lock.
SplicedDoc spliceIn(Directory root, SetRequest request, String text) =>
    writeIn(root, (s) {
      final doc = s.target(request.address);
      final docType = s.index.typeOf(doc)!;
      final statusesOutside = s.project.statusesOutsideApproval;
      final read = parseIndexedDoc(
        docPath: doc.docPath,
        bytes: s.readDocBytes(doc.docPath)!,
        match: MatchedDocType(docType),
        statusesOutside: statusesOutside,
      );
      return splicePart(
        doc: doc,
        docType: docType,
        lfText: toLf(read.content.text),
        sections: read.content.sections,
        target: request.target,
        base: request.base,
        text: text,
        statusesOutside: statusesOutside,
      );
    });

/// Runs [checkFieldWrite] for [fieldId] of [address] with [value] and [held].
void checkFieldIn(
  Directory root,
  String address,
  String fieldId,
  String? value, {
  bool held = false,
}) => writeIn(root, (s) {
  final doc = s.target(address);
  checkFieldWrite(
    doc: doc,
    docType: s.index.typeOf(doc)!,
    fieldId: fieldId,
    value: value,
    held: held,
  );
});

/// Runs [checkPartText] for [request] and [text] on the doc it names.
void checkPartIn(Directory root, SetRequest request, String text) =>
    writeIn(root, (s) {
      final doc = s.target(request.address);
      checkPartText(
        doc: doc,
        docType: s.index.typeOf(doc)!,
        target: request.target,
        text: text,
      );
    });

Matcher throwsIndexFault(IndexFaultCode code) =>
    throwsA(isA<IndexFault>().having((f) => f.code, 'code', code));

Matcher throwsWriteFault(WriteFaultCode code) =>
    throwsA(isA<WriteFault>().having((f) => f.code, 'code', code));

void main() {
  test('set reads the address through the reference grammar and keeps gnfr# as no section key', () {
    final request = fieldReq('gnfr#', 'status', 'abc');
    expect(request.address, 'gnfr');
    expect(request.target, isA<FieldTarget>());
    final typed = req('feature:login#problem', 'abc');
    expect(typed.address, 'feature:login');
    expect(typed.target, isA<SectionTarget>());
  });

  test('a path holding # is the whole address, so set takes --field for it and splits no section key off it', () async {
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

      final titled = SetRequest.parse(
        'prds/notes#draft.md',
        title: true,
        base: 'abc',
        index: s.index,
      );
      expect(titled.address, 'prds/notes#draft.md');
      expect(titled.target, isA<TitleTarget>());
      expect(
        () => answerSet(s, titled, 'Retitled\n'),
        throwsIndexFault(IndexFaultCode.untypedTarget),
      );
    });
    expect(readDoc(root, 'prds/notes#draft.md'), '# Draft\n');
  });

  test('a bare gnfr name with #_lead writes the one gnfr doc as the typed name does', () async {
    const gnfr = 'prds/GNFR.md';
    const doc =
        '# Global non-functional requirements\n\nOld intro.\n\n## Performance\n\nN/A — no budget yet.\n';
    final bare = await writeWriteProject(extra: {'docs/$gnfr': doc});
    final typed = await writeWriteProject(extra: {'docs/$gnfr': doc});
    String write(Directory root, String address) {
      final base = sectionBase(root, address);
      writeIn(root, (s) => answerSet(s, req(address, base), 'New intro.\n'));
      return readDoc(root, gnfr);
    }

    final viaBare = write(bare, 'gnfr#_lead');
    expect(viaBare, write(typed, 'gnfr:gnfr#_lead'));
    expect(
      viaBare,
      contains(
        '# Global non-functional requirements\n\nNew intro.\n\n## Performance',
      ),
    );
    expect(viaBare, contains('draft: true'));
  });

  test('set splits a section key off the first #, as get does, once the whole text names no doc', () async {
    final root = await writeWriteProject(
      extra: {'docs/prds/notes#draft.md': '# Draft\n'},
    );
    writeIn(root, (s) {
      final request = SetRequest.parse(
        'prds/notes#draft.md#scope',
        base: 'abc',
        index: s.index,
      );

      expect(request.address, 'prds/notes');
      expect(request.target, isA<SectionTarget>());
      expect((request.target as SectionTarget).key, 'draft.md#scope');
    });
  });

  test('set names one target and a base', () {
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
  });

  test('set parses the address, the target, and the base', () {
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
  });

  test('markDraft leaves a draft alone and marks any other doc at the field-order slot', () {
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

  test('only the section body changes, and the new base prints', () async {
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
      '==> login/email_login (user_story) · $story1#acceptance_criteria · base $written <==\n',
    );
    expect(docOf(answer), {
      'name': 'login/email_login',
      'docType': 'user_story',
      'path': story1,
      'base': written,
      'draft': true,
    });
    expect(sectionBase(root, target), written);
  });

  test('a changed ### heading is written as given, and a link to its old anchor is reported, not rewritten', () async {
    const link =
        '[sign in](features/f01_login/us01_email_login/USER_STORY.md#scenario-1--happy-sign-in)';
    final root = await writeWriteProject(
      extra: {'docs/prds/d01_context.md': '# Context\n\nSee $link.\n'},
    );
    expect(spots(await checkOf(root), FindingKind.linkAnchorMissing), isEmpty);
    const target = 'user_story:login/email_login#acceptance_criteria';
    writeIn(
      root,
      (s) => answerSet(
        s,
        req(target, sectionBase(root, target)),
        '\n### Scenario 1 — [happy] Sign in again\n- **Given** a registered email\n',
      ),
    );
    expect(
      readDoc(root, story1),
      contains('### Scenario 1 — [happy] Sign in again'),
    );
    expect(readDoc(root, 'prds/d01_context.md'), contains(link));
    expect(spots(await checkOf(root), FindingKind.linkAnchorMissing), [
      'prds/d01_context.md:3: link_anchor_missing',
    ]);
  });
  group('a get-then-set round trip of a section', () {
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
  });

  test(
    'two Agents write two sections of one doc at once and both land',
    () async {
      final root = await writeWriteProject();
      final path = root.path;
      final useCase = sectionBase(
        root,
        'user_story:login/email_login#use_case',
      );
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
          () =>
              write('acceptance_criteria', criteria, '- **Given** a passkey\n'),
        ),
      ]);
      expect(
        readDoc(root, story1),
        allOf(
          contains('## Use Case\n\nSign in with a passkey.\n'),
          contains('## Acceptance Criteria\n\n- **Given** a passkey\n'),
        ),
      );
    },
  );

  test('a stale base is refused with the current section, the file untouched', () async {
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
              '==> login/email_login (user_story) · $story1#use_case · base $current <==',
            ),
      ),
    );
    expect(readDoc(root, story1), before);
  });

  test(
    'a template section the doc lacks is added at its template place',
    () async {
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
    },
  );

  group('a section body is written laid out, whatever blank lines stdin gives it,', () {
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
          expect(docOf(answer)['base'], baseHashOf(laidOut));
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

  test('a non-template section removed after the read exits 64 naming the doc and the key', () async {
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
        isA<IndexFault>()
            .having((f) => f.code, 'code', IndexFaultCode.sectionNotFound)
            .having((f) => f.exitStatus, 'exitStatus', 64)
            .having(
              (f) => f.message,
              'message',
              startsWith(
                'user_story:login/email_login holds no section with the key notes',
              ),
            ),
      ),
    );
    expect(readDoc(root, story1), before);
  });

  test('a hand edit while another call holds the write lock takes no lock, and the next set re-reads it', () async {
    final root = await writeWriteProject();
    const target = 'user_story:login/sign_out#use_case';
    final base = sectionBase(root, target);
    final other = sqlite3.open('${root.path}/.specstone/index.sqlite')
      ..execute('BEGIN IMMEDIATE');
    addTearDown(other.close);
    docFile(root, story2).writeAsStringSync(
      readDoc(root, story2).replaceFirst('Sign out.', 'Signed out by hand.'),
    );
    other.execute('ROLLBACK');
    final handEdited = readDoc(root, story2);
    expect(handEdited, contains('Signed out by hand.'));
    expect(handEdited, isNot(contains('draft:')));

    expect(
      () => writeIn(root, (s) => answerSet(s, req(target, base), 'Out.\n')),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.code, 'code', WriteFaultCode.baseMismatch)
            .having(
              (f) => f.current?.text,
              'current.text',
              contains('Signed out by hand.'),
            ),
      ),
    );
    expect(readDoc(root, story2), handEdited);
  });

  test('empty stdin on a required section the doc lacks is required_target naming it', () async {
    final root = await writeWriteProject(
      extra: {
        'docs/$story1': writeProject['docs/$story1']!.replaceFirst(
          '## Use Case\n\nSign in with an email.\n\n',
          '',
        ),
      },
    );
    final before = readDoc(root, story1);
    expect(before, isNot(contains('## Use Case')));
    expect(
      () => writeIn(
        root,
        (s) => answerSet(
          s,
          req('user_story:login/email_login#use_case', emptyBaseHash),
          '',
        ),
      ),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.code, 'code', WriteFaultCode.requiredTarget)
            .having((f) => f.exitStatus, 'exitStatus', 64)
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

  test('a write to any other part adds no missing section, and only a set on its key with the empty base adds it', () async {
    final root = await writeWriteProject();
    const address = 'user_story:login/email_login';
    const missing = '## Open questions';
    expect(readDoc(root, story1), isNot(contains(missing)));

    String base(String id) => sectionBase(root, '$address#$id');
    final titleBase =
        (getDoc(root, address)['bases']! as Map)['title']! as String;
    writeIn(
      root,
      (s) => answerSet(s, req('$address#use_case', base('use_case')), 'A.\n'),
    );
    writeIn(
      root,
      (s) => answerSet(s, req('$address#_lead', base('_lead')), 'Lead.\n'),
    );
    writeIn(
      root,
      (s) => answerSet(
        s,
        fieldReq(address, 'vision', fieldBase(root, address, 'vision')),
        '- PV-02\n',
      ),
    );
    writeIn(
      root,
      (s) => answerSet(
        s,
        SetRequest.parse(address, title: true, base: titleBase),
        'Sign in\n',
      ),
    );
    final laidOut = readDoc(root, story1);
    expect(laidOut, contains('Lead.'));
    expect(laidOut, contains('# Sign in\n'));
    expect(laidOut, isNot(contains(missing)));

    writeIn(
      root,
      (s) => answerSet(
        s,
        req('$address#open_questions', emptyBaseHash),
        'Which provider?\n',
      ),
    );
    expect(readDoc(root, story1), endsWith('$missing\n\nWhich provider?\n'));
  });

  test(
    'a key no template defines and the doc lacks is section_not_found',
    () async {
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
              .having((f) => f.exitStatus, 'exitStatus', 64)
              .having(
                (f) => f.message,
                'message',
                'user_story:login/email_login holds no section with the key notes, and its template defines none',
              ),
        ),
      );
      expect(readDoc(root, story1), before);
    },
  );

  test('empty stdin on the last section leaves the doc ending in exactly one newline', () async {
    final original = writeProject['docs/$story1']!;
    final root = await writeWriteProject(
      extra: {
        'docs/$story1': '$original\n## Rules\n- BR-01 One account per email.\n',
      },
    );
    const target = 'user_story:login/email_login#rules';
    final answer = writeIn(
      root,
      (s) => answerSet(s, req(target, sectionBase(root, target)), ''),
    );
    expect(
      readDoc(root, story1),
      original.replaceFirst(
        'draft: true\n',
        'draft: true\nretired_ids:\n  - BR-01\n',
      ),
    );
    expect(docOf(answer)['base'], emptyBaseHash);
  });

  test('empty stdin on a middle section keeps the blank line before the next header', () async {
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
    expect(
      readDoc(root, story1),
      original.replaceFirst(
        'draft: true\n',
        'draft: true\nretired_ids:\n  - BR-01\n',
      ),
    );
  });

  test('a doc without draft gains draft: true at its field-order slot, a doc with no frontmatter gains one', () async {
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

  test('an old-format doc is untyped_target', () async {
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
  });

  test(
    'a doc deleted after it was read is doc_not_found, and no file is created',
    () async {
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
    },
  );

  test(
    'an unwritable folder is output_not_writable and the doc keeps its bytes',
    () async {
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
    },
    skip: unreadablePathSkipReason() ?? false,
  );

  test(
    'a read-only doc is output_not_writable and keeps its bytes and mode',
    () async {
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
              .having((f) => f.exitStatus, 'exitStatus', 73)
              .having(
                (f) => f.message,
                'message',
                'cannot write $story1: read-only',
              ),
        ),
      );
      expect(readDoc(root, story1), before);
      expect(file.statSync().mode & 0x80, 0);
    },
    skip: unreadablePathSkipReason() ?? false,
  );

  test('a hand edit is read as it is on disk', () async {
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

  test('a fenced "## install" line in a body round-trips', () async {
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
  });

  test(
    'a body opening with the held section header drops it after blank lines',
    () async {
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
    },
  );

  test('a body opening with the template header drops it for a section the doc lacks', () async {
    for (final lead in ['', '\n\n']) {
      final root = await writeWriteProject();
      const target = 'user_story:login/email_login#open_questions';
      writeIn(
        root,
        (s) => answerSet(
          s,
          req(target, emptyBaseHash),
          '$lead## Open questions\n\nNone yet.\n',
        ),
      );
      final text = readDoc(root, story1);
      final why = '${lead.length} blank lines before it';
      expect(text, endsWith('## Open questions\n\nNone yet.\n'), reason: why);
      expect('## Open questions'.allMatches(text), hasLength(1), reason: why);
    }
  });

  test('the header line inside a fence is written back unchanged', () async {
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
      'header-only stdin on an empty $label section keeps it, empty and byte-equal',
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

  test(
    'a header with trailing spaces is not the own header and refuses',
    () async {
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
    },
  );

  test('get then set of a whole section leaves the file byte-equal', () async {
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

  test('a template section removed after the read refuses with empty current text and the empty base', () async {
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

  test('a CRLF doc keeps CRLF, and its base is its LF twin base', () async {
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
    expect(docOf(answer)['base'], baseHashOf('\nSign in fast.\n'));
  });

  test('a body with no final newline or with trailing blank lines ends in one newline', () async {
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
      expect(docOf(answer)['base'], sectionBase(root, target));
    }
  });

  test('two sections with one key: set writes the first', () async {
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

  test('a field block is rewritten and every other block kept', () async {
    final root = await writeWriteProject();
    const target = 'user_story:login/email_login';
    final answer = writeIn(
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
    expect(
      answer.text,
      '==> login/email_login (user_story) · $story1 · field vision · base ${baseHashOf('vision:\n  - PV-02\n')} <==\n',
    );
  });
  test('an FR declares no implements field under the shipped pack, so set refuses it and writes nothing', () async {
    final root = await writeWriteProject();
    final before = readDoc(root, fr11);
    expect(
      () => writeIn(
        root,
        (s) => answerSet(
          s,
          fieldReq(
            'fr:login/email_login/validate_credentials',
            'implements',
            emptyBaseHash,
          ),
          '- app/lib/src/login/password_check.dart:checkPassword\n',
        ),
      ),
      throwsWriteFault(WriteFaultCode.fieldUnknown),
    );
    expect(readDoc(root, fr11), before);
  });
  test('a set of draft or approved is field_not_writable', () async {
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
              'approved is written only by specstone approve and the hash stamps',
            ),
      ),
    );
  });
  test(
    'set --field retrim writes the marks and empty stdin removes them',
    () async {
      final root = await writeWriteProject();
      const target = 'fr:login/email_login/validate_credentials';
      writeIn(
        root,
        (s) => answerSet(
          s,
          fieldReq(target, 'retrim', emptyBaseHash),
          '- statement\n- behavior\n',
        ),
      );
      expect(readDoc(root, fr11), contains('draft: true\n'));
      expect(
        readDoc(root, fr11),
        contains('retrim:\n  - statement\n  - behavior\n'),
      );
      writeIn(
        root,
        (s) => answerSet(
          s,
          fieldReq(target, 'retrim', fieldBase(root, target, 'retrim')),
          '',
        ),
      );
      expect(readDoc(root, fr11), isNot(contains('retrim:')));
    },
  );
  test('a new title keeps the folder and the name, and marks the doc draft', () async {
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
      '==> login (feature) · $loginFeature · title · base ${baseHashOf('Sign in')} <==\n',
    );
  });

  test('a covers edit leaves an approved record approved', () async {
    final root = await writeWriteProject(extra: loginRecordFile);
    const target = 'implementation:login';
    final answer = writeIn(
      root,
      (s) => answerSet(
        s,
        fieldReq(target, 'covers', fieldBase(root, target, 'covers')),
        '- app/lib/src/login/\n',
      ),
    );
    expect(readDoc(root, loginRecordPath), isNot(contains('draft')));
    expect(
      readDoc(root, loginRecordPath),
      contains('covers:\n  - app/lib/src/login/\n'),
    );
    expect(docOf(answer)['draft'], isFalse);
  });
  test('a list field with 92 single-quoted entries gains one entry as one added line', () async {
    final held = [for (var i = 0; i < 92; i++) 'app/lib/src/f$i/'];
    final block = "covers:\n${[for (final e in held) "  - '$e'\n"].join()}";
    final root = await writeWriteProject(
      extra: {
        loginRecordPath: withKeyBlock(
          loginRecordFile[loginRecordPath]!,
          'covers',
          block,
        ),
      },
    );
    const target = 'implementation:login';
    final before = readDoc(root, loginRecordPath);

    writeIn(
      root,
      (s) => answerSet(
        s,
        fieldReq(target, 'covers', fieldBase(root, target, 'covers')),
        [
          for (final e in [...held, 'app/lib/src/new/']) '- $e\n',
        ].join(),
      ),
    );

    final after = readDoc(root, loginRecordPath);
    expect(after, before.replaceFirst(block, "$block  - 'app/lib/src/new/'\n"));
  });
  test('a list field keeps the quotes of the entries it keeps and styles a new one after them', () async {
    final root = await writeWriteProject(
      extra: {
        loginRecordPath: withKeyBlock(
          loginRecordFile[loginRecordPath]!,
          'covers',
          'covers:\n    - "app/lib/a/"\n    - "app/lib/b/"\n',
        ),
      },
    );
    const target = 'implementation:login';

    writeIn(
      root,
      (s) => answerSet(
        s,
        fieldReq(target, 'covers', fieldBase(root, target, 'covers')),
        '- app/lib/a/\n- app/lib/c/\n',
      ),
    );

    expect(
      readDoc(root, loginRecordPath),
      contains('covers:\n    - "app/lib/a/"\n    - "app/lib/c/"\n'),
    );
  });
  test(
    'status on a feature is field_not_writable; on a story it is written',
    () async {
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
      expect(docOf(answer)['base'], baseHashOf('status: implemented\n'));
    },
  );
  test('a value outside the enum is field_value_invalid', () async {
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
  test('a scalar for a list, a list for a scalar, or invalid YAML is field_value_invalid', () async {
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
  test(
    'empty stdin removes an optional field, and refuses a required one',
    () async {
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
    },
  );
  test(
    'an absent field with the empty base is added after the last key block',
    () async {
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
    },
  );
  test('a field set adds to a doc with no keys lands below the draft flag, as new orders them', () async {
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
  test('an undeclared id is field_unknown', () async {
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
  test('empty stdin removes a held field the type does not declare', () async {
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
    expect(docOf(answer)['base'], emptyBaseHash);
    expect(docOf(answer)['draft'], isTrue);
  });
  test("an empty stdin clears a feature's written status", () async {
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
    expect(docOf(answer)['base'], emptyBaseHash);
    expect(docOf(answer)['draft'], isTrue);
  });
  test('a value for an undeclared field still refuses field_unknown', () async {
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
  test('after a removal runCheck reports no finding for the key', () async {
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
      final report = await runCheck(session);
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
  test('a field changed after the read refuses with its block as current text', () async {
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
            )
            .having(
              (f) => f.current?.heading,
              'heading',
              '==> login/email_login (user_story) · $story1 · field vision · base ${baseHashOf('vision:\n  - PV-09\n')} <==',
            ),
      ),
    );
    expect(readDoc(root, story1), before);
  });
  test('a doc with no title line gains one with the empty base', () async {
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
    expect(docOf(answer)['base'], baseHashOf('Create an account'));
  });
  test('an empty title or two lines is argument_invalid', () async {
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
  });
  test('a title changed after the read refuses with the # line as current text', () async {
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
            )
            .having(
              (f) => f.current?.heading,
              'heading',
              '==> login (feature) · $loginFeature · title · base ${baseHashOf('Sign in fast')} <==',
            ),
      ),
    );
    expect(readDoc(root, loginFeature), before);
  });

  test('whitespace-only stdin counts as empty', () async {
    final root = await writeWriteProject();
    const target = 'user_story:login/email_login#acceptance_criteria';
    final before = readDoc(root, story1);
    expect(
      () => writeIn(
        root,
        (s) => answerSet(s, req(target, sectionBase(root, target)), ' \n\t\n'),
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
  });
  test(
    'a template section no later held section follows is added at the end',
    () async {
      final root = await writeWriteProject();
      const target = 'user_story:login/email_login#open_questions';
      writeIn(
        root,
        (s) => answerSet(s, req(target, emptyBaseHash), 'None yet.\n'),
      );
      expect(
        readDoc(root, story1),
        endsWith('## Open questions\n\nNone yet.\n'),
      );
    },
  );
  test('empty stdin on an absent optional section adds nothing', () async {
    final root = await writeWriteProject();
    const target = 'user_story:login/email_login#rules';
    final before = readDoc(root, story1);
    writeIn(root, (s) => answerSet(s, req(target, emptyBaseHash), '\n'));
    expect(readDoc(root, story1), before);
  });
  test(
    'a base from get on a duplicated field key writes the first block',
    () async {
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
    },
  );
  test('set --field writes a field whose key is quoted', () async {
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
  });
  test('a list value written with a blank line between entries gives one block of consecutive entries', () async {
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
    expect(readDoc(root, story1), contains('vision:\n  - PV-02\n  - PV-03\n'));
  });

  test(
    'set refuses a doc that is not UTF-8 and leaves its bytes unchanged',
    () async {
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
    },
  );
  test('set keeps the BOM of a doc', () async {
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

  test('stdin with many whitespace lines before its last character is read in linear time', () async {
    final root = await writeWriteProject();
    const target = 'user_story:login/email_login#use_case';
    final stdin = 'a${'\n ' * 20000}x';
    final answer = writeIn(
      root,
      (s) => answerSet(s, req(target, sectionBase(root, target)), stdin),
    );
    expect(answer.text, isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 5)));

  test('a field value with many whitespace lines before its last character is read in linear time', () async {
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

  group('set writes the lead through #_lead', () {
    const target = 'user_story:login/email_login#_lead';
    const address = 'user_story:login/email_login';
    final withLead = writeProject['docs/$story1']!.replaceFirst(
      '# Sign in with email\n',
      '# Sign in with email\n\nOld lead.\n',
    );

    Future<Directory> project() =>
        writeWriteProject(extra: {'docs/$story1': withLead});

    String leadBase(Directory root) => getDoc(root, target)['base']! as String;

    test('#_lead parses to a LeadTarget', () {
      expect(SetRequest.parse(target, base: 'abc').target, isA<LeadTarget>());
      expect(SetRequest.parse(target, base: 'abc').address, address);
    });

    test('the lead is replaced, the doc turns draft, and the new base prints', () async {
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
        '==> login/email_login (user_story) · $story1#_lead · base $written <==\n',
      );
      expect(docOf(answer)['base'], written);
      expect(docOf(answer)['draft'], isTrue);
      expect(leadBase(root), written);
    });

    test('a fenced "# install" line in the lead round-trips', () async {
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

    test(
      'a stdin line starting "# " or "## " refuses with argument_invalid',
      () async {
        for (final body in [
          '# X\n',
          '## X\n',
          'fine\n# X\n',
          '# X',
          '## X',
          'fine\n## X',
        ]) {
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
      },
    );

    test('every line Doc.parse reads as a header is refused for a lead and for a section body', () async {
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

    test('empty stdin empties the lead', () async {
      final root = await project();
      final before = readDoc(root, story1);
      final answer = writeIn(
        root,
        (s) => answerSet(s, req(target, leadBase(root)), ''),
      );
      expect(readDoc(root, story1), before.replaceFirst('\nOld lead.\n', ''));
      expect(docOf(answer)['base'], emptyBaseHash);
    });

    test('a stale base refuses with the current lead and its naming line', () async {
      final root = await project();
      expect(
        () => writeIn(root, (s) => answerSet(s, req(target, 'abc'), 'x\n')),
        throwsA(
          isA<WriteFault>()
              .having((f) => f.code, 'code', WriteFaultCode.baseMismatch)
              .having((f) => f.exitStatus, 'exitStatus', 75)
              .having((f) => f.current?.text, 'current', '\nOld lead.\n')
              .having(
                (f) => f.current?.base,
                'base',
                baseHashOf('\nOld lead.\n'),
              )
              .having(
                (f) => f.current?.heading,
                'heading',
                '==> login/email_login (user_story) · $story1#_lead · base ${baseHashOf('\nOld lead.\n')} <==',
              ),
        ),
      );
    });

    const signOutLead = 'user_story:login/sign_out#_lead';

    test('a lead write marks a non-draft doc draft', () async {
      final root = await writeWriteProject();
      final before = readDoc(root, story2);
      expect(before, isNot(contains('draft: true')));
      final answer = writeIn(
        root,
        (s) => answerSet(
          s,
          req(signOutLead, getDoc(root, signOutLead)['base']! as String),
          'Signing out ends the session.\n',
        ),
      );
      expect(
        readDoc(root, story2),
        before
            .replaceFirst('status: planned\n', 'status: planned\ndraft: true\n')
            .replaceFirst(
              '# Sign out\n',
              '# Sign out\n\nSigning out ends the session.\n',
            ),
      );
      expect(docOf(answer)['draft'], isTrue);
    });

    test(
      'a doc with no title line has its whole head replaced as the lead',
      () async {
        final root = await writeWriteProject(
          extra: {
            'docs/$persona':
                '---\ndraft: true\n---\n\nFirst head line.\n\nSecond head line.\n\n'
                '## Profile\nBuys things.\n',
          },
        );
        const target = 'persona:buyer#_lead';
        writeIn(
          root,
          (s) => answerSet(
            s,
            req(target, getDoc(root, target)['base']! as String),
            '\nNew head.\n',
          ),
        );
        expect(
          readDoc(root, persona),
          '---\ndraft: true\n---\n\nNew head.\n\n## Profile\nBuys things.\n',
        );
      },
    );

    test('a title-shaped line in the lead is refused naming the line with exit status 64', () async {
      final root = await project();
      final before = readDoc(root, story1);
      expect(
        () => writeIn(
          root,
          (s) =>
              answerSet(s, req(target, leadBase(root)), 'Intro.\n# Retitled\n'),
        ),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
              .having((f) => f.exitStatus, 'exitStatus', 64)
              .having(
                (f) => f.message,
                'message',
                'the lead holds the line "# Retitled"; send the lead only',
              ),
        ),
      );
      expect(readDoc(root, story1), before);
    });

    test('empty stdin on the lead of a non-draft doc marks it draft', () async {
      final root = await writeWriteProject();
      final before = readDoc(root, story2);
      final answer = writeIn(
        root,
        (s) => answerSet(
          s,
          req(signOutLead, getDoc(root, signOutLead)['base']! as String),
          '',
        ),
      );
      expect(
        readDoc(root, story2),
        before.replaceFirst(
          'status: planned\n',
          'status: planned\ndraft: true\n',
        ),
      );
      expect(docOf(answer)['draft'], isTrue);
      expect(docOf(answer)['base'], emptyBaseHash);
    });

    test(
      'a lead that leaves a fence open exits 64 naming the fence line',
      () async {
        final root = await project();
        final before = readDoc(root, story1);
        expect(
          () => writeIn(
            root,
            (s) => answerSet(
              s,
              req(target, leadBase(root)),
              'Run:\n\n~~~sh\nmake\n',
            ),
          ),
          throwsA(
            isA<IndexFault>()
                .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
                .having((f) => f.exitStatus, 'exitStatus', 64)
                .having(
                  (f) => f.message,
                  'message',
                  'the lead leaves the fence "~~~sh" open; close it',
                ),
          ),
        );
        expect(readDoc(root, story1), before);
      },
    );

    test('a lead write keeps CRLF in a CRLF doc', () async {
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

    // No shipped architecture field is an output_ref, so a layer adds one.
    Future<Directory> archProject(String text) => writeWriteProject(
      extra: {
        '.specstone/templates/architecture.yaml':
            'fields:\n  - id: covers\n    type: output_ref\n    list: true\n'
            '    pointer: prefix\n    description: |-\n      Lists code.\n',
        'docs/$signupArch': text,
      },
    );

    test(
      'the base of the laid-out body writes a body stored unlaid-out',
      () async {
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
        expect(docOf(answer)['base'], baseHashOf('\nNone at all.\n'));
      },
    );

    test('a header that differs from the template header in case or spacing is that section, and set prints the base the next get reads', () async {
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
      expect(docOf(answer)['base'], baseHashOf('\nNew job.\n'));
      expect(docOf(answer)['base'], sectionBase(root, target));
    });

    test(
      'an unlaid-out doc is written whole laid out after a section write',
      () async {
        final root = await archProject(padded);
        const target = '$arch#deployment';
        writeIn(
          root,
          (s) => answerSet(
            s,
            req(target, sectionBase(root, target)),
            'None yet.\n',
          ),
        );
        expect(readDoc(root, signupArch), laidOutArch);
      },
    );

    test(
      'a doc format refuses keeps every other byte after a section write',
      () async {
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
      },
    );

    test(
      'an output_ref write on an approved doc lays it out and adds no draft',
      () async {
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
      },
    );

    test(
      'a doc format refuses keeps every other byte after a field write',
      () async {
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
      },
    );

    test('text before the title line stays as on disk', () async {
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

    test(
      'an unlaid-out doc is written whole laid out after a title write',
      () async {
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
      },
    );

    test(
      'a doc format refuses keeps every other byte after a title write',
      () async {
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
      },
    );

    test(
      'an unlaid-out doc is written whole laid out after a lead write',
      () async {
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
      },
    );

    test(
      'a doc format refuses keeps every other byte after a lead write',
      () async {
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
      },
    );

    String outOfOrder(String mark) =>
        '---\noverrides:\n  - x\n$mark\n---\n\n# Signup architecture\n\n'
        '## Deployment\n\nNone yet.\n\n## Components\n\n'
        '| Component | Responsibility |\n|---|---|\n'
        '| Signup form | Collects the email |\n';

    String inOrder(String mark, {String lead = ''}) =>
        '---\n$mark\noverrides:\n  - x\n---\n\n# Signup architecture\n\n$lead'
        '## Components\n\n| Component | Responsibility |\n|---|---|\n'
        '| Signup form | Collects the email |\n\n## Deployment\n\nNone yet.\n';

    String titleBase(Directory root) =>
        (getDoc(root, arch)['bases']! as Map)['title']! as String;

    Future<List<String>> undeclaredHeaders(Directory root) async {
      final session = openSession(root);
      try {
        final report = await runCheck(session);
        return [
          for (final spot in spots(report, FindingKind.sectionUndeclared))
            if (spot.startsWith('$signupArch:')) spot,
        ];
      } finally {
        session.close();
      }
    }

    test('a field write lays out a doc with keys and sections out of template order', () async {
      final root = await archProject(outOfOrder('approved: true'));
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
        inOrder('approved: true')
            .replaceFirst('  - x\n---', '  - x\ncovers:\n  - app/lib/\n---'),
      );
    });

    test('a title write lays out a doc with keys and sections out of template order', () async {
      final root = await archProject(outOfOrder('draft: true'));
      writeIn(
        root,
        (s) => answerSet(
          s,
          SetRequest.parse(arch, title: true, base: titleBase(root)),
          'Signup architecture\n',
        ),
      );
      expect(readDoc(root, signupArch), inOrder('draft: true'));
    });

    test('a section write lays out a doc with keys and sections out of template order', () async {
      final root = await archProject(outOfOrder('draft: true'));
      const target = '$arch#deployment';
      writeIn(
        root,
        (s) =>
            answerSet(s, req(target, sectionBase(root, target)), 'None yet.\n'),
      );
      expect(readDoc(root, signupArch), inOrder('draft: true'));
    });

    test('a lead write lays out a doc with keys and sections out of template order', () async {
      final root = await archProject(outOfOrder('draft: true'));
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
        inOrder('draft: true', lead: 'Lead.\n\n'),
      );
    });

    test('a field write on a doc format refuses stays approved and check reports the unknown header', () async {
      final root = await archProject(
        refused.replaceFirst('draft: true', 'approved: true'),
      );
      writeIn(
        root,
        (s) => answerSet(
          s,
          fieldReq(arch, 'covers', fieldBase(root, arch, 'covers')),
          '- app/lib/\n',
        ),
      );
      expect(readDoc(root, signupArch), isNot(contains('draft:')));
      expect(
        readDoc(root, signupArch),
        startsWith('---\napproved: true\ncovers:'),
      );
      expect(await undeclaredHeaders(root), [
        '$signupArch:9: section_undeclared',
      ]);
    });

    test('check still reports the unknown header after a title write on a doc format refuses', () async {
      final root = await archProject(refused);
      writeIn(
        root,
        (s) => answerSet(
          s,
          SetRequest.parse(arch, title: true, base: titleBase(root)),
          'Renamed\n',
        ),
      );
      expect(await undeclaredHeaders(root), [
        '$signupArch:7: section_undeclared',
      ]);
    });

    test('check still reports the unknown header after a section write on a doc format refuses', () async {
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
      expect(await undeclaredHeaders(root), [
        '$signupArch:7: section_undeclared',
      ]);
    });

    test('check still reports the unknown header after a lead write on a doc format refuses', () async {
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
      expect(await undeclaredHeaders(root), [
        '$signupArch:8: section_undeclared',
      ]);
    });
  });
  group('splicePart checks and splices one part', () {
    const address = 'user_story:login/email_login';
    final withLead = writeProject['docs/$story1']!.replaceFirst(
      '# Sign in with email\n',
      '# Sign in with email\n\nOld lead.\n',
    );

    String titleBase(Directory root) =>
        (getDoc(root, address)['bases']! as Map)['title']! as String;

    // Each row: the request on a fresh project, its stdin, whether the write
    // marks a draft, and the file text it writes where that is plain to state.
    final cases =
        <String, (SetRequest Function(Directory), String, bool, String?)>{
          'a section': (
            (root) => req(
              '$address#acceptance_criteria',
              sectionBase(root, '$address#acceptance_criteria'),
            ),
            '\n### Scenario 1 — [happy] Sign in\n- **Given** a registered email and its password\n',
            true,
            withLead.replaceFirst(
              'a registered email\n',
              'a registered email and its password\n',
            ),
          ),
          'a section the doc lacks': (
            (root) => req('$address#rules', emptyBaseHash),
            '- BR-01 One account per email.\n',
            true,
            withLead.replaceFirst(
              '## Acceptance Criteria\n',
              '## Rules\n\n- BR-01 One account per email.\n\n## Acceptance Criteria\n',
            ),
          ),
          'the lead': (
            (root) =>
                req('$address#_lead', sectionBase(root, '$address#_lead')),
            'New lead.\n',
            true,
            withLead.replaceFirst('Old lead.\n', 'New lead.\n'),
          ),
          'a field': (
            (root) => fieldReq(address, 'goals', emptyBaseHash),
            '- PG-01\n',
            true,
            null,
          ),
          'the title': (
            (root) =>
                SetRequest.parse(address, title: true, base: titleBase(root)),
            'Sign in fast\n',
            true,
            withLead.replaceFirst('# Sign in with email', '# Sign in fast'),
          ),
        };

    for (final MapEntry(key: name, value: row) in cases.entries) {
      test(
        '$name: returns the text answerSet writes for the same input',
        () async {
          final (requestOf, text, marksDraft, expected) = row;
          final spliced = await writeWriteProject(
            extra: {'docs/$story1': withLead},
          );
          final written = await writeWriteProject(
            extra: {'docs/$story1': withLead},
          );

          final part = spliceIn(spliced, requestOf(spliced), text);
          writeIn(written, (s) => answerSet(s, requestOf(written), text));

          expect(part.marksDraft, marksDraft);
          expect(readDoc(spliced, story1), withLead);
          // The write lays the spliced text out, as answerSet's write does.
          writeIn(
            spliced,
            (s) => s.locked(() {
              final doc = s.target(address);
              return s.writeDoc(
                doc.docPath,
                markDraft(part.lfText, s.index.typeOf(doc)!),
                LineEnding.lf,
              );
            }),
          );
          expect(readDoc(spliced, story1), readDoc(written, story1));
          if (expected != null) expect(readDoc(written, story1), expected);
        },
      );
    }

    test('an output_ref field marks no draft', () async {
      final root = await writeWriteProject(extra: loginRecordFile);
      const record = 'implementation:login';
      final part = spliceIn(
        root,
        fieldReq(record, 'covers', fieldBase(root, record, 'covers')),
        '- a.dart\n',
      );
      expect(part.marksDraft, isFalse);
    });
  });

  group('checkFieldWrite refuses a write', () {
    test(
      'a task_ref entry with no task or no item is field_value_invalid',
      () async {
        final root = await writeWriteProject(
          extra: {
            '.specstone/templates/feature.yaml':
                'fields:\n  - id: tasks\n    type: task_ref\n    list: true\n',
          },
        );
        for (final value in ['- ""', '- "login:"', '- ":T-1"', 'T-1']) {
          expect(
            () => checkFieldIn(root, 'feature:login', 'tasks', value),
            throwsWriteFault(WriteFaultCode.fieldValueInvalid),
            reason: value,
          );
        }
        checkFieldIn(root, 'feature:login', 'tasks', '- T-1\n- "a/b:T-2"');
      },
    );

    test('a source_ref field takes a string and refuses a list', () async {
      final root = await writeWriteProject(
        extra: {
          '.specstone/templates/feature.yaml':
              'fields:\n  - id: origin\n    type: source_ref\n',
        },
      );
      checkFieldIn(root, 'feature:login', 'origin', 'docs/a.md');
      expect(
        () => checkFieldIn(root, 'feature:login', 'origin', '- docs/a.md'),
        throwsWriteFault(WriteFaultCode.fieldValueInvalid),
      );
    });

    test(
      'a task_ref write keeps an approved doc approved and a draft a draft',
      () async {
        final root = await writeWriteProject(
          extra: {
            '.specstone/templates/feature.yaml':
                'fields:\n  - id: tasks\n    type: task_ref\n    list: true\n',
          },
        );
        for (final (address, docPath, isDraft) in [
          ('feature:login', loginFeature, false),
          ('feature:signup', signupFeature, true),
        ]) {
          final before = readDoc(root, docPath);
          writeIn(
            root,
            (s) => answerSet(
              s,
              fieldReq(address, 'tasks', fieldBase(root, address, 'tasks')),
              '- T-1\n',
            ),
          );
          final written = readDoc(root, docPath);
          expect(written, contains('tasks:'), reason: address);
          expect(written.contains('draft: true'), isDraft, reason: address);
          expect(before.contains('draft: true'), isDraft, reason: address);
        }
        expect(spots(await checkOf(root), FindingKind.approvalStale), isEmpty);
      },
    );
  });
  group('a part is refused on its own text before the write lock', () {
    const address = 'user_story:login/email_login';
    const fr = 'fr:login/reset_password/expire_reset_link';

    // Each row: the request, its stdin, and the fault it refuses with.
    final refusals = <String, (SetRequest, String, Matcher)>{
      'an open fence in a section body': (
        req('$address#acceptance_criteria', 'x'),
        '```\ncode\n',
        throwsIndexFault(IndexFaultCode.argumentInvalid),
      ),
      'a ## line in a section body': (
        req('$address#acceptance_criteria', 'x'),
        'a\n## Sub\nb\n',
        throwsIndexFault(IndexFaultCode.argumentInvalid),
      ),
      'a ## line in the lead': (
        req('$address#_lead', 'x'),
        '## Sub\n',
        throwsIndexFault(IndexFaultCode.argumentInvalid),
      ),
      'a # line in the lead': (
        req('$address#_lead', 'x'),
        '# Title\n',
        throwsIndexFault(IndexFaultCode.argumentInvalid),
      ),
      'an open fence in the lead': (
        req('$address#_lead', 'x'),
        '```\ncode\n',
        throwsIndexFault(IndexFaultCode.argumentInvalid),
      ),
      'a title of two lines': (
        SetRequest.parse(address, title: true, base: 'x'),
        'one\ntwo\n',
        throwsIndexFault(IndexFaultCode.argumentInvalid),
      ),
      'a title of no line': (
        SetRequest.parse(address, title: true, base: 'x'),
        '\n',
        throwsIndexFault(IndexFaultCode.argumentInvalid),
      ),
      'the draft field': (
        fieldReq(address, 'draft', 'x'),
        'true\n',
        throwsWriteFault(WriteFaultCode.fieldNotWritable),
      ),
      'a value for a feature status': (
        fieldReq('feature:login', 'status', 'x'),
        'implemented\n',
        throwsWriteFault(WriteFaultCode.fieldNotWritable),
      ),
      'a value its field does not take': (
        fieldReq(address, 'vision', 'x'),
        'PV-01\n',
        throwsWriteFault(WriteFaultCode.fieldValueInvalid),
      ),
      'a required field removed': (
        fieldReq(fr, 'traced_from', 'x'),
        '\n',
        throwsWriteFault(WriteFaultCode.requiredTarget),
      ),
      'an undeclared field given a value': (
        fieldReq(address, 'size', 'x'),
        '1\n',
        throwsWriteFault(WriteFaultCode.fieldUnknown),
      ),
    };

    test(
      'answerSet refuses each at once while another call holds the write lock',
      () async {
        final root = await writeWriteProject();
        // Ages every file out of the index's racy window first, so no later
        // refresh needs a write while the lock below is held, however slow
        // the machine.
        final aged = DateTime.now().subtract(const Duration(minutes: 1));
        for (final file in root.listSync(recursive: true).whereType<File>()) {
          file.setLastModifiedSync(aged);
        }
        writeIn(root, (_) {}); // creates the index
        final other = sqlite3.open('${root.path}/.specstone/index.sqlite')
          ..execute('BEGIN IMMEDIATE');
        addTearDown(other.close);
        for (final MapEntry(key: name, value: (request, text, matcher))
            in refusals.entries) {
          expect(
            () => writeIn(
              root,
              (s) => answerSet(s, request, text),
              busyTimeout: const Duration(milliseconds: 100),
            ),
            matcher,
            reason: name,
          );
        }
      },
    );

    test('checkPartText passes a text it cannot judge without the doc: a first line that may be the own header, and an unheld key emptied', () async {
      final root = await writeWriteProject();
      checkPartIn(
        root,
        req('$address#use_case', 'x'),
        '## Use Case\nSign in.\n',
      );
      checkPartIn(
        root,
        req('$address#use_case', 'x'),
        '```\n## Sub\n```\nbody\n',
      );
      checkPartIn(root, fieldReq(address, 'size', 'x'), '\n');
      checkPartIn(root, req('$address#_lead', 'x'), 'A lead.\n');
    });

    test('checkPartText refuses a ## line after the first line, which may be the own header', () async {
      final root = await writeWriteProject();
      expect(
        () => checkPartIn(
          root,
          req('$address#use_case', 'x'),
          '## Use Case\nSign in.\n## Sub\n',
        ),
        throwsIndexFault(IndexFaultCode.argumentInvalid),
      );
    });

    test(
      'a doc that is not UTF-8 with a title of two lines is argument_invalid',
      () async {
        final root = await writeWriteProject();
        final file = docFile(root, signupFeature);
        file.writeAsBytesSync([...file.readAsBytesSync(), 0xFF, 0x0A]);
        expect(
          () => writeIn(
            root,
            (s) => answerSet(
              s,
              SetRequest.parse('feature:signup', title: true, base: 'x'),
              'one\ntwo\n',
            ),
          ),
          throwsIndexFault(IndexFaultCode.argumentInvalid),
        );
      },
    );

    test(
      'a doc that is not there is doc_not_found whatever the text',
      () async {
        final root = await writeWriteProject();
        expect(
          () => writeIn(
            root,
            (s) => answerSet(
              s,
              req('user_story:login/no_such#_lead', 'x'),
              '```\nopen\n',
            ),
          ),
          throwsIndexFault(IndexFaultCode.docNotFound),
        );
      },
    );

    test('removing a required field on a stale base is required_target, and a required section keeps base_mismatch', () async {
      final root = await writeWriteProject();
      expect(
        () => spliceIn(root, fieldReq(fr, 'traced_from', 'stale'), '\n'),
        throwsWriteFault(WriteFaultCode.requiredTarget),
      );
      expect(
        () => spliceIn(root, req('$address#use_case', 'stale'), ''),
        throwsWriteFault(WriteFaultCode.baseMismatch),
      );
    });

    test('section_not_found names <type>:<name> for an address by DocPath and by bare name', () async {
      final root = await writeWriteProject();
      for (final written in [story1, 'login/email_login', address]) {
        expect(
          () => spliceIn(root, req('$written#notes', emptyBaseHash), 'x\n'),
          throwsA(
            isA<IndexFault>()
                .having((f) => f.code, 'code', IndexFaultCode.sectionNotFound)
                .having(
                  (f) => f.message,
                  'message',
                  startsWith('$address holds no section with the key notes'),
                ),
          ),
          reason: written,
        );
      }
    });
  });

  group('a naming line in a text is refused,', () {
    const naming =
        '==> other (feature) · prds/features/f01_other/FEATURE.md#problem · base 55884d229b07 <==';
    const target = 'user_story:login/email_login#use_case';

    Matcher refusesNamingLine(String line) => throwsA(
      isA<IndexFault>()
          .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
          .having((f) => f.exitStatus, 'exitStatus', 64)
          .having((f) => f.message, 'message', contains('"$line"')),
    );

    test('set of a section refuses a column-0 naming line outside a fence and writes nothing', () async {
      final root = await writeWriteProject();
      final before = readDoc(root, story1);
      final base = sectionBase(root, target);
      for (final text in [
        'Sign in.\n\n$naming\nExample.\n',
        '$naming\n',
        '## Use Case\n\nx\n$naming  \n',
        'x\n==> broken <==\n',
      ]) {
        final line = text.split('\n').firstWhere((l) => l.startsWith('==>'));
        expect(
          () => writeIn(root, (s) => answerSet(s, req(target, base), text)),
          refusesNamingLine(line.trimRight()),
          reason: text,
        );
      }
      expect(
        () => writeIn(
          root,
          (s) => answerSet(s, req(target, base), 'Sign in.\n\n$naming  \n'),
        ),
        throwsA(
          isA<IndexFault>().having(
            (f) => f.message,
            'message',
            'the body holds the naming line "$naming"; indent it or put it in a fenced code block',
          ),
        ),
      );
      expect(readDoc(root, story1), before);
    });

    test(
      'checkPartText refuses it in a lead, with no lock and no doc text',
      () async {
        final root = await writeWriteProject();
        expect(
          () =>
              checkPartIn(root, req('$story1#_lead', 'x'), 'Lead.\n$naming\n'),
          refusesNamingLine(naming),
        );
      },
    );

    test('a field value is not refused for a naming line: it never lands at column 0', () async {
      final root = await writeWriteProject();
      try {
        checkPartIn(
          root,
          fieldReq(story1, 'vision', 'x'),
          '- PV-01\n$naming\n',
        );
      } on IndexFault catch (fault) {
        expect(fault.message, isNot(contains('naming line')));
      } on WriteFault {
        // The field's own value checks may still refuse it.
      }
    });

    test('a fenced line and an indented line pass', () async {
      final root = await writeWriteProject();
      final base = sectionBase(root, target);
      writeIn(
        root,
        (s) => answerSet(
          s,
          req(target, base),
          'Shown as:\n\n```text\n$naming\n```\n\n    $naming\n\n- $naming\n',
        ),
      );
      final text = readDoc(root, story1);
      expect(text, contains('\n```text\n$naming\n```\n'));
      expect(text, contains('\n    $naming\n'));
    });
  });

  test(
    'header-only stdin on a section the doc lacks still writes it empty',
    () async {
      final root = await writeWriteProject();
      const target = 'user_story:login/email_login#open_questions';
      writeIn(
        root,
        (s) => answerSet(s, req(target, emptyBaseHash), '## Open questions\n'),
      );
      expect(readDoc(root, story1), endsWith('## Open questions\n'));
      expect(
        '## Open questions'.allMatches(readDoc(root, story1)),
        hasLength(1),
      );
    },
  );

  group('with two code targets', () {
    const arch = 'architecture:login';
    const recordLayer =
        'id: implementation\n'
        'description: One feature record per target.\n'
        'path: specs/f{nn}_{slug}/IMPLEMENTATION.md\n'
        'parent: feature\n'
        'per_target: true\n'
        'fields:\n'
        '  - id: statuses\n'
        '    type: record_status\n'
        '    list: true\n'
        '  - id: implements\n'
        '    type: output_ref\n'
        '    list: true\n'
        '    pointer: item_exact\n';
    const flutterRecord = 'specs/flutter/f01_login/IMPLEMENTATION.md';
    const jasprRecord = 'specs/jaspr/f01_login/IMPLEMENTATION.md';
    const record =
        '---\nstatuses:\n  - email_login/check_password:implemented\n'
        'implements:\n  - email_login/check_password:app/lib/login.dart\n'
        '---\n\n# Record\n';

    // The helper stamps no per-target doc, so each record gets its hash here.
    Future<Directory> twinWithRecords() async {
      final root = await writeTwinProject(
        extra: {
          '.specstone/templates/implementation.yaml': recordLayer,
          'docs/$flutterRecord': record,
          'docs/$jasprRecord': record,
        },
      );
      final (type, statusesOutside) = writeIn(
        root,
        (s) => (s.index.set.recordDocType!, s.project.statusesOutsideApproval),
      );
      for (final path in [flutterRecord, jasprRecord]) {
        docFile(root, path).writeAsStringSync(
          withApprovalHash(record, type, statusesOutside: statusesOutside),
        );
      }
      return root;
    }

    // The shipped record of each target, which [writeTwinProject] writes
    // approved, with one `covers` entry.
    const twinRecord = 'implementation:login';
    const flutterTwinRecord =
        '.specstone/records/flutter/f01_login/IMPLEMENTATION.md';
    const jasprTwinRecord =
        '.specstone/records/jaspr/f01_login/IMPLEMENTATION.md';

    SetRequest jaspr(String address, String base, {String? field}) =>
        SetRequest.parse(
          address,
          field: field,
          base: base,
          codeTarget: 'jaspr',
        );

    test('--target jaspr writes the covers of the jaspr twin only and leaves it approved', () async {
      final root = await writeTwinProject();
      final flutterBefore = readDoc(root, flutterTwinRecord);
      final answer = writeIn(
        root,
        (s) => answerSet(
          s,
          jaspr(
            twinRecord,
            fieldBase(root, jasprTwinRecord, 'covers'),
            field: 'covers',
          ),
          '- app/lib/login/\n',
        ),
      );
      expect(
        readDoc(root, jasprTwinRecord),
        allOf(
          contains('covers:\n  - app/lib/login/\n'),
          isNot(contains('draft')),
        ),
      );
      expect(readDoc(root, flutterTwinRecord), flutterBefore);
      expect(docOf(answer)['path'], jasprTwinRecord);
      expect(docOf(answer)['draft'], isFalse);
    });

    test('a name that two targets share is argument_invalid listing both docs without --target, and --target must name a target', () async {
      final root = await writeTwinProject();
      final base = fieldBase(root, jasprTwinRecord, 'covers');
      List<String> records() => [
        readDoc(root, flutterTwinRecord),
        readDoc(root, jasprTwinRecord),
      ];
      final before = records();
      expect(
        () => writeIn(
          root,
          (s) => answerSet(
            s,
            fieldReq(twinRecord, 'covers', base),
            '- app/lib/login/\n',
          ),
        ),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
              .having(
                (f) => f.message,
                'message',
                '$twinRecord names 2 docs: $flutterTwinRecord, $jasprTwinRecord',
              ),
        ),
      );
      expect(
        () => writeIn(
          root,
          (s) => answerSet(
            s,
            SetRequest.parse(
              twinRecord,
              field: 'covers',
              base: base,
              codeTarget: 'dart',
            ),
            '- app/lib/login/\n',
          ),
        ),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
              .having(
                (f) => f.message,
                'message',
                '--target dart: the code targets are flutter, jaspr',
              ),
        ),
      );
      expect(records(), before);
    });

    test('an implements write and, at the statuses pin, a statuses write on a target record leave it approved', () async {
      final root = await twinWithRecords();
      const address = 'implementation:login';
      final flutterBefore = readDoc(root, flutterRecord);
      final approvedBefore = RegExp('approved: "[0-9a-f]{12}"')
          .firstMatch(readDoc(root, jasprRecord))![0]!;
      final answer = writeIn(
        root,
        (s) => answerSet(
          s,
          jaspr(
            address,
            fieldBase(root, jasprRecord, 'implements'),
            field: 'implements',
          ),
          '- email_login/check_password:app/lib/login.dart:SignInPage\n',
        ),
      );
      final written = readDoc(root, jasprRecord);
      expect(
        written,
        allOf(
          contains(
            'implements:\n'
            '  - email_login/check_password:app/lib/login.dart:SignInPage\n',
          ),
          contains(approvedBefore),
          isNot(contains('draft')),
        ),
      );
      expect(docOf(answer)['draft'], isFalse);
      expect(readDoc(root, flutterRecord), flutterBefore);
      expect(spots(await checkOf(root), FindingKind.approvalStale), isEmpty);

      final status = writeIn(
        root,
        (s) => answerSet(
          s,
          jaspr(
            address,
            fieldBase(root, jasprRecord, 'statuses'),
            field: 'statuses',
          ),
          '- email_login/check_password:skipped\n',
        ),
      );
      expect(docOf(status)['draft'], isFalse);
      expect(
        readDoc(root, jasprRecord),
        allOf(
          contains('  - email_login/check_password:skipped\n'),
          contains(approvedBefore),
          isNot(contains('draft')),
        ),
      );
      expect(spots(await checkOf(root), FindingKind.approvalStale), isEmpty);
    });

    test('an implements entry with a fingerprint leaves a record approved or draft as it was', () async {
      final root = await twinWithRecords();
      docFile(
        root,
        flutterRecord,
      ).writeAsStringSync(record.replaceFirst('---\n', '---\ndraft: true\n'));
      const entry =
          'email_login/check_password:app/lib/login.dart:SignInPage 5d1e0c4b7a92';
      final approvedBefore = RegExp('approved: "[0-9a-f]{12}"')
          .firstMatch(readDoc(root, jasprRecord))![0]!;

      final answers = {
        for (final path in [flutterRecord, jasprRecord])
          path: writeIn(
            root,
            (s) => answerSet(
              s,
              SetRequest.parse(
                path,
                field: 'implements',
                base: fieldBase(root, path, 'implements'),
              ),
              '- $entry\n',
            ),
          ),
      };

      expect(readDoc(root, flutterRecord), contains('draft: true\n'));
      expect(readDoc(root, flutterRecord), contains('  - $entry\n'));
      expect(docOf(answers[flutterRecord]!)['draft'], isTrue);
      expect(
        readDoc(root, jasprRecord),
        allOf(
          contains('  - $entry\n'),
          contains(approvedBefore),
          isNot(contains('draft')),
        ),
      );
      expect(docOf(answers[jasprRecord]!)['draft'], isFalse);
    });

    test(
      'below the statuses pin, a statuses write on a target record drafts it',
      () async {
        final root = await writeTwinProject(
          extra: {
            '.specstone/templates/implementation.yaml': recordLayer,
            'docs/$jasprRecord': record,
          },
        );
        pinStatusesBelow(root);
        T below<T>(T Function(WriteSession session) body) =>
            writeIn(root, body, templates: statusesBelowResolver);
        final type = below((s) => s.index.set.recordDocType!);
        docFile(root, jasprRecord).writeAsStringSync(
          withApprovalHash(record, type, statusesOutside: false),
        );
        final base = below((s) {
          final docs = answerGet(s.index, [jasprRecord]).json['docs']! as List;
          final bases = (docs.single as Map)['bases']! as Map;
          return (bases['fields']! as Map)['statuses']! as String;
        });

        final status = below(
          (s) => answerSet(
            s,
            jaspr('implementation:login', base, field: 'statuses'),
            '- email_login/check_password:skipped\n',
          ),
        );

        expect(docOf(status)['draft'], isTrue);
        expect(readDoc(root, jasprRecord), contains('draft: true'));
      },
    );

    test('a statuses line that check refuses is field_value_invalid, naming the four statuses', () async {
      final root = await twinWithRecords();
      final before = readDoc(root, jasprRecord);
      for (final stdin in [
        '- email_login/check_password:wip\n',
        '- email_login/check_password\n',
      ]) {
        expect(
          () => writeIn(
            root,
            (s) => answerSet(
              s,
              jaspr(
                'implementation:login',
                fieldBase(root, jasprRecord, 'statuses'),
                field: 'statuses',
              ),
              stdin,
            ),
          ),
          throwsA(
            isA<WriteFault>()
                .having((f) => f.code, 'code', WriteFaultCode.fieldValueInvalid)
                .having(
                  (f) => f.message,
                  'message',
                  'statuses takes a line <item>:<status>, the status planned, '
                      'implemented, deprecated, or skipped',
                ),
          ),
          reason: stdin,
        );
      }
      expect(readDoc(root, jasprRecord), before);
    });

    test(
      'a section of one twin is written and the other twin keeps its text',
      () async {
        final root = await writeTwinProject();
        final flutterBefore = readDoc(root, flutterArchitecture);
        final answer = writeIn(
          root,
          (s) => answerSet(
            s,
            jaspr(
              '$arch#components',
              sectionBase(root, '$jasprArchitecture#components'),
            ),
            '- Jaspr page\n',
          ),
        );
        expect(
          readDoc(root, jasprArchitecture),
          contains('## Components\n\n- Jaspr page\n'),
        );
        expect(readDoc(root, flutterArchitecture), flutterBefore);
        expect(docOf(answer)['path'], jasprArchitecture);
        expect(docOf(answer)['draft'], isTrue);
      },
    );
  });

  group('set --replace', () {
    const useCase = 'user_story:login/email_login#use_case';
    const signOutUseCase = 'user_story:login/sign_out#use_case';
    const criteria = 'user_story:login/email_login#acceptance_criteria';

    String stdin(String oldText, String newText) =>
        '==> old <==\n$oldText\n==> new <==\n$newText\n';

    SetRequest replaceReq(String target, String base) =>
        SetRequest.parse(target, base: base, replace: true);

    ReadAnswer replace(Directory root, String target, String text) => writeIn(
      root,
      (s) => answerSet(s, replaceReq(target, sectionBase(root, target)), text),
    );

    test('replaces the one match, marks the doc draft, and prints the new base', () async {
      final root = await writeWriteProject();
      final before = readDoc(root, story2);
      expect(before, isNot(contains('draft: true')));
      final answer = replace(
        root,
        signOutUseCase,
        stdin('Sign out.', 'Sign out now.'),
      );
      final written = baseHashOf('\nSign out now.\n');
      expect(
        readDoc(root, story2),
        before
            .replaceFirst('Sign out.\n', 'Sign out now.\n')
            .replaceFirst(
              'status: planned\n',
              'status: planned\ndraft: true\n',
            ),
      );
      expect(
        answer.text,
        '==> login/sign_out (user_story) · $story2#use_case · base $written <==\n',
      );
      expect(docOf(answer)['base'], written);
      expect(docOf(answer)['draft'], isTrue);
      expect(sectionBase(root, signOutUseCase), written);
    });

    test('refuses an old passage found 0 times with the current section', () async {
      final root = await writeWriteProject();
      final before = readDoc(root, story1);
      final current = sectionBase(root, useCase);
      expect(
        () => replace(root, useCase, stdin('Blue fish.', 'x')),
        throwsA(
          isA<WriteFault>()
              .having((f) => f.code, 'code', WriteFaultCode.replaceUnmatched)
              .having((f) => f.exitStatus, 'exitStatus', 75)
              .having((f) => (f.file, f.key), 'location', (story1, 'use_case'))
              .having(
                (f) => f.current?.text,
                'current.text',
                '## Use Case\n\nSign in with an email.\n',
              )
              .having((f) => f.current?.base, 'current.base', current)
              .having(
                (f) => f.current?.heading,
                'heading',
                '==> login/email_login (user_story) · $story1#use_case · base $current <==',
              ),
        ),
      );
      expect(readDoc(root, story1), before);
    });

    test(
      'refuses an old passage found 2 or more times and names the count',
      () async {
        final root = await writeWriteProject();
        final before = readDoc(root, story1);
        expect(
          () => replace(root, useCase, stdin('a', 'x')),
          throwsA(
            isA<WriteFault>()
                .having((f) => f.code, 'code', WriteFaultCode.replaceAmbiguous)
                .having((f) => f.exitStatus, 'exitStatus', 64)
                .having((f) => f.message, 'message', contains('occurs 2 times'))
                .having((f) => f.current, 'current', isNull),
          ),
        );
        expect(readDoc(root, story1), before);
      },
    );

    test('keeps CRLF line ends after a replace', () async {
      final root = await writeWriteProject();
      docFile(
        root,
        story1,
      ).writeAsStringSync(readDoc(root, story1).replaceAll('\n', '\r\n'));
      replace(
        root,
        criteria,
        stdin(
          '### Scenario 1 — [happy] Sign in\n\n- **Given** a registered email',
          '### Scenario 1 — [happy] Sign in\n\n- **Given** a registered email and its password',
        ),
      );
      expect(
        readDoc(root, story1).replaceAll('\r\n', ''),
        isNot(contains('\n')),
      );
      expect(
        readDoc(root, story1),
        contains(
          '### Scenario 1 — [happy] Sign in\r\n\r\n- **Given** a registered email and its password\r\n',
        ),
      );
    });

    test('matches a CRLF old passage against a body with LF ends', () async {
      final root = await writeWriteProject();
      final before = readDoc(root, story1);
      const passage =
          '### Scenario 1 — [happy] Sign in\n\n- **Given** a registered email';
      expect(before, contains(passage));
      replace(
        root,
        criteria,
        '==> old <==\r\n### Scenario 1 — [happy] Sign in\r\n\r\n'
        '- **Given** a registered email\r\n==> new <==\r\nx\r\n',
      );
      expect(readDoc(root, story1), before.replaceFirst(passage, 'x'));

      replace(
        root,
        useCase,
        '==> old <==\r\nwith an email\r\n==> new <==\r\nwith a link\r\n',
      );
      expect(
        readDoc(root, story1),
        before
            .replaceFirst(passage, 'x')
            .replaceFirst('with an email', 'with a link'),
      );
    });

    test(
      'refuses an old passage holding a lone CR against an LF body',
      () async {
        final root = await writeWriteProject();
        final before = readDoc(root, story1);
        expect(
          () => replace(
            root,
            useCase,
            '==> old <==\nSign\rin with an email\n==> new <==\nx\n',
          ),
          throwsA(
            isA<WriteFault>()
                .having((f) => f.code, 'code', WriteFaultCode.replaceUnmatched)
                .having((f) => f.exitStatus, 'exitStatus', 75),
          ),
        );
        expect(readDoc(root, story1), before);
      },
    );

    test('an empty new passage deletes the old passage', () async {
      final root = await writeWriteProject();
      final before = readDoc(root, story1);
      replace(root, useCase, '==> old <==\n an email\n==> new <==\n');
      expect(readDoc(root, story1), before.replaceFirst(' an email', ''));
    });

    test('refuses a new passage that leaves a fence open', () async {
      final root = await writeWriteProject();
      final before = readDoc(root, story1);
      expect(
        () => replace(root, useCase, stdin('Sign in', '```\nSign in')),
        throwsIndexFault(IndexFaultCode.argumentInvalid),
      );
      expect(readDoc(root, story1), before);
    });

    test('refuses malformed stdin before it checks the base', () async {
      final root = await writeWriteProject();
      final stale = sectionBase(root, useCase);
      writeIn(
        root,
        (s) => answerSet(s, req(useCase, stale), 'Someone else wrote this.\n'),
      );
      final before = readDoc(root, story1);
      for (final bad in ['Sign in\n', '==> old <==\n\n==> new <==\nx\n']) {
        expect(
          () => writeIn(
            root,
            (s) => answerSet(s, replaceReq(useCase, stale), bad),
          ),
          throwsIndexFault(IndexFaultCode.argumentInvalid),
          reason: bad,
        );
      }
      expect(readDoc(root, story1), before);
    });

    test('refuses a stale base before it matches the old passage', () async {
      final root = await writeWriteProject();
      final stale = sectionBase(root, useCase);
      writeIn(
        root,
        (s) => answerSet(s, req(useCase, stale), 'Someone else wrote this.\n'),
      );
      final before = readDoc(root, story1);
      expect(
        () => writeIn(
          root,
          (s) => answerSet(
            s,
            replaceReq(useCase, stale),
            stdin('Blue fish.', 'x'),
          ),
        ),
        throwsWriteFault(WriteFaultCode.baseMismatch),
      );
      expect(readDoc(root, story1), before);
    });

    test('reads a template section the doc lacks as an empty body', () async {
      final root = await writeWriteProject();
      final before = readDoc(root, story1);
      expect(
        () => writeIn(
          root,
          (s) => answerSet(
            s,
            replaceReq('user_story:login/email_login#rules', emptyBaseHash),
            stdin('a', 'b'),
          ),
        ),
        throwsA(
          isA<WriteFault>()
              .having((f) => f.code, 'code', WriteFaultCode.replaceUnmatched)
              .having((f) => f.exitStatus, 'exitStatus', 75),
        ),
      );
      expect(readDoc(root, story1), before);
    });

    test('refuses stdin with no new marker or a second marker with exit status 64 and leaves the doc', () async {
      final root = await writeWriteProject();
      final before = readDoc(root, story1);
      for (final bad in [
        '==> old <==\nSign in\n',
        '==> old <==\nSign in\n==> new <==\nx\n==> new <==\ny\n',
      ]) {
        expect(
          () => replace(root, useCase, bad),
          throwsA(
            isA<IndexFault>()
                .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
                .having((f) => f.exitStatus, 'exitStatus', 64),
          ),
          reason: bad,
        );
      }
      expect(readDoc(root, story1), before);
    });

    test('refuses a new passage that makes a header line naming the line with exit status 64', () async {
      final root = await writeWriteProject();
      final before = readDoc(root, story1);
      expect(
        () => replace(
          root,
          useCase,
          stdin('Sign in with an email.', 'Sign in.\n\n## Other'),
        ),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
              .having((f) => f.exitStatus, 'exitStatus', 64)
              .having(
                (f) => f.message,
                'message',
                'the body holds the header line "## Other"; send the body only',
              ),
        ),
      );
      expect(readDoc(root, story1), before);
    });
  });

  group('set refuses and lays out edge cases of one section or field', () {
    const useCase = 'user_story:login/email_login#use_case';
    const naming =
        '==> other (feature) · prds/features/f01_other/FEATURE.md#problem · base 55884d229b07 <==';
    const paddedArch =
        '---\ndraft: true\n---\n\n# Signup architecture\n\n## Components\n'
        '| Component   | Responsibility |\n|-------------|----------------|\n'
        '| Signup form | Collects the email |\n\n## Deployment\nNone yet.\n';

    final linksUnavailable = Platform.isWindows
        ? 'a link needs a privilege on Windows'
        : null;

    /// Replaces the file of [docPath] by a link to a copy of it outside the
    /// project, as a file swapped after the index read it is; returns the copy.
    File leaveProject(Directory root, String docPath) {
      final outside = Directory.systemTemp.createTempSync('set_outside_');
      addTearDown(() => outside.deleteSync(recursive: true));
      final copy = File('${outside.path}/doc.md')
        ..writeAsStringSync(readDoc(root, docPath));
      final file = docFile(root, docPath)..deleteSync();
      Link(file.path).createSync(copy.path);
      return copy;
    }

    Matcher refusesAsLeavingTheProject(String docPath) => throwsA(
      isA<RenderFault>()
          .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
          .having((f) => f.exitStatus, 'exitStatus', 73)
          .having(
            (f) => f.message,
            'message',
            'cannot write docs/$docPath: it leads outside the project',
          ),
    );

    test(
      'a field added to a doc holding an undeclared key lands before that key',
      () async {
        final root = await writeWriteProject(
          extra: {
            'docs/$story1':
                '---\nstatus: planned\ndraft: true\nsize: 1\npersona:\n  - buyer\nvision:\n  - PV-01\n---\n\n'
                '# Sign in with email\n\n## Use Case\n\nSign in with an email.\n\n'
                '## Acceptance Criteria\n\n- **Given** a registered email\n',
          },
        );
        const target = 'user_story:login/email_login';
        writeIn(
          root,
          (s) => answerSet(
            s,
            fieldReq(target, 'goals', emptyBaseHash),
            '- PG-01\n',
          ),
        );
        expect(
          readDoc(root, story1),
          startsWith(
            '---\nstatus: planned\ndraft: true\nvision:\n  - PV-01\ngoals:\n  - PG-01\npersona:\n  - buyer\nsize: 1\n---\n',
          ),
        );
      },
    );

    test('a task_ref entry shaped :ENG-42 or INV-4: is field_value_invalid with exit status 64, and a tasks write on an approved spec doc keeps it approved', () async {
      final root = await writeWriteProject();
      const target = 'architecture:login';
      final before = readDoc(root, loginArch);
      for (final value in ['- ":ENG-42"\n', '- "INV-4:"\n']) {
        expect(
          () => writeIn(
            root,
            (s) => answerSet(
              s,
              fieldReq(target, 'tasks', fieldBase(root, target, 'tasks')),
              value,
            ),
          ),
          throwsA(
            isA<WriteFault>()
                .having((f) => f.code, 'code', WriteFaultCode.fieldValueInvalid)
                .having((f) => f.exitStatus, 'exitStatus', 64),
          ),
          reason: value,
        );
      }
      expect(readDoc(root, loginArch), before);
      final answer = writeIn(
        root,
        (s) => answerSet(
          s,
          fieldReq(target, 'tasks', fieldBase(root, target, 'tasks')),
          '- INV-4:ENG-42\n',
        ),
      );
      expect(readDoc(root, loginArch), contains('tasks:\n  - INV-4:ENG-42\n'));
      expect(readDoc(root, loginArch), isNot(contains('draft:')));
      expect(readDoc(root, loginArch), contains('approved: "'));
      expect(docOf(answer)['draft'], isFalse);
    });

    test('a list write into an absent block writes plain entries and single-quotes S1: x and true', () async {
      final root = await writeWriteProject();
      const target = 'user_story:login/email_login';
      writeIn(
        root,
        (s) => answerSet(
          s,
          fieldReq(target, 'goals', emptyBaseHash),
          '- PG-01\n- "S1: x"\n- "true"\n',
        ),
      );
      expect(
        readDoc(root, story1),
        contains("goals:\n  - PG-01\n  - 'S1: x'\n  - 'true'\n"),
      );
    });

    test('a list write into a present empty block writes plain entries and single-quotes S1: x and true', () async {
      final root = await writeWriteProject(
        extra: {
          'docs/$story1': writeProject['docs/$story1']!.replaceFirst(
            'persona:\n  - buyer\n',
            'persona:\n  - buyer\ngoals:\n',
          ),
        },
      );
      const target = 'user_story:login/email_login';
      writeIn(
        root,
        (s) => answerSet(
          s,
          fieldReq(target, 'goals', fieldBase(root, target, 'goals')),
          '- PG-01\n- "S1: x"\n- "true"\n',
        ),
      );
      expect(
        readDoc(root, story1),
        contains("goals:\n  - PG-01\n  - 'S1: x'\n  - 'true'\n"),
      );
    });

    test('a write that lays out the whole doc leaves the older base of another section valid', () async {
      final root = await writeWriteProject(
        extra: {'docs/$signupArch': paddedArch},
      );
      const components = 'architecture:signup#components';
      const deployment = 'architecture:signup#deployment';
      final olderBase = sectionBase(root, components);
      writeIn(
        root,
        (s) => answerSet(
          s,
          req(deployment, sectionBase(root, deployment)),
          'Nothing yet.\n',
        ),
      );
      expect(
        readDoc(root, signupArch),
        contains('| Component | Responsibility |\n|---|---|\n'),
      );
      writeIn(
        root,
        (s) => answerSet(
          s,
          req(components, olderBase),
          '| A | B |\n|---|---|\n| 1 | 2 |\n',
        ),
      );
      expect(
        readDoc(root, signupArch),
        allOf(
          contains('## Components\n\n| A | B |\n|---|---|\n| 1 | 2 |\n'),
          contains('## Deployment\n\nNothing yet.\n'),
        ),
      );
    });

    test('empty stdin on an absent optional section writes a non-draft doc marked draft', () async {
      final root = await writeWriteProject();
      final before = readDoc(root, story2);
      expect(before, isNot(contains('draft: true')));
      final answer = writeIn(
        root,
        (s) => answerSet(
          s,
          req('user_story:login/sign_out#rules', emptyBaseHash),
          '',
        ),
      );
      expect(
        readDoc(root, story2),
        before.replaceFirst(
          'status: planned\n',
          'status: planned\ndraft: true\n',
        ),
      );
      expect(docOf(answer)['draft'], isTrue);
      expect(docOf(answer)['base'], emptyBaseHash);
    });

    test('a section set on a doc with no frontmatter adds frontmatter holding draft: true and one blank line', () async {
      final root = await writeWriteProject(
        extra: {'docs/$persona': '# Buyer\n\n## Snapshot\nBuys things.\n'},
      );
      const target = 'persona:buyer#snapshot';
      writeIn(
        root,
        (s) => answerSet(
          s,
          req(target, sectionBase(root, target)),
          'Buys many things.\n',
        ),
      );
      expect(
        readDoc(root, persona),
        '---\ndraft: true\n---\n\n# Buyer\n\n## Snapshot\n\nBuys many things.\n',
      );
    });

    test('a body that leaves a fence open exits 64 naming the fence line and the file stays', () async {
      final root = await writeWriteProject();
      final before = readDoc(root, story1);
      expect(
        () => writeIn(
          root,
          (s) => answerSet(
            s,
            req(useCase, sectionBase(root, useCase)),
            'See:\n\n~~~sh\nmake\n',
          ),
        ),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
              .having((f) => f.exitStatus, 'exitStatus', 64)
              .having(
                (f) => f.message,
                'message',
                'the body leaves the fence "~~~sh" open; close it',
              ),
        ),
      );
      expect(readDoc(root, story1), before);
    });

    test('a ## line in a body exits 64 and a four-space-indented ## line is accepted', () async {
      final root = await writeWriteProject();
      final before = readDoc(root, story1);
      for (final header in ['## Other', '## Acceptance Criteria']) {
        expect(
          () => writeIn(
            root,
            (s) => answerSet(
              s,
              req(useCase, sectionBase(root, useCase)),
              'Sign in.\n\n$header\n',
            ),
          ),
          throwsA(
            isA<IndexFault>()
                .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
                .having((f) => f.exitStatus, 'exitStatus', 64)
                .having(
                  (f) => f.message,
                  'message',
                  'the body holds the header line "$header"; send the body only',
                ),
          ),
        );
      }
      expect(readDoc(root, story1), before);
      writeIn(
        root,
        (s) => answerSet(
          s,
          req(useCase, sectionBase(root, useCase)),
          'Sign in.\n\n    ## Other\n',
        ),
      );
      expect(readDoc(root, story1), contains('Sign in.\n\n    ## Other\n'));
    });

    test('a naming line is refused in a lead and in a new doc text, each message opening with its own subject', () async {
      final root = await writeWriteProject();
      const lead = 'user_story:login/email_login#_lead';
      expect(
        () => writeIn(
          root,
          (s) => answerSet(
            s,
            req(lead, getDoc(root, lead)['base']! as String),
            'Intro.\n$naming\n',
          ),
        ),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
              .having(
                (f) => f.message,
                'message',
                startsWith('the lead holds the naming line "$naming"'),
              ),
        ),
      );
      expect(
        () => writeIn(
          root,
          (s) => answerNew(
            s,
            docTypeId: 'user_story',
            parent: 'login',
            slug: 'quoted',
            text: '# Mine\n\n$naming\n',
          ),
        ),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
              .having(
                (f) => f.message,
                'message',
                startsWith('the text holds the naming line "$naming"'),
              ),
        ),
      );
    });

    test('a doc file leading outside the project is output_not_writable with exit status 73 and stays untouched', () async {
      final root = await writeWriteProject();
      final base = sectionBase(root, useCase);
      late final File copy;
      expect(
        () => writeIn(root, (s) {
          copy = leaveProject(root, story1);
          return answerSet(s, req(useCase, base), 'x\n');
        }),
        refusesAsLeavingTheProject(story1),
      );
      expect(copy.readAsStringSync(), writeProject['docs/$story1']);
      expect(FileSystemEntity.isLinkSync(docFile(root, story1).path), isTrue);
    }, skip: linksUnavailable);
  });

  group('a record matrix section write', () {
    const address = 'implementation:login';
    const matrix = '$address#verification_matrix';
    const notes = '$address#notes';
    SetRequest replaceOf(String target, String base) =>
        SetRequest.parse(target, base: base, replace: true);

    for (final isDraft in [false, true]) {
      final state = isDraft ? 'a draft' : 'an approved';

      test('a set leaves $state record as it was', () async {
        final root = await writeMatrixRecordProject(isDraft: isDraft);
        final before = readDoc(root, loginRecord);

        final answer = writeIn(
          root,
          (s) => answerSet(
            s,
            req(matrix, sectionBase(root, matrix)),
            '$matrixRow- email_login/check_password E02: `an empty password`\n',
          ),
        );

        expect(
          readDoc(root, loginRecord),
          before.replaceFirst(
            matrixRow,
            '$matrixRow- email_login/check_password E02: `an empty password`\n',
          ),
        );
        expect(docOf(answer)['draft'], isDraft);
      });
    }

    test('a replace leaves the approved record as it was', () async {
      final root = await writeMatrixRecordProject(isDraft: false);
      final before = readDoc(root, loginRecord);

      final answer = writeIn(
        root,
        (s) => answerSet(
          s,
          replaceOf(matrix, sectionBase(root, matrix)),
          '==> old <==\na wrong password\n==> new <==\na wrong email\n',
        ),
      );

      expect(
        readDoc(root, loginRecord),
        before.replaceFirst('a wrong password', 'a wrong email'),
      );
      expect(docOf(answer)['draft'], isFalse);
    });

    test(
      'a set of any other section marks the approved record draft',
      () async {
        final root = await writeMatrixRecordProject(isDraft: false);

        final answer = writeIn(
          root,
          (s) =>
              answerSet(s, req(notes, sectionBase(root, notes)), 'Changed.\n'),
        );

        expect(docOf(answer)['draft'], isTrue);
        expect(readDoc(root, loginRecord), contains('draft: true\n'));
      },
    );

    test(
      'empty text for a matrix section the record lacks leaves it approved',
      () async {
        final root = await writeMatrixRecordProject(
          isDraft: false,
          hasMatrix: false,
        );
        final before = readDoc(root, loginRecord);

        final answer = writeIn(
          root,
          (s) => answerSet(s, req(matrix, emptyBaseHash), ''),
        );

        expect(readDoc(root, loginRecord), before);
        expect(docOf(answer)['draft'], isFalse);
      },
    );

    test('empty text for a held matrix section removes it and leaves the record approved', () async {
      final root = await writeMatrixRecordProject(isDraft: false);
      final before = readDoc(root, loginRecord);

      final answer = writeIn(
        root,
        (s) => answerSet(s, req(matrix, sectionBase(root, matrix)), ''),
      );

      expect(
        readDoc(root, loginRecord),
        before.replaceFirst('## Verification matrix\n\n$matrixRow\n', ''),
      );
      expect(docOf(answer)['draft'], isFalse);
    });

    test(
      'a batch writing the matrix and another section marks the record draft',
      () async {
        final root = await writeMatrixRecordProject(isDraft: false);
        final text =
            writeIn(root, (s) => answerGet(s.index, [matrix, notes]).text)
                .replaceFirst('a wrong password', 'a wrong email')
                .replaceFirst('See the rows.', 'See the table.');

        final answer = writeIn(
          root,
          (s) => answerSetBatch(s, parseBatchFile('batch.md', text)),
        );

        expect(readDoc(root, loginRecord), contains('draft: true\n'));
        expect(answer.json['blocks'], hasLength(2));
        expect(
          answer.json['blocks'],
          everyElement(containsPair('draft', true)),
        );
      },
    );

    test('check reports no approval_stale after a matrix write on an approved record', () async {
      final root = await writeMatrixRecordProject(isDraft: false);
      Future<List<String>> staleRecords() async {
        final session = openSession(root);
        try {
          return spots(await runCheck(session), FindingKind.approvalStale);
        } finally {
          session.close();
        }
      }

      expect(await staleRecords(), isEmpty);
      writeIn(
        root,
        (s) => answerSet(
          s,
          req(matrix, sectionBase(root, matrix)),
          '$matrixRow- email_login/check_password E02: `an empty password`\n',
        ),
      );
      expect(readDoc(root, loginRecord), contains('an empty password'));
      expect(await staleRecords(), isEmpty);
      docFile(root, loginRecord).writeAsStringSync(
        readDoc(
          root,
          loginRecord,
        ).replaceFirst('See the rows.', 'See the table.'),
      );
      expect(await staleRecords(), isNotEmpty);
    });
  });

  group('set retires the item ids it removes', () {
    const lock = 'fr:login/email_login/lock_after_failures';
    const edgeCases = '$lock#edge_cases';

    String lockDoc({String retired = ''}) =>
        '---\ndraft: true\ntraced_from: US-01\nverify_method: test\n$retired---\n\n'
        '# Lock after failures\n\n## Statement\n\nThe system shall lock the account.\n\n'
        '## Edge cases\n\n1. E01 — A wrong password → refused.\n2. E02 — Five failures → locked.\n';

    String rulesDoc({String retired = ''}) => writeProject['docs/$story1']!
        .replaceFirst('draft: true\n', 'draft: true\n$retired')
        .replaceFirst(
          '## Acceptance Criteria',
          '## Rules\n\n- BR-01 One account per email.\n'
              '- BR-02 Emails are lowercase.\n\n## Acceptance Criteria',
        );
    const rules = 'user_story:login/email_login#rules';

    test(
      'section write that drops an item adds its id to the retired list',
      () async {
        final root = await writeWriteProject(
          extra: {'docs/$story1': rulesDoc()},
        );
        writeIn(
          root,
          (s) => answerSet(
            s,
            req(rules, sectionBase(root, rules)),
            '- BR-01 One account per email.\n',
          ),
        );
        expect(readDoc(root, story1), contains('retired_ids:\n  - BR-02\n'));
        expect(readDoc(root, story1), isNot(contains('BR-01\n  -')));
      },
    );

    for (final (name, held, written) in [
      ('one entry', '  - BR-09\n', '  - BR-09\n  - BR-02\n'),
      (
        'out of order',
        '  - BR-09\n  - BR-04\n',
        '  - BR-09\n  - BR-04\n  - BR-02\n',
      ),
      ('a duplicate entry', '  - BR-09\n  - BR-09\n', '  - BR-09\n  - BR-02\n'),
    ]) {
      test(
        'retired list written by hand keeps every prior entry: $name',
        () async {
          final root = await writeWriteProject(
            extra: {'docs/$story1': rulesDoc(retired: 'retired_ids:\n$held')},
          );
          writeIn(
            root,
            (s) => answerSet(
              s,
              req(rules, sectionBase(root, rules)),
              '- BR-01 One account per email.\n',
            ),
          );
          expect(readDoc(root, story1), contains('retired_ids:\n$written'));
        },
      );
    }

    for (final (name, held) in [
      ('that does not parse', '  - [BR-09\n'),
      ('with an entry that is no string', '  - 9\n'),
    ]) {
      test('retired list $name is refused, not overwritten', () async {
        final root = await writeWriteProject(
          extra: {'docs/$story1': rulesDoc(retired: 'retired_ids:\n$held')},
        );
        final before = readDoc(root, story1);
        expect(
          () => writeIn(
            root,
            (s) => answerSet(
              s,
              req(rules, sectionBase(root, rules)),
              '- BR-01 One account per email.\n',
            ),
          ),
          throwsA(
            isA<IndexFault>()
                .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
                .having(
                  (f) => f.message,
                  'message',
                  '$story1: its retired_ids is not a YAML list of IDs; fix it '
                      'by hand before a write that retires an ID',
                ),
          ),
        );
        expect(readDoc(root, story1), before);
      });
    }

    test('section write that drops an edge case retires no id', () async {
      final root = await writeWriteProject(extra: {'docs/$fr12': lockDoc()});
      writeIn(
        root,
        (s) => answerSet(
          s,
          req(edgeCases, sectionBase(root, edgeCases)),
          '1. E01 — A wrong password → refused.\n',
        ),
      );
      expect(readDoc(root, fr12), isNot(contains('retired_ids')));
    });

    test('field write of the retired list is refused', () async {
      final root = await writeWriteProject(extra: {'docs/$fr12': lockDoc()});
      final before = readDoc(root, fr12);
      expect(
        () => writeIn(
          root,
          (s) => answerSet(
            s,
            fieldReq(lock, 'retired_ids', emptyBaseHash),
            '- E01\n',
          ),
        ),
        throwsWriteFault(WriteFaultCode.fieldNotWritable),
      );
      expect(readDoc(root, fr12), before);
    });
  });
}
