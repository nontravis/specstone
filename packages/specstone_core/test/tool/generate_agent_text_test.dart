// A test name is one literal so the sync matrix reads it whole.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:specstone_core/src/document_writing/report_grammar.dart';
import 'package:specstone_core/src/setup_migration/agent_files.dart';
import 'package:specstone_core/src/setup_migration/agent_text.g.dart';
import 'package:test/test.dart';

import '../../tool/generate_agent_text.dart';
import '../helpers/package_root.dart';

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

final Map<String, Uint8List> _twoAssets = {
  'a.md': _bytes('${'x' * 60}\n'),
  'b.md': _bytes('${'y' * 60}\n'),
};

Map<String, String> _renderedAssets(String source) {
  final match = RegExp(
    r'const Map<String, String> agentAssetsBase64 = \{(.*?)\};',
    dotAll: true,
  ).firstMatch(source);
  expect(match, isNotNull, reason: source);
  return {
    for (final entry in RegExp(
      r"'([^']+)':\s*'([^']*)'",
    ).allMatches(match!.group(1)!))
      entry.group(1)!: utf8.decode(base64Decode(entry.group(2)!)),
  };
}

ProcessResult _git(Directory dir, List<String> args) => Process.runSync('git', [
  '-c',
  'user.name=t',
  '-c',
  'user.email=t@t',
  '-c',
  'commit.gpgsign=false',
  ...args,
], workingDirectory: dir.path);

void main() {
  group('renderAgentText', () {
    test('holds the constant and decodes back to the input', () {
      final text = renderAgentText(_bytes('a\n'), const {});

      expect(text, startsWith('// GENERATED CODE - DO NOT MODIFY BY HAND\n'));
      final match = RegExp(r"const String agentMdTextBase64 =\s*'([^']*)';")
          .firstMatch(text);
      expect(match, isNotNull, reason: text);
      expect(utf8.decode(base64Decode(match!.group(1)!)), 'a\n');
    });

    test('a long text wraps the constant onto its own indented line', () {
      final text = renderAgentText(_bytes('${'a' * 300}\n'), const {});

      expect(
        text,
        matches(RegExp("const String agentMdTextBase64 =\n    '[^']+';\n")),
      );
    });

    test('the rendered text is dart format stable', () {
      for (final (index, text) in [
        renderAgentText(_bytes('a\n'), _twoAssets),
        renderAgentText(_bytes('${'a' * 300}\n'), _twoAssets),
      ].indexed) {
        final out = File(
          '${Directory.systemTemp.path}/specstone_agent_render_$index.dart',
        );
        addTearDown(out.deleteSync);

        out.writeAsStringSync(text);
        final result = Process.runSync(Platform.resolvedExecutable, [
          'format',
          '--output=none',
          '--set-exit-if-changed',
          out.path,
        ]);

        expect(result.exitCode, 0, reason: text);
      }
    });

    test('refuses a text that does not end in one line feed', () {
      for (final text in ['', 'a', 'a\n\n']) {
        expect(
          () => renderAgentText(_bytes(text), const {}),
          throwsStateError,
          reason: text.isEmpty ? '(empty)' : text,
        );
      }
    });
  });

  group('renderAgentText assets', () {
    test('holds each asset with LF alone, keys sorted', () {
      final text = renderAgentText(_bytes('a\n'), {
        'b/SKILL.md': _bytes('one\r\ntwo\r\n'),
        'a.md': _bytes('x\ny\n'),
      });

      final assets = _renderedAssets(text);
      expect(assets.keys.toList(), ['a.md', 'b/SKILL.md']);
      expect(assets['b/SKILL.md'], 'one\ntwo\n');
      expect(assets['a.md'], 'x\ny\n');
    });

    test('the rendered text is dart format stable', () {
      final out = File(
        '${Directory.systemTemp.path}/specstone_assets_render.dart',
      );
      addTearDown(out.deleteSync);

      out.writeAsStringSync(
        renderAgentText(_bytes('a\n'), {
          'b/SKILL.md': _bytes('${'long ' * 40}\n'),
          'a.md': _bytes('x\n'),
        }),
      );
      final result = Process.runSync(Platform.resolvedExecutable, [
        'format',
        '--output=none',
        '--set-exit-if-changed',
        out.path,
      ]);

      expect(result.exitCode, 0, reason: out.readAsStringSync());
    });
  });

  group('listAgentAssetPaths', () {
    test(
      'lists tracked files under assets/agent, not untracked or AGENT.md',
      () {
        final repo = Directory.systemTemp.createTempSync('specstone_assets_');
        addTearDown(() => repo.deleteSync(recursive: true));
        final agent = Directory('${repo.path}/assets/agent/specstone-x')
          ..createSync(recursive: true);
        File('${agent.path}/SKILL.md').writeAsStringSync('s\n');
        File('${repo.path}/assets/agent/AGENT.md').writeAsStringSync('a\n');
        File('${repo.path}/assets/agent/specstone-y.md')
            .writeAsStringSync('y\n');
        File('${repo.path}/assets/other.md').writeAsStringSync('o\n');
        expect(_git(repo, ['init']).exitCode, 0);
        expect(_git(repo, ['add', 'assets']).exitCode, 0);
        expect(_git(repo, ['commit', '-m', 'seed']).exitCode, 0);
        File('${repo.path}/assets/agent/untracked.md').writeAsStringSync('u\n');

        expect(listAgentAssetPaths(repo), [
          'specstone-x/SKILL.md',
          'specstone-y.md',
        ]);
      },
    );
  });

  group('report blocks', () {
    // D4: the generator writes each template's report fence from the grammar.
    test('writeReportBlocks sets each declared fence body and keeps every other line', () {
      final root = Directory.systemTemp.createTempSync('specstone_blocks_');
      addTearDown(() => root.deleteSync(recursive: true));
      String template(ReportBlock block, List<String> body) => [
        'intro of ${block.id}',
        '',
        '```',
        'not a report fence',
        '```',
        '',
        '```',
        ...body,
        '```',
        '',
        'after',
        '',
      ].join('\n');
      File asset(ReportBlock block) =>
          File('${root.path}/assets/agent/${block.templatePath}');
      for (final block in reportBlocks) {
        asset(block)
          ..createSync(recursive: true)
          ..writeAsStringSync(
            template(block, [block.firstLine, '- a stale line']),
          );
      }

      writeReportBlocks(root);
      final once = {
        for (final block in reportBlocks)
          block: asset(block).readAsStringSync(),
      };
      writeReportBlocks(root);

      for (final block in reportBlocks) {
        final declared = [for (final line in block.lines) line.label];
        expect(once[block], template(block, declared), reason: block.id);
        expect(asset(block).readAsStringSync(), once[block], reason: block.id);
      }
    });

    test('a declared first line opening no fence or two fences fails naming its template', () {
      final block = reportBlocks.first;
      final fence = '```\n${block.firstLine}\n```\n';
      for (final text in ['no fence\n', '$fence\n$fence']) {
        expect(
          () => withReportBlock(text, block),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains(block.templatePath),
            ),
          ),
          reason: text,
        );
      }
    });

    test('a report fence that never closes fails naming its template', () {
      final block = reportBlocks.first;

      expect(
        () =>
            withReportBlock('```\n${block.firstLine}\n- a stale line\n', block),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(contains(block.templatePath), contains('never closes')),
          ),
        ),
      );
    });
  });

  group('committed output', () {
    test('agent_text.g.dart equals renderAgentText over the committed '
        'assets/agent/AGENT.md', () {
      final root = packageRoot();
      final asset = File.fromUri(root.uri.resolve('assets/agent/AGENT.md'));
      final committed = File.fromUri(
        root.uri.resolve('lib/src/setup_migration/agent_text.g.dart'),
      );

      expect(
        committed.readAsStringSync(),
        renderAgentText(
          asset.readAsBytesSync(),
          readAgentAssets(root, listAgentAssetPaths(root)),
        ),
      );
    });

    test('agentAssetsBase64 holds every tracked asset but AGENT.md', () {
      final root = packageRoot();
      final paths = listAgentAssetPaths(root);

      expect(agentAssetsBase64.keys.toList(), paths);
      expect(paths, contains('specstone-read-sdd/SKILL.md'));
      expect(paths, contains('specstone-sdd-engineer.md'));
      expect(paths, isNot(contains('AGENT.md')));
    });

    test('agentAssetsBase64 holds every tracked or untracked asset file but '
        'AGENT.md', () {
      // Lists tracked files and untracked files git does not ignore, so a
      // new asset left unstaged fails here, and a local `.DS_Store` does not.
      final result = Process.runSync(
        'git',
        [
          'ls-files',
          '-z',
          '--cached',
          '--others',
          '--exclude-standard',
          '--',
          'assets/agent/',
        ],
        workingDirectory: packageRoot().path,
        stdoutEncoding: utf8,
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      const prefix = 'assets/agent/';
      final expected = {
        for (final path in (result.stdout as String).split('\u0000'))
          if (path.startsWith(prefix) && path != '${prefix}AGENT.md')
            path.substring(prefix.length),
      }.toList()..sort();

      expect(agentAssetsBase64.keys.toList(), expected);
    });

    test('agentMdText equals the asset bytes and the generated constant', () {
      final root = packageRoot();
      final asset = File.fromUri(root.uri.resolve('assets/agent/AGENT.md'));

      expect(utf8.encode(agentMdText), asset.readAsBytesSync());
    });

    test('git pins the asset as binary and the constant as LF', () {
      final root = packageRoot();
      final result = Process.runSync('git', [
        'check-attr',
        'text',
        'eol',
        '--',
        'assets/agent/AGENT.md',
        'lib/src/setup_migration/agent_text.g.dart',
      ], workingDirectory: root.path);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect((result.stdout as String).trim().split('\n'), [
        'assets/agent/AGENT.md: text: unset',
        'assets/agent/AGENT.md: eol: unspecified',
        'lib/src/setup_migration/agent_text.g.dart: text: set',
        'lib/src/setup_migration/agent_text.g.dart: eol: lf',
      ]);
    });
  });
}
