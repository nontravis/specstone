import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/fingerprint.dart';
import 'package:specstone_core/src/document_writing/new_doc.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/journeys/first_confirmations.dart';
import 'package:specstone_core/src/journeys/journey_generators.dart';
import 'package:specstone_core/src/journeys/journey_steps.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/format_run.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';
import '../../helpers/write_fixture.dart' show readDoc, writeIn;

const _story = 'login/email_login';
const _journeyDoc = 'prds/journeys/sign_in/JOURNEY.md';

String _scenario(int n) =>
    '### Scenario $n — [happy] Step $n\n- **Given** a\n- **When** b\n'
    '- **Then** c';

// The login story with scenarios 1 to 5; 1 and 2 are the fixture's own.
Map<String, String> _fiveScenarios() => {
  'docs/$loginStory':
      '${checkProjectFiles()['docs/$loginStory']}\n'
      '${[for (var n = 3; n <= 5; n++) _scenario(n)].join('\n\n')}\n',
};

String _blockOf(int n) => switch (n) {
  1 => loginScenario1,
  2 => loginScenario2,
  _ => _scenario(n),
};

String _label(int n) => '$_story#S$n';

String _entry(int n) => '  - ${_label(n)} ${fingerprintOf(_blockOf(n))}\n';

String _step(int number, int scenario) =>
    '### $number. Step $number\nstep: $_story S$scenario\n';

String _body(List<String> steps) =>
    '# Sign in\n\n## Goal\nReach the home page.\n\n## Flow\n\n'
    '## Steps\n${steps.join('\n')}';

Future<Directory> _project() => writeCheckProject(extra: _fiveScenarios());

String _new(Directory root, {String text = ''}) {
  writeIn(
    root,
    (session) => answerNew(
      session,
      docTypeId: 'journey',
      slug: 'sign_in',
      text: text,
      generators: journeyGenerators(),
      firstConfirmations: withFirstConfirmations,
    ),
  );
  return readDoc(root, _journeyDoc);
}

List<Finding> _check(Directory root) =>
    checkOf(root, docPath: _journeyDoc).findings;

FormatReport _format(Directory root) {
  final project = DocsProject.open(
    templates: TemplateResolver(),
    workingDirectory: root,
    homeDirectory: null,
  );
  return runFormat<DocIndex>(
    project,
    project.resolveTarget(
      null,
      workingDirectory: root,
      defaultsToDocsRoot: true,
    ),
    check: false,
    generators: GeneratorRun<DocIndex>(
      registry: journeyGenerators(),
      open: () {
        final session = openSession(root);
        return (resolver: session.index, close: session.close);
      },
    ),
  );
}

int _count(String text, String needle) => needle.allMatches(text).length;

File _file(Directory root) =>
    File.fromUri(root.uri.resolve('docs/$_journeyDoc'));

void main() {
  test(
    'f10/us01/s1, f10/us01/fr05/e01: five resolving steps give five entries, '
    'the flow block, and five copies',
    () async {
      final root = await _project();

      final text = _new(
        root,
        text: _body([for (var n = 1; n <= 5; n++) _step(n, n)]),
      );

      expect(text, startsWith('---\ndraft: true\nconfirmed:\n'));
      for (var n = 1; n <= 5; n++) {
        expect(text, contains(_entry(n)));
      }
      expect(_count(text, generatedOpenMarker(journeyFlowKind)), 1);
      expect(_count(text, generatedOpenMarker(scenarioCopyKind)), 5);
      final waiting = _check(root);
      expect(waiting, hasLength(5));
      expect(waiting.map((f) => f.kind), everyElement(FindingKind.unconfirmed));

      _file(root).writeAsStringSync(text.replaceFirst('draft: true\n', ''));
      expect(_check(root), isEmpty);
    },
  );

  test('f10/us01/s6, f10/us01/fr05/e02: a step naming a missing scenario gets '
      'no entry and no block', () async {
    final root = await _project();

    final text = _new(
      root,
      text: _body([_step(1, 1), _step(2, 9), _step(3, 2)]),
    );

    expect(text, contains(_entry(1)));
    expect(text, contains(_entry(2)));
    expect(text, isNot(contains('#S9')));
    expect(_count(text, generatedOpenMarker(scenarioCopyKind)), 2);
    expect(
      _check(root).map((f) => f.kind),
      contains(FindingKind.journeyStepUnresolved),
    );
  });

  test(
    'f10/us01/fr05/e03: no stdin writes the starter text, an empty flowchart, '
    'and no confirmed key',
    () async {
      final root = await _project();

      final text = _new(root);

      expect(text, startsWith('---\ndraft: true\n---\n'));
      expect(text, isNot(contains('confirmed')));
      expect(
        text,
        contains(
          '${generatedOpenMarker(journeyFlowKind)}\n'
          '```mermaid\nflowchart TD\n```\n$generatedEndMarker\n',
        ),
      );
      expect(_count(text, generatedOpenMarker(scenarioCopyKind)), 0);
    },
  );

  test(
    'f10/us01/fr05: format right after new journey changes nothing',
    () async {
      final root = await _project();
      final text = _new(root);

      final report = _format(root);

      expect(
        report.files.where((f) => f.path.endsWith('JOURNEY.md')).single.status,
        FileStatus.unchanged,
      );
      expect(_file(root).readAsStringSync(), text);
    },
  );

  test('f10/us01/fr05/e04: an entry stdin holds for a step is kept as written '
      'and not added twice', () async {
    final root = await _project();
    const held = '  - $_story#S1 aaaaaaaaaaaa\n';

    final text = _new(
      root,
      text: '---\nconfirmed:\n$held---\n\n${_body([_step(1, 1), _step(2, 2)])}',
    );

    expect(text, contains(held));
    expect(_count(text, '$_story#S1 '), 1);
    expect(text, contains(_entry(2)));
  });

  test('f10/us01/fr05: draft is inserted above persona, confirmed below it, and '
      'stdin is otherwise kept', () async {
    final root = await _project();
    final stdin =
        '---\npersona:\n  - owner\n---\n\n${_body([_step(1, 1), _step(2, 2)])}';

    final text = _new(root, text: stdin);

    expect(
      text,
      startsWith(
        '---\ndraft: true\npersona:\n  - owner\nconfirmed:\n'
        '${_entry(1)}${_entry(2)}---\n',
      ),
    );
    final restored = text
        .replaceFirst('draft: true\n', '')
        .replaceFirst('confirmed:\n${_entry(1)}${_entry(2)}', '')
        .replaceAll(
          RegExp(
            '${RegExp.escape('<!-- specstone:generated ')}[a-z_]+'
            '${RegExp.escape(' (do not edit) -->')}\n[\\s\\S]*?'
            '${RegExp.escape(generatedEndMarker)}\n',
          ),
          '',
        );
    expect(restored, stdin);
    final report = _format(root);
    expect(
      report.files.where((f) => f.path.endsWith('JOURNEY.md')).single.status,
      FileStatus.unchanged,
    );
    expect(_file(root).readAsStringSync(), text);
  });

  test('f10/us01/fr05: an existing confirmed list gains its new entries at its '
      'end', () async {
    final root = await _project();
    const other = '  - other/story#S1 bbbbbbbbbbbb\n';

    final text = _new(
      root,
      text:
          '---\nconfirmed:\n$other---\n\n${_body([_step(1, 1), _step(2, 2)])}',
    );

    expect(
      text,
      startsWith(
        '---\ndraft: true\nconfirmed:\n$other${_entry(1)}${_entry(2)}---\n',
      ),
    );
  });

  test(
    'f10/us01/fr05: two steps naming one scenario get one confirmed entry',
    () async {
      final root = await _project();

      final text = _new(root, text: _body([_step(1, 1), _step(2, 1)]));

      expect(_count(text, '$_story#S1 '), 1);
      expect(_count(text, generatedOpenMarker(scenarioCopyKind)), 2);
    },
  );

  test('f10/us01/fr05: stdin holding an open block still gets draft and the '
      'first confirmed entries, and no block', () async {
    final root = await _project();
    final open = '${generatedOpenMarker(journeyFlowKind)}\n';
    final stdin = _body([_step(1, 1)])
        .replaceFirst('## Flow\n', '## Flow\n$open');

    final text = _new(root, text: stdin);

    expect(text, contains('draft: true\n'));
    expect(text, contains(_entry(1)));
    expect(text, isNot(contains(generatedEndMarker)));
    expect(_count(text, generatedOpenMarker(scenarioCopyKind)), 0);
  });

  test(
    'f10/us01/fr05: a malformed confirmed list in stdin is written as given',
    () async {
      final root = await _project();
      const held = 'confirmed:\n  - "login/email_login#S1\n';
      final stdin = '---\n$held---\n\n${_body([_step(1, 1)])}';

      final text = _new(root, text: stdin);

      expect(text, startsWith('---\ndraft: true\n$held---\n'));
      expect(_count(text, '$_story#S1 '), 0);
    },
  );

  test(
    'f05/us03/fr01: a doc type with no generators is written as before',
    () async {
      final plain = await _project();
      final hooked = await _project();

      writeIn(
        plain,
        (s) =>
            answerNew(s, docTypeId: 'user_story', parent: 'login', slug: 'a'),
      );
      writeIn(
        hooked,
        (s) => answerNew(
          s,
          docTypeId: 'user_story',
          parent: 'login',
          slug: 'a',
          generators: journeyGenerators(),
          firstConfirmations: withFirstConfirmations,
        ),
      );

      const path = 'prds/features/f01_login/us02_a/USER_STORY.md';
      expect(readDoc(hooked, path), readDoc(plain, path));
    },
  );
}
