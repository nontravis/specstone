import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

const _guideMarker = 'guide line: ';

/// One pattern entry and where it sits in its doc type.
final class _Located {
  const new(this.where, this.entry);

  final String where;
  final PatternEntry entry;

  /// The guide line the entry's message names; null when it names none.
  String? get namedLine {
    final at = entry.message.indexOf(_guideMarker);
    return at < 0 ? null : entry.message.substring(at + _guideMarker.length);
  }
}

/// The doc-level and section-level pattern entries of [type].
Iterable<_Located> _entriesOf(MergedDocType type) sync* {
  for (final entry in type.lint.bannedPatterns ?? const <PatternEntry>[]) {
    yield _Located('${type.id} (doc)', entry);
  }
  for (final section in type.sections) {
    for (final entry in [
      ...?section.bannedPatterns,
      ...?section.requiredPatterns,
    ]) {
      yield _Located('${type.id}.${section.id}', entry);
    }
  }
}

List<String> _shippedPackNames() => {
  for (final key in shippedPackFiles.keys) key.substring(0, key.indexOf('/')),
}.toList()..sort();

/// Returns [pack] and every pack it extends, nearest first.
List<String> _chainOf(TemplateResolver resolver, String pack) {
  final chain = <String>[];
  String? next = pack;
  while (next != null) {
    chain.add(next);
    next = resolver.availableManifests([
      next,
    ], homeDirectory: null)[next]!.extendsPack;
  }
  return chain;
}

MergedSet _resolve(TemplateResolver resolver, String pack) => resolver
    .resolveCarried(packNames: _chainOf(resolver, pack), homeDirectory: null);

void main() {
  final resolver = TemplateResolver();

  for (final pack in _shippedPackNames()) {
    test('$pack prints each guide line a message names', () {
      for (final type in _resolve(resolver, pack).docTypes) {
        final guide = type.renderGuide();
        for (final located in _entriesOf(type)) {
          final line = located.namedLine;
          if (line == null) continue;
          expect(
            guide,
            contains(line),
            reason: '${located.where}, entry ${located.entry.id}',
          );
        }
      }
    });
  }

  test('the shipped packs hold messages that name a guide line', () {
    final named = [
      for (final pack in _shippedPackNames())
        for (final type in _resolve(resolver, pack).docTypes)
          for (final located in _entriesOf(type))
            if (located.namedLine != null) located,
    ];
    expect(named, isNotEmpty);
  });
}
