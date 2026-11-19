import 'dart:convert';

import 'package:specstone_core/src/templates/layer_source.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/pack_manifest.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

const _yamlExtension = '.yaml';

/// The shared lines that make up the readability bar, in print order.
const _barIds = [
  'one_rule_per_item',
  'cite_at_item_end',
  'one_example',
  'condition_first',
];

/// A size a `lint` key holds, such as `300 characters` or `5 lines`.
final _sizeBound = RegExp(
  r'\b\d[\d,]*\s*(characters?|chars|words?|lines?|sentences?|tokens?)\b',
  caseSensitive: false,
);

/// The opening word of a line that restates the guide's requirement line.
final _requirementWord = RegExp(r'^(Required|Optional)\b');

/// The guide labels a description line must not repeat.
const _guideLabels = ['Limits:', 'Banned words:', 'Fields (frontmatter):'];

final _titleLine = RegExp(r'^Title it\b');
final _itemShapeLine = RegExp(r'^Write one rule per\b');

/// One line of a description and where it sits in its doc type.
final class _DescribedLine {
  const new(this.where, this.text);

  final String where;
  final String text;

  String get shown => '$where: $text';
}

/// One shipped pack, resolved under its `extends` chain alone.
final class _Pack {
  const new({
    required this.name,
    required this.chain,
    required this.set,
    required this.ownIds,
    required this.manifests,
  });

  final String name;

  /// This pack and every pack it extends, nearest first.
  final List<String> chain;

  final MergedSet set;

  /// The ids of the doc types this pack's own files carry.
  final List<String> ownIds;

  /// The manifest of every pack in [chain], by name.
  final Map<String, PackManifest> manifests;

  Iterable<MergedDocType> get ownTypes sync* {
    for (final id in ownIds) {
      final type = set.lookup(id);
      if (type != null) yield type;
    }
  }
}

/// One check over a pack, returning a line for each break it finds.
final class _Check {
  const new(this.name, this.run);

  final String name;
  final List<String> Function(_Pack pack, Map<String, _Pack> packs) run;
}

List<String> _linesOf(String? text) => [
  for (final line in (text ?? '').split('\n'))
    if (line.trim().isNotEmpty) line.trim(),
];

/// The description lines of the doc, each section, and each declared field of
/// [type], never its shared lines.
List<_DescribedLine> _descriptionLines(MergedDocType type) => [
  for (final line in _linesOf(type.description))
    _DescribedLine('${type.id} (doc)', line),
  for (final section in type.sections)
    for (final line in _linesOf(section.description))
      _DescribedLine('${type.id}.${section.id}', line),
  for (final field in type.fields)
    if (!field.isBuiltIn)
      for (final line in _linesOf(field.description))
        _DescribedLine('${type.id}.${field.id} (field)', line),
];

String _normalized(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

bool _isShapeLine(String line) =>
    _titleLine.hasMatch(line) || _itemShapeLine.hasMatch(line);

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

Map<String, List<String>> _ownIdsByPack() {
  final ids = <String, List<String>>{};
  for (final key in shippedPackFiles.keys) {
    if (key.split('/') case [final pack, final file]
        when file != packManifestName && file.endsWith(_yamlExtension)) {
      ids
          .putIfAbsent(pack, () => [])
          .add(file.substring(0, file.length - _yamlExtension.length));
    }
  }
  return ids;
}

Map<String, PackManifest> _manifests() => {
  for (final key in shippedPackFiles.keys)
    if (key.split('/') case [final pack, packManifestName])
      pack: PackManifest.parse(utf8.decode(shippedPackFiles[key]!), file: key),
};

Map<String, _Pack> _shippedPacks() {
  final resolver = TemplateResolver();
  final ownIds = _ownIdsByPack();
  final manifests = _manifests();
  return {
    for (final name in manifests.keys.toList()..sort())
      name: _Pack(
        name: name,
        chain: _chainOf(resolver, name),
        set: resolver.resolveCarried(
          packNames: _chainOf(resolver, name),
          homeDirectory: null,
        ),
        ownIds: [...?ownIds[name]]..sort(),
        manifests: manifests,
      ),
  };
}

List<String> _sizeStates(_Pack pack, Map<String, _Pack> packs) => [
  for (final type in pack.ownTypes)
    for (final line in _descriptionLines(type))
      if (_sizeBound.hasMatch(line.text)) line.shown,
];

List<String> _guideRestates(_Pack pack, Map<String, _Pack> packs) => [
  for (final type in pack.ownTypes)
    for (final line in _descriptionLines(type))
      if (_requirementWord.hasMatch(line.text) ||
          _guideLabels.any(line.text.contains))
        line.shown,
];

List<String> _sharedRestates(_Pack pack, Map<String, _Pack> packs) {
  final found = <String>[];
  for (final type in pack.ownTypes) {
    final sharedFields = pack.set.shared.fieldsNaming(type.id);
    final sharedFieldIds = {for (final field in sharedFields) field.id};
    final shared = [
      for (final line in type.sharedLines) _normalized(line.text),
      for (final field in sharedFields)
        for (final line in _linesOf(field.entry.description)) _normalized(line),
    ];
    for (final line in _descriptionLines(type)) {
      if (line.where.endsWith('(field)') &&
          sharedFieldIds.contains(
            line.where.split('.').last.split(' ').first,
          )) {
        continue;
      }
      final text = _normalized(line.text);
      if (shared.any(text.contains)) found.add(line.shown);
    }
  }
  return found;
}

List<String> _sharedByThree(_Pack pack, Map<String, _Pack> packs) {
  final holders = <String, Set<String>>{};
  for (final type in pack.ownTypes) {
    for (final line in _linesOf(type.description)) {
      if (!_isShapeLine(line)) holders.putIfAbsent(line, () => {}).add(type.id);
    }
  }
  return [
    for (final MapEntry(:key, :value) in holders.entries)
      if (value.length >= 3) '${value.toList()..sort()}: $key',
  ];
}

List<String> _sharedByTwoPacks(_Pack pack, Map<String, _Pack> packs) {
  final found = <String>[];
  for (final ancestor in pack.chain.skip(1)) {
    final held = <String, String>{
      for (final id in packs[ancestor]!.ownIds)
        for (final line in _linesOf(
          packs[ancestor]!.set.lookup(id)?.description,
        ))
          if (!_isShapeLine(line)) line: id,
    };
    for (final type in pack.ownTypes) {
      for (final line in _linesOf(type.description)) {
        final other = held[line];
        // A doc type that overrides an ancestor's inherits its description.
        if (other != null && other != type.id && !_isShapeLine(line)) {
          found.add('${type.id} and $ancestor/$other: $line');
        }
      }
    }
    for (final mine in pack.manifests[pack.name]!.shared.lines) {
      for (final theirs in pack.manifests[ancestor]!.shared.lines) {
        if (_normalized(mine.text ?? '') != _normalized(theirs.text ?? '')) {
          continue;
        }
        final mineIds = mine.forDocTypes ?? const <String>[];
        final theirIds = theirs.forDocTypes ?? const <String>[];
        final problems = [
          if (mine.id == theirs.id) 'same id',
          if (mineIds.isEmpty || theirIds.isEmpty) 'names no doc type',
          if (mineIds.any((id) => !pack.ownIds.contains(id)))
            '${mine.id} names a doc type of another pack',
          if (theirIds.any((id) => !packs[ancestor]!.ownIds.contains(id)))
            '${theirs.id} names a doc type of another pack',
          if (mineIds.any(theirIds.contains)) 'both reach one doc type',
        ];
        if (problems.isNotEmpty) {
          found.add('${mine.id} and ${theirs.id}: ${problems.join(', ')}');
        }
      }
    }
  }
  return found;
}

List<String> _shapeStays(_Pack pack, Map<String, _Pack> packs) {
  final found = <String>[
    for (final line in pack.set.shared.lines)
      if (_isShapeLine(line.text) || line.text.contains('one rule per'))
        'shared line ${line.id} is a shape line',
  ];
  for (final type in pack.ownTypes) {
    final guide = type.renderGuide();
    final shapeAt = [
      for (final line in _linesOf(type.description))
        if (line.contains('one rule per')) guide.indexOf(line),
    ];
    if (shapeAt.isEmpty) continue;
    for (final id in _barIds) {
      final line = type.sharedLines.where((l) => l.id == id).firstOrNull;
      if (line == null) continue;
      if (guide.indexOf(line.text) < shapeAt.first) {
        found.add('${type.id}: $id prints before the item shape');
      }
    }
  }
  return found;
}

List<String> _sharedStandsAlone(_Pack pack, Map<String, _Pack> packs) {
  final lines = pack.set.shared.lines;
  return [
    for (final line in lines)
      for (final other in lines)
        if (other.id != line.id &&
            (RegExp('\\b${RegExp.escape(other.id)}\\b').hasMatch(line.text) ||
                (line.text != other.text && line.text.contains(other.text))))
          '${line.id} names ${other.id}',
  ];
}

void main() {
  final packs = _shippedPacks();

  const checks = <_Check>[
    _Check('no description line states a size a lint key holds', _sizeStates),
    _Check(
      'no description line repeats a requirement line or a guide label',
      _guideRestates,
    ),
    _Check(
      'no description line restates a shared entry that reaches its doc type',
      _sharedRestates,
    ),
    _Check(
      'no doc-level line shared by three doc types is left in the '
      'descriptions',
      _sharedByThree,
    ),
    _Check(
      'no doc-level line repeats between a pack and a pack it extends',
      _sharedByTwoPacks,
    ),
    _Check(
      'a title or item-shape line stays in each description, ahead of the '
      'readability bar',
      _shapeStays,
    ),
    _Check('a shared line names no other shared line', _sharedStandsAlone),
  ];

  for (final pack in packs.values) {
    for (final check in checks) {
      test('${pack.name}: ${check.name}', () {
        final found = check.run(pack, packs);
        expect(found, isEmpty, reason: found.join('\n'));
      });
    }
  }

  test('the shipped packs hold doc types and shared lines to check', () {
    expect(packs, isNotEmpty);
    for (final pack in packs.values) {
      expect(pack.ownIds, isNotEmpty, reason: pack.name);
      expect(pack.ownTypes, isNotEmpty, reason: pack.name);
    }
    expect([
      for (final pack in packs.values) ...pack.set.shared.lines,
    ], isNotEmpty);
  });
}
