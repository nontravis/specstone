import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/setup_migration/project_root.dart';
import 'package:specstone_core/src/setup_migration/run_kind.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/shipped_pins.dart';
import '../../helpers/temp_tree.dart';

final String _journal = jsonEncode(
  const MoveJournal([
    CommitStep(message: 'move', paths: ['a'], base: 'abc'),
  ]).toJson(),
);

const _laidOutFeature = '## Problem\n\nn\n\n## Benefit hypothesis\n\ng\n';
const _offLayoutFeature = '## Benefit hypothesis\n\ng\n\n\n## Problem\n\nn\n';

RunKind _choose(Directory root, {Directory? home}) =>
    chooseRun(root, templates: TemplateResolver(), homeDirectory: home);

Matcher _pinNewer() => throwsA(
  isA<TemplateFault>()
      .having((f) => f.code, 'code', FaultCode.packPinNewer)
      .having((f) => f.key, 'key', 'packs.prd-core'),
);

void main() {
  test('f06/us01/fr01/e07: a pending migrate journal is resume', () async {
    final root = await writeTree({
      MoveJournal.journalPath: _journal,
      '.specstone/config.yaml': shippedPinsConfig(),
      legacyContextPath: '# D-01\n',
    });

    expect(_choose(root), RunKind.resume);
  });

  test('f06/us01/fr01/e03: config and legacy context doc together are '
      'legacy', () async {
    final root = await writeTree({
      '.specstone/config.yaml': shippedPinsConfig(),
      legacyContextPath: '# D-01\n',
    });

    expect(_choose(root), RunKind.legacy);
  });

  test('f06/us01/fr01/e04, f06/us02/s6: pins equal to the carried versions '
      'are none', () async {
    final root = await writeTree({
      '.specstone/config.yaml': shippedPinsConfig(),
    });

    expect(_choose(root), RunKind.none);
  });

  test('setup_migration/migrate_legacy_docs/find_project_root E04: pins equal '
      'and every typed doc laid out is none', () async {
    final root = await writeTree({
      '.specstone/config.yaml': shippedPinsConfig(),
      'docs/prds/features/f01_a/FEATURE.md': _laidOutFeature,
    });

    expect(_choose(root), RunKind.none);
  });

  test('setup_migration/migrate_legacy_docs/find_project_root E04: pins equal '
      'and one typed doc off its layout is upgrade', () async {
    final root = await writeTree({
      '.specstone/config.yaml': shippedPinsConfig(),
      'docs/prds/features/f01_a/FEATURE.md': _laidOutFeature,
      'docs/prds/features/f02_b/FEATURE.md': _offLayoutFeature,
    });

    expect(_choose(root), RunKind.upgrade);
  });

  test('setup_migration/migrate_legacy_docs/find_project_root E04: a doc '
      'format refuses alone is none', () async {
    final root = await writeTree({
      '.specstone/config.yaml': shippedPinsConfig(),
      'docs/prds/features/f01_a/FEATURE.md': '## Notes\nx   \n',
    });

    expect(_choose(root), RunKind.none);
  });

  test('f06/us01/fr01/e06, f06/us02/fr01/e03, f06/us02/s7: a newer pin '
      'refuses pack_pin_newer, alone or beside an older pin', () async {
    final alone = await writeTree({
      '.specstone/config.yaml': 'packs:\n  prd-core: 9.0.0\n',
    });
    final beside = await writeTree({
      '.specstone/config.yaml':
          'packs:\n  prd-core: 9.0.0\n  software-tech: 1.0.0\n',
    });

    expect(() => _choose(alone), _pinNewer());
    expect(() => _choose(beside), _pinNewer());
  });

  test('f06/us02/fr01/e03: with two newer pins the refusal names the earlier '
      'pack in code point order', () async {
    final root = await writeTree({
      '.specstone/config.yaml':
          'packs:\n  software-tech: 9.0.0\n  prd-core: 9.0.0\n',
    });

    expect(() => _choose(root), _pinNewer());
  });

  test('f06/us02/fr01: an older pin is upgrade', () async {
    final root = await writeTree({
      '.specstone/config.yaml':
          '${shippedPinsConfig(['prd-core'])}  software-tech: 1.0.0\n',
    });

    expect(_choose(root), RunKind.upgrade);
  });

  test('f06/us02/fr01: a personal pack pinned below its home-folder version '
      'is upgrade', () async {
    final home = await writeTree({
      '.specstone/packs/acme/pack.yaml':
          'name: acme\nversion: 1.2.0\nextends: software-tech\n',
    });
    final root = await writeTree({
      '.specstone/config.yaml':
          '${shippedPinsConfig(['prd-core'])}  acme: 1.0.0\n',
    });

    expect(_choose(root, home: home), RunKind.upgrade);
  });
}
