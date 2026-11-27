import 'package:specstone_core/src/templates/format_keys.dart';
import 'package:specstone_core/src/templates/pack_migration.dart';
import 'package:test/test.dart';

const _docTypeTopKeys = [
  'id',
  'description',
  'path',
  'path_from',
  'file',
  'title',
  'max_depth',
  'per_target',
  'fixed_numbers',
  'parent',
  'extends',
  'fields',
  'sections',
  'lint',
  'reference',
  'bundle',
  'bundle_refs',
  'summary_for',
  'generators',
];

const _packTopKeys = [
  'name',
  'version',
  'extends',
  'migrations',
  'leftover_homes',
  'shared_lines',
  'shared_fields',
  'shared_banned_patterns',
  'shared_required_patterns',
];

const _stepKinds = {
  'rename_section',
  'rename_field',
  'move_file',
  'relink_merged_docs',
  'bullet_lines',
  'drop_shared_lines',
  'mark_retrim',
  'drop_section',
  'merge_doc',
  'drop_doc_type',
  'regenerate',
};

Iterable<FormatKey> _walk(List<FormatKey> keys) sync* {
  for (final key in keys) {
    yield key;
    yield* _walk(key.children);
    for (final variant in key.variants) {
      yield* _walk(variant.children);
    }
  }
}

String _line(String dotted, String when, String form, String meaning) =>
    '- `$dotted` ($when, $form) — $meaning';

/// The lines a depth-first walk of [table] builds before any dedup, one per
/// key reached; fills [viaVariant] with the dotted keys reached through a
/// two-shape entry's variants.
List<MapEntry<String, String>> _rawLines(
  List<FormatKey> table,
  Set<String> viaVariant,
) {
  final lines = <MapEntry<String, String>>[];

  void add(String dotted, FormatKey key) => lines.add(
    MapEntry(
      dotted,
      _line(dotted, key.whenRequired, key.valueForm, key.meaning),
    ),
  );

  void walk(List<FormatKey> keys, String parent, {required bool variant}) {
    for (final key in keys) {
      final dotted = parent.isEmpty ? key.name : '$parent.${key.name}';
      if (variant) viaVariant.add(dotted);
      add(dotted, key);
      walk(key.children, dotted, variant: variant);
      for (final form in key.variants) {
        walk(form.children, dotted, variant: true);
      }
      final change = switch (key.shape) {
        KeyShape.entriesOrChange => const [
          FormatKey(
            'add',
            whenRequired: 'optional',
            valueForm: 'list of maps',
            meaning: 'entries added to the layer below',
          ),
          FormatKey(
            'remove',
            whenRequired: 'optional',
            valueForm: 'list of strings',
            meaning:
                'merge key values of the entries to drop from the layer below',
          ),
        ],
        KeyShape.valuesOrChange => const [
          FormatKey(
            'add',
            whenRequired: 'optional',
            valueForm: 'list of strings',
            meaning: 'values added to the layer below',
          ),
          FormatKey(
            'remove',
            whenRequired: 'optional',
            valueForm: 'list of strings',
            meaning: 'values to drop from the layer below',
          ),
        ],
        _ => const <FormatKey>[],
      };
      for (final entry in change) {
        add('$dotted.${entry.name}', entry);
      }
    }
  }

  walk(table, '', variant: false);
  return lines;
}

List<String> _expectedLines(List<FormatKey> table) {
  final seen = <String>{};
  return [
    for (final line in _rawLines(table, {}))
      if (seen.add(line.key)) line.value,
  ];
}

void main() {
  test('formatKeysAt returns the top keys of the doc-type format in loader '
      'order', () {
    expect(
      formatKeysAt(docTypeFileFormat, '').toList(),
      equals(_docTypeTopKeys),
    );
  });

  test('formatKeysAt returns the item_count keys', () {
    expect(
      formatKeysAt(docTypeFileFormat, 'sections.lint.item_count'),
      equals({'min', 'max', 'per_subsection', 'prefixes', 'waits_for'}),
    );
  });

  test('formatKeysAt returns the pack.yaml top keys', () {
    expect(formatKeysAt(packFileFormat, '').toList(), equals(_packTopKeys));
  });

  test('an unknown path throws', () {
    expect(
      () => formatKeysAt(docTypeFileFormat, 'sections.nope'),
      throwsStateError,
    );
  });

  test('a change map holds add and remove', () {
    expect(
      formatKeysAt(docTypeFileFormat, 'bundle', change: true),
      equals({'add', 'remove'}),
    );
    expect(
      () => formatKeysAt(docTypeFileFormat, 'id', change: true),
      throwsStateError,
    );
  });

  test('each leftover home variant holds its own keys', () {
    expect(
      formatKeysAt(packFileFormat, 'leftover_homes', variant: 'path'),
      equals({'path', 'to', 'home'}),
    );
    expect(
      formatKeysAt(packFileFormat, 'leftover_homes', variant: 'section'),
      equals({'doc_types', 'section', 'to', 'home'}),
    );
    expect(
      () => formatKeysAt(packFileFormat, 'leftover_homes', variant: 'nope'),
      throwsStateError,
    );
  });

  test('the sentence cap languages come from the table at doc and field '
      'level', () {
    for (final (key, languages) in [
      ('max_sentence_words', {'default', 'ko', 'ar', 'he', 'hi', 'el'}),
      ('max_sentence_chars', {'default', 'th', 'lo', 'km', 'my', 'zh', 'ja'}),
    ]) {
      expect(
        formatKeysAt(docTypeFileFormat, 'lint.$key'),
        equals(languages),
        reason: key,
      );
      expect(
        formatKeysAt(docTypeFileFormat, 'fields.lint.$key'),
        equals(languages),
        reason: key,
      );
    }
  });

  test('each sentence cap key prints the rule its loader applies', () {
    final text = renderFileFormat();

    for (final (dotted, rule) in [
      ('lint.max_sentence_words', 'optional'),
      ('lint.max_sentence_words.default', 'optional'),
      ('lint.max_sentence_chars.default', 'optional'),
      ('fields.lint.max_sentence_words', 'when max_sentence_chars is set'),
      ('fields.lint.max_sentence_chars', 'when max_sentence_words is set'),
      ('fields.lint.max_sentence_words.default', 'required'),
      ('fields.lint.max_sentence_chars.default', 'required'),
      (
        'shared_fields.lint.max_sentence_words',
        'when max_sentence_chars is set',
      ),
      ('shared_fields.lint.max_sentence_chars.default', 'required'),
    ]) {
      expect(text, contains('\n- `$dotted` ($rule, '), reason: dotted);
    }
  });

  test('the migration step kinds come from the table', () {
    final kinds = formatKeysAt(packFileFormat, 'migrations.steps');

    expect(kinds, equals(migrationStepKinds));
    expect(kinds, equals(_stepKinds));
  });

  test('the file format opens with the doc type file line and holds the '
      'pack.yaml line after it', () {
    final lines = renderFileFormat().trimRight().split('\n');
    final packAt = lines.indexOf('==> pack.yaml <==');

    expect(lines.first, '==> doc type file <==');
    expect(lines.where((line) => line == '==> pack.yaml <==').length, 1);
    expect(
      lines.sublist(1, packAt).every((line) => line.startsWith('- `')),
      isTrue,
    );
  });

  test('each key prints once in table order as one line', () {
    final text = renderFileFormat();
    final packAt = text.indexOf('==> pack.yaml <==\n');
    final docTypeLines = text
        .substring('==> doc type file <==\n'.length, packAt)
        .trimRight()
        .split('\n');
    final packLines = text
        .substring(packAt + '==> pack.yaml <==\n'.length)
        .trimRight()
        .split('\n');

    expect(docTypeLines, _expectedLines(docTypeFileFormat));
    expect(packLines, _expectedLines(packFileFormat));
    expect(docTypeLines.toSet(), hasLength(docTypeLines.length));
    expect(packLines.toSet(), hasLength(packLines.length));
  });

  test('a dotted key repeats only between variants of one entry, with one '
      'line', () {
    for (final table in [docTypeFileFormat, packFileFormat]) {
      final viaVariant = <String>{};
      final byKey = <String, List<String>>{};
      for (final line in _rawLines(table, viaVariant)) {
        (byKey[line.key] ??= []).add(line.value);
      }

      for (final entry in byKey.entries.where((e) => e.value.length > 1)) {
        expect(viaVariant, contains(entry.key), reason: entry.key);
        expect(entry.value.toSet(), hasLength(1), reason: entry.key);
      }
    }
  });

  test('no printed key holds an uppercase letter, and sections.prefix_id '
      'prints', () {
    final text = renderFileFormat();
    final dotted = RegExp(
      '^- `([^`]+)`',
      multiLine: true,
    ).allMatches(text).map((match) => match[1]!);

    expect(dotted.where((key) => key.contains(RegExp('[A-Z]'))), isEmpty);
    expect(dotted, contains('sections.prefix_id'));
  });

  test('each pattern list prints pattern_ref after pattern, and pattern is '
      'required only without it', () {
    final lists = [
      for (final table in [docTypeFileFormat, packFileFormat])
        for (final key in _walk(table))
          if (key.children.any((child) => child.name == 'pattern')) key,
    ];

    expect(lists.map((key) => key.name), [
      'banned_patterns',
      'required_patterns',
      'banned_patterns',
      'shared_banned_patterns',
      'shared_required_patterns',
    ]);
    for (final list in lists) {
      final names = list.children.map((child) => child.name).toList();
      final pattern = list.children[names.indexOf('pattern')];
      final ref = list.children[names.indexOf('pattern') + 1];
      expect(ref.name, 'pattern_ref', reason: list.name);
      expect(pattern.whenRequired, 'when no pattern_ref is set');
      expect(ref.whenRequired, 'when no pattern is set');
      expect(ref.valueForm, 'string');
      expect(
        ref.meaning,
        'the id of the shared pattern whose regex the entry takes',
      );
    }
  });

  test('the shared pattern lists require for_doc_types of a new entry no '
      'pattern_ref names', () {
    for (final name in ['shared_banned_patterns', 'shared_required_patterns']) {
      final list = packFileFormat.singleWhere((key) => key.name == name);
      final forDocTypes = list.children.singleWhere(
        (key) => key.name == 'for_doc_types',
      );
      expect(forDocTypes.whenRequired, 'new entry no pattern_ref names');
    }
  });

  test('no table line breaks the printout field marks', () {
    final keys = [..._walk(docTypeFileFormat), ..._walk(packFileFormat)];

    for (final key in keys) {
      expect(key.whenRequired, isNot(contains(',')), reason: key.name);
      expect(key.valueForm, isNot(contains(')')), reason: key.name);
    }
  });
}
