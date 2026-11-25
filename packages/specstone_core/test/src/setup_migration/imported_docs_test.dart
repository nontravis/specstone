import 'dart:io';

import 'package:specstone_core/src/setup_migration/agent_files.dart';
import 'package:specstone_core/src/setup_migration/imported_docs.dart';
import 'package:specstone_core/src/version.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';
import '../../helpers/shipped_pins.dart';

const _claudeCode = {'CLAUDECODE': '1'};
const _project = 'prds/PROJECT.md';
const _features = 'prds/FEATURES.md';
const _gnfr = 'prds/GNFR.md';

/// The block `init` writes, its doc paths read from [prefix].
String _block([String prefix = '']) => importBlock(
  cliVersion: specstoneVersion,
  agentMdPath: '$prefix.specstone/AGENT.md',
  projectDocPath: '${prefix}docs/prds/PROJECT.md',
  goalDocPath: '${prefix}docs/prds/GOAL.md',
  featuresDocPath: '${prefix}docs/prds/FEATURES.md',
);

/// Returns what [importedDocPaths] gives for the login project plus [files].
Future<Set<String>> _imported(
  Map<String, String> files, {
  Map<String, String> environment = _claudeCode,
  String Function(Directory root)? claudeText,
}) async {
  final root = await writeLoginProject(extra: files);
  if (claudeText != null) {
    File('${root.path}/CLAUDE.md').writeAsStringSync(claudeText(root));
  }
  final session = openSession(root);
  addTearDown(session.close);
  return importedDocPaths(
    session.project,
    session.index,
    environment: environment,
  );
}

void main() {
  group('importLinesOf', () {
    test('lists the at-paths of one well-formed block', () {
      expect(importLinesOf('Owner text\n\n${_block()}after\n'), [
        '.specstone/AGENT.md',
        'docs/prds/PROJECT.md',
        'docs/prds/GOAL.md',
        'docs/prds/FEATURES.md',
      ]);
    });

    test('lists nothing for a missing or malformed block', () {
      expect(importLinesOf('@docs/prds/PROJECT.md\n'), isEmpty);
      expect(
        importLinesOf(_block().replaceAll('<!-- END specstone -->', '')),
        isEmpty,
      );
    });
  });

  group('importedDocPaths', () {
    test('a well-formed block at the project root imports each doc its '
        'at-lines reach', () async {
      expect(await _imported({'CLAUDE.md': _block()}), {_project, _features});
    });

    test('a block at a repository top imports the docs its at-lines reach '
        'from that folder', () async {
      final files = {
        '.specstone/config.yaml': '${shippedPinsConfig()}code_root: vendor\n',
        'vendor/.git/HEAD': 'ref\n',
        'vendor/lib/a': '',
        'vendor/CLAUDE.md': _block('../'),
      };

      expect(await _imported(files), {_project, _features});
    });

    test('an empty or missing Claude Code variable imports no doc', () async {
      final files = {'CLAUDE.md': _block()};

      expect(await _imported(files, environment: {}), isEmpty);
      expect(await _imported(files, environment: {'CLAUDECODE': ''}), isEmpty);
    });

    test('a block with broken markers, or one inside an open fence, adds no '
        'doc', () async {
      const end = '<!-- END specstone -->\n';
      final texts = [
        _block().replaceAll(end, ''),
        '${_block()}${_block()}',
        '```\n${_block()}',
      ];

      for (final text in texts) {
        expect(await _imported({'CLAUDE.md': text}), isEmpty, reason: text);
      }
    });

    test('an at-line naming a missing file, a file that is no doc, or a path '
        'outside the project adds no doc', () async {
      final other = await writeLoginProject();
      String text(Directory root) => [
        '<!-- BEGIN specstone v$specstoneVersion -->',
        '@docs/prds/PROJECT.md',
        '@docs/prds/MISSING.md',
        '@docs/specs/schema.dbml',
        '@docs/../app/lib/main.dart',
        '@${other.path}/docs/prds/FEATURES.md',
        '@${root.path}/docs/prds/GNFR.md',
        '@../${other.uri.pathSegments.lastWhere((s) => s.isNotEmpty)}/docs/prds/FEATURES.md',
        '<!-- END specstone -->',
        '',
      ].join('\n');

      expect(await _imported({}, claudeText: text), {_project});
    });

    test('an at-line outside the block adds no doc', () async {
      final text = '@docs/prds/GNFR.md\n\n${_block()}\n@docs/prds/GNFR.md\n';

      final docs = await _imported({'CLAUDE.md': text});

      expect(docs, {_project, _features});
      expect(docs, isNot(contains(_gnfr)));
    });
  });
}
