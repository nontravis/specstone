import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:specstone_core/src/setup_migration/agent_files.dart';
import 'package:test/test.dart';

import '../../tool/generate_agent_text.dart';
import '../helpers/package_root.dart';

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  group('renderAgentText', () {
    test('holds the constant and decodes back to the input', () {
      final text = renderAgentText(_bytes('a\n'));

      expect(text, startsWith('// GENERATED CODE - DO NOT MODIFY BY HAND\n'));
      final match = RegExp(r"const String agentMdTextBase64 =\s*'([^']*)';")
          .firstMatch(text);
      expect(match, isNotNull, reason: text);
      expect(utf8.decode(base64Decode(match!.group(1)!)), 'a\n');
    });

    test('a long text wraps the constant onto its own indented line', () {
      final text = renderAgentText(_bytes('${'a' * 300}\n'));

      expect(
        text,
        matches(RegExp("const String agentMdTextBase64 =\n    '[^']+';\n")),
      );
    });

    test('the rendered text is dart format stable', () {
      for (final (index, text) in [
        renderAgentText(_bytes('a\n')),
        renderAgentText(_bytes('${'a' * 300}\n')),
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
          () => renderAgentText(_bytes(text)),
          throwsStateError,
          reason: text.isEmpty ? '(empty)' : text,
        );
      }
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
        renderAgentText(asset.readAsBytesSync()),
      );
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
