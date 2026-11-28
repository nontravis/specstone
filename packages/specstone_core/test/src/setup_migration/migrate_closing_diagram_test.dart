@Tags(['integration'])
library;

import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/document_writing/owner_confirmation.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/setup_migration/migrate_run.dart';
import 'package:specstone_core/src/shipped_generators.dart'
    show shippedGenerators;
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/cold_node.dart';
import '../../helpers/git_repo.dart';
import '../../helpers/legacy_fixture.dart' show gitFixture;
import '../../helpers/shipped_pins.dart';
import '../../helpers/upgrade_fixture.dart';

const _refused = 'sequenceDiagram\n  A->>B: ok\n  A->>B: x;y';

String _architectureWith(String block) =>
    '---\ncovers:\n  - app/lib/\n---\n\n# Login architecture\n\n'
    '## Technical diagram\n\n```mermaid\n$block\n```\n\n## Components\n\n'
    '| Component | Responsibility |\n|---|---|\n'
    '| Sign-in page | Takes the form |\n';

bool _nodeStarts() {
  try {
    return Process.runSync('node', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void main() {
  useColdHostNode();

  test(
    'the closing count of an applied upgrade holds the diagram_parse_failed '
    'finding of a refused block',
    () async {
      final home = await acmeHome();
      final root = await gitFixture({
        for (final MapEntry(:key, :value) in checkProjectFiles().entries)
          key: value,
        '.specstone/config.yaml': '${shippedPinsConfig()}$acmeOldPinLine',
        'docs/$loginArchitecture': _architectureWith(_refused),
      });
      final out = StringBuffer();
      var call = 0;

      final status = await runMigrate(
        MigrateRequest(
          workingDirectory: root,
          homeDirectory: home,
          templates: TemplateResolver(),
          dryRun: false,
          confirmation: OwnerConfirmation.prompt,
          readLine: () => call++ == 0 ? 'y' : null,
          out: out,
          warn: (_) {},
          generators: shippedGenerators(),
        ),
      );

      expect(status, 0, reason: out.toString());
      final report = await ReadSession.runAsync(
        (session) async => runCheck(session),
        templates: TemplateResolver(),
        workingDirectory: root,
        homeDirectory: home,
      );
      final parseFindings = report.findings.where(
        (f) => f.kind == FindingKind.diagramParseFailed,
      );
      expect(parseFindings, hasLength(1));
      expect(
        out.toString().trim().split('\n').last,
        'check: ${report.findings.length} findings left; '
        'run specstone check to see them',
      );
    },
    skip: !hasGit
        ? 'git is not available'
        : (_nodeStarts() ? null : 'node is not on PATH'),
  );
}
