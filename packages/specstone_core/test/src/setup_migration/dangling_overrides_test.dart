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

const _sharedEntry = '''
shared_lines:
  - {id: be_brief, text: Be brief., for_doc_types: [runbook]}
  - {id: old_tone, text: Old.}
''';

const _packFiles = {
  '.specstone/packs/acme/pack.yaml':
      'name: acme\nversion: 1.2.0\nextends: software-tech\n$_sharedEntry'
      '$_renameEntry',
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
  new(this.project, this.home, this.packs, {this.acmePin = '1.0.0'});

  final List<String> packs;
  final String acmePin;
  final Directory project;
  final Directory home;

  void run() {
    final resolver = TemplateResolver();
    final target = resolver.resolveCarried(
      packNames: packs,
      homeDirectory: home,
    );
    final available = resolver.availableManifests(packs, homeDirectory: home);
    final pins = {
      for (final entry in available.entries)
        entry.key: entry.key == 'acme'
            ? PackVersion.parse(acmePin, file: 'c', key: 'k')
            : entry.value.version,
    };
    refuseDanglingOverrides(
      loadProjectTemplates(project),
      target: target,
      targetVersions: {
        for (final entry in available.entries) entry.key: entry.value.version,
      },
      upgrades: selectUpgrades(pins, available),
      sharedLines: loadProjectSharedLines(project),
    );
  }
}

Future<_Case> _case(
  Map<String, String> overrides, {
  Map<String, String> packFiles = _packFiles,
  List<String> packs = _packs,
  String acmePin = '1.0.0',
}) async {
  final project = await writeTree({
    for (final entry in overrides.entries)
      '.specstone/templates/${entry.key}.yaml': entry.value,
  });
  final home = await writeTree(packFiles);
  return _Case(project, home, packs, acmePin: acmePin);
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
  test('an override naming a section the new '
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

  test('an override naming a section a selected step '
      'renames does not refuse', () async {
    final fixture = await _case({
      'runbook': 'sections: [{id: steps, required: true}]',
    });

    expect(fixture.run, returnsNormally);
  });

  test('a removed section no override names does not '
      'refuse', () async {
    final fixture = await _case({'user_story': 'description: Mine'});

    expect(fixture.run, returnsNormally);
  });

  test('several dangling entries refuse once, listing '
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

  test('an override of a doc type the new version lacks '
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

  test('an entry that adds a section with its header is not '
      'dangling', () async {
    final fixture = await _case({
      'runbook': 'sections: [{id: notes, header: Notes}]',
    });

    expect(fixture.run, returnsNormally);
  });

  test('a path: override of a pack doc type is still checked '
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

  test('a layer that writes path: for a new doc type defines '
      'its own and is skipped', () async {
    final fixture = await _case({
      'playbook':
          'path: prds/playbooks/{slug}/PLAYBOOK.md\n'
          'sections: [{id: x, required: true}]',
    });

    expect(fixture.run, returnsNormally);
  });

  group('shared.yaml entries', () {
    const file = '.specstone/templates/shared.yaml';
    const tail = 'edit the override, then run specstone migrate again';

    test('a line that is no complete new entry and whose id the new '
        'version lacks refuses, naming the file and the id', () async {
      final fault = _refusal(
        await _case({
          'shared': 'shared_lines: [{id: ghost, for_doc_types: [runbook]}]',
        }),
      );

      expect(fault.code, MigrateFaultCode.overrideDangling);
      expect(fault.exitStatus, 78);
      expect(fault.file, file);
      expect(fault.key, 'shared_lines.ghost');
      expect(
        fault.toText(),
        '$file: shared_lines.ghost: no pack defines the shared line ghost; '
        '$tail',
      );
    });

    test('a disabling entry whose id the new version lacks '
        'refuses', () async {
      final fault = _refusal(
        await _case({'shared': 'shared_lines: [{id: ghost, disabled: true}]'}),
      );

      expect(fault.key, 'shared_lines.ghost');
    });

    test('an entry that disables a line a pack declared and a higher pack '
        'disabled does not refuse', () async {
      final fixture = await _case(
        {'shared': 'shared_lines: [{id: old_tone, disabled: true}]'},
        packs: [..._packs, 'acme_top'],
        packFiles: {
          ..._packFiles,
          '.specstone/packs/acme_top/pack.yaml':
              'name: acme_top\nversion: 1.0.0\nextends: acme\n'
              'shared_lines:\n  - {id: old_tone, disabled: true}\n',
        },
      );

      expect(fixture.run, returnsNormally);
    });

    test('a line that dangles on its id and on a doc type lists the id '
        'first', () async {
      final fault = _refusal(
        await _case({
          'shared': 'shared_lines: [{id: ghost, for_doc_types: [gone_a]}]',
        }),
      );

      expect(fault.key, 'shared_lines.ghost');
      expect(fault.more.map((more) => more.key), [
        'shared_lines.ghost.for_doc_types',
      ]);
    });

    test('a complete new entry, and an entry that changes a line the '
        'new version defines, do not refuse', () async {
      final fixture = await _case({
        'shared':
            'shared_lines: [{id: fresh, text: Fresh.}, '
            '{id: be_brief, text: Shorter.}]',
      });

      expect(fixture.run, returnsNormally);
    });

    test('a line naming two dropped doc types lists one entry for '
        'each', () async {
      final fault = _refusal(
        await _case({
          'shared':
              'shared_lines: [{id: be_brief, for_doc_types: '
              '[gone_a, runbook, gone_b]}]',
        }),
      );

      expect(fault.key, 'shared_lines.be_brief.for_doc_types');
      const head =
          '$file: shared_lines.be_brief.for_doc_types: no pack defines';
      expect(fault.toText().split('\n'), [
        '$head the doc type gone_a that shared line be_brief names; $tail',
        '$head the doc type gone_b that shared line be_brief names; $tail',
      ]);
    });

    test('a doc type a project layer defines or a personal pack '
        'defines is not dropped', () async {
      final fixture = await _case({
        'playbook': 'path: prds/playbooks/{slug}/PLAYBOOK.md\n',
        'shared':
            'shared_lines: [{id: fresh, text: Fresh., '
            'for_doc_types: [playbook, runbook]}]',
      });

      expect(fixture.run, returnsNormally);
    });

    Map<String, String> dropFiles(String from) => {
      ..._packFiles,
      '.specstone/packs/acme/pack.yaml':
          'name: acme\nversion: 1.2.0\nextends: software-tech\n'
          'migrations:\n  - from: $from\n    steps:\n'
          '      - drop_shared_lines: {ids: [ghost]}\n',
    };

    for (final (entry, from) in [
      ('{id: ghost, text: Mine.}', '1.0.0'),
      ('{id: ghost, text: Mine., for_doc_types: [runbook]}', '1.0.0'),
      ('{id: ghost, text: Mine.}', '1.1.0'),
    ]) {
      test('an entry a selected drop step names refuses, any keys: '
          '$entry from $from', () async {
        final fault = _refusal(
          await _case({
            'shared': 'shared_lines: [$entry]',
          }, packFiles: dropFiles(from)),
        );

        expect(fault.code, MigrateFaultCode.overrideDangling);
        expect(fault.exitStatus, 78);
        expect(fault.file, file);
        expect(fault.key, 'shared_lines.ghost');
        expect(fault.more, isEmpty);
        expect(
          fault.toText(),
          '$file: shared_lines.ghost: no pack defines the shared line ghost; '
          '$tail',
        );
      });
    }

    test('a drop step below the pin spares a complete line', () async {
      final fixture = await _case({
        'shared': 'shared_lines: [{id: ghost, text: Mine.}]',
      }, packFiles: dropFiles('0.9.0'));

      expect(fixture.run, returnsNormally);
    });

    test('a dropped id another pack declares spares the entry', () async {
      final fixture = await _case(
        {'shared': 'shared_lines: [{id: ghost, text: Mine.}]'},
        packs: [..._packs, 'acme_top'],
        packFiles: {
          ...dropFiles('1.0.0'),
          '.specstone/packs/acme_top/pack.yaml':
              'name: acme_top\nversion: 1.0.0\nextends: acme\n'
              'shared_lines:\n  - {id: ghost, text: Declared.}\n',
        },
      );

      expect(fixture.run, returnsNormally);
    });

    test('the entries join the override faults in file order', () async {
      final fault = _refusal(
        await _case({
          'runbook': 'sections: [{id: checklist, required: true}]',
          'shared': 'shared_lines: [{id: ghost, for_doc_types: [runbook]}]',
          'user_story': 'fields: [{id: owner_team, required: true}]',
        }),
      );

      expect(fault.more.map((more) => more.file), [
        file,
        '.specstone/templates/user_story.yaml',
      ]);
    });
  });

  group('drop_section step', () {
    final packFiles = {
      ..._packFiles,
      '.specstone/packs/acme/pack.yaml':
          'name: acme\nversion: 1.2.0\nextends: software-tech\n'
          'migrations:\n  - from: 1.0.0\n    steps:\n'
          '      - drop_section: {doc_types: [runbook], '
          'section: {id: legacy, header: Legacy}}\n',
    };

    for (final entry in [
      '{id: legacy, disabled: true}',
      '{id: legacy, required: true}',
    ]) {
      test('a disabled or headerless entry for a dropped section dangles '
          'before any write: $entry', () async {
        final fault = _refusal(
          await _case({'runbook': 'sections: [$entry]'}, packFiles: packFiles),
        );

        expect(fault.code, MigrateFaultCode.overrideDangling);
        expect(fault.exitStatus, 78);
        expect(fault.file, '.specstone/templates/runbook.yaml');
        expect(fault.key, 'sections.legacy');
        expect(fault.more, isEmpty);
      });
    }

    test('an entry writing a dropped section whole never dangles', () async {
      final fixture = await _case({
        'runbook': 'sections: [{id: legacy, header: Legacy}]',
      }, packFiles: packFiles);

      expect(fixture.run, returnsNormally);
    });
  });

  group('merge_doc step', () {
    final packFiles = {
      ..._packFiles,
      '.specstone/packs/acme/pack.yaml':
          'name: acme\nversion: 1.2.0\nextends: software-tech\n'
          'migrations:\n  - from: 1.0.0\n    steps:\n'
          '      - merge_doc: {from: {id: playbook, path: specs/PLAYBOOK.md}, '
          'to: runbook, sections: [{from: {id: moves, header: Moves}, '
          'to: procedure}]}\n',
    };
    const dangling = 'sections: [{id: gone, required: true}]';

    Future<void> expectSpared(String layer, {required String pin}) async {
      final fixture = await _case(
        {'playbook': layer},
        packFiles: packFiles,
        acmePin: pin,
      );

      expect(fixture.run, returnsNormally);
    }

    test(
      'a layer file of the folded doc type with no path never dangles '
      'while the step is selected',
      () => expectSpared(dangling, pin: '1.0.0'),
    );

    test(
      'a layer file of the folded doc type with no path never dangles '
      'when the pin already passed the step',
      () => expectSpared(dangling, pin: '1.2.0'),
    );

    test('a layer file with a path of a folded doc type the target still '
        'defines never dangles', () async {
      final fixture = await _case(
        {'playbook': 'path: playbooks/{slug}.md\n$dangling'},
        packFiles: {
          ...packFiles,
          '.specstone/packs/acme/playbook.yaml':
              'id: playbook\ndescription: A playbook.\n'
              'path: prds/playbooks/{slug}/PLAYBOOK.md\n',
        },
      );

      expect(fixture.run, returnsNormally);
    });

    test('a shared line naming a folded doc type dangles though a layer '
        'with a path writes it', () async {
      final fault = _refusal(
        await _case({
          'playbook': 'path: playbooks/{slug}.md\n',
          'shared':
              'shared_lines: '
              '[{id: mine, text: Mine., for_doc_types: [playbook]}]',
        }, packFiles: packFiles),
      );

      expect(fault.code, MigrateFaultCode.overrideDangling);
      expect(fault.file, '.specstone/templates/shared.yaml');
      expect(fault.key, 'shared_lines.mine.for_doc_types');
    });

    test('an override of a doc type no step folds still dangles', () async {
      final fault = _refusal(
        await _case({'notes': dangling}, packFiles: packFiles),
      );

      expect(fault.code, MigrateFaultCode.overrideDangling);
      expect(fault.file, '.specstone/templates/notes.yaml');
    });
  });

  group('drop_doc_type step', () {
    final packFiles = {
      ..._packFiles,
      '.specstone/packs/acme/pack.yaml':
          'name: acme\nversion: 1.2.0\nextends: software-tech\n'
          'migrations:\n  - from: 1.0.0\n    steps:\n'
          '      - drop_doc_type: {id: x, path: "xs/{slug}.md"}\n',
    };
    const dangling = 'sections: [{id: gone, required: true}]';

    Future<void> expectSpared(String layer, {required String pin}) async {
      final fixture = await _case(
        {'x': layer},
        packFiles: packFiles,
        acmePin: pin,
      );

      expect(fixture.run, returnsNormally);
    }

    test(
      'a layer file of the dropped doc type never dangles while the step is '
      'selected',
      () => expectSpared(dangling, pin: '1.0.0'),
    );

    test(
      'a layer file of the dropped doc type never dangles when the pin '
      'already passed the step',
      () => expectSpared(dangling, pin: '1.2.0'),
    );

    test(
      'a layer file with a path of the dropped doc type never dangles',
      () => expectSpared('path: xs/{slug}.md\n$dangling', pin: '1.0.0'),
    );

    test('an override of a doc type no step drops still dangles', () async {
      final fault = _refusal(
        await _case({'z': dangling}, packFiles: packFiles),
      );

      expect(fault.code, MigrateFaultCode.overrideDangling);
      expect(fault.file, '.specstone/templates/z.yaml');
    });
  });

  group('move_to_record record override', () {
    const file = '.specstone/templates/implementation.yaml';

    test('no layer sets the record path and architecture '
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

    test('the entry joins the other dangling entries, '
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

    test('once the record override sets path, the plan '
        'prints', () async {
      final fixture = await _case({
        'architecture': _slugNamedArchitecture,
        'implementation': 'path: specs/{slug}/f{nn}_{slug}.md\n',
      }, packFiles: _recordPackFiles);

      expect(fixture.run, returnsNormally);
    });

    test('an architecture path the pack gives, or one '
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

    test('a run with no move_to_record step does not '
        'refuse', () async {
      final fixture = await _case({'architecture': _slugNamedArchitecture});

      expect(fixture.run, returnsNormally);
    });
  });
}
