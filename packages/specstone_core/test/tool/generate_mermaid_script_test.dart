@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import '../../tool/generate_mermaid_script.dart';
import '../helpers/package_root.dart';

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

String _render(
  String script, {
  String license = 'L',
  String parseScript = 'P',
  String patches = '[]',
}) => renderMermaidScript(
  _bytes(script),
  _bytes(license),
  parseScript: _bytes(parseScript),
  patches: _bytes(patches),
);

String _patchesJson(List<String> finds) => jsonEncode([
  for (final find in finds) {'find': find, 'replace': 'R'},
]);

String _constant(String text, String name) {
  final match = RegExp("const String $name =\\s*'([^']*)';").firstMatch(text);
  if (match == null) fail('constant $name is missing from:\n$text');
  return match.group(1)!;
}

void main() {
  group('renderMermaidScript', () {
    test('holds each constant and decodes back to the inputs', () {
      final patches = _patchesJson(['a']);
      final text = _render('a\nb', parseScript: 'P', patches: patches);

      expect(text, startsWith('// GENERATED CODE - DO NOT MODIFY BY HAND\n'));
      expect(
        utf8.decode(base64Decode(_constant(text, 'mermaidScriptBase64'))),
        'a\nb',
      );
      expect(
        utf8.decode(base64Decode(_constant(text, 'mermaidLicenseBase64'))),
        'L',
      );
      expect(
        utf8.decode(base64Decode(_constant(text, 'mermaidParseScriptBase64'))),
        'P',
      );
      expect(
        utf8.decode(base64Decode(_constant(text, 'mermaidNodePatchesBase64'))),
        patches,
      );
      expect(
        _constant(text, 'mermaidParserSha256'),
        matches(r'^[0-9a-f]{64}$'),
      );
    });

    test('a long script wraps each constant onto its own indented line', () {
      final text = _render('a' * 300);

      expect(
        text,
        matches(RegExp("const String mermaidScriptBase64 =\n    '[^']+';\n")),
      );
    });

    test('the rendered text is dart format stable', () {
      final samples = [
        _render('a\nb'),
        _render('a' * 300, license: 'b' * 100, parseScript: 'c' * 100),
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
        expect(() => _render(script), throwsStateError, reason: script);
      }
    });

    test('refuses a patch whose find the script does not hold, naming it', () {
      expect(
        () => _render('abc', patches: _patchesJson(['zz'])),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', contains('zz')),
        ),
      );
    });

    test('refuses a patch whose find the script holds twice', () {
      expect(
        () => _render('ab ab', patches: _patchesJson(['ab'])),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', contains('ab')),
        ),
      );
    });

    test('accepts a patch whose find the script holds once', () {
      expect(
        () => _render('ab cd', patches: _patchesJson(['ab'])),
        returnsNormally,
      );
    });

    test('refuses a parse script over the Windows command line cap', () {
      expect(() => _render('a', parseScript: 'x' * 30000), returnsNormally);
      expect(() => _render('a', parseScript: 'x' * 30001), throwsStateError);
    });

    test('the parser hash changes when the script, parse script, or patches '
        'change', () {
      String hashOf(String text) => _constant(text, 'mermaidParserSha256');
      final base = hashOf(_render('ab', parseScript: 'P'));
      final others = [
        hashOf(_render('abc', parseScript: 'P')),
        hashOf(_render('ab', parseScript: 'Q')),
        hashOf(_render('ab', parseScript: 'P', patches: _patchesJson(['a']))),
      ];

      expect(hashOf(_render('ab', parseScript: 'P', license: 'X')), base);
      for (final other in others) {
        expect(other, isNot(base));
      }
    });
  });

  group('committed output', () {
    test('mermaid_script.g.dart equals renderMermaidScript over the committed '
        'assets/mermaid/ files', () {
      final root = packageRoot();
      final script = File.fromUri(
        root.uri.resolve('assets/mermaid/mermaid.min.js'),
      );
      final license = File.fromUri(root.uri.resolve('assets/mermaid/LICENSE'));
      final parseScript = File.fromUri(
        root.uri.resolve('assets/mermaid/parse_diagrams.js'),
      );
      final patches = File.fromUri(
        root.uri.resolve('assets/mermaid/node_patches.json'),
      );
      final committed = File.fromUri(
        root.uri.resolve('lib/src/rendering/mermaid_script.g.dart'),
      );

      expect(
        committed.readAsStringSync(),
        renderMermaidScript(
          script.readAsBytesSync(),
          license.readAsBytesSync(),
          parseScript: parseScript.readAsBytesSync(),
          patches: patches.readAsBytesSync(),
        ),
      );
    });

    test('git pins the script as binary and the constants as LF', () {
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
