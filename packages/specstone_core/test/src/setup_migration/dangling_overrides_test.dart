import 'dart:io';

import 'package:specstone_core/src/setup_migration/dangling_overrides.dart';
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/setup_migration/migration_chain.dart';
import 'package:specstone_core/src/templates/layer_source.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/temp_tree.dart';

const _packs = ['prd-core', 'software-tech', 'acme'];

const _renameEntry = '''
migrations:
  - from: 1.0.0
    steps:
      - rename_section: {doc_type: runbook, from: {id: steps, header: Steps}, to: {id: procedure, header: Procedure}}
''';

const _packFiles = {
  '.specstone/packs/acme/pack.yaml':
      'name: acme\nversion: 1.2.0\nextends: software-tech\n$_renameEntry',
  '.specstone/packs/acme/runbook.yaml': '''
id: runbook
description: A runbook.
path: prds/runbooks/{slug}/RUNBOOK.md
fields:
  - {id: on_call, type: string}
sections:
  - {id: procedure, header: Procedure, required: true}
  - {id: rollback, header: Rollback, required: false}
''',
};

class _Case {
  new(this.project, this.home);

  final Directory project;
  final Directory home;

  void run() {
    final resolver = TemplateResolver();
    final target = resolver.resolveCarried(
      packNames: _packs,
      homeDirectory: home,
    );
    final available = resolver.availableManifests(_packs, homeDirectory: home);
    final pins = {
      for (final entry in available.entries)
        entry.key: entry.key == 'acme'
            ? PackVersion.parse('1.0.0', file: 'c', key: 'k')
            : entry.value.version,
    };
    refuseDanglingOverrides(
      loadProjectTemplates(project),
      target: target,
      targetVersions: {
        for (final entry in available.entries) entry.key: entry.value.version,
      },
      upgrades: selectUpgrades(pins, available),
    );
  }
}

Future<_Case> _case(Map<String, String> overrides) async {
  final project = await writeTree({
    for (final entry in overrides.entries)
      '.specstone/templates/${entry.key}.yaml': entry.value,
  });
  final home = await writeTree(_packFiles);
  return _Case(project, home);
}

MigrateFault _refusal(_Case fixture) {
  try {
    fixture.run();
  } on MigrateFault catch (fault) {
    return fault;
  }
  fail('expected a MigrateFault');
}

void main() {
  test('f06/us02/fr03, f06/us02/s8: an override naming a section the new '
      'version lacks and no step renames refuses', () async {
    final fault = _refusal(
      await _case({'runbook': 'sections: [{id: checklist, required: true}]'}),
    );

    expect(fault.code, MigrateFaultCode.overrideDangling);
    expect(fault.exitStatus, 78);
    expect(
      fault.toText(),
      '.specstone/templates/runbook.yaml: sections.checklist: pack acme 1.2.0 '
      'defines no section checklist and no step renames it; edit the '
      'override, then run specstone migrate again',
    );
  });

  test('f06/us02/fr03/e01: an override naming a section a selected step '
      'renames does not refuse', () async {
    final fixture = await _case({
      'runbook': 'sections: [{id: steps, required: true}]',
    });

    expect(fixture.run, returnsNormally);
  });

  test('f06/us02/fr03/e02: a removed section no override names does not '
      'refuse', () async {
    final fixture = await _case({'user_story': 'description: Mine'});

    expect(fixture.run, returnsNormally);
  });

  test('f06/us02/fr03/e03: several dangling entries refuse once, listing '
      'every one in file order', () async {
    final fault = _refusal(
      await _case({
        'runbook':
            'sections: [{id: checklist, required: true}, '
            '{id: gone, disabled: true}]',
        'user_story': 'fields: [{id: owner_team, required: true}]',
      }),
    );

    const file = '.specstone/templates/runbook.yaml';
    const head = 'pack acme 1.2.0 defines no section';
    const tail =
        'and no step renames it; edit the override, then run '
        'specstone migrate again';
    expect(fault.toText().split('\n'), [
      '$file: sections.checklist: $head checklist $tail',
      '$file: sections.gone: $head gone $tail',
      startsWith(
        '.specstone/templates/user_story.yaml: fields.owner_team: pack ',
      ),
    ]);
    expect(fault.more, hasLength(2));
  });

  test('f06/us02/fr03/e04: an override of a doc type the new version lacks '
      'is listed', () async {
    final fault = _refusal(
      await _case({'playbook': 'sections: [{id: x, required: true}]'}),
    );

    expect(
      fault.toText(),
      '.specstone/templates/playbook.yaml: no pack defines the doc type '
      'playbook and no step renames it; edit the override, then run '
      'specstone migrate again',
    );
    expect(fault.key, isNull);
  });

  test('f06/us02/fr03: an entry that adds a section with its header is not '
      'dangling', () async {
    final fixture = await _case({
      'runbook': 'sections: [{id: notes, header: Notes}]',
    });

    expect(fixture.run, returnsNormally);
  });

  test('f06/us02/fr03: a layer that writes path: defines its own doc type and '
      'is skipped', () async {
    final fixture = await _case({
      'playbook':
          'path: prds/playbooks/{slug}/PLAYBOOK.md\n'
          'sections: [{id: x, required: true}]',
    });

    expect(fixture.run, returnsNormally);
  });
}
