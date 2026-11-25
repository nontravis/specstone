// The expected texts are doc literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/remove_task_refs.dart';
import 'package:specstone_core/src/document_writing/root_trust.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart' show checkOf, spots;
import '../../helpers/relative_link.dart';
import '../../helpers/target_fixture.dart';
import '../../helpers/temp_tree.dart';
import '../../helpers/write_fixture.dart';

const _loginApiDoc = 'specs/f01_login/API.md';

/// The arch and API docs of the shipped `software-tech` pack both carry the
/// `tasks` field.
const _apiText = '---\ndraft: true\ntasks:\n  - ENG-42\n---\n\n# Login API\n';

/// The docs of [root] as bytes, for the check that a run wrote nothing.
Map<String, List<int>> _docBytes(Directory root) =>
    treeBytes(Directory('${root.path}/docs'));

/// Returns [text] with its `tasks` key block set to [entries].
String _withTasks(String text, List<String> entries, {String key = 'tasks'}) =>
    withKeyBlock(
      text,
      key,
      '$key:\n${entries.map((entry) => '  - $entry\n').join()}',
    );

/// A project whose login architecture holds three entries and whose login API
/// holds one, beside the draft signup architecture.
Future<Directory> _project({
  List<String> arch = const ['INV-4:ENG-42', 'ENG-42', 'INV-7:ENG-50'],
  Map<String, String> extra = const {},
}) => writeWriteProject(
  extra: {
    'docs/$loginArch': _withTasks(writeProject['docs/$loginArch']!, arch),
    'docs/$_loginApiDoc': _apiText,
    ...extra,
  },
);

String _baseOf(Directory root, String docPath) =>
    getDoc(root, docPath)['base']! as String;

ReadAnswer _remove(Directory root, List<String> tasks, {String? codeTarget}) =>
    writeIn(root, (s) => answerRemoveTasks(s, tasks, codeTarget: codeTarget));

/// The naming line of [docPath] as the run prints it, `<base>` the doc's base
/// on disk now.
String _line(Directory root, String docPath, String removed) {
  final doc = getDoc(root, docPath);
  return '==> ${doc['name']} (${doc['docType']}) · $docPath · base ${_baseOf(root, docPath)} · removed $removed <==\n';
}

void main() {
  group('requireTaskIds', () {
    test('an empty value or one with a colon is argument_invalid, naming the value', () {
      for (final value in ['', 'INV-4:ENG-42', ':']) {
        expect(
          () => requireTaskIds(['ENG-42', value]),
          throwsA(
            isA<IndexFault>()
                .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
                .having(
                  (f) => f.message,
                  'message',
                  '--remove-task takes a task id that is not empty and holds no ":"; got "$value"',
                ),
          ),
          reason: value,
        );
      }
      requireTaskIds(['ENG-42', 'a/b', 'T 1']);
    });
  });

  group('answerRemoveTasks', () {
    test('every entry of the task goes from every doc, an emptied list loses its key block, 2 lines print', () async {
      final root = await _project();
      final apiBefore = readDoc(root, _loginApiDoc);
      final signupBefore = readDoc(root, signupArch);

      final answer = _remove(root, ['ENG-42']);

      expect(
        readDoc(root, loginArch),
        contains('tasks:\n  - INV-7:ENG-50\n---'),
      );
      expect(readDoc(root, loginArch), isNot(contains('ENG-42')));
      expect(readDoc(root, _loginApiDoc), isNot(contains('tasks')));
      expect(apiBefore, contains('tasks'));
      expect(readDoc(root, signupArch), signupBefore);
      expect(
        answer.text,
        _line(root, _loginApiDoc, 'ENG-42') +
            _line(root, loginArch, 'INV-4:ENG-42, ENG-42'),
      );
      expect(MoveJournal.pending(root), isFalse);
    });

    test('the json holds docs in doc path order, noRefs, and each doc new base equal to the base get prints', () async {
      final root = await _project();

      final answer = _remove(root, ['ENG-42', 'ENG-43']);

      expect(answer.json.keys, ['docs', 'noRefs']);
      expect(answer.json['noRefs'], ['ENG-43']);
      expect(answer.json['docs'], [
        {
          'path': _loginApiDoc,
          'name': 'login',
          'docType': 'api',
          'removed': ['ENG-42'],
          'base': _baseOf(root, _loginApiDoc),
        },
        {
          'path': loginArch,
          'name': 'login',
          'docType': 'architecture',
          'removed': ['INV-4:ENG-42', 'ENG-42'],
          'base': _baseOf(root, loginArch),
        },
      ]);
    });

    test('a task no doc holds prints its no refs line after the doc lines, and the held task is removed', () async {
      final root = await _project();

      final answer = _remove(root, ['ENG-42', 'ENG-43']);

      expect(answer.text, endsWith('ENG-43 · no refs\n'));
      expect(answer.text, startsWith('==> '));
      expect(readDoc(root, loginArch), isNot(contains('ENG-42')));
    });

    test('a task no doc holds writes no doc and no journal, and a rerun changes nothing', () async {
      final root = await _project();
      _remove(root, ['ENG-42']);
      final after = _docBytes(root);

      final again = _remove(root, ['ENG-42']);

      expect(again.text, 'ENG-42 · no refs\n');
      expect(again.json['docs'], isEmpty);
      expect(again.json['noRefs'], ['ENG-42']);
      expect(_docBytes(root), after);
      expect(Directory('${root.path}/.specstone/trash').existsSync(), isFalse);
    });

    test(
      'an entry that holds the task only as a prefix or in another case stays',
      () async {
        final root = await _project(
          arch: ['ENG-421', 'INV-4:eng-42', 'INV-4:ENG-42', 'ENG-42'],
        );

        final answer = _remove(root, ['ENG-42']);

        expect(
          readDoc(root, loginArch),
          contains('tasks:\n  - ENG-421\n  - INV-4:eng-42\n---'),
        );
        expect(
          answer.json['docs'],
          contains(containsPair('removed', ['INV-4:ENG-42', 'ENG-42'])),
        );
      },
    );

    test(
      'one entry held twice in a doc goes twice and is listed twice',
      () async {
        final root = await _project(arch: ['ENG-42', 'INV-7:ENG-50', 'ENG-42']);

        final answer = _remove(root, ['ENG-42']);

        expect(readDoc(root, loginArch), isNot(contains('ENG-42')));
        expect(answer.text, contains(' · removed ENG-42, ENG-42 <==\n'));
      },
    );

    test('a task named twice is matched once and printed once', () async {
      final root = await _project();

      final held = _remove(root, ['ENG-42', 'ENG-42']);
      final missing = _remove(root, ['ENG-9', 'ENG-9']);

      expect(held.json['noRefs'], isEmpty);
      expect(held.json['docs'], hasLength(2));
      expect(missing.text, 'ENG-9 · no refs\n');
      expect(missing.json['noRefs'], ['ENG-9']);
    });

    test('a CRLF doc with a BOM is written back CRLF with its BOM', () async {
      final lf = _withTasks(writeProject['docs/$loginArch']!, [
        'ENG-42',
        'ENG-50',
      ]);
      final root = await writeWriteProject(
        extra: {'docs/$loginArch': '\uFEFF${lf.replaceAll('\n', '\r\n')}'},
      );

      _remove(root, ['ENG-42']);

      final written = docFile(root, loginArch).readAsBytesSync();
      expect(written.take(3), [0xEF, 0xBB, 0xBF]);
      final text = String.fromCharCodes(written.skip(3));
      expect(text, contains('tasks:\r\n  - ENG-50\r\n---'));
      expect(text, isNot(matches(RegExp(r'(?<!\r)\n'))));
    });

    test(
      '--target keeps the removal to that target docs and the shared docs',
      () async {
        Future<Directory> twins() async {
          final root = await writeTwinProject();
          for (final (docPath, other) in [
            (_loginApiDoc, 'ENG-50'),
            (flutterArchitecture, 'ENG-50'),
            (jasprArchitecture, 'ENG-51'),
          ]) {
            docFile(root, docPath).writeAsStringSync(
              _withTasks(readDoc(root, docPath), ['ENG-42', other]),
            );
          }
          return root;
        }

        final root = await twins();
        final answer = _remove(root, ['ENG-42'], codeTarget: 'jaspr');
        expect(readDoc(root, jasprArchitecture), isNot(contains('ENG-42')));
        expect(readDoc(root, flutterArchitecture), contains('ENG-42'));
        expect(readDoc(root, _loginApiDoc), isNot(contains('ENG-42')));
        expect(readDoc(root, _loginApiDoc), contains('ENG-50'));
        expect(answer.json['docs'], [
          containsPair('path', _loginApiDoc),
          containsPair('path', jasprArchitecture),
        ]);

        final all = _remove(await twins(), ['ENG-42']);
        expect(all.json['docs'], hasLength(3));
      },
    );

    test(
      'an approved doc gains no draft flag and keeps its approval stamp',
      () async {
        final root = await _project();
        final before = readDoc(root, loginArch);
        expect(before, contains('approved:'));
        expect(before, isNot(contains('draft:')));

        _remove(root, ['ENG-42']);

        final after = readDoc(root, loginArch);
        expect(after, isNot(contains('draft:')));
        expect(
          RegExp('approved: .*').firstMatch(after)!.group(0),
          RegExp('approved: .*').firstMatch(before)!.group(0),
        );
      },
    );

    test('an approved doc stays approved and a draft stays a draft', () async {
      final root = await _project(
        extra: {
          'docs/$signupArch': _withTasks(writeProject['docs/$signupArch']!, [
            'ENG-42',
            'ENG-50',
          ]),
        },
      );
      final approved = RegExp('approved: .*')
          .firstMatch(readDoc(root, loginArch))!
          .group(0)!;

      _remove(root, ['ENG-42']);

      expect(readDoc(root, loginArch), contains(approved));
      expect(readDoc(root, signupArch), contains('draft: true'));
      expect(readDoc(root, signupArch), isNot(contains('ENG-42')));
      expect(spots(await checkOf(root), FindingKind.approvalStale), isEmpty);
    });

    test('a task_ref field under another id is found by its type', () async {
      final root = await writeWriteProject(
        extra: {
          '.specstone/templates/feature.yaml':
              'fields:\n  - id: work\n    type: task_ref\n    list: true\n',
          'docs/$signupFeature': _withTasks(
            writeProject['docs/$signupFeature']!,
            ['ENG-42', 'ENG-50'],
            key: 'work',
          ),
        },
      );

      final answer = _remove(root, ['ENG-42']);

      expect(readDoc(root, signupFeature), contains('work:\n  - ENG-50\n'));
      expect(answer.json['docs'], [
        containsPair('removed', ['ENG-42']),
      ]);
    });

    test('a scalar task_ref field is dropped when it holds the task', () async {
      final root = await writeWriteProject(
        extra: {
          '.specstone/templates/feature.yaml':
              'fields:\n  - id: work\n    type: task_ref\n',
          'docs/$signupFeature': withKeyBlock(
            writeProject['docs/$signupFeature']!,
            'work',
            'work: INV-4:ENG-42\n',
          ),
        },
      );

      final answer = _remove(root, ['ENG-42', 'ENG-43']);

      expect(readDoc(root, signupFeature), isNot(contains('work')));
      expect(answer.json['docs'], [
        containsPair('removed', ['INV-4:ENG-42']),
      ]);
      expect(answer.json['noRefs'], ['ENG-43']);
    });

    test('a scalar task_ref field that holds another task stays', () async {
      final root = await writeWriteProject(
        extra: {
          '.specstone/templates/feature.yaml':
              'fields:\n  - id: work\n    type: task_ref\n',
          'docs/$signupFeature': withKeyBlock(
            writeProject['docs/$signupFeature']!,
            'work',
            'work: ENG-50\n',
          ),
        },
      );
      final before = _docBytes(root);

      final answer = _remove(root, ['ENG-42']);

      expect(answer.text, 'ENG-42 · no refs\n');
      expect(_docBytes(root), before);
    });

    test('a required scalar task_ref field that holds the task refuses', () async {
      final root = await writeWriteProject(
        extra: {
          '.specstone/templates/feature.yaml':
              'fields:\n  - id: work\n    type: task_ref\n    required: true\n',
          'docs/$signupFeature': withKeyBlock(
            writeProject['docs/$signupFeature']!,
            'work',
            'work: ENG-42\n',
          ),
        },
      );
      final before = _docBytes(root);

      expect(
        () => _remove(root, ['ENG-42']),
        throwsA(
          isA<WriteFault>().having(
            (f) => f.code,
            'code',
            WriteFaultCode.requiredTarget,
          ),
        ),
      );

      expect(_docBytes(root), before);
    });

    test('a plain block list keeps its comments, quotes, and other entries byte for byte', () async {
      const block =
          'tasks:\n'
          '  # first the open work\n'
          '  - "INV-7:ENG-50"\n'
          '  - ENG-42 # to drop\n'
          '\n'
          '  # then the rest\n'
          '  - INV-4:ENG-51   # keep\n';
      final root = await writeWriteProject(
        extra: {
          'docs/$loginArch': withKeyBlock(
            writeProject['docs/$loginArch']!,
            'tasks',
            block,
          ),
        },
      );

      _remove(root, ['ENG-42']);

      expect(
        readDoc(root, loginArch),
        contains(
          'tasks:\n'
          '  # first the open work\n'
          '  - "INV-7:ENG-50"\n'
          '\n'
          '  # then the rest\n'
          '  - INV-4:ENG-51   # keep\n'
          '---',
        ),
      );
    });

    test(
      'a flow list is written anew as a block list without the task',
      () async {
        final root = await writeWriteProject(
          extra: {
            'docs/$loginArch': withKeyBlock(
              writeProject['docs/$loginArch']!,
              'tasks',
              'tasks: [ENG-42, ENG-50]\n',
            ),
          },
        );

        _remove(root, ['ENG-42']);

        expect(readDoc(root, loginArch), contains('tasks:\n  - ENG-50\n---'));
      },
    );

    test('a changed doc that fails a write check refuses the whole run, and no doc is written', () async {
      final root = await _project(
        extra: {
          '.specstone/templates/feature.yaml': 'fields:\n  - id: work\n    type: task_ref\n    list: true\n    required: true\n',
          'docs/$signupFeature': _withTasks(
            writeProject['docs/$signupFeature']!,
            ['ENG-42'],
            key: 'work',
          ),
        },
      );
      final before = _docBytes(root);

      expect(
        () => _remove(root, ['ENG-42']),
        throwsA(
          isA<WriteFault>().having(
            (f) => f.code,
            'code',
            WriteFaultCode.requiredTarget,
          ),
        ),
      );

      expect(_docBytes(root), before);
    });

    test(
      'a project whose roots wait for the trust record refuses with the trust text and writes nothing',
      () async {
        final base = await writeTree({
          for (final MapEntry(:key, :value) in writeProject.entries)
            if (key == 'docs/$loginArch')
              'ext/${key.substring(5)}': _withTasks(value, ['ENG-42'])
            else if (key.startsWith('docs/'))
              'ext/${key.substring(5)}': value
            else
              'src/clone/$key': value,
        });
        createRelativeLink('${base.path}/src/clone/docs', '../../ext');
        final clone = Directory('${base.path}/src/clone');
        final before = treeBytes(Directory('${base.path}/ext'));

        expect(
          () => _remove(clone, ['ENG-42']),
          throwsA(
            predicate(
              (f) => '$f'.contains(
                'run specstone trust at a terminal to allow it',
              ),
            ),
          ),
        );

        expect(treeBytes(Directory('${base.path}/ext')), before);
        RootTrust.locate(clone, homeDirectory: testHome()).record();
        _remove(clone, ['ENG-42']);
        expect(
          File('${base.path}/ext/$loginArch').readAsStringSync(),
          isNot(contains('ENG-42')),
        );
      },
      skip: Platform.isWindows ? 'a link needs a privilege on Windows' : false,
    );

    test('a code target the project lacks is argument_invalid', () async {
      final root = await _project();

      expect(
        () => _remove(root, ['ENG-42'], codeTarget: 'nowhere'),
        throwsA(
          isA<IndexFault>().having(
            (f) => f.code,
            'code',
            IndexFaultCode.argumentInvalid,
          ),
        ),
      );
    });
  });
}
