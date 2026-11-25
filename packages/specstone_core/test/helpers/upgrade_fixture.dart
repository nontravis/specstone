import 'dart:io';

import 'legacy_fixture.dart' show commitRepo, gitFixture, linkCodeDocs;
import 'shipped_pins.dart';
import 'temp_tree.dart';
import 'write_fixture.dart' show testHome;

/// A project that pins the personal pack `acme` below its home-folder version.
final class UpgradeFixture {
  const new({required this.project, required this.home});

  /// The committed project, on the shipped pins plus `acme: 1.0.0`.
  final Directory project;

  /// The home folder holding `acme` 1.1.0: the test home, so its journal
  /// records and the pack share one folder.
  final Directory home;
}

/// An [UpgradeFixture] whose project `ws/` is reached through a docs link in
/// its code folder `ws/code/`.
final class LinkedUpgradeFixture {
  const new({required this.tree, required this.project, required this.home});

  /// The folder holding `ws/`, as the writer made it.
  final Directory tree;

  /// The project `ws/`, by its real path.
  final Directory project;

  /// The test home, holding `acme` 1.1.0.
  final Directory home;

  /// The folder whose `docs` link leads to the project's docs.
  Directory get code => Directory('${project.path}/code');
}

/// The `config.yaml` pin line of the project of [upgradeFixture].
const acmeOldPinLine = '  acme: 1.0.0\n';

/// The ProjectPath of the runbook of [upgradeFixture] before the run.
const acmeRunbookPath = 'docs/prds/runbooks/deploy/RUNBOOK.md';

/// The text of the runbook of [upgradeFixture] before the run.
const acmeRunbookText = '# Deploy\n\n## Steps\n\nRun it.\n';

/// The ProjectPath the run of [upgradeFixture] moves the runbook to.
const acmeMovedRunbookPath = 'docs/prds/ops/deploy/RUNBOOK.md';

const _renameSteps =
    '      - rename_section: {doc_type: runbook, from: {id: steps, header: '
    'Steps}, to: {id: procedure, header: Procedure}}\n';

const _moveStep =
    '      - move_file: {doc_type: runbook, from: '
    '"prds/runbooks/{slug}/RUNBOOK.md", to: "prds/ops/{slug}/RUNBOOK.md"}\n';

/// The files of the personal pack `acme` 1.1.0, under a home folder.
///
/// The pack renames the runbook's `Steps` section. With [movesRunbook] it also
/// moves the runbook from `prds/runbooks/{slug}/` to `prds/ops/{slug}/`, so a
/// run over it makes both commits.
Map<String, String> _acmePack({required bool movesRunbook}) => {
  '.specstone/packs/acme/pack.yaml': '''
name: acme
version: 1.1.0
extends: software-tech
migrations:
  - from: 1.0.0
    steps:
${movesRunbook ? _moveStep : ''}$_renameSteps''',
  '.specstone/packs/acme/runbook.yaml':
      '''
id: runbook
description: A runbook.
path: prds/${movesRunbook ? 'ops' : 'runbooks'}/{slug}/RUNBOOK.md
sections:
  - {id: procedure, header: Procedure, required: true}
''',
};

/// A new home folder holding the personal pack `acme` at 1.1.0, which renames
/// the runbook's `Steps` section; with [movesRunbook] it moves the runbook too.
Future<Directory> acmeHome({bool movesRunbook = false}) =>
    writeTree(_acmePack(movesRunbook: movesRunbook));

/// Writes `acme` 1.1.0, moving the runbook, into the test home and returns it.
Directory acmeInTestHome() {
  final home = testHome();
  for (final MapEntry(:key, :value) in _acmePack(movesRunbook: true).entries) {
    File('${home.path}/$key')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(value);
  }
  return home;
}

/// The files of the project of [upgradeFixture]: the shipped pins plus `acme`
/// pinned at 1.0.0, and one runbook.
Map<String, String> upgradeFiles() => {
  '.specstone/config.yaml': '${shippedPinsConfig()}$acmeOldPinLine',
  acmeRunbookPath: acmeRunbookText,
};

/// A committed project pinning `acme` at 1.0.0 beside the shipped pins, whose
/// home 1.1.0 moves its runbook and renames its section, with [files] over
/// [upgradeFiles].
///
/// The home is the test home, so a run that passes no home finds `acme`. A
/// shipped pack pinned below its floor is refused, so a test that needs an
/// older pin pins this personal pack.
Future<UpgradeFixture> upgradeFixture({
  Map<String, String> files = const {},
}) async {
  final home = acmeInTestHome();
  final project = await gitFixture({...upgradeFiles(), ...files});
  return UpgradeFixture(project: project, home: home);
}

/// An upgrade project `ws/` with an empty code folder `ws/code/` whose `docs`
/// links to `../docs`, as stratum_ui does, with [files] over [upgradeFiles];
/// keys are relative to `ws/`.
///
/// Commits `ws/` when [commit] holds. Returns null, marking the test skipped,
/// where links need privileges.
Future<LinkedUpgradeFixture?> linkedUpgradeFixture({
  Map<String, String> files = const {},
  bool commit = false,
}) async {
  final home = acmeInTestHome();
  final tree = await writeTree({
    for (final MapEntry(:key, :value) in {
      ...upgradeFiles(),
      'code/keep.txt': '',
      '.gitignore': 'code/docs\n',
      ...files,
    }.entries)
      'ws/$key': value,
  });
  if (!linkCodeDocs(tree)) return null;
  final project = Directory('${tree.resolveSymbolicLinksSync()}/ws');
  if (commit) commitRepo(project);
  return LinkedUpgradeFixture(tree: tree, project: project, home: home);
}
