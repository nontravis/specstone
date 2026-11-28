@Tags(['integration'])
library;

import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/document_writing/new_doc.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/setup_migration/agent_files.dart';
import 'package:specstone_core/src/setup_migration/host_render.dart';
import 'package:specstone_core/src/setup_migration/init_project.dart';
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/setup_migration/project_root.dart';
import 'package:specstone_core/src/templates/project_config.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:specstone_core/src/version.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart' show checkOf, spots;
import '../../helpers/cold_node.dart';
import '../../helpers/git_repo.dart';
import '../../helpers/index_fixture.dart' show openSession;
import '../../helpers/legacy_fixture.dart';
import '../../helpers/posix_modes.dart';
import '../../helpers/relative_link.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/skill_files.dart';
import '../../helpers/temp_tree.dart';
import '../../helpers/write_fixture.dart' show testHome;

const _trustLine =
    'trust the Specstone hook in Codex: open /hooks in a trusted project';

const _draftPaths = [
  'docs/prds/PROJECT.md',
  'docs/prds/GOAL.md',
  'docs/prds/GLOSSARY.md',
  'docs/prds/FEATURES.md',
  'docs/prds/GNFR.md',
  'docs/specs/TECH_STACK.md',
];

/// Runs `init` on [root] and returns its status with the printed lines.
Future<(int, List<String>)> _run(
  Directory root, {
  List<String>? warnings,
}) async {
  final out = StringBuffer();
  final status = await runInit(
    InitRequest(
      workingDirectory: root,
      homeDirectory: testHome(),
      templates: TemplateResolver(),
      out: out,
      warn: (warnings ?? <String>[]).add,
    ),
  );
  return (status, out.toString().split('\n')..removeLast());
}

/// A `CLAUDE.md` whose block imports the `.specstone/AGENT.md` it lacks.
final _importingClaude = '# Owner\n\n$_importBlock';

final String _importBlock = importBlock(
  cliVersion: specstoneVersion,
  agentMdPath: '.specstone/AGENT.md',
  projectDocPath: 'docs/prds/PROJECT.md',
  goalDocPath: 'docs/prds/GOAL.md',
  featuresDocPath: 'docs/prds/FEATURES.md',
);

/// The config `init` writes on the shipped pins: the running Version stamped.
String _stampedConfig() =>
    '${shippedPinsConfig(shippedPinsDefaultPacks, const [])}'
    'agent_file_groups:\n  - claude_code\n  - shared\n  - codex_agents\n'
    '  - cursor_agents\n'
    'agent_files_version: $specstoneVersion\n';

String _configLine() {
  final versions = shippedPackVersions();
  return 'created .specstone/config.yaml: '
      'prd-core ${versions['prd-core']}, '
      'software-tech ${versions['software-tech']}';
}

String _read(Directory root, String relative) =>
    File.fromUri(root.uri.resolve(relative)).readAsStringSync();

/// The text of every file under [root] outside `.git`, keyed by its
/// `/`-separated path relative to [root].
Map<String, String> _bytesUnder(Directory root) {
  final prefix = '${root.path}${Platform.pathSeparator}';
  return {
    for (final entity in root.listSync(recursive: true, followLinks: false))
      if (entity is File &&
          !entity.path.startsWith('$prefix.git${Platform.pathSeparator}'))
        entity.path
            .substring(prefix.length)
            .replaceAll(Platform.pathSeparator, '/'): entity
            .readAsStringSync(),
  };
}

void main() {
  useColdHostNode();

  test('an empty folder gets six empty drafts, '
      'then the config', () async {
    final root = await writeTree({'keep.txt': 'x\n'});

    final (status, lines) = await _run(root);

    expect(status, 0);
    expect(lines, [
      'created docs/prds/PROJECT.md (draft)',
      'created docs/prds/GOAL.md (draft)',
      'created docs/prds/GLOSSARY.md (draft)',
      'created docs/prds/FEATURES.md (draft)',
      'created docs/prds/GNFR.md (draft)',
      'created docs/specs/TECH_STACK.md (draft)',
      'created .specstone/AGENT.md',
      'created AGENTS.md',
      ...skillCountLines(),
      _configLine(),
      _trustLine,
    ]);
    expect(_read(root, '.specstone/config.yaml'), _stampedConfig());
    for (final path in _draftPaths) {
      expect(_read(root, path), startsWith('---\ndraft: true\n'), reason: path);
    }
  });

  test('init lists the four groups in agent_file_groups', () async {
    final root = await writeTree({'keep.txt': 'x\n'});

    await _run(root);

    expect(ProjectConfig.read(root).agentFileGroups, [
      'claude_code',
      'shared',
      'codex_agents',
      'cursor_agents',
    ]);
  });

  test('a rerun that finds every agent file as written still stamps the '
      'config', () async {
    final root = await writeTree({'keep.txt': 'x\n'});
    await _run(root);
    File('${root.path}/.specstone/config.yaml').deleteSync();

    final (status, lines) = await _run(root);

    expect(status, 0);
    expect(lines.where((line) => line.startsWith('created .')), [
      _configLine(),
    ]);
    expect(lines, isNot(contains(_trustLine)));
    expect(_read(root, '.specstone/config.yaml'), _stampedConfig());
  });

  test('an empty folder gets .codex/hooks.json, and the Codex trust line is '
      'the last line, once', () async {
    final root = await writeTree({'keep.txt': 'x\n'});

    final (status, lines) = await _run(root);

    expect(status, 0);
    expect(_read(root, '.codex/hooks.json'), codexHooksFileText);
    expect(lines.last, _trustLine);
    expect(lines.where((line) => line == _trustLine), hasLength(1));
    expect(lines[lines.length - 2], _configLine());
    final hooksLine = lines.indexOf('created .codex/hooks.json');
    expect(hooksLine, isNonNegative);
    expect(
      lines.indexWhere((line) => line.endsWith(' files')),
      greaterThan(hooksLine),
    );
  });

  test('a rerun that changes a stale .codex/hooks.json prints the Codex trust '
      'line last, and one that changes nothing in it prints none', () async {
    final root = await writeTree({'keep.txt': 'x\n'});
    await _run(root);
    File('${root.path}/.specstone/config.yaml').deleteSync();
    File('${root.path}/.codex/hooks.json').writeAsStringSync('{}\n');

    final (_, changed) = await _run(root);
    File('${root.path}/.specstone/config.yaml').deleteSync();
    final (_, unchanged) = await _run(root);

    expect(changed, contains('updated .codex/hooks.json'));
    expect(changed.last, _trustLine);
    expect(unchanged, isNot(contains(_trustLine)));
    expect(unchanged.last, _configLine());
  });

  test(
    'an instruction file importing the missing AGENT.md ends stamped',
    () async {
      final root = await writeTree({'CLAUDE.md': _importingClaude});

      final (status, _) = await _run(root);

      expect(status, 0);
      expect(_read(root, '.specstone/config.yaml'), _stampedConfig());
    },
  );

  test('init then check reports no format_drift on the six drafts', () async {
    final root = await writeTree({'keep.txt': 'x\n'});

    final (status, _) = await _run(root);

    expect(status, 0);
    expect(spots(await checkOf(root), FindingKind.formatDrift), isEmpty);
  });

  test('an existing doc is kept and named', () async {
    final root = await writeTree({'docs/prds/PROJECT.md': '# Mine\n'});

    final (status, lines) = await _run(root);

    expect(status, 0);
    expect(lines, [
      'kept docs/prds/PROJECT.md: exists',
      'created docs/prds/GOAL.md (draft)',
      'created docs/prds/GLOSSARY.md (draft)',
      'created docs/prds/FEATURES.md (draft)',
      'created docs/prds/GNFR.md (draft)',
      'created docs/specs/TECH_STACK.md (draft)',
      'created .specstone/AGENT.md',
      'created AGENTS.md',
      ...skillCountLines(),
      _configLine(),
      _trustLine,
    ]);
    expect(_read(root, 'docs/prds/PROJECT.md'), '# Mine\n');
  });

  test('a run stopped before the config is finished by '
      'the next init', () async {
    // A full run supplies the two drafts a crash after them leaves.
    final whole = await writeTree({'keep.txt': 'x\n'});
    await _run(whole);
    final project = _read(whole, _draftPaths[0]);
    final features = _read(whole, _draftPaths[3]);
    final root = await writeTree({
      _draftPaths[0]: project,
      _draftPaths[3]: features,
    });

    final (status, lines) = await _run(root);

    expect(status, 0);
    expect(lines, [
      'kept docs/prds/PROJECT.md: exists',
      'created docs/prds/GOAL.md (draft)',
      'created docs/prds/GLOSSARY.md (draft)',
      'kept docs/prds/FEATURES.md: exists',
      'created docs/prds/GNFR.md (draft)',
      'created docs/specs/TECH_STACK.md (draft)',
      'created .specstone/AGENT.md',
      'created AGENTS.md',
      ...skillCountLines(),
      _configLine(),
      _trustLine,
    ]);
    expect(_read(root, _draftPaths[0]), project);
    expect(_read(root, _draftPaths[3]), features);
  });

  test('rerun keeps project and goal and creates glossary and the rest in '
      'order', () async {
    final whole = await writeTree({'keep.txt': 'x\n'});
    await _run(whole);
    final project = _read(whole, _draftPaths[0]);
    final goal = _read(whole, _draftPaths[1]);
    final root = await writeTree({
      _draftPaths[0]: project,
      _draftPaths[1]: goal,
    });

    final (status, lines) = await _run(root);

    expect(status, 0);
    expect(lines.take(6), [
      'kept docs/prds/PROJECT.md: exists',
      'kept docs/prds/GOAL.md: exists',
      'created docs/prds/GLOSSARY.md (draft)',
      'created docs/prds/FEATURES.md (draft)',
      'created docs/prds/GNFR.md (draft)',
      'created docs/specs/TECH_STACK.md (draft)',
    ]);
    expect(_read(root, _draftPaths[0]), project);
    expect(_read(root, _draftPaths[1]), goal);
  });

  test(
    'init writes GLOSSARY with its title and the bare Terms header',
    () async {
      final root = await writeTree({'keep.txt': 'x\n'});

      await _run(root);

      expect(
        _read(root, 'docs/prds/GLOSSARY.md'),
        allOf(
          startsWith('---\ndraft: true\n'),
          contains('\n# Domain glossary\n'),
          endsWith('\n## Terms\n'),
        ),
      );
    },
  );

  test('init writes GOAL with its three headers', () async {
    final root = await writeTree({'keep.txt': 'x\n'});

    await _run(root);

    expect(
      _read(root, 'docs/prds/GOAL.md'),
      allOf(
        startsWith('---\ndraft: true\n'),
        contains('\n# Project goals\n'),
        contains('\n## Long-term goals\n'),
        contains('\n## Mid-term goals\n'),
        contains('\n## Short-term goals\n'),
        isNot(contains('\n### ')),
      ),
    );
  });

  test('verification: '
      'init upserts each file, keeps the Owner bytes, and prints them before '
      'the config', () async {
    final root = await writeTree({
      'CLAUDE.md': "Owner's rules\n",
      'AGENTS.md':
          'before\n<!-- BEGIN specstone v0.0.1 -->\nold\n'
          '<!-- END specstone -->\nafter\n',
      '.cursor/keep': 'x',
    });

    final (status, lines) = await _run(root);

    expect(status, 0);
    final expected = [
      'created .specstone/AGENT.md',
      'updated CLAUDE.md',
      'updated AGENTS.md',
      'created .cursor/rules/specstone.mdc',
      ...skillCountLines(),
      _configLine(),
      _trustLine,
    ];
    expect(lines.sublist(lines.length - expected.length), expected);
    expect(_read(root, '.specstone/AGENT.md'), agentMdText);
    final imports = importBlock(
      cliVersion: specstoneVersion,
      agentMdPath: '.specstone/AGENT.md',
      projectDocPath: 'docs/prds/PROJECT.md',
      goalDocPath: 'docs/prds/GOAL.md',
      featuresDocPath: 'docs/prds/FEATURES.md',
    );
    expect(_read(root, 'CLAUDE.md'), "Owner's rules\n\n$imports");
    expect(
      _read(root, 'AGENTS.md'),
      'before\n${inlineBlock(cliVersion: specstoneVersion)}after\n',
    );
    expect(
      _read(root, '.cursor/rules/specstone.mdc'),
      cursorRulesText(cliVersion: specstoneVersion),
    );
  });

  test(
    'init writes every skill and agent file, prints one count line per '
    'folder before the config, and leaves the Owner skill byte-equal',
    () async {
      final root = await writeTree({
        '.claude/skills/my-skill/SKILL.md': 'mine\n',
        '.claude/skills/my-skill/notes/a.txt': 'note\n',
      });
      final before = _bytesUnder(root);

      final (status, lines) = await _run(root);

      expect(status, 0);
      final rendered = renderHostFiles();
      for (final file in rendered) {
        expect(_read(root, file.path), file.text, reason: file.path);
      }
      final after = _bytesUnder(root);
      for (final MapEntry(:key, :value) in before.entries) {
        expect(after[key], value, reason: key);
      }
      final expected = [
        'created AGENTS.md',
        ...skillCountLines(),
        _configLine(),
        _trustLine,
      ];
      expect(lines.sublist(lines.length - expected.length), expected);
      expect(lines.where((line) => line.contains('specstone-')), isEmpty);
    },
  );

  test('a root with no instruction file and no .cursor folder gets AGENTS.md '
      'and no Cursor rules file, though .cursor/agents is written', () async {
    final root = await writeTree({'keep.txt': 'x\n'});

    final (status, lines) = await _run(root);

    expect(status, 0);
    expect(File('${root.path}/AGENTS.md').existsSync(), isTrue);
    expect(
      File('${root.path}/.cursor/rules/specstone.mdc').existsSync(),
      isFalse,
    );
    expect(Directory('${root.path}/.cursor/agents').existsSync(), isTrue);
    expect(lines, contains(startsWith('created .cursor/agents: ')));
    expect(lines, isNot(contains(contains('specstone.mdc'))));
  });

  test(
    'a .claude folder linked outside the project is named and left, the '
    'other folders are written, and the folder outside keeps its bytes',
    () async {
      final base = await writeTree({'outside/keep.txt': 'mine\n'});
      final project = Directory('${base.path}/proj')..createSync();
      Link('${project.path}/.claude').createSync('../outside');
      final warnings = <String>[];
      final before = _bytesUnder(Directory('${base.path}/outside'));

      final (status, lines) = await _run(project, warnings: warnings);

      expect(status, 0);
      expect(warnings, [
        '.claude reaches outside the project root; left as it is',
      ]);
      expect(_bytesUnder(Directory('${base.path}/outside')), before);
      expect(lines, isNot(contains(startsWith('created .claude/'))));
      expect(lines, contains(startsWith('created .agents/skills: ')));
    },
    skip: Platform.isWindows ? 'symbolic links need a privilege' : null,
  );

  test('a .cursor file that is no folder is named and left, and init still '
      'writes the other folders and the config', () async {
    final root = await writeTree({'.cursor': 'mine\n'});
    final warnings = <String>[];

    final (status, lines) = await _run(root, warnings: warnings);

    expect(status, 0);
    expect(warnings, ['.cursor is not a folder; left as it is']);
    expect(File('${root.path}/.cursor').readAsStringSync(), 'mine\n');
    expect(lines, isNot(contains(startsWith('created .cursor/'))));
    expect(lines, contains(startsWith('created .claude/skills: ')));
    expect(File('${root.path}/.specstone/config.yaml').existsSync(), isTrue);
  });

  test('a rerun after a stop before the config writes no skill or agent file '
      'and prints no count line', () async {
    final root = await writeTree({'keep.txt': 'x\n'});
    await _run(root);
    File('${root.path}/.specstone/config.yaml').deleteSync();
    final before = _bytesUnder(root)..remove('.specstone/config.yaml');

    final (status, lines) = await _run(root);

    expect(status, 0);
    expect(lines, isNot(contains(matches(RegExp(r'^created .*: \d+ files$')))));
    expect(_bytesUnder(root)..remove('.specstone/config.yaml'), before);
  });

  test('a rerun after a stop writes no Cursor rules file when the root had no '
      '.cursor folder before the first run', () async {
    final root = await writeTree({'keep.txt': 'x\n'});
    await _run(root);
    File('${root.path}/.specstone/config.yaml').deleteSync();

    await _run(root);

    expect(
      File('${root.path}/.cursor/rules/specstone.mdc').existsSync(),
      isFalse,
    );
  });

  test('a root that holds .cursor/keep gets the Cursor rules file on the first '
      'run, and a rerun leaves it', () async {
    final root = await writeTree({'.cursor/keep': 'x'});
    await _run(root);
    expect(
      File('${root.path}/.cursor/rules/specstone.mdc').existsSync(),
      isTrue,
    );
    File('${root.path}/.specstone/config.yaml').deleteSync();
    final before = _bytesUnder(root)..remove('.specstone/config.yaml');

    await _run(root);

    expect(_bytesUnder(root)..remove('.specstone/config.yaml'), before);
  });

  test(
    'an agent of the Owner in .cursor/agents counts as a .cursor folder',
    () async {
      final root = await writeTree({'.cursor/agents/my-agent.md': 'mine\n'});

      final (_, lines) = await _run(root);

      expect(
        File('${root.path}/.cursor/rules/specstone.mdc').existsSync(),
        isTrue,
      );
      expect(File('${root.path}/AGENTS.md').existsSync(), isFalse);
      expect(lines, contains('created .cursor/rules/specstone.mdc'));
    },
  );

  test('a '
      'malformed file refuses before any write', () async {
    final root = await writeTree({
      'CLAUDE.md': '<!-- BEGIN specstone v1.0.0 -->\nno end\n',
    });
    final before = _bytesUnder(root);

    await expectLater(
      () => _run(root),
      throwsA(
        isA<MigrateFault>()
            .having((f) => f.code, 'code', MigrateFaultCode.agentBlockMalformed)
            .having((f) => f.exitStatus, 'exitStatus', 65)
            .having((f) => f.file, 'file', 'CLAUDE.md')
            .having((f) => f.line, 'line', 1),
      ),
    );
    expect(_bytesUnder(root), before);
  });

  test(
    'a rerun '
    'after a stop before the config changes 0 bytes of the agent files',
    () async {
      final root = await writeTree({'CLAUDE.md': "Owner's rules\n"});
      await _run(root);
      File.fromUri(root.uri.resolve('.specstone/config.yaml')).deleteSync();
      final before = _bytesUnder(root)..remove('.specstone/config.yaml');

      final (status, lines) = await _run(root);

      expect(status, 0);
      expect(lines.where((line) => line.contains('AGENT')), isEmpty);
      expect(lines.last, _configLine());
      expect(lines, isNot(contains(_trustLine)));
      expect(_bytesUnder(root)..remove('.specstone/config.yaml'), before);
    },
  );

  test(
    'a symbolic link CLAUDE.md stays a link and its target takes the block',
    () async {
      final root = await writeTree({'shared/rules.md': 'shared\n'});
      try {
        createRelativeLink('${root.path}/CLAUDE.md', 'shared/rules.md');
      } on FileSystemException {
        markTestSkipped('symbolic links are not available');
        return;
      }

      final (status, _) = await _run(root);

      expect(status, 0);
      expect(
        FileSystemEntity.typeSync('${root.path}/CLAUDE.md', followLinks: false),
        FileSystemEntityType.link,
      );
      expect(_read(root, 'shared/rules.md'), startsWith('shared\n'));
      expect(_read(root, 'shared/rules.md'), contains('@.specstone/AGENT.md'));
    },
  );

  test('a repository '
      'top inside the project that a code entry reaches is upserted, printed, '
      'and listed in the config', () async {
    final base = await writeTree({
      'project/docs/specs/TECH_STACK.md':
          '---\ncode:\n  - other/\n---\n# Tech stack\n',
      'project/other/.git/HEAD': 'ref\n',
      'project/other/AGENTS.md': 'Owner\n',
    });
    final project = Directory('${base.path}/project');

    final (status, lines) = await _run(project);

    expect(status, 0);
    final topLine = lines.indexOf('updated other/AGENTS.md');
    expect(topLine, isNonNegative);
    expect(lines.indexOf(_configLine()), greaterThan(topLine));
    expect(
      File('${base.path}/project/other/AGENTS.md').readAsStringSync(),
      'Owner\n\n${inlineBlock(cliVersion: specstoneVersion)}',
    );
    expect(
      _read(project, '.specstone/config.yaml'),
      contains('agent_file_roots:\n  - other\n'),
    );
  });

  test('a '
      'repository top outside the project root is named, never written, and '
      'not listed', () async {
    final base = await writeTree({
      'project/docs/specs/TECH_STACK.md':
          '---\ncode:\n  - ../other/\n---\n# Tech stack\n',
      'other/.git/HEAD': 'ref\n',
      'other/AGENTS.md': 'Owner\n',
    });
    final project = Directory('${base.path}/project');
    final warnings = <String>[];

    final (status, lines) = await _run(project, warnings: warnings);

    expect(status, 0);
    expect(warnings, [
      '../other/AGENTS.md reaches outside the project root; left as it is',
      '../other reaches outside the project root; left as it is',
    ]);
    expect(lines, isNot(contains(contains('other'))));
    expect(File('${base.path}/other/AGENTS.md').readAsStringSync(), 'Owner\n');
    expect(
      _read(project, '.specstone/config.yaml'),
      isNot(contains('agent_file_roots')),
    );
  });

  group('a link that '
      'leads out of the write bounds', () {
    final skipLinks = Platform.isWindows
        ? 'symbolic links need a privilege'
        : null;

    test('a linked .specstone/AGENT.md leading outside the project is named '
        'and left, and the file outside keeps its bytes', () async {
      final base = await writeTree({
        'victim.txt': 'mine\n',
        'proj/.specstone/keep.txt': '',
      });
      Link('${base.path}/proj/.specstone/AGENT.md')
          .createSync('../../victim.txt');
      final warnings = <String>[];

      final (status, lines) = await _run(
        Directory('${base.path}/proj'),
        warnings: warnings,
      );

      expect(status, 0);
      expect(warnings, [
        '.specstone/AGENT.md reaches outside the project root; left as it is',
      ]);
      expect(lines, isNot(contains(contains('AGENT.md'))));
      expect(File('${base.path}/victim.txt').readAsStringSync(), 'mine\n');
    }, skip: skipLinks);

    test('a CLAUDE.md linked into .git is named and left, and .git/config '
        'keeps its bytes', () async {
      final base = await writeTree({
        'proj/.git/config': '[core]\n\tbare = false\n',
        'proj/keep.txt': '',
      });
      Link('${base.path}/proj/CLAUDE.md').createSync('.git/config');
      final warnings = <String>[];

      final (status, lines) = await _run(
        Directory('${base.path}/proj'),
        warnings: warnings,
      );

      expect(status, 0);
      expect(warnings, ['CLAUDE.md lies under .git; left as it is']);
      expect(lines, isNot(contains('updated CLAUDE.md')));
      expect(
        File('${base.path}/proj/.git/config').readAsStringSync(),
        '[core]\n\tbare = false\n',
      );
    }, skip: skipLinks);

    test('a dangling AGENTS.md link refuses output_not_writable, not a raw '
        'exception', () async {
      final base = await writeTree({'proj/keep.txt': ''});
      Link('${base.path}/proj/AGENTS.md').createSync('missing.md');

      await expectLater(
        () => _run(Directory('${base.path}/proj')),
        throwsA(
          isA<RenderFault>()
              .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
              .having((f) => f.exitStatus, 'exit', 73)
              .having((f) => f.message, 'message', startsWith('cannot write')),
        ),
      );

      expect(File('${base.path}/proj/missing.md').existsSync(), isFalse);
    }, skip: skipLinks);

    test('a dangling AGENTS.md link refuses naming the file, and nothing is '
        'created through the link', () async {
      final base = await writeTree({'proj/keep.txt': ''});
      Link('${base.path}/proj/AGENTS.md').createSync('missing.md');

      await expectLater(
        () => _run(Directory('${base.path}/proj')),
        throwsA(
          isA<RenderFault>()
              .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
              .having((f) => f.exitStatus, 'exit', 73)
              .having(
                (f) => f.message,
                'message',
                startsWith('cannot write AGENTS.md: '),
              ),
        ),
      );

      expect(File('${base.path}/proj/missing.md').existsSync(), isFalse);
      expect(
        File('${base.path}/proj/.specstone/config.yaml').existsSync(),
        isFalse,
      );
    }, skip: skipLinks);

    test('a draft that is a link leading outside refuses with the link path, '
        'the drafts before it stay, and a rerun once the link is gone '
        'finishes', () async {
      final base = await writeTree({'proj/keep.txt': '', 'outside/x': ''});
      final proj = Directory('${base.path}/proj');
      Directory('${proj.path}/docs/prds').createSync(recursive: true);
      final link = Link('${proj.path}/docs/prds/GLOSSARY.md')
        ..createSync('../../../outside/g.md');

      await expectLater(
        () => _run(proj),
        throwsA(
          isA<RenderFault>()
              .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
              .having((f) => f.exitStatus, 'exit', 73)
              .having((f) => f.file, 'file', 'docs/prds/GLOSSARY.md')
              .having(
                (f) => f.message,
                'message',
                'cannot write docs/prds/GLOSSARY.md: it leads outside the project',
              ),
        ),
      );

      expect(File('${base.path}/outside/g.md').existsSync(), isFalse);
      expect(File('${proj.path}/docs/prds/PROJECT.md').existsSync(), isTrue);
      expect(File('${proj.path}/.specstone/config.yaml').existsSync(), isFalse);

      link.deleteSync();
      final (status, lines) = await _run(proj);

      expect(status, 0);
      expect(lines, contains('kept docs/prds/PROJECT.md: exists'));
      expect(File('${proj.path}/docs/prds/GLOSSARY.md').existsSync(), isTrue);
      expect(File('${proj.path}/.specstone/config.yaml').existsSync(), isTrue);
    }, skip: skipLinks);

    test('a .specstone/config.yaml that is a link leading outside refuses '
        'with its path after the drafts, and a rerun finishes', () async {
      final base = await writeTree({'proj/keep.txt': '', 'outside/x': ''});
      final proj = Directory('${base.path}/proj');
      Directory('${proj.path}/.specstone').createSync();
      final link = Link('${proj.path}/.specstone/config.yaml')
        ..createSync('../../outside/c.yaml');

      await expectLater(
        () => _run(proj),
        throwsA(
          isA<RenderFault>()
              .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
              .having((f) => f.exitStatus, 'exit', 73)
              .having((f) => f.file, 'file', '.specstone/config.yaml')
              .having(
                (f) => f.message,
                'message',
                'cannot write .specstone/config.yaml: it leads outside the project',
              ),
        ),
      );

      expect(File('${base.path}/outside/c.yaml').existsSync(), isFalse);
      expect(File('${proj.path}/docs/prds/PROJECT.md').existsSync(), isTrue);

      link.deleteSync();
      final (status, _) = await _run(proj);

      expect(status, 0);
      expect(File('${proj.path}/.specstone/config.yaml').existsSync(), isTrue);
    }, skip: skipLinks);

    test('a docs folder linked outside the project refuses a draft written '
        'through it, and the folder outside is unchanged', () async {
      final base = await writeTree({
        'outside/keep.txt': 'mine\n',
        'proj/docs/keep.md': '',
      });
      Link('${base.path}/proj/docs/prds').createSync('../../outside');

      await expectLater(
        () => _run(Directory('${base.path}/proj')),
        throwsA(
          isA<RenderFault>()
              .having((f) => f.exitStatus, 'exit', 73)
              .having((f) => f.file, 'file', isNotNull),
        ),
      );

      expect(
        Directory('${base.path}/outside')
            .listSync()
            .map((e) => e.uri.pathSegments.lastWhere((s) => s.isNotEmpty)),
        ['keep.txt'],
      );
    }, skip: skipLinks);
  });

  test('a repository '
      'top folder named with a # gets its agent file at that folder, not at '
      'a URI fragment', () async {
    final base = await writeTree({
      'project/docs/specs/TECH_STACK.md':
          '---\ncode:\n  - other#1/\n---\n# Tech stack\n',
      'project/other#1/.git/HEAD': 'ref\n',
    });
    final project = Directory('${base.path}/project');

    final (status, _) = await _run(project);

    expect(status, 0);
    expect(File('${base.path}/project/other#1/AGENTS.md').existsSync(), isTrue);
  });

  for (final (:real, :link) in [
    (real: 'AGENTS.md', link: 'CLAUDE.md'),
    (real: 'CLAUDE.md', link: 'AGENTS.md'),
  ]) {
    test('$link '
        'linked to $real takes the inline block and prints one line', () async {
      final root = await writeTree({real: 'Owner\n'});
      try {
        createRelativeLink('${root.path}/$link', real);
      } on FileSystemException {
        markTestSkipped('symbolic links are not available');
        return;
      }

      final (status, lines) = await _run(root);

      expect(status, 0);
      expect(
        _read(root, real),
        'Owner\n\n${inlineBlock(cliVersion: specstoneVersion)}',
      );
      expect(FileSystemEntity.isLinkSync('${root.path}/$link'), isTrue);
      expect(
        lines.where((l) => l.endsWith('CLAUDE.md') || l.endsWith('AGENTS.md')),
        hasLength(1),
      );
    });
  }

  test('init writes no .gitignore and '
      'no templates folder', () async {
    final root = await writeTree({'keep.txt': 'x\n'});

    final (status, _) = await _run(root);

    expect(status, 0);
    expect(File('${root.path}/.specstone/.gitignore').existsSync(), isFalse);
    expect(
      Directory('${root.path}/.specstone/templates').existsSync(),
      isFalse,
    );
  });

  test('init leaves a root .gitignore as it was, adds no entry for the index '
      'or the build output, and makes none when there was none', () async {
    final kept = await writeTree({'.gitignore': 'node_modules/\n'});
    final none = await writeTree({'keep.txt': 'x\n'});

    expect((await _run(kept)).$1, 0);
    expect((await _run(none)).$1, 0);

    expect(_read(kept, '.gitignore'), 'node_modules/\n');
    expect(File('${none.path}/.gitignore').existsSync(), isFalse);
  });

  test('init leaves .specstone/.gitignore to the first index, which writes its '
      'lines there and no root entry', () async {
    final root = await writeTree({'keep.txt': 'x\n'});
    expect((await _run(root)).$1, 0);
    expect(File('${root.path}/.specstone/.gitignore').existsSync(), isFalse);

    openSession(root).close();

    expect(
      _read(root, '.specstone/.gitignore').trimRight().split('\n'),
      containsAll(['index.sqlite*', 'build/']),
    );
    expect(File('${root.path}/.gitignore').existsSync(), isFalse);
  });

  test('each draft holds every required field empty and '
      'every required section, nothing else', () async {
    final root = await writeTree({'keep.txt': 'x\n'});
    final set = TemplateResolver().resolveCarried(
      packNames: const ['prd-core', 'software-tech'],
      homeDirectory: testHome(),
    );

    await _run(root);

    for (final docType in set.docTypes) {
      final path = 'docs/${docType.path}';
      if (!_draftPaths.contains(path)) continue;
      expect(
        _read(root, path),
        skeletonOf(docType, docType.title ?? docType.id),
        reason: path,
      );
    }
  });

  test('init makes no commit', () async {
    final root = await gitFixture({'keep.txt': 'x\n'});
    final headBefore = git(root, ['rev-parse', 'HEAD']).stdout as String;

    final (status, _) = await _run(root);

    expect(status, 0);
    expect(git(root, ['rev-parse', 'HEAD']).stdout as String, headBefore);
    final untracked =
        git(root, ['ls-files', '--others', '--exclude-standard']).stdout
            as String;
    expect(untracked, contains('docs/prds/PROJECT.md'));
  }, skip: hasGit ? null : 'git is not available');

  test('a configured folder refuses '
      'config_exists and writes nothing', () async {
    for (final legacy in [null, acmeLegacy]) {
      final root = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(),
        ...?legacy,
      });
      final before = _bytesUnder(root);

      await expectLater(
        () => _run(root),
        throwsA(
          isA<MigrateFault>()
              .having((f) => f.code, 'code', MigrateFaultCode.configExists)
              .having((f) => f.exitStatus, 'exitStatus', 64)
              .having((f) => f.file, 'file', '.specstone/config.yaml')
              .having(
                (f) => f.message,
                'message',
                'this folder is already a Specstone project; run specstone '
                    'migrate to upgrade its packs',
              ),
        ),
      );
      expect(_bytesUnder(root), before);
    }
  });

  test('a folder holding an old context doc and no config gets the six '
      'drafts and the config, and the doc stays', () async {
    final root = await writeTree(acmeLegacy);

    final (status, lines) = await _run(root);

    expect(status, 0);
    expect(lines, contains(_configLine()));
    expect(_read(root, '.specstone/config.yaml'), _stampedConfig());
    expect(
      File('${root.path}/docs/prds/d01_context.md').existsSync(),
      isTrue,
      reason: 'the old context doc stays as the Owner left it',
    );
  });

  test('a folder that refuses writes is '
      'output_not_writable naming the path', () async {
    final root = await writeTree({'keep.txt': 'x\n'});
    expect(Process.runSync('chmod', ['555', root.path]).exitCode, 0);
    addTearDown(() => Process.runSync('chmod', ['755', root.path]));

    await expectLater(
      () => _run(root),
      throwsA(
        isA<RenderFault>()
            .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
            .having(
              (f) => f.message,
              'message',
              startsWith('cannot write docs/prds/PROJECT.md: '),
            ),
      ),
    );
  }, skip: unreadablePathSkipReason());

  test('a folder inside another project becomes its own '
      'project', () async {
    final outer = await writeTree({
      '.specstone/config.yaml': shippedPinsConfig(),
      'docs/prds/PROJECT.md': '# Outer\n',
      'app/keep.txt': 'x\n',
    });
    final inner = Directory.fromUri(outer.uri.resolve('app'));

    final (status, lines) = await _run(inner);

    expect(status, 0);
    expect(lines[lines.length - 2], _configLine());
    expect(lines.last, _trustLine);
    expect(
      File.fromUri(outer.uri.resolve('.specstone/config.yaml'))
          .readAsStringSync(),
      shippedPinsConfig(),
    );
    expect(
      File.fromUri(inner.uri.resolve('.specstone/config.yaml')).existsSync(),
      isTrue,
    );
  });

  test('a docs link puts the config beside the real docs '
      'folder', () async {
    final tree = await writeTree({
      'docsrepo/docs/keep.txt': 'x\n',
      'repo/code/keep.txt': 'x\n',
    });
    try {
      createRelativeLink('${tree.path}/repo/code/docs', '../../docsrepo/docs');
    } on FileSystemException {
      markTestSkipped('symbolic links need privileges on this machine');
      return;
    }
    final code = Directory('${tree.path}/repo/code');
    locateSetupTrust(code, homeDirectory: testHome()).record();

    final (status, lines) = await _run(code);

    expect(status, 0);
    expect(lines[lines.length - 2], _configLine());
    expect(lines.last, _trustLine);
    expect(
      File('${tree.path}/docsrepo/.specstone/config.yaml').existsSync(),
      isTrue,
    );
    expect(
      Directory('${tree.path}/repo/code/.specstone').existsSync(),
      isFalse,
    );
  });
}
