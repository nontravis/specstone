import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/format_run.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:specstone_core/src/rendering/models/opened_resolver.dart';
import 'package:specstone_core/src/shipped_generators.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/grouped_fixture.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/temp_tree.dart';
import '../../helpers/write_fixture.dart' show testHome;

const _mapPath = 'prds/FEATURES.md';
const _groupPath = 'prds/features/kitchen/FEATURES.md';
const _catalogKind = 'feature_catalog';
const _groupKind = 'group_feature_catalog';

Map<String, String> _plainFiles() => {
  '.specstone/config.yaml': shippedPinsConfig(),
  'docs/$_mapPath': '# Feature map\n\n## Features\n',
  'docs/prds/features/f01_login/FEATURE.md': '# Login\n',
};

Map<String, String> _groupedFiles() => {
  ...featureGroupedFiles(),
  'docs/$_mapPath': '# Feature map\n\n## Features\n',
};

GeneratorRun<DocIndex> _run(
  Directory root,
  GeneratorRegistry<DocIndex> registry,
) => GeneratorRun<DocIndex>(
  registry: registry,
  open: () {
    final session = ReadSession.open(
      templates: TemplateResolver(),
      workingDirectory: root,
      homeDirectory: testHome(),
    );
    return OpenedResolver(
      resolver: session.index,
      close: session.close,
      lockWrites: (write) => session.writeIndex((_) => write()),
    );
  },
);

/// Runs `format` over the docs root and returns the paths it lists as
/// changing, or writes them when [check] is false.
List<String> _format(
  Directory root, {
  required bool check,
  GeneratorRegistry<DocIndex>? registry,
}) {
  final project = DocsProject.open(
    templates: TemplateResolver(),
    workingDirectory: root,
    homeDirectory: testHome(),
  );
  final report = runFormat<DocIndex>(
    project,
    project.resolveTarget(
      null,
      workingDirectory: root,
      defaultsToDocsRoot: true,
      includeRecordsRoot: true,
    ),
    check: check,
    homeDirectory: testHome(),
    generators: _run(root, registry ?? shippedGenerators()),
  );
  return [
    for (final file in report.files)
      if (file.status == FileStatus.formatted ||
          file.status == FileStatus.deleted)
        file.path,
  ];
}

Future<List<Finding>> _stale(
  Directory root, {
  GeneratorRegistry<DocIndex>? registry,
}) async {
  final session = ReadSession.open(
    templates: TemplateResolver(),
    workingDirectory: root,
    homeDirectory: testHome(),
  );
  try {
    final report = await runCheck(session, generators: registry);
    return [
      for (final finding in report.findings)
        if (finding.kind == FindingKind.generatedBlockStale) finding,
    ];
  } finally {
    session.close();
  }
}

String _docsPath(String docPath) => 'docs/$docPath';

void _rewrite(Directory root, String docPath, String Function(String) edit) {
  final file = File('${root.path}/${_docsPath(docPath)}');
  file.writeAsStringSync(edit(file.readAsStringSync()));
}

void main() {
  test('a features doc formatted, then given a new feature, is reported at '
      "its block's opening marker and `format --check` lists it", () async {
    // D5: one finding at the opening marker line of the first stale block.
    final root = await writeTree(_plainFiles());
    _format(root, check: false);
    expect(await _stale(root), isEmpty);

    File('${root.path}/docs/prds/features/f02_billing/FEATURE.md')
        .createSync(recursive: true);
    File('${root.path}/docs/prds/features/f02_billing/FEATURE.md')
        .writeAsStringSync('# Billing\n');

    final findings = await _stale(root);
    final markerLine =
        File('${root.path}/${_docsPath(_mapPath)}')
            .readAsLinesSync()
            .indexOf(generatedOpenMarker(_catalogKind)) +
        1;
    expect(markerLine, greaterThan(1));
    expect(findings.map((finding) => finding.path), [_mapPath]);
    final finding = findings.single;
    expect(finding.line, markerLine);
    expect(finding.waitsFor, WaitsFor.agent);
    expect(
      finding.message,
      'generated block $_catalogKind is stale; run specstone format $_mapPath',
    );
    expect(finding.toJson(), isNot(contains('fix')));
    expect(
      _format(root, check: true).where((path) => path.endsWith(_mapPath)),
      hasLength(1),
    );
  });

  test('a doc that lacks a block is reported at line 1 and listed by '
      '`format --check`', () async {
    // D5: line 1 when the doc lacks the block.
    final root = await writeTree(_plainFiles());
    _format(root, check: false);
    _rewrite(
      root,
      _mapPath,
      (text) => text.replaceAll(
        RegExp('<!-- specstone:generated.*?end -->\n', dotAll: true),
        '',
      ),
    );

    final findings = await _stale(root);
    expect(findings.map((finding) => finding.path), [_mapPath]);
    expect(findings.single.line, 1);
    expect(findings.single.message, contains('block $_catalogKind is stale'));
    expect(
      _format(root, check: true).where((path) => path.endsWith(_mapPath)),
      hasLength(1),
    );
  });

  test('a grouped features doc that is current itself while a group features '
      'doc lags is reported as `features`, beside the group doc', () async {
    // D5: `features` when the group features docs lag; Review Focus 4.
    final root = await writeTree(_groupedFiles());
    _format(root, check: false);
    expect(await _stale(root), isEmpty);

    _rewrite(
      root,
      _groupPath,
      (text) => text.replaceFirst(
        RegExp(
          '(<!-- specstone:generated $_groupKind.*?-->\n)'
          '.*?(<!-- specstone:generated end)',
          dotAll: true,
        ),
        r'$1old row\n$2',
      ),
    );

    final findings = await _stale(root);
    final byPath = {for (final f in findings) f.path: f};
    expect(byPath.keys.toSet(), {_mapPath, _groupPath});
    expect(byPath[_mapPath]!.line, 1);
    expect(
      byPath[_mapPath]!.message,
      'generated block features is stale; run specstone format $_mapPath',
    );
    expect(byPath[_groupPath]!.message, contains('block $_groupKind is stale'));
    final listed = _format(root, check: true);
    expect(listed.any((path) => path.endsWith(_mapPath)), isTrue);
    expect(listed.any((path) => path.endsWith(_groupPath)), isTrue);
  });

  test('a block no generator resolves gives no finding, as `format --check` '
      'lists none for it', () async {
    // D5: a block its generator cannot resolve gives none.
    final root = await writeTree(_plainFiles());
    final registry = GeneratorRegistry<DocIndex>({});

    expect(await _stale(root, registry: registry), isEmpty);
    expect(
      _format(
        root,
        check: true,
        registry: registry,
      ).where((path) => path.endsWith(_mapPath)),
      isEmpty,
    );
  });

  test('a features doc format refuses gives no stale block finding, as '
      '`format` would not write it', () async {
    // D5: the message's `run specstone format` holds only for a doc format
    // writes.
    final root = await writeTree(_plainFiles());
    _format(root, check: false);
    File('${root.path}/docs/prds/features/f02_billing/FEATURE.md')
      ..createSync(recursive: true)
      ..writeAsStringSync('# Billing\n');
    _rewrite(root, _mapPath, (text) => '$text\n## Unknown\n\nText.\n');

    expect(await _stale(root), isEmpty);
  });

  test('a grouped features doc whose group a refused group features doc '
      'blocks gives no stale block finding, as `format --check` lists none '
      'for it', () async {
    // D5: `format` writes no doc of a blocked group, so its advice would not
    // hold; the refused group doc's own refusal is the finding to act on.
    final root = await writeTree(_groupedFiles());
    _format(root, check: false);
    _rewrite(root, _groupPath, (text) => '$text\n## Unknown\n\nText.\n');
    File('${root.path}/docs/prds/features/garden/f01_beds/FEATURE.md')
      ..createSync(recursive: true)
      ..writeAsStringSync('# Beds\n');

    expect(await _stale(root), isEmpty);
    expect(
      _format(root, check: true).where((path) => path.endsWith(_mapPath)),
      isEmpty,
    );
  });
}
