import 'dart:io';

import 'package:specstone_core/src/setup_migration/dangling_overrides.dart';
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/setup_migration/migration_chain.dart';
import 'package:specstone_core/src/templates/layer_source.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/record_fixture.dart' show recordLayer;
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

Future<_Case> _case(
  Map<String, String> overrides, {
  Map<String, String> packFiles = _packFiles,
}) async {
  final project = await writeTree({
    for (final entry in overrides.entries)
      '.specstone/templates/${entry.key}.yaml': entry.value,
  });
  final home = await writeTree(packFiles);
  return _Case(project, home);
}

const Map<String, String> _recordPackFiles = {
  '.specstone/packs/acme/pack.yaml': '''
name: acme
version: 1.2.0
extends: software-tech
migrations:
  - from: 1.0.0
    steps:
      - move_to_record: {doc_types: [user_story, fr], fields: [status, implements], to: implementation}
''',
  '.specstone/packs/acme/implementation.yaml': recordLayer,
};

const _slugNamedArchitecture = 'path: specs/{slug}/f{nn}_{slug}.md\n';

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

  test('f06/us02/fr03: a path: override of a pack doc type is still checked '
      'for dangling entries', () async {
    final fault = _refusal(
      await _case({
        'runbook':
            'path: custom/{slug}.md\n'
            'sections: [{id: checklist, required: true}]',
      }),
    );

    expect(fault.code, MigrateFaultCode.overrideDangling);
    expect(fault.key, 'sections.checklist');
  });

  test('f06/us02/fr03: a layer that writes path: for a new doc type defines '
      'its own and is skipped', () async {
    final fixture = await _case({
      'playbook':
          'path: prds/playbooks/{slug}/PLAYBOOK.md\n'
          'sections: [{id: x, required: true}]',
    });

    expect(fixture.run, returnsNormally);
  });

  group('move_to_record record override', () {
    const file = '.specstone/templates/implementation.yaml';

    test('f06/us02/fr03/e06: no layer sets the record path and architecture '
        'names its file by the feature slug, so the run refuses and lists '
        'the override to write', () async {
      final fault = _refusal(
        await _case({
          'architecture': _slugNamedArchitecture,
        }, packFiles: _recordPackFiles),
      );

      expect(fault.code, MigrateFaultCode.overrideDangling);
      expect(fault.exitStatus, 78);
      expect(fault.file, file);
      expect(fault.key, 'path');
      expect(fault.toText(), startsWith('$file: path: '));
      expect(fault.more, isEmpty);
    });

    test('f06/us02/fr03/e06: the entry joins the other dangling entries, '
        'after them', () async {
      final fault = _refusal(
        await _case({
          'architecture': _slugNamedArchitecture,
          'user_story': 'fields: [{id: owner_team, required: true}]',
        }, packFiles: _recordPackFiles),
      );

      expect(fault.file, '.specstone/templates/user_story.yaml');
      expect(fault.more.map((more) => more.file), [file]);
    });

    test('f06/us02/fr03/e06: once the record override sets path, the plan '
        'prints', () async {
      final fixture = await _case({
        'architecture': _slugNamedArchitecture,
        'implementation': 'path: specs/{slug}/f{nn}_{slug}.md\n',
      }, packFiles: _recordPackFiles);

      expect(fixture.run, returnsNormally);
    });

    test('f06/us02/fr03/e06: an architecture path the pack gives, or one '
        'whose file has no slug, does not refuse', () async {
      expect(
        (await _case(const {}, packFiles: _recordPackFiles)).run,
        returnsNormally,
      );
      expect(
        (await _case({
          'architecture': 'path: specs/{slug}/f{nn}_{slug}/ARCHITECTURE.md\n',
        }, packFiles: _recordPackFiles)).run,
        returnsNormally,
      );
    });

    test('f06/us02/fr03/e06: a run with no move_to_record step does not '
        'refuse', () async {
      final fixture = await _case({'architecture': _slugNamedArchitecture});

      expect(fixture.run, returnsNormally);
    });
  });
}
