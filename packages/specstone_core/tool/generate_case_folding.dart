import 'dart:io';
import 'dart:isolate';

// markdown exports no case-folding table, so this reads its source.
import 'package:markdown/src/assets/case_folding.dart';

/// Renders the Dart source of `markdownCaseFolding`, a copy of [table] in its
/// order.
///
/// Each key and value is a single-quoted literal; a code point outside
/// printable ASCII, a quote, a backslash, and a `$` are written as `\u{...}`,
/// so the source holds no invisible character.
String renderCaseFolding(Map<String, String> table) {
  final out = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
    ..writeln('//')
    ..writeln('// Source: package:markdown/src/assets/case_folding.dart')
    ..writeln('// Script: tool/generate_case_folding.dart')
    ..writeln()
    ..writeln(
      "/// The case-folding table `markdown`'s `normalizeLinkLabel` folds a "
      'link',
    )
    ..writeln('/// label by, one UTF-16 unit at a time.')
    ..writeln('const markdownCaseFolding = <String, String>{');
  for (final MapEntry(:key, :value) in table.entries) {
    out.writeln('  ${_literal(key)}: ${_literal(value)},');
  }
  return (out..writeln('};')).toString();
}

/// The first and last printable ASCII code points.
const _printableFirst = 0x20;
const _printableLast = 0x7E;

/// The code points a single-quoted literal cannot hold as written.
const _quoted = {0x24, 0x27, 0x5C};

String _literal(String text) {
  final out = StringBuffer("'");
  for (final rune in text.runes) {
    final plain =
        rune >= _printableFirst &&
        rune <= _printableLast &&
        !_quoted.contains(rune);
    out.write(
      plain
          ? String.fromCharCode(rune)
          : '${r'\u'}{${rune.toRadixString(16).toUpperCase()}}',
    );
  }
  return (out..write("'")).toString();
}

Future<void> main() async {
  final libUri = Isolate.resolvePackageUriSync(
    Uri.parse('package:specstone_core/specstone_core.dart'),
  );
  if (libUri == null) {
    throw StateError('cannot resolve package:specstone_core');
  }
  final out = File.fromUri(
    libUri.resolve('src/index_query/case_folding.g.dart'),
  );
  await out.writeAsString(renderCaseFolding(caseFoldingMap));
}
