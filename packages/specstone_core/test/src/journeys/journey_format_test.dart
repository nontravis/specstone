import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/fingerprint.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/journeys/journey_generators.dart';
import 'package:specstone_core/src/journeys/journey_steps.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/format_run.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:specstone_core/src/rendering/html_build.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';

const _story = 'login/email_login';
const _journeyKey = 'docs/prds/journeys/sign_in/JOURNEY.md';

String _step(String number, String heading, String scenario, {String? after}) =>
    '### $number. $heading\nstep: $_story $scenario\n'
    '${after == null ? '' : 'after: $after\n'}';

String _journey(List<String> steps, {String frontMatter = ''}) =>
    '$frontMatter# Sign in\n\n## Goal\nReach the home page.\n\n## Flow\n\n'
    '## Steps\n${steps.join('\n')}';

final String _branched = _journey([
  _step('1', 'Open', 'S1'),
  _step('2', 'Type', 'S1'),
  _step('3', 'Submit', 'S1'),
  _step('4', 'Home', 'S1'),
  _step('5', 'Done', 'S1'),
  _step('3x', 'Wrong password', 'S2', after: '2'),
]);

Future<Directory> _project(String journey, {Map<String, String>? extra}) =>
    writeCheckProject(extra: {_journeyKey: journey, ...?extra});

DocsProject _open(Directory root) => DocsProject.open(
  templates: TemplateResolver(),
  workingDirectory: root,
  homeDirectory: null,
);

FormatReport _format(Directory root, {bool check = false}) {
  final project = _open(root);
  return runFormat<DocIndex>(
    project,
    project.resolveTarget(
      null,
      workingDirectory: root,
      defaultsToDocsRoot: true,
    ),
    check: check,
    generators: GeneratorRun<DocIndex>(
      registry: journeyGenerators(),
      open: () {
        final session = openSession(root);
        return (resolver: session.index, close: session.close);
      },
    ),
  );
}

String _read(Directory root) =>
    File.fromUri(root.uri.resolve(_journeyKey)).readAsStringSync();

int _count(String text, String needle) => needle.allMatches(text).length;

void main() {
  test('f10/us01/s2: format draws two paths for a branched journey', () async {
    final root = await _project(_branched);

    _format(root);

    final text = _read(root);
    expect(text, contains('  s2 --> s3x'));
    expect(text, contains('  s4 --> s5'));
  });

  test('f10/us01/s3, f10/us01/fr04/e04, f05/us03/s2, f05/us03/fr01/e01: a '
      'step added by hand gets its scenario text and its node', () async {
    final root = await _project(
      _journey([_step('1', 'Open', 'S1'), _step('2', 'Wrong', 'S2')]),
    );

    _format(root);

    final text = _read(root);
    expect(_count(text, generatedOpenMarker(journeyFlowKind)), 1);
    expect(_count(text, generatedOpenMarker(scenarioCopyKind)), 2);
    expect(text, contains('  s1["1. Open"]'));
    expect(text, contains('  s2["2. Wrong"]'));
    expect(text, contains('- **When** the Agent signs in'));
    expect(text, contains('- **When** the Agent types a'));
  });

  test('f10/us01/fr04/e02, f05/us03/s1, f05/us03/s5: a story edit re-pastes '
      'the copy on the next format, confirmed and draft unchanged', () async {
    final root = await _project(
      _journey(
        [_step('1', 'Open', 'S1')],
        frontMatter:
            '---\nconfirmed:\n'
            '  - $_story#S1 ${fingerprintFor(loginScenario1)}\n'
            'draft: false\n---\n\n',
      ),
    );
    _format(root);
    final before = _read(root);
    final storyFile = File.fromUri(root.uri.resolve('docs/$loginStory'));
    storyFile.writeAsStringSync(
      storyFile.readAsStringSync().replaceFirst(
        '- **Then** the Agent sees the home page',
        '- **Then** the Agent sees the dashboard',
      ),
    );

    _format(root);

    final after = _read(root);
    expect(before, contains('sees the home page'));
    expect(after, contains('sees the dashboard'));
    expect(after, isNot(contains('sees the home page')));
    expect(after.replaceAll('dashboard', 'home page'), before);
    expect(after, contains('draft: false'));
  });

  test('f10/us01/s2: a second format of a branched journey changes '
      'nothing', () async {
    final root = await _project(_branched);
    _format(root);
    final first = _read(root);

    final report = _format(root);

    expect(_read(root), first);
    expect(report.exitStatus, 0);
    expect(_format(root, check: true).exitStatus, 0);
  });

  test('f10/us01/fr03/e06: an html build of a journey holds its flowchart '
      'and no network source', () async {
    final root = await _project(
      _journey([_step('1', 'Open', 'S1'), _step('2', 'Type', 'S1')]),
    );
    _format(root);
    final project = _open(root);

    final build = buildHtml(
      project,
      project.resolveTarget(
        null,
        workingDirectory: root,
        defaultsToDocsRoot: true,
      ),
    );

    expect(build.html, contains('<pre class="mermaid">'));
    expect(build.html, contains('flowchart TD'));
    expect(build.html, contains('s1 --&gt; s2'));
    expect(build.html, isNot(contains('src="http')));
  });

  group('tracked step links after a format', () {
    const label1 = '$_story#S1';
    const label2 = '$_story#S2';
    const journeyDocPath = 'prds/journeys/sign_in/JOURNEY.md';
    final scenario1 = fingerprintOf(loginScenario1);
    final scenario2 = fingerprintOf(loginScenario2);

    String front(List<String> entries, {bool draft = false}) =>
        '---\nconfirmed:\n${entries.map((e) => '  - $e\n').join()}'
        '${draft ? 'draft: true\n' : ''}---\n\n';

    List<Finding> check(Directory root) =>
        checkOf(root, docPath: journeyDocPath).findings;

    void rewrite(Directory root, String Function(String) change) {
      final file = File.fromUri(root.uri.resolve(_journeyKey));
      file.writeAsStringSync(change(file.readAsStringSync()));
    }

    String withFront(String text, String frontMatter) =>
        '$frontMatter${text.substring(text.indexOf('# Sign in'))}';

    test('f04/us04/s9, f04/us04/fr01/e10: format re-pastes an edited '
        'scenario and the journey stays suspect', () async {
      final root = await _project(
        _journey([
          _step('1', 'Open', 'S1'),
        ], frontMatter: front(['$label1 $scenario1'])),
      );
      final storyFile = File.fromUri(root.uri.resolve('docs/$loginStory'));
      final edited = loginScenario1.replaceFirst('home page', 'dashboard');
      storyFile.writeAsStringSync(
        storyFile.readAsStringSync().replaceFirst(loginScenario1, edited),
      );

      _format(root);

      expect(_read(root), contains('sees the dashboard'));
      final suspect = check(root).single;
      expect(suspect.kind, FindingKind.suspect);
      expect(suspect.toJson(), containsPair('link', label1));

      final recorded = fingerprintOf(edited);
      rewrite(
        root,
        (text) => withFront(text, front(['$label1 $recorded'], draft: true)),
      );
      final waiting = check(root).single;
      expect(waiting.kind, FindingKind.unconfirmed);
      expect(waiting.message, contains("waits for the Owner's approve"));

      rewrite(root, (text) => withFront(text, front(['$label1 $recorded'])));
      expect(check(root), isEmpty);
    });

    test('f10/us01/s3: a step added by hand stays unconfirmed until the '
        'Agent confirms it and the Owner approves', () async {
      final root = await _project(
        _journey([
          _step('1', 'Open', 'S1'),
        ], frontMatter: front(['$label1 $scenario1'])),
      );
      _format(root);
      expect(check(root), isEmpty);
      rewrite(
        root,
        (text) => '${text.trimRight()}\n\n${_step('2', 'Wrong', 'S2')}',
      );

      _format(root);

      final added = check(root).single;
      expect(added.kind, FindingKind.unconfirmed);
      expect(added.toJson(), containsPair('link', label2));

      final both = ['$label1 $scenario1', '$label2 $scenario2'];
      rewrite(root, (text) => withFront(text, front(both, draft: true)));
      expect(
        check(root).map((f) => f.kind),
        everyElement(FindingKind.unconfirmed),
      );
      expect(check(root), isNotEmpty);

      rewrite(root, (text) => withFront(text, front(both)));
      expect(check(root), isEmpty);
    });
  });
}
