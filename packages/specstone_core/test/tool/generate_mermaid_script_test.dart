import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import '../../tool/generate_mermaid_script.dart';
import '../helpers/package_root.dart';

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

String _constant(String text, String name) {
  final match = RegExp("const String $name =\\s*'([^']*)';").firstMatch(text);
  if (match == null) fail('constant $name is missing from:\n$text');
  return match.group(1)!;
}

void main() {
  group('renderMermaidScript', () {
    test('holds both constants and decodes back to the inputs', () {
      final text = renderMermaidScript(_bytes('a\nb'), _bytes('L'));

      expect(text, startsWith('// GENERATED CODE - DO NOT MODIFY BY HAND\n'));
      expect(
        utf8.decode(base64Decode(_constant(text, 'mermaidScriptBase64'))),
        'a\nb',
      );
      expect(
        utf8.decode(base64Decode(_constant(text, 'mermaidLicenseBase64'))),
        'L',
      );
    });

    test('a long script wraps each constant onto its own indented line', () {
      final text = renderMermaidScript(
        Uint8List.fromList(List<int>.filled(300, 0x61)),
        _bytes('L'),
      );

      expect(
        text,
        matches(RegExp("const String mermaidScriptBase64 =\n    '[^']+';\n")),
      );
    });

    test('the rendered text is dart format stable', () {
      final samples = [
        renderMermaidScript(_bytes('a\nb'), _bytes('L')),
        renderMermaidScript(
          Uint8List.fromList(List<int>.filled(300, 0x61)),
          Uint8List.fromList(List<int>.filled(100, 0x62)),
        ),
      ];
      for (final (index, text) in samples.indexed) {
        final out = File(
          '${Directory.systemTemp.path}/specstone_mermaid_render_$index.dart',
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

    test('refuses a script holding a script tag in any letter case', () {
      for (final script in ['x</SCRIPT>y', 'x<script y', 'x</Script']) {
        expect(
          () => renderMermaidScript(_bytes(script), _bytes('L')),
          throwsStateError,
          reason: script,
        );
      }
    });
  });

  group('main output', () {
    test('the committed constants match assets/mermaid/', () {
      final root = packageRoot();
      final script = File.fromUri(
        root.uri.resolve('assets/mermaid/mermaid.min.js'),
      );
      final license = File.fromUri(root.uri.resolve('assets/mermaid/LICENSE'));
      final committed = File.fromUri(
        root.uri.resolve('lib/src/rendering/mermaid_script.g.dart'),
      );

      expect(
        committed.readAsStringSync(),
        renderMermaidScript(
          script.readAsBytesSync(),
          license.readAsBytesSync(),
        ),
      );
    });

    test('NFR-Po01: git pins the script as binary and the constants as LF', () {
      final root = packageRoot();
      final result = Process.runSync('git', [
        'check-attr',
        'text',
        'eol',
        '--',
        'assets/mermaid/mermaid.min.js',
        'lib/src/rendering/mermaid_script.g.dart',
      ], workingDirectory: root.path);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect((result.stdout as String).trim().split('\n'), [
        'assets/mermaid/mermaid.min.js: text: unset',
        'assets/mermaid/mermaid.min.js: eol: unspecified',
        'lib/src/rendering/mermaid_script.g.dart: text: set',
        'lib/src/rendering/mermaid_script.g.dart: eol: lf',
      ]);
    });
  });
}
