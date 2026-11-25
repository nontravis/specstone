// Test names are kept whole as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/set_doc.dart';
import 'package:specstone_core/src/document_writing/set_dry_run.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart' as check;
import '../../helpers/index_fixture.dart' show openSession;
import '../../helpers/posix_modes.dart';
import '../../helpers/write_fixture.dart';

const _fr = 'fr:login/email_login/check_password';
const _badYamlGlossary = '---\nkey: [unclosed\n---\n\n# Domain glossary\n';
const _badYamlWarning =
    'prds/GLOSSARY.md: frontmatter is not valid YAML; its values are not indexed';
const _shortEdge = '1. E01 — An empty password → refused.\n';

String _long(String start) => start.padRight(640, '.');

String _longEdge(int number) => _long('$number. E0$number — A long case →');

/// The project whose first edge case already runs past the item limit.
Future<Directory> _projectWithLongEdge({
  Map<String, String> extra = const {},
}) => check.writeCheckProject(
  extra: {...check.fr(_shortEdge, '${_longEdge(1)}\n'), ...extra},
);

Future<ReadAnswer> _dryRun(
  Directory root,
  String target,
  String text, {
  String? base,
  Directory? home,
}) async {
  final session = openSession(root);
  try {
    return await answerSetDryRun(
      session,
      DryRunRequest.parse(target, base: base, index: session.index),
      text,
      homeDirectory: home ?? testHome(),
    );
  } finally {
    session.close();
  }
}

String _baseOf(Directory root, String target) =>
    getDoc(root, target)['base']! as String;

/// Every file the docs hold, as bytes by path, the index left out.
Map<String, List<int>> _docBytes(Directory root) => {
  for (final MapEntry(:key, :value) in treeBytes(root).entries)
    if (key.startsWith('docs/') || key == '.specstone/config.yaml') key: value,
};

void main() {
  test('prints only the findings the write adds, under the naming line with the current base', () async {
    final root = await _projectWithLongEdge();
    const target = '$_fr#edge_cases';
    final base = _baseOf(root, target);

    final answer = await _dryRun(
      root,
      target,
      '${_longEdge(1)}\n${_longEdge(2)}\n',
      base: base,
    );

    final lines = answer.text.split('\n');
    expect(lines.first, startsWith('==> '));
    expect(lines.first, endsWith('#edge_cases · base $base <=='));
    expect(lines.where((line) => line.contains('item_over_limit')), [
      contains('item E02 of section edge_cases has 640 characters'),
    ]);
    expect(lines.where((line) => line.contains('E01 of')), isEmpty);
    expect(answer.text, endsWith('1 finding\n'));
    expect(answer.exitStatus, 0);
  });

  test('leaves out a finding of another kind the current text gives at the same place', () async {
    final root = await check.writeCheckProject(
      extra: {'.specstone/templates/fr.yaml': 'lint:\n  max_chars: 100\n'},
    );
    const target = '$_fr#rationale';
    final current = await check.checkOf(root, docPath: check.loginFr);
    expect(
      current.findings.map((f) => f.kind),
      contains(FindingKind.charsOverLimit),
    );

    final held = await _dryRun(root, target, 'A wrong password is refused.\n');

    expect(held.text, endsWith('0 findings\n'));
    expect(held.text, isNot(contains('chars_over_limit')));
  });

  test('writes no byte, sets no draft flag, and retires no id', () async {
    final root = await _projectWithLongEdge();
    final before = _docBytes(root);

    final answer = await _dryRun(
      root,
      '$_fr#edge_cases',
      '${_longEdge(2)}\n',
      base: _baseOf(root, '$_fr#edge_cases'),
    );

    expect(answer.text, contains('item_over_limit'));
    expect(_docBytes(root), before);
    final text = readDoc(root, check.loginFr);
    expect(text, isNot(contains('draft: true')));
    expect(text, isNot(contains('retired_ids')));
  });

  test('judges the current section when no base is given', () async {
    final root = await _projectWithLongEdge();
    const target = '$_fr#edge_cases';

    final answer = await _dryRun(root, target, '${_longEdge(2)}\n');

    expect(
      answer.text.split('\n').first,
      endsWith('#edge_cases · base ${_baseOf(root, target)} <=='),
    );
    expect(answer.text, contains('item E02 of section edge_cases'));
  });

  test(
    'refuses a stale base with the current section as the write does',
    () async {
      final root = await _projectWithLongEdge();
      const target = '$_fr#edge_cases';
      final current = _baseOf(root, target);

      await expectLater(
        _dryRun(root, target, '1. E01 — A new case.\n', base: '0123456789ab'),
        throwsA(
          isA<WriteFault>()
              .having((f) => f.code, 'code', WriteFaultCode.baseMismatch)
              .having((f) => f.current?.base, 'current base', current)
              .having(
                (f) => f.current?.text,
                'current text',
                contains(_longEdge(1)),
              ),
        ),
      );
    },
  );

  test(
    'refuses empty text on a required section and an unfenced header line',
    () async {
      final root = await check.writeCheckProject();

      await expectLater(
        _dryRun(root, '$_fr#statement', ''),
        throwsA(
          isA<WriteFault>().having(
            (f) => f.code,
            'code',
            WriteFaultCode.requiredTarget,
          ),
        ),
      );
      await expectLater(
        _dryRun(root, '$_fr#rationale', 'A reason.\n## Another\nMore.\n'),
        throwsA(
          isA<IndexFault>().having(
            (f) => f.code,
            'code',
            IndexFaultCode.argumentInvalid,
          ),
        ),
      );
    },
  );

  test('judges a lead target as the lead write', () async {
    final root = await check.writeCheckProject();
    const target = '$_fr#_lead';
    final base = _baseOf(root, target);

    final answer = await _dryRun(root, target, '${_long('A long lead')}\n');

    expect(answer.text.split('\n').first, endsWith('#_lead · base $base <=='));
    expect(answer.text, contains('item_over_limit'));
    expect(answer.text, contains('section _lead'));
  });

  test(
    'a target that is no section or lead refuses argument_conflict',
    () async {
      final root = await check.writeCheckProject();
      final session = openSession(root);
      addTearDown(session.close);

      await expectLater(
        answerSetDryRun(
          session,
          const DryRunRequest(address: _fr, target: TitleTarget()),
          'A title\n',
          homeDirectory: testHome(),
        ),
        throwsA(
          isA<IndexFault>().having(
            (f) => f.code,
            'code',
            IndexFaultCode.argumentConflict,
          ),
        ),
      );
    },
  );

  group('a pending journal', () {
    const move = MoveStep(
      'docs/prds/features/f01_login',
      'docs/prds/features/f01_signin',
    );
    const commit = CommitStep(
      message: 'move',
      paths: ['docs/prds/features'],
      base: '0000000',
    );

    test('leaves a pending move journal as it is', () async {
      final root = await check.writeCheckProject();
      writeJournal(root, [move]);
      final journal = File('${root.path}/${MoveJournal.journalPath}');
      final journalText = journal.readAsStringSync();
      final before = _docBytes(root);

      final answer = await _dryRun(root, '$_fr#rationale', 'A reason.\n');

      expect(answer.text, contains('==> '));
      expect(journal.readAsStringSync(), journalText);
      expect(_docBytes(root), before);
      expect(
        Directory('${root.path}/docs/prds/features/f01_signin').existsSync(),
        isFalse,
      );
    });

    test('refuses a pending migrate as the write does', () async {
      final root = await check.writeCheckProject();
      writeJournal(root, [move, commit]);
      final journal = File('${root.path}/${MoveJournal.journalPath}');
      final journalText = journal.readAsStringSync();

      await expectLater(
        _dryRun(root, '$_fr#rationale', 'A reason.\n'),
        throwsA(
          isA<WriteFault>().having(
            (f) => f.code,
            'code',
            WriteFaultCode.migratePending,
          ),
        ),
      );
      expect(journal.readAsStringSync(), journalText);
    });

    test('refuses a move journal no run on this machine wrote', () async {
      final root = await check.writeCheckProject();
      writeJournal(root, [move], recorded: false);
      final journal = File('${root.path}/${MoveJournal.journalPath}');
      final journalText = journal.readAsStringSync();

      await expectLater(
        _dryRun(root, '$_fr#rationale', 'A reason.\n'),
        throwsA(
          isA<RenderFault>()
              .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
              .having((f) => f.file, 'file', MoveJournal.journalPath),
        ),
      );
      expect(journal.readAsStringSync(), journalText);
    });
  });

  test('a read-only doc is output_not_writable as the write refuses it and keeps its bytes', () async {
    final root = await check.writeCheckProject();
    final file = docFile(root, check.loginFr);
    Process.runSync('chmod', ['444', file.path]);
    addTearDown(() => Process.runSync('chmod', ['644', file.path]));
    final before = _docBytes(root);

    await expectLater(
      _dryRun(root, '$_fr#rationale', 'A reason.\n'),
      throwsA(
        isA<RenderFault>()
            .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
            .having(
              (f) => f.message,
              'message',
              'cannot write ${check.loginFr}: read-only',
            ),
      ),
    );
    expect(_docBytes(root), before);
  }, skip: unreadablePathSkipReason() ?? false);

  test('a dry run on a doc the format command refuses judges the spliced text and writes no byte', () async {
    final root = await check.writeCheckProject(
      extra: check.fr(
        '## Rationale\n',
        '## Rationale\n\nTwice.\n\n## Rationale\n',
      ),
    );
    final before = _docBytes(root);
    const target = '$_fr#statement';

    final answer = await _dryRun(
      root,
      target,
      '${_long('A long statement')}\n',
    );

    expect(answer.text, contains('item_over_limit'));
    expect(answer.text, contains('section statement'));
    expect(_docBytes(root), before);
  });

  test(
    'lists findings in its json as check --json does, with warnings',
    () async {
      final root = await _projectWithLongEdge(
        extra: {'docs/prds/GLOSSARY.md': _badYamlGlossary},
      );
      const target = '$_fr#edge_cases';

      final answer = await _dryRun(
        root,
        target,
        '${_longEdge(1)}\n${_longEdge(2)}\n',
      );

      final findings = answer.json['findings']! as List;
      expect(findings, hasLength(1));
      expect(
        findings.single,
        allOf(
          containsPair('kind', 'item_over_limit'),
          containsPair('section', 'edge_cases'),
          containsPair('id', 'E02'),
          containsPair('limit', 600),
          containsPair('actual', 640),
        ),
      );
      expect(answer.warnings, [_badYamlWarning]);
      expect(jsonEncode(answer.json), isNot(contains('E01')));
    },
  );
}
