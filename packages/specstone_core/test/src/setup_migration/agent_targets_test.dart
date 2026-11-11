import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/setup_migration/agent_files.dart';
import 'package:specstone_core/src/setup_migration/agent_targets.dart';
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:specstone_core/src/version.dart';
import 'package:test/test.dart';

import '../../helpers/shipped_pins.dart';
import '../../helpers/temp_tree.dart';

const _write = 'setup_migration/set_up_new_project/write_agent_files';
const _stale =
    'consistency_check/find_template_breaks/report_stale_agent_blocks';
const _agentMd = '.specstone/AGENT.md';
const _cursor = '.cursor/rules/specstone.mdc';
const _gitFile = 'gitdir: ../elsewhere/.git/worktrees/w\n';

/// The base folder of a fixture, canonical so paths compare on every platform.
///
/// Project files go under `proj/`; a second repository sits at `other/`.
Future<Directory> _base(Map<String, String> files) async {
  final base = await writeTree(files);
  return Directory(base.resolveSymbolicLinksSync());
}

Directory _at(Directory base, String path) => Directory(
  Directory.fromUri(base.uri.resolve(path)).path
      .replaceAll(RegExp(r'[\\/]$'), ''),
);

AgentFileInputs _inputs(
  Directory base, {
  List<String> code = const [],
  List<String> roots = const [],
  String cliVersion = specstoneVersion,
}) => AgentFileInputs(
  projectRoot: _at(base, 'proj/'),
  cliVersion: cliVersion,
  codeRootFolders: [for (final folder in code) _at(base, folder)],
  agentFileRoots: roots,
);

String _imports(String prefix) => importBlock(
  cliVersion: specstoneVersion,
  agentMdPath: '$prefix.specstone/AGENT.md',
  projectDocPath: '${prefix}docs/prds/PROJECT.md',
);

String _inline() => inlineBlock(cliVersion: specstoneVersion);

AgentWrite _writeAt(AgentWritePlan plan, String path) => [
  ...plan.rootWrites,
  ...plan.topWrites,
].singleWhere((write) => write.path == path);

List<String> _paths(AgentWritePlan plan) => [
  for (final write in [...plan.rootWrites, ...plan.topWrites]) write.path,
];

void _apply(Directory base, AgentWritePlan plan) {
  for (final write in [...plan.rootWrites, ...plan.topWrites]) {
    final file = File.fromUri(_at(base, 'proj/').uri.resolve(write.path));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(utf8.encode(write.text));
  }
}

void main() {
  group('agentFilesSince', () {
    test('$_write: prd-core 1.7.0 and software-tech 1.4.0', () {
      expect(
        agentFilesSince.keys,
        unorderedEquals(['prd-core', 'software-tech']),
      );
      expect(
        agentFilesSince['prd-core'],
        PackVersion.parse('1.7.0', file: 'x', key: 'x'),
      );
      expect(
        agentFilesSince['software-tech'],
        PackVersion.parse('1.4.0', file: 'x', key: 'x'),
      );
    });
  });

  group('repositoryTopOf', () {
    test(
      '$_write E16: the nearest folder above holding a .git folder',
      () async {
        final base = await _base({
          'other/.git/HEAD': 'ref\n',
          'other/lib/src/a.dart': '',
        });

        expect(
          repositoryTopOf(_at(base, 'other/lib/src/'))?.path,
          _at(base, 'other/').resolveSymbolicLinksSync(),
        );
        expect(
          repositoryTopOf(_at(base, 'other/'))?.path,
          _at(base, 'other/').resolveSymbolicLinksSync(),
        );
      },
    );

    test(
      '$_write E16: a .git file, as a worktree holds, marks the top',
      () async {
        final base = await _base({
          'other/.git': _gitFile,
          'other/lib/a.dart': '',
        });

        expect(
          repositoryTopOf(_at(base, 'other/lib/'))?.path,
          _at(base, 'other/').path,
        );
      },
    );

    test('$_write E16: a folder inside no repository has no top', () async {
      final base = await _base({'free/lib/a.dart': ''});

      expect(repositoryTopOf(_at(base, 'free/lib/')), isNull);
    });

    test(
      '$_write E16: a folder that is missing walks up from its parent',
      () async {
        final base = await _base({'other/.git/HEAD': 'ref\n'});

        expect(
          repositoryTopOf(_at(base, 'other/not/there/'))?.path,
          _at(base, 'other/').path,
        );
      },
    );
  });

  group('AgentWritePlan.writeSet', () {
    test('$_write E15: the canonical path of each write the plan lists, all '
        'inside the project root, and none of a top outside it', () async {
      final base = await _base({
        'proj/vendor/.git/HEAD': 'ref\n',
        'proj/vendor/lib/a': '',
        'other/.git/HEAD': 'ref\n',
        'other/lib/a': '',
      });

      final plan = planAgentWrites(
        _inputs(base, code: ['proj/vendor/lib/', 'other/lib/']),
        full: true,
      );

      expect(plan.writeSet, {
        File.fromUri(_at(base, 'proj/').uri.resolve(_agentMd)).path,
        File.fromUri(_at(base, 'proj/').uri.resolve('AGENTS.md')).path,
        File.fromUri(_at(base, 'proj/vendor/').uri.resolve('AGENTS.md')).path,
      });
    });
  });

  group('codeRootFolders', () {
    test('$_write E15: the code root and each entry under it, once', () async {
      final base = await _base({'proj/lib/a.dart': ''});

      final folders = codeRootFolders(
        _at(base, 'proj/'),
        codeRoot: '.',
        codeEntries: ['lib/', 'lib', 'apps/web/'],
      );

      expect(
        [for (final folder in folders) folder.path],
        [
          _at(base, 'proj/').path,
          _at(base, 'proj/lib/').path,
          _at(base, 'proj/apps/web/').path,
        ],
      );
    });

    test('$_write E15: an entry that is no relative / path names no folder, '
        'so a drive letter does not throw and a backslash does not climb '
        'out of the project', () async {
      final base = await _base({'proj/lib/a.dart': '', 'shared/a.dart': ''});

      final folders = codeRootFolders(
        _at(base, 'proj/'),
        codeRoot: '.',
        codeEntries: [r'..\shared\', 'C:/x/', '/abs/', 'lib ', 'lib/'],
      );

      expect(
        [for (final folder in folders) folder.path],
        [_at(base, 'proj/').path, _at(base, 'proj/lib/').path],
      );
    });

    test(
      '$_write E15: a code root outside the project reads from there',
      () async {
        final base = await _base({'other/lib/a.dart': ''});

        final folders = codeRootFolders(
          _at(base, 'proj/'),
          codeRoot: '../other',
          codeEntries: ['lib/'],
        );

        expect(
          [for (final folder in folders) folder.path],
          [_at(base, 'other/').path, _at(base, 'other/lib/').path],
        );
      },
    );
  });

  group('codeEntriesOnDisk', () {
    test(
      '$_write E15: the code entries of each doc whose type holds code',
      () async {
        final base = await _base({
          'proj/.specstone/config.yaml': shippedPinsConfig(),
          'proj/docs/specs/TECH_STACK.md':
              '---\ncode:\n  - lib/\n  - ../other/lib/\n---\n# Tech stack\n',
          'proj/docs/prds/PROJECT.md': '---\ncode:\n  - ignored/\n---\n# P\n',
        });
        final set = TemplateResolver().resolve(
          workingDirectory: _at(base, 'proj/'),
          homeDirectory: null,
        );

        expect(codeEntriesOnDisk(_at(base, 'proj/'), set), [
          'lib/',
          '../other/lib/',
        ]);
      },
    );

    test(
      '$_write E15: a project without a docs folder has no entries',
      () async {
        final base = await _base({
          'proj/.specstone/config.yaml': shippedPinsConfig(),
        });
        final set = TemplateResolver().resolve(
          workingDirectory: _at(base, 'proj/'),
          homeDirectory: null,
        );

        expect(codeEntriesOnDisk(_at(base, 'proj/'), set), isEmpty);
      },
    );
  });

  group('planAgentWrites', () {
    test('$_write E01: an empty root gets AGENT.md and AGENTS.md', () async {
      final base = await _base({'proj/.keep': ''});

      final plan = planAgentWrites(_inputs(base), full: true);

      expect(_paths(plan), [_agentMd, 'AGENTS.md']);
      expect(_writeAt(plan, _agentMd).text, agentMdText);
      expect(_writeAt(plan, _agentMd).isNew, isTrue);
      expect(_writeAt(plan, 'AGENTS.md').text, _inline());
      expect(_writeAt(plan, 'AGENTS.md').isAtTop, isFalse);
      expect(plan.topWrites, isEmpty);
      expect(plan.agentFileRoots, isEmpty);
      expect(plan.line, 'agent files: .specstone/AGENT.md, AGENTS.md');
    });

    test('$_write E02: a block is appended and the Owner text stays', () async {
      final base = await _base({'proj/CLAUDE.md': 'Owner text\n'});

      final plan = planAgentWrites(_inputs(base), full: true);

      expect(_writeAt(plan, 'CLAUDE.md').text, 'Owner text\n${_imports('')}');
      expect(_writeAt(plan, 'CLAUDE.md').isNew, isFalse);
      expect(_paths(plan), isNot(contains('AGENTS.md')));
    });

    test(
      '$_write E03: a block with another body is replaced in place',
      () async {
        const old =
            '<!-- BEGIN specstone v0.0.1 -->\nold\n<!-- END specstone -->\n';
        final base = await _base({'proj/AGENTS.md': 'before\n${old}after\n'});

        final plan = planAgentWrites(_inputs(base), full: false);

        expect(_writeAt(plan, 'AGENTS.md').text, 'before\n${_inline()}after\n');
      },
    );

    test('$_write E04: a block that matches writes 0 bytes whatever its '
        'version', () async {
      final older = _inline().replaceFirst(specstoneVersion, '0.0.1');
      final base = await _base({
        'proj/AGENTS.md': older,
        'proj/.specstone/AGENT.md': agentMdText,
      });

      for (final full in [true, false]) {
        final plan = planAgentWrites(_inputs(base), full: full);

        expect(plan.isEmpty, isTrue, reason: 'full: $full');
        expect(plan.line, isEmpty);
      }
    });

    test('$_write E04: files a pre-release CLI wrote plan no write for the '
        'next pre-release', () async {
      const first = '1.2.0-beta.1';
      const next = '1.2.0-beta.2';
      final base = await _base({
        'proj/CLAUDE.md': 'Owner\n',
        'proj/AGENTS.md': 'Owner\n',
        'proj/.github/copilot-instructions.md': 'Owner\n',
        'proj/.cursor/x.json': '{}',
      });
      _apply(
        base,
        planAgentWrites(_inputs(base, cliVersion: first), full: true),
      );
      final written = File.fromUri(_at(base, 'proj/').uri.resolve(_cursor))
          .readAsStringSync();

      expect(written, contains('<!-- BEGIN specstone v$first -->'));
      for (final full in [true, false]) {
        final plan = planAgentWrites(
          _inputs(base, cliVersion: next),
          full: full,
        );

        expect(_paths(plan), isEmpty, reason: 'full: $full');
        expect(plan.isEmpty, isTrue, reason: 'full: $full');
      }
    });

    test('$_write E03: a block body an older CLI wrote is replaced, the BEGIN '
        'line naming the pre-release', () async {
      const old =
          '<!-- BEGIN specstone v1.2.0-beta.1 -->\n'
          'old\n<!-- END specstone -->\n';
      final base = await _base({'proj/AGENTS.md': 'before\n${old}after\n'});

      final plan = planAgentWrites(
        _inputs(base, cliVersion: '1.2.0-beta.2'),
        full: false,
      );

      expect(
        _writeAt(plan, 'AGENTS.md').text,
        'before\n${inlineBlock(cliVersion: '1.2.0-beta.2')}after\n',
      );
    });

    test(
      '$_write E13: a .cursor rules file whose BEGIN line holds build '
      'metadata is never up to date; one naming another pre-release is',
      () async {
        const version = '1.2.0-beta.1';
        final rules = cursorRulesText(cliVersion: version);
        final withBuild = await _base({
          'proj/$_cursor': rules.replaceFirst('v$version', 'v1.2.0+build.5'),
          'proj/.specstone/AGENT.md': agentMdText,
        });
        final withOther = await _base({
          'proj/$_cursor': rules.replaceFirst('v$version', 'v1.2.0-beta.7'),
          'proj/.specstone/AGENT.md': agentMdText,
        });

        expect(
          () => planAgentWrites(
            _inputs(withBuild, cliVersion: version),
            full: false,
          ),
          throwsA(
            isA<MigrateFault>()
                .having(
                  (f) => f.code,
                  'code',
                  MigrateFaultCode.agentBlockMalformed,
                )
                .having((f) => f.file, 'file', _cursor),
          ),
        );
        expect(
          planAgentWrites(
            _inputs(withOther, cliVersion: version),
            full: false,
          ).isEmpty,
          isTrue,
        );
      },
    );

    test('$_write E06: AGENT.md with other bytes is rewritten', () async {
      final base = await _base({
        'proj/.specstone/AGENT.md': 'hand edit\n',
        'proj/AGENTS.md': _inline(),
      });

      final plan = planAgentWrites(_inputs(base), full: false);

      expect(_paths(plan), [_agentMd]);
      expect(_writeAt(plan, _agentMd).isNew, isFalse);
    });

    test(
      '$_write E07: a .cursor folder gets the rules file, not AGENTS.md',
      () async {
        final base = await _base({'proj/.cursor/x.json': '{}'});

        final plan = planAgentWrites(_inputs(base), full: true);

        expect(_paths(plan), [_agentMd, _cursor]);
        expect(
          _writeAt(plan, _cursor).text,
          cursorRulesText(cliVersion: specstoneVersion),
        );
        expect(_writeAt(plan, _cursor).isNew, isTrue);
      },
    );

    test(
      '$_write: a .cursor file is no .cursor folder; AGENTS.md is made',
      () async {
        final base = await _base({'proj/.cursor': 'not a folder'});

        final plan = planAgentWrites(_inputs(base), full: true);

        expect(_paths(plan), [_agentMd, 'AGENTS.md']);
      },
    );

    test('$_write E21: a .cursor rules file differing in frontmatter only is '
        'rewritten whole', () async {
      final base = await _base({
        'proj/$_cursor': cursorRulesText(cliVersion: specstoneVersion)
            .replaceFirst('alwaysApply: true', 'alwaysApply: false'),
        'proj/.specstone/AGENT.md': agentMdText,
      });

      final plan = planAgentWrites(_inputs(base), full: false);

      expect(
        _writeAt(plan, _cursor).text,
        cursorRulesText(cliVersion: specstoneVersion),
      );
    });

    test('$_write E14: CRLF and a byte order mark stay', () async {
      const crlf = 'Owner\r\ntext\r\n';
      final base = await _base({'proj/CLAUDE.md': '﻿$crlf'});

      final plan = planAgentWrites(_inputs(base), full: true);

      expect(
        _writeAt(plan, 'CLAUDE.md').text,
        '﻿$crlf${_imports('').replaceAll('\n', '\r\n')}',
      );
    });

    test('$_write E13: a marker inside the Owner fence is no marker', () async {
      const fenced = '```\n<!-- BEGIN specstone v1.0.0 -->\n```\n';
      final base = await _base({'proj/CLAUDE.md': fenced});

      final plan = planAgentWrites(_inputs(base), full: true);

      expect(_writeAt(plan, 'CLAUDE.md').text, '$fenced${_imports('')}');
    });

    test('$_write E05: a malformed file refuses the plan, naming every '
        'malformed file with its first marker line', () async {
      final base = await _base({
        'proj/CLAUDE.md': 'x\n<!-- BEGIN specstone v1.0.0 -->\nbody\n',
        'proj/AGENTS.md': '<!-- END specstone -->\n',
        'proj/GEMINI.md': 'fine\n',
      });

      for (final full in [true, false]) {
        expect(
          () => planAgentWrites(_inputs(base), full: full),
          throwsA(
            isA<MigrateFault>()
                .having(
                  (f) => f.code,
                  'code',
                  MigrateFaultCode.agentBlockMalformed,
                )
                .having((f) => f.file, 'file', 'CLAUDE.md')
                .having((f) => f.line, 'line', 2)
                .having((f) => f.more.single.file, 'second file', 'AGENTS.md')
                .having((f) => f.more.single.line, 'second line', 1)
                .having((f) => f.exitStatus, 'exit', 65),
          ),
        );
      }
    });

    test(
      '$_write R56: an unclosed fence names closing it as its own fix',
      () async {
        final base = await _base({
          'proj/CLAUDE.md': 'x\n```\ncode\n',
          'proj/AGENTS.md': '<!-- BEGIN specstone v1.0.0 -->\nbody\n',
        });

        expect(
          () => planAgentWrites(_inputs(base), full: true),
          throwsA(
            isA<MigrateFault>()
                .having((f) => f.file, 'file', 'CLAUDE.md')
                .having((f) => f.line, 'line', 2)
                .having(
                  (f) => f.message,
                  'message',
                  'close the code fence that opens on this line, then run the '
                      'command again',
                )
                .having(
                  (f) => f.more.single.message,
                  'second message',
                  isNot(contains('close the code fence')),
                ),
          ),
        );
      },
    );

    test('$_write R56: an unclosed fence after a well-formed block still wins '
        'the line', () async {
      final base = await _base({
        'proj/CLAUDE.md': '${_imports('')}x\n```\ncode\n',
      });

      expect(
        () => planAgentWrites(_inputs(base), full: true),
        throwsA(
          isA<MigrateFault>()
              .having((f) => f.file, 'file', 'CLAUDE.md')
              .having((f) => f.line, 'line', 6)
              .having(
                (f) => f.message,
                'message',
                'close the code fence that opens on this line, then run the '
                    'command again',
              ),
        ),
      );
    });

    test('$_write E05: a malformed file at a listed top refuses too', () async {
      final base = await _base({
        'other/.git/HEAD': 'ref\n',
        'other/AGENTS.md': '<!-- END specstone -->\n',
      });

      expect(
        () => planAgentWrites(
          _inputs(base, code: ['other/'], roots: ['../other']),
          full: false,
        ),
        throwsA(
          isA<MigrateFault>().having(
            (f) => f.file,
            'file',
            '../other/AGENTS.md',
          ),
        ),
      );
    });

    test('$_write E15: an unlisted top in another repository is written and '
        'listed once; its imports run to the project root', () async {
      final base = await _base({
        'proj/other/.git/HEAD': 'ref\n',
        'proj/other/CLAUDE.md': 'Owner\n',
      });

      final plan = planAgentWrites(
        _inputs(base, code: ['proj/other/', 'proj/other/']),
        full: true,
      );

      expect(_paths(plan), [_agentMd, 'AGENTS.md', 'other/CLAUDE.md']);
      final write = _writeAt(plan, 'other/CLAUDE.md');
      expect(write.text, 'Owner\n${_imports('../')}');
      expect(write.isAtTop, isTrue);
      expect(plan.agentFileRoots, ['other']);
    });

    test('$_write E16: a top reached by two code roots and by a link is '
        'written once', () async {
      final base = await _base({
        'proj/other/.git/HEAD': 'ref\n',
        'proj/other/lib/a': '',
      });
      Link(_at(base, 'viaLink').path)
          .createSync(_at(base, 'proj/other/lib').path);

      final plan = planAgentWrites(
        _inputs(base, code: ['proj/other/lib/', 'viaLink/', 'proj/other/']),
        full: true,
      );

      expect(plan.topWrites.map((w) => w.path), ['other/AGENTS.md']);
      expect(plan.agentFileRoots, ['other']);
    }, skip: Platform.isWindows ? 'symbolic links need a privilege' : null);

    test('$_write E16: a missing code folder under a link to another '
        'repository finds that repository top', () async {
      final base = await _base({
        'proj/other/.git/HEAD': 'ref\n',
        'proj/.keep': '',
      });
      Link(_at(base, 'viaLink').path).createSync(_at(base, 'proj/other').path);

      expect(
        repositoryTopOf(_at(base, 'viaLink/not/there'))?.path,
        _at(base, 'proj/other').path,
      );
      final plan = planAgentWrites(
        _inputs(base, code: ['viaLink/not/there/']),
        full: true,
      );

      expect(plan.agentFileRoots, ['other']);
      expect(plan.topWrites.map((w) => w.path), ['other/AGENTS.md']);
    }, skip: Platform.isWindows ? 'symbolic links need a privilege' : null);

    test('R48: a listed top that no code root reaches is neither refreshed '
        'nor checked, and stays listed', () async {
      final base = await _base({
        'proj/other/.git/HEAD': 'ref\n',
        'proj/other/AGENTS.md': 'x\n<!-- END specstone -->\n',
        'proj/.specstone/AGENT.md': agentMdText,
        'proj/AGENTS.md': _inline(),
      });
      final inputs = _inputs(base, roots: ['other']);

      final plan = planAgentWrites(inputs, full: false);

      expect(plan.isEmpty, isTrue);
      expect(plan.agentFileRoots, ['other']);
      expect(agentFileDrifts(inputs), isEmpty);
    });

    test('R48: a repository nested in the project is a top, written at the '
        'top and listed', () async {
      final base = await _base({
        'proj/vendor/.git/HEAD': 'ref\n',
        'proj/vendor/lib/a': '',
      });

      final plan = planAgentWrites(
        _inputs(base, code: ['proj/vendor/lib/']),
        full: true,
      );

      expect(plan.topWrites.map((w) => w.path), ['vendor/AGENTS.md']);
      expect(plan.topWrites.single.isAtTop, isTrue);
      expect(plan.agentFileRoots, ['vendor']);
    });

    test('R48: an instruction file that is not UTF-8 is skipped, with no '
        'write and no drift', () async {
      final base = await _base({'proj/.specstone/AGENT.md': agentMdText});
      File.fromUri(_at(base, 'proj/').uri.resolve('CLAUDE.md'))
          .writeAsBytesSync([0xFF, 0xFE, 0x41, 0x80]);
      final inputs = _inputs(base);

      expect(planAgentWrites(inputs, full: true).isEmpty, isTrue);
      expect(agentFileDrifts(inputs), isEmpty);
    });

    test('$_write E16: a .git file at the top qualifies it', () async {
      final base = await _base({
        'proj/other/.git': _gitFile,
        'proj/other/lib/a': '',
      });

      final plan = planAgentWrites(
        _inputs(base, code: ['proj/other/lib/']),
        full: true,
      );

      expect(plan.agentFileRoots, ['other']);
    });

    test(
      '$_write E16: a code root inside no repository takes no files',
      () async {
        final base = await _base({'free/lib/a': ''});

        final plan = planAgentWrites(
          _inputs(base, code: ['free/lib/']),
          full: true,
        );

        expect(plan.topWrites, isEmpty);
        expect(plan.agentFileRoots, isEmpty);
      },
    );

    test('$_write E17: a code root in the repository that holds the project '
        'root takes no files', () async {
      final base = await _base({
        '.git/HEAD': 'ref\n',
        'lib/a.dart': '',
        'proj/.keep': '',
      });

      final plan = planAgentWrites(
        _inputs(base, code: ['lib/', 'proj/']),
        full: true,
      );

      expect(plan.topWrites, isEmpty);
      expect(plan.agentFileRoots, isEmpty);
    });

    test(
      '$_write E19: a listed top is refreshed, never created into',
      () async {
        const stale =
            '<!-- BEGIN specstone v0.0.1 -->\nold\n<!-- END specstone -->\n';
        final base = await _base({
          'proj/other/.git/HEAD': 'ref\n',
          'proj/other/AGENTS.md': stale,
          'proj/.keep': '',
        });

        final plan = planAgentWrites(
          _inputs(base, code: ['proj/other/'], roots: ['other']),
          full: false,
        );

        expect(plan.rootWrites, isEmpty);
        expect(plan.topWrites.single.path, 'other/AGENTS.md');
        expect(plan.agentFileRoots, ['other']);
      },
    );

    test('$_write E19: a listed top whose files the Owner deleted stays '
        'empty', () async {
      final base = await _base({
        'proj/other/.git/HEAD': 'ref\n',
        'proj/.keep': '',
      });

      for (final full in [true, false]) {
        final plan = planAgentWrites(
          _inputs(base, code: ['proj/other/'], roots: ['other']),
          full: full,
        );

        expect(plan.topWrites, isEmpty, reason: 'full: $full');
      }
    });

    test('$_write E18: an unlisted top whose files already match is listed '
        'with 0 bytes written', () async {
      final base = await _base({
        'proj/other/.git/HEAD': 'ref\n',
        'proj/other/AGENTS.md': _inline(),
        'proj/AGENTS.md': _inline(),
        'proj/.specstone/AGENT.md': agentMdText,
      });

      final plan = planAgentWrites(
        _inputs(base, code: ['proj/other/']),
        full: false,
      );

      expect(plan.topWrites, isEmpty);
      expect(plan.agentFileRoots, ['other']);
      expect(plan.isEmpty, isFalse);
      expect(plan.line, isEmpty);
    });

    test('$_write E11: a non-full plan at the root creates nothing', () async {
      final base = await _base({'proj/.keep': ''});

      final plan = planAgentWrites(_inputs(base), full: false);

      expect(plan.isEmpty, isTrue);
    });

    test(
      '$_write E11: AGENT.md returns only while a block imports it',
      () async {
        final importing = await _base({'proj/CLAUDE.md': _imports('')});
        final inlineOnly = await _base({'proj/AGENTS.md': _inline()});

        expect(_paths(planAgentWrites(_inputs(importing), full: false)), [
          _agentMd,
        ]);
        expect(
          planAgentWrites(_inputs(inlineOnly), full: false).isEmpty,
          isTrue,
        );
      },
    );

    test('$_write E11: the unlisted-top trigger brings AGENT.md back for an '
        'import block it writes', () async {
      final base = await _base({
        'proj/other/.git/HEAD': 'ref\n',
        'proj/other/GEMINI.md': 'Owner\n',
        'proj/.keep': '',
      });

      final plan = planAgentWrites(
        _inputs(base, code: ['proj/other/']),
        full: false,
      );

      expect(_paths(plan), [_agentMd, 'other/GEMINI.md']);
    });

    test('$_write E22: two names for one file give one inline write', () async {
      final base = await _base({'proj/CLAUDE.md': 'Owner\n'});
      Link(_at(base, 'proj/').uri.resolve('AGENTS.md').toFilePath())
          .createSync('CLAUDE.md');

      final plan = planAgentWrites(_inputs(base), full: true);

      expect(_paths(plan), [_agentMd, 'CLAUDE.md']);
      expect(_writeAt(plan, 'CLAUDE.md').text, 'Owner\n${_inline()}');
    }, skip: Platform.isWindows ? 'symbolic links need a privilege' : null);

    test('review focus: a symbolic-link instruction file plans a write from '
        'its target and keeps its own path', () async {
      final base = await _base({
        'proj/shared/CLAUDE.md': 'Shared\n',
        'proj/.keep': '',
      });
      Link(_at(base, 'proj/').uri.resolve('CLAUDE.md').toFilePath()).createSync(
        _at(base, 'proj/shared/CLAUDE.md').path.replaceAll(RegExp(r'/$'), ''),
      );

      final plan = planAgentWrites(_inputs(base), full: true);

      expect(_writeAt(plan, 'CLAUDE.md').text, 'Shared\n${_imports('')}');
      expect(_paths(plan), isNot(contains('AGENTS.md')));
    }, skip: Platform.isWindows ? 'symbolic links need a privilege' : null);

    test('$_write R99: a top in another repository, outside the project '
        'root, is named and left: no write, not listed', () async {
      final base = await _base({
        'other/.git/HEAD': 'ref\n',
        'other/CLAUDE.md': 'Owner\n',
        'proj/.keep': '',
      });
      final inputs = _inputs(base, code: ['other/']);

      final plan = planAgentWrites(inputs, full: true);

      expect(_paths(plan), [_agentMd, 'AGENTS.md']);
      expect(plan.skipped, [
        '../other/CLAUDE.md reaches outside the project root; left as it is',
      ]);
      expect(plan.agentFileRoots, isEmpty);
      expect(plan.addedRoots, isEmpty);
      expect(plan.writeSet, isNot(contains(contains('other'))));
      expect(agentFileDrifts(inputs), isEmpty);
    });

    test('$_write R99: a root file linked to a file outside the project root '
        'is named and left, and the plan lists no write for it', () async {
      final base = await _base({
        'shared/CLAUDE.md': 'Shared\n',
        'proj/.keep': '',
      });
      Link(_at(base, 'proj/').uri.resolve('CLAUDE.md').toFilePath()).createSync(
        _at(base, 'shared/CLAUDE.md').path.replaceAll(RegExp(r'/$'), ''),
      );
      final inputs = _inputs(base);

      final plan = planAgentWrites(inputs, full: true);

      expect(_paths(plan), [_agentMd]);
      expect(plan.skipped, [
        'CLAUDE.md reaches outside the project root; left as it is',
      ]);
      expect(plan.writeSet, {
        File.fromUri(_at(base, 'proj/').uri.resolve(_agentMd)).path,
      });
      expect(agentFileDrifts(inputs), isEmpty);
    }, skip: Platform.isWindows ? 'symbolic links need a privilege' : null);

    test('$_write R99: an instruction file linked into .git and an AGENT.md '
        'linked outside the project are named by their own reasons', () async {
      final base = await _base({
        'victim.txt': 'mine\n',
        'proj/.git/config': '[core]\n',
        'proj/.specstone/keep': '',
      });
      Link(_at(base, 'proj/').uri.resolve('CLAUDE.md').toFilePath())
          .createSync('.git/config');
      Link(_at(base, 'proj/').uri.resolve(_agentMd).toFilePath())
          .createSync('../../victim.txt');
      final inputs = _inputs(base);

      final plan = planAgentWrites(inputs, full: true);

      expect(plan.skipped, [
        '.specstone/AGENT.md reaches outside the project root; left as it is',
        'CLAUDE.md lies under .git; left as it is',
      ]);
      expect(_paths(plan), isEmpty);
      expect(plan.writeSet, isEmpty);
      expect(agentFileDrifts(inputs), isEmpty);
    }, skip: Platform.isWindows ? 'symbolic links need a privilege' : null);

    group('$_write E27: a root file linked to a file at a top', () {
      const stale =
          'Owner\n<!-- BEGIN specstone v0.0.1 -->\nold rules\n'
          '<!-- END specstone -->\n';

      Future<Directory> linkedBase(String topText) async {
        final base = await _base({
          'proj/other/.git/HEAD': 'ref\n',
          'proj/other/AGENTS.md': topText,
          'proj/.keep': '',
        });
        Link(_at(base, 'proj/').uri.resolve('AGENTS.md').toFilePath())
            .createSync('other/AGENTS.md');
        return base;
      }

      test('gives one write, the root one, and one drift', () async {
        final base = await linkedBase(stale);
        final inputs = _inputs(base, code: ['proj/other/'], roots: ['other']);

        final plan = planAgentWrites(inputs, full: false);

        expect(_paths(plan), ['AGENTS.md']);
        expect(_writeAt(plan, 'AGENTS.md').text, 'Owner\n${_inline()}');
        expect(agentFileDrifts(inputs), [
          (path: 'AGENTS.md', line: 2, kind: AgentDriftKind.blockStale),
        ]);
      });

      test('takes the full upsert of the unlisted top', () async {
        final base = await linkedBase('Owner\n');

        final plan = planAgentWrites(
          _inputs(base, code: ['proj/other/']),
          full: false,
        );

        expect(_paths(plan), ['AGENTS.md']);
        expect(_writeAt(plan, 'AGENTS.md').text, 'Owner\n${_inline()}');
        expect(plan.addedRoots, ['other']);
      });
    }, skip: Platform.isWindows ? 'symbolic links need a privilege' : null);

    test(
      '$_write E09: writing twice changes 0 bytes the second time',
      () async {
        final base = await _base({
          'proj/other/.git/HEAD': 'ref\n',
          'proj/other/CLAUDE.md': 'Owner\n',
          'proj/GEMINI.md': 'Mine\n',
          'proj/.cursor/x': '',
        });
        final first = planAgentWrites(
          _inputs(base, code: ['proj/other/']),
          full: true,
        );
        _apply(base, first);

        final second = planAgentWrites(
          _inputs(base, code: ['proj/other/'], roots: first.agentFileRoots),
          full: true,
        );

        expect(second.isEmpty, isTrue);
      },
    );
  });

  group('agentFileDrifts', () {
    Future<Directory> fresh([Map<String, String> extra = const {}]) async {
      final base = await _base({'proj/CLAUDE.md': 'Owner\n', ...extra});
      _apply(base, planAgentWrites(_inputs(base), full: true));
      return base;
    }

    test('$_stale E01: every file as the CLI writes it has no drift', () async {
      final base = await fresh({'proj/.cursor/x': ''});
      _apply(base, planAgentWrites(_inputs(base), full: true));

      expect(agentFileDrifts(_inputs(base)), isEmpty);
    });

    test(
      '$_stale E02: an older version in the BEGIN line is no drift',
      () async {
        final base = await _base({
          'proj/AGENTS.md': _inline().replaceFirst(specstoneVersion, '0.0.1'),
          'proj/.specstone/AGENT.md': agentMdText,
        });

        expect(agentFileDrifts(_inputs(base)), isEmpty);
      },
    );

    test('$_stale E03: a hand-edited rule line is one blockStale on the '
        'BEGIN line', () async {
      final base = await _base({
        'proj/AGENTS.md': 'top\n${_inline().replaceFirst('Rules', 'Rule')}',
        'proj/.specstone/AGENT.md': agentMdText,
      });

      expect(agentFileDrifts(_inputs(base)), [
        (path: 'AGENTS.md', line: 2, kind: AgentDriftKind.blockStale),
      ]);
    });

    test('$_stale E04: no block, and no rules file, is no drift', () async {
      final base = await _base({
        'proj/CLAUDE.md': 'Owner only\n',
        'proj/.cursor/x': '',
      });

      expect(agentFileDrifts(_inputs(base)), isEmpty);
    });

    test('$_stale E05: an import block with AGENT.md missing is one '
        'agentMdMissing on its BEGIN line', () async {
      final base = await _base({'proj/CLAUDE.md': 'x\n${_imports('')}'});

      expect(agentFileDrifts(_inputs(base)), [
        (path: 'CLAUDE.md', line: 2, kind: AgentDriftKind.agentMdMissing),
      ]);
    });

    test('$_stale E06: AGENT.md with other bytes is one agentMdStale on '
        'line 1', () async {
      final base = await _base({
        'proj/.specstone/AGENT.md': 'edited\n',
        'proj/AGENTS.md': _inline(),
      });

      expect(agentFileDrifts(_inputs(base)), [
        (path: _agentMd, line: 1, kind: AgentDriftKind.agentMdStale),
      ]);
    });

    test('$_stale E07: a malformed file is one markersMalformed on its first '
        'marker line', () async {
      final base = await _base({
        'proj/AGENTS.md': 'x\n<!-- END specstone -->\n',
      });

      expect(agentFileDrifts(_inputs(base)), [
        (path: 'AGENTS.md', line: 2, kind: AgentDriftKind.markersMalformed),
      ]);
    });

    test(
      '$_stale E09: a project without blocks or AGENT.md has no drift',
      () async {
        final base = await _base({'proj/.keep': ''});

        expect(agentFileDrifts(_inputs(base)), isEmpty);
      },
    );

    test('$_stale E10: CRLF with a matching block is no drift', () async {
      final base = await _base({
        'proj/AGENTS.md': _inline().replaceAll('\n', '\r\n'),
        'proj/.specstone/AGENT.md': agentMdText,
      });

      expect(agentFileDrifts(_inputs(base)), isEmpty);
    });

    test('$_stale E11, E16: a rules file differing in frontmatter is on line '
        '1; one differing in body is on its BEGIN line', () async {
      final text = cursorRulesText(cliVersion: specstoneVersion);
      final frontmatter = await _base({
        'proj/$_cursor': text.replaceFirst('true', 'false'),
        'proj/.specstone/AGENT.md': agentMdText,
      });
      final both = await _base({
        'proj/$_cursor': text
            .replaceFirst('true', 'false')
            .replaceFirst('Rules', 'Rule'),
        'proj/.specstone/AGENT.md': agentMdText,
      });

      expect(agentFileDrifts(_inputs(frontmatter)), [
        (path: _cursor, line: 1, kind: AgentDriftKind.blockStale),
      ]);
      expect(agentFileDrifts(_inputs(both)), [
        (path: _cursor, line: 4, kind: AgentDriftKind.blockStale),
      ]);
    });

    test(
      '$_stale E12: a stale block at a listed top names that path',
      () async {
        final base = await _base({
          'proj/other/.git/HEAD': 'ref\n',
          'proj/other/AGENTS.md': _inline().replaceFirst('Rules', 'Rule'),
          'proj/.keep': '',
        });

        expect(
          agentFileDrifts(
            _inputs(base, code: ['proj/other/'], roots: ['other']),
          ),
          [(path: 'other/AGENTS.md', line: 1, kind: AgentDriftKind.blockStale)],
        );
      },
    );

    test('$_stale E13: an unlisted top is one topUnlisted on line 1, whatever '
        'its files hold', () async {
      final base = await _base({
        'proj/other/.git/HEAD': 'ref\n',
        'proj/other/AGENTS.md': _inline().replaceFirst('Rules', 'Rule'),
        'proj/.keep': '',
      });

      expect(
        agentFileDrifts(_inputs(base, code: ['proj/other/', 'proj/other/'])),
        [(path: 'other', line: 1, kind: AgentDriftKind.topUnlisted)],
      );
    });

    test(
      '$_stale E14: a listed top whose files were deleted is no drift',
      () async {
        final base = await _base({
          'proj/other/.git/HEAD': 'ref\n',
          'proj/.keep': '',
        });

        expect(
          agentFileDrifts(
            _inputs(base, code: ['proj/other/'], roots: ['other']),
          ),
          isEmpty,
        );
      },
    );

    test('$_stale E15: a code root in no repository, or in the project '
        'repository, raises nothing', () async {
      final base = await _base({
        'free/lib/a': '',
        'proj/lib/a': '',
        'proj/.git/HEAD': 'ref\n',
      });

      expect(
        agentFileDrifts(_inputs(base, code: ['free/lib/', 'proj/lib/'])),
        isEmpty,
      );
    });
  });

  group('one predicate', () {
    final fixtures = <String, Map<String, String>>{
      'empty root': {'proj/.keep': ''},
      'owner file only': {'proj/CLAUDE.md': 'Owner\n'},
      'current inline': {
        'proj/AGENTS.md': _inline(),
        'proj/.specstone/AGENT.md': agentMdText,
      },
      'stale inline': {
        'proj/AGENTS.md':
            '<!-- BEGIN specstone v1.0.0 -->\nold\n'
            '<!-- END specstone -->\n',
        'proj/.specstone/AGENT.md': agentMdText,
      },
      'import without AGENT.md': {'proj/CLAUDE.md': _imports('')},
      'AGENT.md edited': {'proj/.specstone/AGENT.md': 'x\n'},
      'AGENT.md alone': {'proj/.specstone/AGENT.md': agentMdText},
      'cursor folder': {'proj/.cursor/x': ''},
      'cursor stale': {
        'proj/$_cursor': 'plain\n',
        'proj/.specstone/AGENT.md': agentMdText,
      },
      'crlf current': {
        'proj/GEMINI.md': _imports('').replaceAll('\n', '\r\n'),
        'proj/.specstone/AGENT.md': agentMdText,
      },
    };

    for (final MapEntry(:key, :value) in fixtures.entries) {
      test('$_stale: drifts are empty exactly when the non-full plan is '
          'empty ($key)', () async {
        final base = await _base(value);

        expect(
          agentFileDrifts(_inputs(base)).isEmpty,
          planAgentWrites(_inputs(base), full: false).isEmpty,
        );
      });
    }

    test(
      '$_stale: the same holds with unlisted, listed, and clean tops',
      () async {
        final shared = {
          'proj/.specstone/AGENT.md': agentMdText,
          'proj/AGENTS.md': _inline(),
          'proj/other/.git/HEAD': 'ref\n',
        };
        final cases = <(Map<String, String>, List<String>)>[
          ({...shared}, []),
          ({...shared, 'proj/other/AGENTS.md': _inline()}, []),
          ({...shared, 'proj/other/AGENTS.md': _inline()}, ['other']),
          ({...shared, 'proj/other/AGENTS.md': 'x\n'}, ['other']),
          ({...shared, 'proj/other/CLAUDE.md': _imports('../')}, ['other']),
        ];
        for (final (files, roots) in cases) {
          final base = await _base(files);
          final inputs = _inputs(base, code: ['proj/other/'], roots: roots);

          expect(
            agentFileDrifts(inputs).isEmpty,
            planAgentWrites(inputs, full: false).isEmpty,
            reason: '$files $roots',
          );
        }
      },
    );
  });
}
