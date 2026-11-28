import 'dart:io';

import 'package:specstone_test_support/specstone_test_support.dart';
import 'package:test/test.dart';

import '../helpers/temp_tree.dart';

const _call = 'Process.runSync';
const _tearOff = 'Process.run';
const _tagged = "@Tags(['integration'])\nlibrary;\n";
const _pure = 'void main() {}\n';
const _spawning = "void main() {\n  final r = $_call('id', []);\n}\n";

String _lines(List<String> lines) => '${lines.join('\n')}\n';

void main() {
  group('spawnLineOf', () {
    test('ignores a glob slash-star mid-line, so later lines stay', () {
      final source = _lines(["final g = '**/*.md';", 'final r = $_call(1);']);

      expect(spawnLineOf(source), 2);
    });

    test('M2: a slash-star inside a string does not open a comment', () {
      final source = _lines([
        "final a = 'rm -rf /*';",
        "final r = $_call('x', []);",
        "final g = '**/*.md';",
      ]);

      expect(spawnLineOf(source), 2);
    });

    test('M2: a double slash inside a string does not end the line', () {
      expect(spawnLineOf("f(' //', $_tearOff);"), 1);
    });

    test('correctness 1: a string slash-star with a later close keeps the '
        'spawn between', () {
      final source = _lines([
        "final a = ' /*';",
        "final r = $_call('x', []);",
        "final b = '*/';",
      ]);

      expect(spawnLineOf(source), 2);
    });

    test('ignores a call named only inside a string, counts one in '
        'an interpolation', () {
      expect(spawnLineOf("final s = '$_call(1)';"), isNull);
      expect(spawnLineOf("final s = '\${$_call(1)}';"), 1);
    });

    test('M5: a nested block comment holds the whole call', () {
      expect(spawnLineOf('/* a /* b */ $_call(x) */'), isNull);
    });

    test('finds the first call line and skips comments', () {
      final source = _lines([
        '// $_call(',
        '/* $_call( */',
        "final r = $_call('id', []);",
      ]);

      expect(spawnLineOf(source), 3);
      expect(spawnLineOf(_lines(['// $_call(', '/* $_call( */'])), isNull);
    });

    test('counts a prefixed call and a tear-off', () {
      expect(spawnLineOf("final r = io.$_call('x');"), 1);
      expect(spawnLineOf('final f = $_tearOff;'), 1);
    });

    test('ignores an escaped regex mention', () {
      const type = 'Process';
      const mention = "final p = RegExp(r'$type\\.run(');";

      expect(spawnLineOf(mention), isNull);
    });

    test('ignores a source holding no call', () {
      expect(spawnLineOf(_pure), isNull);
    });
  });

  group('tagsOf', () {
    test('reads every tag of the library tags list', () {
      final source = _lines([
        "@TestOn('!windows')",
        "@Tags(['timing', 'integration'])",
        'library;',
      ]);

      expect(tagsOf(source), ['timing', 'integration']);
      expect(tagsOf(_pure), isEmpty);
      expect(tagsOf("// @Tags(['integration'])"), isEmpty);
    });

    test('ignores a string-literal mention mid-line', () {
      expect(tagsOf(r"const s = '@Tags([\'integration\'])';"), isEmpty);
    });

    test('M1: a tag after library; is not library metadata', () {
      final source = _lines(['library;', '', "@Tags(['integration'])", _pure]);

      expect(tagsOf(source), isEmpty);
    });

    test('M1: a tag line inside a raw triple-quoted string is text', () {
      final source = _lines([
        "import 'dart:io';",
        "const s = r'''",
        "@Tags(['integration'])",
        "''';",
      ]);

      expect(tagsOf(source), isEmpty);
    });

    test('correctness 2: a tag line inside a fixture string is text', () {
      final source = _lines([
        "import 'dart:io';",
        'const s = "',
        "@Tags(['integration'])",
        '";',
      ]);

      expect(tagsOf(source), isEmpty);
    });

    test('M4: a const, typed, or prefixed tags list reads as package:test '
        'reads it', () {
      final forms = [
        "@Tags(const ['integration'])\nlibrary;\n",
        "@Tags(<String>['integration'])\nlibrary;\n",
        _lines([
          "@test.Tags(['integration'])",
          'library;',
          "import 'package:test/test.dart' as test;",
        ]),
      ];

      for (final form in forms) {
        expect(tagsOf(form), ['integration'], reason: form);
      }
    });
  });

  group('directivesOf', () {
    test('reads multi-line and double-quoted directives', () {
      final source = _lines([
        "import 'package:test/test.dart';",
        "import 'dart:io';",
        "import '../helpers/a.dart'",
        '    show x;',
        'export "b.dart";',
      ]);

      expect(directivesOf(source), [
        'package:test/test.dart',
        'dart:io',
        '../helpers/a.dart',
        'b.dart',
      ]);
    });

    test('ignores a string-literal mention mid-line', () {
      expect(directivesOf(r"const s = 'import \'a.dart\'';"), isEmpty);
    });

    test('reads every URI of a conditional directive, not its condition', () {
      final source = _lines([
        "import 'stub.dart'",
        "    if (dart.library.io == 'true') 'real.dart'",
        "    if (dart.library.html) 'web.dart';",
      ]);

      expect(directivesOf(source), ['stub.dart', 'real.dart', 'web.dart']);
    });

    test('M5: directive text inside a raw multi-line string is not read', () {
      final source = _lines([
        'void main() {}',
        "const s = r'''",
        "import 'helpers/h.dart';",
        "''';",
      ]);

      expect(directivesOf(source), isEmpty);
    });

    test('reads a part directive but not a part-of directive', () {
      final source = _lines(["part 'x.dart';", "part of 'owner.dart';"]);

      expect(directivesOf(source), ['x.dart']);
    });
  });

  test('reads a CRLF source like an LF one', () {
    String crlf(String s) => s.replaceAll('\n', '\r\n');
    final spawning = _lines(['// $_call(', "final r = $_call('id', []);"]);
    final tagged = _lines([
      "@TestOn('!windows')",
      "@Tags(['timing', 'integration'])",
      'library;',
    ]);
    final directives = _lines([
      "import 'package:test/test.dart';",
      "import '../helpers/a.dart'",
      '    show x;',
      'export "b.dart";',
    ]);

    expect(spawnLineOf(crlf(spawning)), spawnLineOf(spawning));
    expect(tagsOf(crlf(tagged)), tagsOf(tagged));
    expect(directivesOf(crlf(directives)), [
      'package:test/test.dart',
      '../helpers/a.dart',
      'b.dart',
    ]);
  });

  group('scanIntegrationTags', () {
    Future<IntegrationTagReport> scan(
      Map<String, String> files, {
      Map<String, String> allowlist = const {},
    }) async {
      final root = await writeTree(files);
      return scanIntegrationTags(
        packagesRoot: root,
        package: 'a',
        followedPackages: ['a', 'b'],
        libraryPackages: ['helper_pkg'],
        allowlist: allowlist,
      );
    }

    void expectClean(IntegrationTagReport report) {
      expect(report.untaggedSpawning, isEmpty);
      expect(report.taggedPure, isEmpty);
      expect(report.staleAllowlist, isEmpty);
    }

    test('a test importing a spawning helper of the other package is '
        'untagged spawning, with its chain', () async {
      final report = await scan({
        'a/test/x_test.dart': "import 'helpers/h.dart';\n",
        'a/test/helpers/h.dart': "export '../../../b/test/helpers/g.dart';\n",
        'b/test/helpers/g.dart': _lines(['// g', 'void f() {', '$_call(1);']),
      });

      const chain =
          'a/test/x_test.dart -> a/test/helpers/h.dart '
          '-> b/test/helpers/g.dart:3';
      expect(report.untaggedSpawning, ['test/x_test.dart: $chain']);
      expect(report.taggedPure, isEmpty);
      expect(report.staleAllowlist, isEmpty);
    });

    test('an own spawn is reported with its line', () async {
      final report = await scan({'a/test/x_test.dart': _spawning});

      expect(report.untaggedSpawning, [
        'test/x_test.dart: a/test/x_test.dart:2',
      ]);
    });

    test('a package: import and a tool/ import are not followed', () async {
      final report = await scan({
        'a/test/y_test.dart':
            "import 'package:a/z.dart';\nimport '../tool/t.dart';\n",
        'a/lib/z.dart': _spawning,
        'a/tool/t.dart': _spawning,
      });

      expectClean(report);
    });

    test('M3: a package: import of a listed library package is followed, '
        'an unlisted one is not', () async {
      final report = await scan({
        'a/test/x_test.dart':
            "import 'package:helper_pkg/x.dart';\n"
            "import 'package:other_pkg/y.dart';\n",
        'helper_pkg/lib/x.dart': _spawning,
        'other_pkg/lib/y.dart': _spawning,
      });

      expect(report.untaggedSpawning, [
        'test/x_test.dart: a/test/x_test.dart -> helper_pkg/lib/x.dart:2',
      ]);
    });

    test('M6: a packages root with a space and a CRLF source scan like '
        'plain ones', () async {
      final tree = await writeTree({
        'with space/a/test/x_test.dart': "import 'helpers/h.dart';\r\n",
        'with space/a/test/helpers/h.dart':
            "void f() {\r\n  $_call('id', []);\r\n}\r\n",
      });

      final report = scanIntegrationTags(
        packagesRoot: Directory('${tree.path}/with space'),
        package: 'a',
        followedPackages: const ['a'],
        libraryPackages: const [],
        allowlist: const {},
      );

      expect(report.untaggedSpawning, [
        'test/x_test.dart: a/test/x_test.dart -> a/test/helpers/h.dart:2',
      ]);
    });

    test('an import cycle among helpers ends', () async {
      final report = await scan({
        'a/test/x_test.dart': "import 'helpers/h1.dart';\n",
        'a/test/helpers/h1.dart': "import 'h2.dart';\n",
        'a/test/helpers/h2.dart': "import 'h1.dart';\n",
      });

      expectClean(report);
    });

    test(
      'a tagged file with no spawn is tagged pure unless allowlisted',
      () async {
        final report = await scan(
          {'a/test/p_test.dart': _tagged, 'a/test/q_test.dart': _tagged},
          allowlist: {'test/q_test.dart': 'reason'},
        );

        const reason =
            'tagged integration, no spawn in its source or test/ imports';
        expect(report.taggedPure, ['test/p_test.dart: $reason']);
        expect(report.untaggedSpawning, isEmpty);
        expect(report.staleAllowlist, isEmpty);
      },
    );

    test('an allowlist entry that is missing or untagged is stale', () async {
      final report = await scan(
        {'a/test/u_test.dart': _pure},
        allowlist: {'test/gone_test.dart': 'r', 'test/u_test.dart': 'r'},
      );

      expect(report.staleAllowlist, [
        'test/gone_test.dart: listed but missing',
        'test/u_test.dart: listed but untagged',
      ]);
    });

    test('the guard file is not scanned', () async {
      final report = await scan({
        'a/test/$integrationGuardFileName': _spawning,
      });

      expectClean(report);
    });

    test(
      'a same-named file in a subfolder or with a prefix is scanned',
      () async {
        final report = await scan({
          'a/test/x_$integrationGuardFileName': _spawning,
          'a/test/sub/$integrationGuardFileName': _spawning,
        });

        const sub = 'test/sub/$integrationGuardFileName';
        const prefixed = 'test/x_$integrationGuardFileName';
        expect(report.untaggedSpawning, [
          '$sub: a/$sub:2',
          '$prefixed: a/$prefixed:2',
        ]);
      },
    );

    test('a conditional export follows its later URI', () async {
      final report = await scan({
        'a/test/x_test.dart':
            "export 'stub.dart' if (dart.library.io == 'true') 'real.dart';\n",
        'a/test/stub.dart': _pure,
        'a/test/real.dart': _spawning,
      });

      expect(report.untaggedSpawning, [
        'test/x_test.dart: a/test/x_test.dart -> a/test/real.dart:2',
      ]);
    });

    test('a part file that spawns is followed', () async {
      final report = await scan({
        'a/test/x_test.dart': "part 'x_part.dart';\n",
        'a/test/x_part.dart': _spawning,
      });

      expect(report.untaggedSpawning, [
        'test/x_test.dart: a/test/x_test.dart -> a/test/x_part.dart:2',
      ]);
    });

    test(
      'a file that spawns in its own source and carries the tag passes',
      () async {
        final report = await scan({
          'a/test/t_test.dart':
              "@Tags(['$integrationTag'])\nlibrary;\n$_spawning",
        });

        expectClean(report);
      },
    );
  });
}
