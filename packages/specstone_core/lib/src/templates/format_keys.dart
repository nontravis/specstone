/// How a key's value holds the keys under it.
enum KeyShape {
  /// A scalar or a plain list: no keys under it.
  value,

  /// One map: `children` are its keys.
  map,

  /// A list of maps: `children` are each entry's keys.
  entries,

  /// A list of maps in the defining layer, or an `add`/`remove` map above it.
  entriesOrChange,

  /// A plain list in the defining layer, or an `add`/`remove` map above it.
  valuesOrChange,
}

/// One form of an entry that takes two key sets by shape, such as a path-form
/// leftover home.
final class FormatVariant {
  /// Creates the form [name] holding [children].
  const new(this.name, this.children);

  /// The form name, such as `path` or `section`.
  final String name;

  /// The keys of this form.
  final List<FormatKey> children;
}

/// One key a loader accepts, with the line the format printout gives it.
final class FormatKey {
  /// Creates the key [name].
  ///
  /// [whenRequired] holds no comma and [valueForm] holds no `)`, so a printout
  /// line can mark them apart.
  const new(
    this.name, {
    required this.whenRequired,
    required this.valueForm,
    required this.meaning,
    this.shape = KeyShape.value,
    this.children = const [],
    this.variants = const [],
  });

  /// The key name as written in the file.
  final String name;

  /// `required`, `optional`, or the condition that makes the key required.
  final String whenRequired;

  /// What the value looks like, such as `string` or `list of strings`.
  final String valueForm;

  /// One short line saying what the key does.
  final String meaning;

  /// How the value holds the keys under it.
  final KeyShape shape;

  /// The keys under this one, for a [KeyShape.map] or entries shape.
  final List<FormatKey> children;

  /// The key sets of a two-shape entry, set in place of [children].
  final List<FormatVariant> variants;
}

const _entriesChangeKeys = <FormatKey>[
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
    meaning: 'merge key values of the entries to drop from the layer below',
  ),
];

const _valuesChangeKeys = <FormatKey>[
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
];

/// The `add` and `remove` keys of a key of change [shape], or null when its
/// shape takes no change map.
List<FormatKey>? _changeKeysOf(KeyShape? shape) => switch (shape) {
  KeyShape.entriesOrChange => _entriesChangeKeys,
  KeyShape.valuesOrChange => _valuesChangeKeys,
  _ => null,
};

/// Returns the key names under [dottedPath] of [table] (`''` for the top), in
/// table order, memoized per (table, path, change, variant).
///
/// A path joins key names with dots and holds no list index.
/// - [change]: the `{add, remove}` keys of an `entriesOrChange` or
///   `valuesOrChange` key's change map.
/// - [variant]: the keys of that named variant of a two-shape entry.
///
/// Throws StateError for an unknown path, a [change] on a key of another
/// shape, or an unknown [variant].
Set<String> formatKeysAt(
  List<FormatKey> table,
  String dottedPath, {
  bool change = false,
  String? variant,
}) {
  final memo = _memo.putIfAbsent(table, () => <String, Set<String>>{});
  final memoKey = '$dottedPath|$change|${variant ?? ''}';
  return memo.putIfAbsent(
    memoKey,
    () => Set.unmodifiable(
      _keysAt(table, dottedPath, change: change, variant: variant),
    ),
  );
}

final _memo = Map<List<FormatKey>, Map<String, Set<String>>>.identity();

Iterable<String> _keysAt(
  List<FormatKey> table,
  String dottedPath, {
  required bool change,
  required String? variant,
}) {
  final node = dottedPath.isEmpty ? null : _walkTo(table, dottedPath);
  if (change) {
    final keys = _changeKeysOf(node?.shape);
    if (keys == null) {
      throw StateError('"$dottedPath" takes no add and remove change map');
    }
    return keys.map((key) => key.name);
  }
  if (variant != null) {
    final form = node?.variants.where((v) => v.name == variant).firstOrNull;
    if (form == null) {
      throw StateError('"$dottedPath" has no variant "$variant"');
    }
    return form.children.map((key) => key.name);
  }
  if (node == null) return table.map((key) => key.name);
  if (node.variants.isNotEmpty) {
    throw StateError('"$dottedPath" holds variants: name one');
  }
  return node.children.map((key) => key.name);
}

FormatKey _walkTo(List<FormatKey> table, String dottedPath) {
  var level = table;
  late FormatKey node;
  for (final segment in dottedPath.split('.')) {
    final found = level.where((key) => key.name == segment).firstOrNull;
    if (found == null) {
      throw StateError('no key "$segment" in path "$dottedPath"');
    }
    node = found;
    level = [
      ...node.children,
      for (final form in node.variants) ...form.children,
    ];
  }
  return node;
}

const _capDefaultMeaning = 'the cap for every language the map does not name';

/// The `default` cap of a doc-level map; optional, as the map lays over the
/// built-in caps.
const _docCapDefault = FormatKey(
  'default',
  whenRequired: 'optional',
  valueForm: 'integer of 1 or more',
  meaning: _capDefaultMeaning,
);

/// The `default` cap of a field-level map, which the loader requires.
const _fieldCapDefault = FormatKey(
  'default',
  whenRequired: 'required',
  valueForm: 'integer of 1 or more',
  meaning: _capDefaultMeaning,
);

/// The languages a word cap names besides `default`.
const _wordLanguages = <FormatKey>[
  FormatKey(
    'ko',
    whenRequired: 'optional',
    valueForm: 'integer of 1 or more',
    meaning: 'the cap for Korean',
  ),
  FormatKey(
    'ar',
    whenRequired: 'optional',
    valueForm: 'integer of 1 or more',
    meaning: 'the cap for Arabic',
  ),
  FormatKey(
    'he',
    whenRequired: 'optional',
    valueForm: 'integer of 1 or more',
    meaning: 'the cap for Hebrew',
  ),
  FormatKey(
    'hi',
    whenRequired: 'optional',
    valueForm: 'integer of 1 or more',
    meaning: 'the cap for Hindi',
  ),
  FormatKey(
    'el',
    whenRequired: 'optional',
    valueForm: 'integer of 1 or more',
    meaning: 'the cap for Greek',
  ),
];

/// The languages a character cap names besides `default`.
const _charLanguages = <FormatKey>[
  FormatKey(
    'th',
    whenRequired: 'optional',
    valueForm: 'integer of 1 or more',
    meaning: 'the cap for Thai',
  ),
  FormatKey(
    'lo',
    whenRequired: 'optional',
    valueForm: 'integer of 1 or more',
    meaning: 'the cap for Lao',
  ),
  FormatKey(
    'km',
    whenRequired: 'optional',
    valueForm: 'integer of 1 or more',
    meaning: 'the cap for Khmer',
  ),
  FormatKey(
    'my',
    whenRequired: 'optional',
    valueForm: 'integer of 1 or more',
    meaning: 'the cap for Burmese',
  ),
  FormatKey(
    'zh',
    whenRequired: 'optional',
    valueForm: 'integer of 1 or more',
    meaning: 'the cap for Chinese',
  ),
  FormatKey(
    'ja',
    whenRequired: 'optional',
    valueForm: 'integer of 1 or more',
    meaning: 'the cap for Japanese',
  ),
];

const _wordsMeaning = 'most words one sentence holds, by language';

const _charsMeaning =
    'most characters one sentence holds in a script with no spaces, by '
    'language';

const _docWordsKey = FormatKey(
  'max_sentence_words',
  whenRequired: 'optional',
  valueForm: 'map of language to integer',
  meaning: _wordsMeaning,
  shape: KeyShape.map,
  children: [_docCapDefault, ..._wordLanguages],
);

const _docCharsKey = FormatKey(
  'max_sentence_chars',
  whenRequired: 'optional',
  valueForm: 'map of language to integer',
  meaning: _charsMeaning,
  shape: KeyShape.map,
  children: [_docCapDefault, ..._charLanguages],
);

/// A field's word cap; the loader refuses it without its char partner.
const _fieldWordsKey = FormatKey(
  'max_sentence_words',
  whenRequired: 'when max_sentence_chars is set',
  valueForm: 'map of language to integer',
  meaning: _wordsMeaning,
  shape: KeyShape.map,
  children: [_fieldCapDefault, ..._wordLanguages],
);

/// A field's char cap; the loader refuses it without its word partner.
const _fieldCharsKey = FormatKey(
  'max_sentence_chars',
  whenRequired: 'when max_sentence_words is set',
  valueForm: 'map of language to integer',
  meaning: _charsMeaning,
  shape: KeyShape.map,
  children: [_fieldCapDefault, ..._charLanguages],
);

const _patternRef = FormatKey(
  'pattern_ref',
  whenRequired: 'when no pattern is set',
  valueForm: 'string',
  meaning: 'the id of the shared pattern whose regex the entry takes',
);

const _bannedPatternKeys = <FormatKey>[
  FormatKey(
    'id',
    whenRequired: 'required',
    valueForm: 'string',
    meaning: 'the pattern id; the merge key',
  ),
  FormatKey(
    'pattern',
    whenRequired: 'when no pattern_ref is set',
    valueForm: 'regular expression',
    meaning: 'the text a finding fires on',
  ),
  _patternRef,
  FormatKey(
    'message',
    whenRequired: 'required',
    valueForm: 'string',
    meaning: 'what the finding says',
  ),
  FormatKey(
    'in',
    whenRequired: 'optional',
    valueForm: 'text or code or all',
    meaning: 'where the pattern looks; text when absent',
  ),
  FormatKey(
    'except',
    whenRequired: 'optional',
    valueForm: 'list of regular expressions',
    meaning: 'matched texts the pattern lets pass',
  ),
];

const _requiredPatternKeys = <FormatKey>[
  FormatKey(
    'id',
    whenRequired: 'required',
    valueForm: 'string',
    meaning: 'the pattern id; the merge key',
  ),
  FormatKey(
    'pattern',
    whenRequired: 'when no pattern_ref is set',
    valueForm: 'regular expression',
    meaning: 'the text the section must hold',
  ),
  _patternRef,
  FormatKey(
    'message',
    whenRequired: 'required',
    valueForm: 'string',
    meaning: 'what the finding says',
  ),
  FormatKey(
    'in',
    whenRequired: 'optional',
    valueForm: 'text or code or all',
    meaning: 'where the pattern looks; text when absent',
  ),
  FormatKey(
    'per_subsection',
    whenRequired: 'optional',
    valueForm: 'boolean',
    meaning: 'true makes each ### subsection match it',
  ),
];

const _sectionRefKeys = <FormatKey>[
  FormatKey(
    'id',
    whenRequired: 'required',
    valueForm: 'string',
    meaning: 'the section id',
  ),
  FormatKey(
    'header',
    whenRequired: 'required',
    valueForm: 'string',
    meaning: 'the section heading text',
  ),
];

const _fieldChildren = <FormatKey>[
  FormatKey(
    'id',
    whenRequired: 'required',
    valueForm: 'string',
    meaning: 'the frontmatter field id; the merge key',
  ),
  FormatKey(
    'type',
    whenRequired: 'new field',
    valueForm:
        'string or integer or boolean or date or enum or doc_ref or '
        'output_ref or source_ref or record_status or task_ref',
    meaning: 'what the field holds',
  ),
  FormatKey(
    'list',
    whenRequired: 'optional',
    valueForm: 'boolean',
    meaning: 'true makes the field a list of its type',
  ),
  FormatKey(
    'enum',
    whenRequired: 'when type is enum',
    valueForm: 'list of strings',
    meaning: 'the allowed values',
  ),
  FormatKey(
    'doc_types',
    whenRequired: 'optional',
    valueForm: 'list of strings',
    meaning: 'on a doc_ref field the doc type ids its target may have',
  ),
  FormatKey(
    'pointer',
    whenRequired: 'when type is output_ref',
    valueForm: 'exact or prefix or item_exact or item_test',
    meaning: 'the kind of pointer an output_ref entry holds',
  ),
  FormatKey(
    'root',
    whenRequired: 'optional',
    valueForm: 'code or project',
    meaning: 'on an output_ref field the root its paths resolve from',
  ),
  FormatKey(
    'bundle_with',
    whenRequired: 'optional',
    valueForm: 'boolean',
    meaning: 'true on a doc_ref field joins the docs it links into a bundle',
  ),
  FormatKey(
    'required',
    whenRequired: 'optional',
    valueForm: 'boolean',
    meaning: 'whether a doc must carry the field',
  ),
  FormatKey(
    'description',
    whenRequired: 'optional',
    valueForm: 'string',
    meaning: 'what the field holds',
  ),
  FormatKey(
    'lint',
    whenRequired: 'optional',
    valueForm: 'map',
    meaning: 'sentence caps that make a string field a prose field',
    shape: KeyShape.map,
    children: [
      FormatKey(
        'max_sentences',
        whenRequired: 'optional',
        valueForm: 'integer of 1 or more',
        meaning: 'most sentences the field holds',
      ),
      _fieldWordsKey,
      _fieldCharsKey,
    ],
  ),
  FormatKey(
    'disabled',
    whenRequired: 'optional',
    valueForm: 'boolean',
    meaning: 'true in an overriding layer turns the matched field off',
  ),
];

const _wordListKeys = <FormatKey>[
  FormatKey(
    'banned_words',
    whenRequired: 'optional',
    valueForm: 'list of strings or an add and remove map',
    meaning: 'words a finding fires on where the limit applies',
    shape: KeyShape.valuesOrChange,
  ),
  FormatKey(
    'allowed_words',
    whenRequired: 'optional',
    valueForm: 'list of strings or an add and remove map',
    meaning: 'words a ban lets pass where the limit applies',
    shape: KeyShape.valuesOrChange,
  ),
];

/// The keys a doc-type file accepts, at every level.
const docTypeFileFormat = <FormatKey>[
  FormatKey(
    'id',
    whenRequired: 'new doc type',
    valueForm: 'string',
    meaning: 'the doc type id; equals the file name without .yaml',
  ),
  FormatKey(
    'description',
    whenRequired: 'new doc type without extends',
    valueForm: 'string',
    meaning: 'the intro of the doc type guide',
  ),
  FormatKey(
    'path',
    whenRequired: 'new doc type without path_from',
    valueForm: 'string',
    meaning:
        'file pattern under the docs root; {nn} marks the number and {slug} '
        'the slug',
  ),
  FormatKey(
    'path_from',
    whenRequired: 'optional',
    valueForm: 'feature_groups',
    meaning: 'derives the patterns from the group levels of the feature path',
  ),
  FormatKey(
    'file',
    whenRequired: 'when path_from is set',
    valueForm: 'file name ending in .md',
    meaning: 'the doc file name each derived pattern ends with',
  ),
  FormatKey(
    'title',
    whenRequired: 'optional',
    valueForm: 'string',
    meaning: 'the fixed text of the # line of every doc of the type',
  ),
  FormatKey(
    'max_depth',
    whenRequired: 'optional',
    valueForm: 'integer of 0 or more',
    meaning: 'the folder nesting cap; 0 keeps the type flat',
  ),
  FormatKey(
    'per_target',
    whenRequired: 'optional',
    valueForm: 'boolean',
    meaning: 'true reads the type patterns once per target',
  ),
  FormatKey(
    'fixed_numbers',
    whenRequired: 'optional',
    valueForm: 'boolean',
    meaning: 'true keeps a doc number for good so reorder refuses the type',
  ),
  FormatKey(
    'parent',
    whenRequired: 'optional',
    valueForm: 'string',
    meaning: 'the parent doc type id; absent marks a top-level type',
  ),
  FormatKey(
    'extends',
    whenRequired: 'optional',
    valueForm: 'string',
    meaning: 'the doc type this one builds on',
  ),
  FormatKey(
    'fields',
    whenRequired: 'optional',
    valueForm: 'list of maps',
    meaning: 'the frontmatter fields of the type',
    shape: KeyShape.entries,
    children: _fieldChildren,
  ),
  FormatKey(
    'sections',
    whenRequired: 'optional',
    valueForm: 'list of maps',
    meaning: 'the sections of the type',
    shape: KeyShape.entries,
    children: [
      FormatKey(
        'id',
        whenRequired: 'required',
        valueForm: 'string',
        meaning: 'the section id; the merge key',
      ),
      FormatKey(
        'prefix_id',
        whenRequired: 'optional',
        valueForm: 'string',
        meaning: 'the id prefix of items in the section, such as PV-',
      ),
      FormatKey(
        'required',
        whenRequired: 'optional',
        valueForm: 'boolean',
        meaning: 'whether a doc must carry the section',
      ),
      FormatKey(
        'header',
        whenRequired: 'new section',
        valueForm: 'string',
        meaning: 'the section heading',
      ),
      FormatKey(
        'description',
        whenRequired: 'optional',
        valueForm: 'string',
        meaning: 'the guidance the guide prints for the section',
      ),
      FormatKey(
        'template',
        whenRequired: 'optional',
        valueForm: 'string',
        meaning: 'starter text that new writes',
      ),
      FormatKey(
        'lint',
        whenRequired: 'optional',
        valueForm: 'map',
        meaning: 'limits and rules for this section',
        shape: KeyShape.map,
        children: [
          FormatKey(
            'max_chars',
            whenRequired: 'optional',
            valueForm: 'integer',
            meaning: 'character limit of the section body',
          ),
          FormatKey(
            'max_lines',
            whenRequired: 'optional',
            valueForm: 'integer',
            meaning: 'line ceiling of the section body',
          ),
          ..._wordListKeys,
          FormatKey(
            'line_prefix',
            whenRequired: 'optional',
            valueForm: 'string',
            meaning:
                'limits the section banned words to lines starting with it',
          ),
          FormatKey(
            'banned_patterns',
            whenRequired: 'optional',
            valueForm: 'list of maps or an add and remove map',
            meaning: 'patterns a finding fires on in this section',
            shape: KeyShape.entriesOrChange,
            children: _bannedPatternKeys,
          ),
          FormatKey(
            'required_patterns',
            whenRequired: 'optional',
            valueForm: 'list of maps or an add and remove map',
            meaning: 'patterns this section must match',
            shape: KeyShape.entriesOrChange,
            children: _requiredPatternKeys,
          ),
          FormatKey(
            'min_lines',
            whenRequired: 'optional',
            valueForm: 'integer',
            meaning: 'floor of non-blank lines in the section',
          ),
          FormatKey(
            'catalog',
            whenRequired: 'optional',
            valueForm: 'map',
            meaning: 'marks each table holding the column as a code catalog',
            shape: KeyShape.map,
            children: [
              FormatKey(
                'column',
                whenRequired: 'required',
                valueForm: 'string',
                meaning: 'the header of the column that holds the codes',
              ),
            ],
          ),
          FormatKey(
            'names_codes',
            whenRequired: 'optional',
            valueForm: 'boolean',
            meaning: 'true lets a code span name a catalog code',
          ),
          FormatKey(
            'item_fields',
            whenRequired: 'optional',
            valueForm: 'list of maps or an add and remove map',
            meaning: 'fields each item of the section must carry',
            shape: KeyShape.entriesOrChange,
            children: [
              FormatKey(
                'field',
                whenRequired: 'required',
                valueForm: 'string',
                meaning: 'the item field name; the merge key',
              ),
              FormatKey(
                'values',
                whenRequired: 'optional',
                valueForm: 'list of strings',
                meaning: 'the values the field may hold',
              ),
              FormatKey(
                'when',
                whenRequired: 'optional',
                valueForm: 'map',
                meaning:
                    'requires the field only when another field has a '
                    'value; one of when and optional and default_from',
                shape: KeyShape.map,
                children: [
                  FormatKey(
                    'field',
                    whenRequired: 'required',
                    valueForm: 'string',
                    meaning: 'the other field',
                  ),
                  FormatKey(
                    'value',
                    whenRequired: 'required',
                    valueForm: 'string',
                    meaning: 'the value that makes the field required',
                  ),
                ],
              ),
              FormatKey(
                'optional',
                whenRequired: 'optional',
                valueForm: 'boolean',
                meaning:
                    'true lets an item leave the field out; false when '
                    'absent',
              ),
              FormatKey(
                'default_from',
                whenRequired: 'optional',
                valueForm: 'entities',
                meaning: 'takes the default from the entities section',
              ),
            ],
          ),
          FormatKey(
            'required_when',
            whenRequired: 'optional',
            valueForm: 'map',
            meaning: 'requires the section when a field of another has a value',
            shape: KeyShape.map,
            children: [
              FormatKey(
                'section',
                whenRequired: 'required',
                valueForm: 'string',
                meaning: 'the section the field sits in',
              ),
              FormatKey(
                'field',
                whenRequired: 'required',
                valueForm: 'string',
                meaning: 'the item field to read',
              ),
              FormatKey(
                'value',
                whenRequired: 'required',
                valueForm: 'string',
                meaning: 'the value that requires this section',
              ),
            ],
          ),
          FormatKey(
            'diagram',
            whenRequired: 'optional',
            valueForm: 'map',
            meaning: 'rules for the mermaid blocks of the section',
            shape: KeyShape.map,
            children: [
              FormatKey(
                'title',
                whenRequired: 'optional',
                valueForm: 'boolean',
                meaning: 'true checks the block title',
              ),
              FormatKey(
                'edge_labels',
                whenRequired: 'optional',
                valueForm: 'boolean',
                meaning: 'true checks the edge labels',
              ),
              FormatKey(
                'banned_labels',
                whenRequired: 'optional',
                valueForm: 'list of strings',
                meaning: 'labels a block may not hold',
              ),
              FormatKey(
                'names',
                whenRequired: 'optional',
                valueForm: 'boolean',
                meaning: 'true checks the node names',
              ),
            ],
          ),
          FormatKey(
            'max_sentences',
            whenRequired: 'optional',
            valueForm: 'list of maps',
            meaning: 'caps on sentences per line or per column cell',
            shape: KeyShape.entries,
            children: [
              FormatKey(
                'count',
                whenRequired: 'required',
                valueForm: 'integer',
                meaning: 'most sentences allowed',
              ),
              FormatKey(
                'line_prefix',
                whenRequired: 'optional',
                valueForm: 'string',
                meaning: 'limits the cap to lines starting with it',
              ),
              FormatKey(
                'column',
                whenRequired: 'optional',
                valueForm: 'string',
                meaning: 'limits the cap to the cells of one table column',
              ),
            ],
          ),
          FormatKey(
            'item_count',
            whenRequired: 'optional',
            valueForm: 'map',
            meaning: 'bounds on the number of items in the section',
            shape: KeyShape.map,
            children: [
              FormatKey(
                'min',
                whenRequired: 'optional',
                valueForm: 'integer',
                meaning: 'fewest items; at most max',
              ),
              FormatKey(
                'max',
                whenRequired: 'optional',
                valueForm: 'integer',
                meaning: 'most items',
              ),
              FormatKey(
                'per_subsection',
                whenRequired: 'optional',
                valueForm: 'boolean',
                meaning: 'true counts each ### subsection apart',
              ),
              FormatKey(
                'prefixes',
                whenRequired: 'optional',
                valueForm: 'list of maps',
                meaning: 'item counts per line prefix',
                shape: KeyShape.entries,
                children: [
                  FormatKey(
                    'line_prefix',
                    whenRequired: 'required',
                    valueForm: 'string',
                    meaning: 'the line opening to count',
                  ),
                  FormatKey(
                    'count',
                    whenRequired: 'required',
                    valueForm: 'integer',
                    meaning: 'how many lines start with it',
                  ),
                ],
              ),
              FormatKey(
                'waits_for',
                whenRequired: 'optional',
                valueForm: 'agent or owner',
                meaning:
                    'who the out-of-range finding waits for; agent when '
                    'absent',
              ),
            ],
          ),
          FormatKey(
            'max_subsections',
            whenRequired: 'optional',
            valueForm: 'integer of 1 or more',
            meaning: 'cap on the ### subsections of the section',
          ),
          FormatKey(
            'max_item_lines',
            whenRequired: 'optional',
            valueForm: 'integer of 1 or more',
            meaning: 'cap on the non-blank lines of each item',
          ),
          FormatKey(
            'max_code_blocks',
            whenRequired: 'optional',
            valueForm: 'map',
            meaning: 'cap on the fenced code blocks of the section',
            shape: KeyShape.map,
            children: [
              FormatKey(
                'count',
                whenRequired: 'required',
                valueForm: 'integer of 1 or more',
                meaning: 'most code blocks allowed',
              ),
              FormatKey(
                'per_subsection',
                whenRequired: 'optional',
                valueForm: 'boolean',
                meaning: 'true caps each ### subsection instead',
              ),
            ],
          ),
        ],
      ),
      FormatKey(
        'disabled',
        whenRequired: 'optional',
        valueForm: 'boolean',
        meaning: 'true in an overriding layer turns the matched section off',
      ),
      FormatKey(
        'after',
        whenRequired: 'optional',
        valueForm: 'string',
        meaning: 'in an adding layer the section the new one follows',
      ),
      FormatKey(
        'query',
        whenRequired: 'optional',
        valueForm: 'boolean',
        meaning: 'true keeps the section in a context bundle of mode query',
      ),
      FormatKey(
        'summary',
        whenRequired: 'optional',
        valueForm: 'boolean',
        meaning: 'true prints the section in a summary doc of a design bundle',
      ),
      FormatKey(
        'summary_rows',
        whenRequired: 'optional',
        valueForm: 'integer of 1 or more or false',
        meaning: 'body rows of the first table a summary doc prints',
      ),
      FormatKey(
        'skeleton',
        whenRequired: 'optional',
        valueForm: 'boolean',
        meaning: 'true puts an optional section header in the new skeleton',
      ),
      FormatKey(
        'when_field',
        whenRequired: 'optional',
        valueForm: 'map',
        meaning: 'binds the section to docs whose field holds a listed value',
        shape: KeyShape.map,
        children: [
          FormatKey(
            'field',
            whenRequired: 'required',
            valueForm: 'string',
            meaning: 'a field id of the doc type',
          ),
          FormatKey(
            'values',
            whenRequired: 'required',
            valueForm: 'list of strings',
            meaning: 'one or more values of the field',
          ),
        ],
      ),
      FormatKey(
        'output_ref',
        whenRequired: 'optional',
        valueForm: 'boolean',
        meaning: 'true marks verification_matrix lines as pointers to check',
      ),
    ],
  ),
  FormatKey(
    'lint',
    whenRequired: 'optional',
    valueForm: 'map',
    meaning: 'doc-level limits and rules',
    shape: KeyShape.map,
    children: [
      FormatKey(
        'max_chars',
        whenRequired: 'optional',
        valueForm: 'integer',
        meaning: 'character limit of a doc',
      ),
      FormatKey(
        'max_lines',
        whenRequired: 'optional',
        valueForm: 'integer',
        meaning: 'line ceiling of a doc',
      ),
      FormatKey(
        'max_item_chars',
        whenRequired: 'optional',
        valueForm: 'integer',
        meaning: 'character limit of one item; 600 when no layer writes it',
      ),
      ..._wordListKeys,
      FormatKey(
        'banned_patterns',
        whenRequired: 'optional',
        valueForm: 'list of maps or an add and remove map',
        meaning: 'patterns a finding fires on in a doc',
        shape: KeyShape.entriesOrChange,
        children: _bannedPatternKeys,
      ),
      FormatKey(
        'required_field_groups',
        whenRequired: 'optional',
        valueForm: 'list of lists of strings',
        meaning: 'a doc must fill at least one field of every group',
      ),
      _docWordsKey,
      _docCharsKey,
      FormatKey(
        'trace_note_last',
        whenRequired: 'optional',
        valueForm: 'boolean',
        meaning: 'true makes a trace note close its item',
      ),
      FormatKey(
        'title_no_number',
        whenRequired: 'optional',
        valueForm: 'boolean',
        meaning: 'true makes a digit in the # line a finding',
      ),
    ],
  ),
  FormatKey(
    'reference',
    whenRequired: 'optional',
    valueForm: 'list of maps or an add and remove map',
    meaning: 'sources the guide cites',
    shape: KeyShape.entriesOrChange,
    children: [
      FormatKey(
        'title',
        whenRequired: 'required',
        valueForm: 'string',
        meaning: 'the source name; the merge key',
      ),
      FormatKey(
        'url',
        whenRequired: 'optional',
        valueForm: 'string',
        meaning: 'a link shown as written; one of url and file and doc',
      ),
      FormatKey(
        'file',
        whenRequired: 'optional',
        valueForm: 'string',
        meaning:
            'a file inside the template folder; one of url and file and '
            'doc',
      ),
      FormatKey(
        'doc',
        whenRequired: 'optional',
        valueForm: 'string',
        meaning: 'a project doc identity; project layer only',
      ),
      FormatKey(
        'locator',
        whenRequired: 'optional',
        valueForm: 'string',
        meaning: 'chapter or page or appendix',
      ),
    ],
  ),
  FormatKey(
    'bundle',
    whenRequired: 'optional',
    valueForm: 'list of query or implement or design',
    meaning: 'the modes in which context adds every doc of the type',
    shape: KeyShape.valuesOrChange,
  ),
  FormatKey(
    'bundle_refs',
    whenRequired: 'optional',
    valueForm: 'boolean',
    meaning: 'sends the bundle join of the type to the refs file',
  ),
  FormatKey(
    'summary_for',
    whenRequired: 'optional',
    valueForm: 'list of strings',
    meaning:
        'doc types whose bundles print a cited doc of this type in '
        'summary',
  ),
  FormatKey(
    'generators',
    whenRequired: 'optional',
    valueForm: 'list of strings or an add and remove map',
    meaning: 'the generator kinds format and new run on a doc of the type',
    shape: KeyShape.valuesOrChange,
  ),
];

const _forDocTypes = FormatKey(
  'for_doc_types',
  whenRequired: 'new entry',
  valueForm: 'list of strings',
  meaning: 'the doc types the entry reaches',
);

const _sharedPatternExtras = <FormatKey>[
  FormatKey(
    'for_doc_types',
    whenRequired: 'new entry no pattern_ref names',
    valueForm: 'list of strings',
    meaning: 'the doc types the entry reaches',
  ),
  FormatKey(
    'sections',
    whenRequired: 'optional',
    valueForm: 'list of strings',
    meaning: 'limits the pattern to these section ids',
  ),
  FormatKey(
    'disabled',
    whenRequired: 'optional',
    valueForm: 'boolean',
    meaning: 'true turns the lower pattern off',
  ),
];

const _stepKinds = <FormatKey>[
  FormatKey(
    'rename_section',
    whenRequired: 'one per step',
    valueForm: 'map',
    meaning: 'renames a section id and header of a doc type',
    shape: KeyShape.map,
    children: [
      FormatKey(
        'doc_type',
        whenRequired: 'required',
        valueForm: 'string',
        meaning: 'the doc type id',
      ),
      FormatKey(
        'from',
        whenRequired: 'required',
        valueForm: 'map',
        meaning: 'the old section',
        shape: KeyShape.map,
        children: _sectionRefKeys,
      ),
      FormatKey(
        'to',
        whenRequired: 'required',
        valueForm: 'map',
        meaning: 'the new section',
        shape: KeyShape.map,
        children: _sectionRefKeys,
      ),
    ],
  ),
  FormatKey(
    'rename_field',
    whenRequired: 'one per step',
    valueForm: 'map',
    meaning: 'renames a frontmatter key of a doc type',
    shape: KeyShape.map,
    children: [
      FormatKey(
        'doc_type',
        whenRequired: 'required',
        valueForm: 'string',
        meaning: 'the doc type id',
      ),
      FormatKey(
        'from',
        whenRequired: 'required',
        valueForm: 'string',
        meaning: 'the old key',
      ),
      FormatKey(
        'to',
        whenRequired: 'required',
        valueForm: 'string',
        meaning: 'the new key',
      ),
    ],
  ),
  FormatKey(
    'move_file',
    whenRequired: 'one per step',
    valueForm: 'map',
    meaning: 'moves the docs of a type to a new path pattern',
    shape: KeyShape.map,
    children: [
      FormatKey(
        'doc_type',
        whenRequired: 'required',
        valueForm: 'string',
        meaning: 'the doc type id',
      ),
      FormatKey(
        'from',
        whenRequired: 'required',
        valueForm: 'string',
        meaning: 'the old path pattern',
      ),
      FormatKey(
        'to',
        whenRequired: 'required',
        valueForm: 'string',
        meaning: 'the new pattern; holds the placeholders of from in order',
      ),
    ],
  ),
  FormatKey(
    'relink_merged_docs',
    whenRequired: 'one per step',
    valueForm: 'empty map',
    meaning: 'rewrites links to docs a merge_doc step folded',
    shape: KeyShape.map,
  ),
  FormatKey(
    'bullet_lines',
    whenRequired: 'one per step',
    valueForm: 'map',
    meaning: 'turns bare lines of a section into bullet lines',
    shape: KeyShape.map,
    children: [
      FormatKey(
        'doc_type',
        whenRequired: 'required',
        valueForm: 'string',
        meaning: 'the doc type id',
      ),
      FormatKey(
        'section',
        whenRequired: 'required',
        valueForm: 'string',
        meaning: 'the section id',
      ),
      FormatKey(
        'prefixes',
        whenRequired: 'required',
        valueForm: 'list of strings',
        meaning: 'the bare line openings to turn into bullet lines',
      ),
    ],
  ),
  FormatKey(
    'drop_shared_lines',
    whenRequired: 'one per step',
    valueForm: 'map',
    meaning: 'drops shared lines the pack no longer defines',
    shape: KeyShape.map,
    children: [
      FormatKey(
        'ids',
        whenRequired: 'required',
        valueForm: 'list of strings',
        meaning: 'the shared line ids to drop',
      ),
    ],
  ),
  FormatKey(
    'mark_retrim',
    whenRequired: 'one per step',
    valueForm: 'map',
    meaning: 'marks sections so a doc is trimmed again',
    shape: KeyShape.map,
    children: [
      FormatKey(
        'doc_types',
        whenRequired: 'required',
        valueForm: 'list of strings',
        meaning: 'the doc type ids',
      ),
      FormatKey(
        'sections',
        whenRequired: 'required',
        valueForm: 'list of strings',
        meaning: 'the section ids to mark',
      ),
    ],
  ),
  FormatKey(
    'drop_section',
    whenRequired: 'one per step',
    valueForm: 'map',
    meaning: 'removes a section the merged type no longer defines',
    shape: KeyShape.map,
    children: [
      FormatKey(
        'doc_types',
        whenRequired: 'required',
        valueForm: 'list of strings',
        meaning: 'the doc type ids',
      ),
      FormatKey(
        'section',
        whenRequired: 'required',
        valueForm: 'map',
        meaning: 'the section to remove',
        shape: KeyShape.map,
        children: _sectionRefKeys,
      ),
    ],
  ),
  FormatKey(
    'merge_doc',
    whenRequired: 'one per step',
    valueForm: 'map',
    meaning: 'folds the docs of one doc type into another',
    shape: KeyShape.map,
    children: [
      FormatKey(
        'from',
        whenRequired: 'required',
        valueForm: 'map',
        meaning: 'the doc type folded away',
        shape: KeyShape.map,
        children: [
          FormatKey(
            'id',
            whenRequired: 'required',
            valueForm: 'string',
            meaning: 'the doc type id',
          ),
          FormatKey(
            'path',
            whenRequired: 'required',
            valueForm: 'string',
            meaning: 'its path pattern',
          ),
        ],
      ),
      FormatKey(
        'to',
        whenRequired: 'required',
        valueForm: 'string',
        meaning: 'the doc type id the sections move to',
      ),
      FormatKey(
        'sections',
        whenRequired: 'required',
        valueForm: 'list of maps',
        meaning: 'the section map from the old type to the new',
        shape: KeyShape.entries,
        children: [
          FormatKey(
            'from',
            whenRequired: 'required',
            valueForm: 'map',
            meaning: 'the old section',
            shape: KeyShape.map,
            children: _sectionRefKeys,
          ),
          FormatKey(
            'to',
            whenRequired: 'required',
            valueForm: 'string',
            meaning: 'the new section id',
          ),
        ],
      ),
    ],
  ),
  FormatKey(
    'drop_doc_type',
    whenRequired: 'one per step',
    valueForm: 'map',
    meaning: 'drops a doc type with no merge; writes no doc',
    shape: KeyShape.map,
    children: [
      FormatKey(
        'id',
        whenRequired: 'required',
        valueForm: 'string',
        meaning: 'the doc type id',
      ),
      FormatKey(
        'path',
        whenRequired: 'required',
        valueForm: 'string',
        meaning: 'its path pattern',
      ),
    ],
  ),
  FormatKey(
    'regenerate',
    whenRequired: 'one per step',
    valueForm: 'map',
    meaning: 'reruns generators over the docs root',
    shape: KeyShape.map,
    children: [
      FormatKey(
        'generators',
        whenRequired: 'required',
        valueForm: 'list of strings',
        meaning: 'the generator kinds to run',
      ),
    ],
  ),
];

/// The keys a `pack.yaml` accepts, at every level.
const packFileFormat = <FormatKey>[
  FormatKey(
    'name',
    whenRequired: 'required',
    valueForm: 'string',
    meaning: 'the pack name; equals its folder name and its packs key',
  ),
  FormatKey(
    'version',
    whenRequired: 'required',
    valueForm: 'MAJOR.MINOR.PATCH',
    meaning: 'the pack version; matched with the pin exactly',
  ),
  FormatKey(
    'extends',
    whenRequired: 'optional',
    valueForm: 'string',
    meaning: 'the pack this one builds on',
  ),
  FormatKey(
    'migrations',
    whenRequired: 'optional',
    valueForm: 'list of maps',
    meaning: 'the steps that bring a project from an older version',
    shape: KeyShape.entries,
    children: [
      FormatKey(
        'from',
        whenRequired: 'required',
        valueForm: 'MAJOR.MINOR.PATCH',
        meaning: 'the pack version the entry migrates from',
      ),
      FormatKey(
        'steps',
        whenRequired: 'required',
        valueForm: 'list of one-kind maps',
        meaning: 'the steps in order; each holds exactly one kind',
        shape: KeyShape.entries,
        children: _stepKinds,
      ),
    ],
  ),
  FormatKey(
    'leftover_homes',
    whenRequired: 'optional',
    valueForm: 'list of maps',
    meaning: 'where each leftover section or file of an old release goes',
    shape: KeyShape.entries,
    variants: [
      FormatVariant('path', [
        FormatKey(
          'path',
          whenRequired: 'required for a path home',
          valueForm: 'string',
          meaning: 'the path pattern of the leftover file',
        ),
        FormatKey(
          'to',
          whenRequired: 'required',
          valueForm: 'list of strings',
          meaning: 'the doc types the home names',
        ),
        FormatKey(
          'home',
          whenRequired: 'required',
          valueForm: 'string',
          meaning: 'one line saying where its statements go',
        ),
      ]),
      FormatVariant('section', [
        FormatKey(
          'doc_types',
          whenRequired: 'required for a section home',
          valueForm: 'list of strings',
          meaning: 'the doc types whose leftover section this names',
        ),
        FormatKey(
          'section',
          whenRequired: 'required for a section home',
          valueForm: 'map',
          meaning: 'the leftover section',
          shape: KeyShape.map,
          children: _sectionRefKeys,
        ),
        FormatKey(
          'to',
          whenRequired: 'required',
          valueForm: 'list of strings',
          meaning: 'the doc types the home names',
        ),
        FormatKey(
          'home',
          whenRequired: 'required',
          valueForm: 'string',
          meaning: 'one line saying where its statements go',
        ),
      ]),
    ],
  ),
  FormatKey(
    'shared_lines',
    whenRequired: 'optional',
    valueForm: 'list of maps',
    meaning: 'guide lines shared by several doc types',
    shape: KeyShape.entries,
    children: [
      FormatKey(
        'id',
        whenRequired: 'required',
        valueForm: 'slug',
        meaning: 'the line id; the merge key',
      ),
      FormatKey(
        'text',
        whenRequired: 'new line',
        valueForm: 'one line of text',
        meaning: 'the guide line',
      ),
      _forDocTypes,
      FormatKey(
        'disabled',
        whenRequired: 'optional',
        valueForm: 'boolean',
        meaning: 'true turns the lower line off',
      ),
    ],
  ),
  FormatKey(
    'shared_fields',
    whenRequired: 'optional',
    valueForm: 'list of maps',
    meaning: 'frontmatter fields shared by several doc types',
    shape: KeyShape.entries,
    children: [..._fieldChildren, _forDocTypes],
  ),
  FormatKey(
    'shared_banned_patterns',
    whenRequired: 'optional',
    valueForm: 'list of maps',
    meaning: 'banned patterns shared by several doc types',
    shape: KeyShape.entries,
    children: [..._bannedPatternKeys, ..._sharedPatternExtras],
  ),
  FormatKey(
    'shared_required_patterns',
    whenRequired: 'optional',
    valueForm: 'list of maps',
    meaning: 'required patterns shared by several doc types',
    shape: KeyShape.entries,
    children: [..._requiredPatternKeys, ..._sharedPatternExtras],
  ),
];

/// Returns the file format text: one line per key of [docTypeFileFormat] under
/// `==> doc type file <==`, then of [packFileFormat] under `==> pack.yaml <==`.
///
/// Keys print depth-first as `- `dotted.key` (when, form) — meaning`; a key two
/// variants share prints once.
String renderFileFormat() {
  final buffer = StringBuffer('==> doc type file <==\n');
  _writeTable(buffer, docTypeFileFormat);
  buffer.write('==> pack.yaml <==\n');
  _writeTable(buffer, packFileFormat);
  return buffer.toString();
}

void _writeTable(StringBuffer buffer, List<FormatKey> table) {
  final seen = <String>{};

  void line(String dotted, FormatKey key) {
    if (!seen.add(dotted)) return;
    buffer.writeln(
      '- `$dotted` (${key.whenRequired}, ${key.valueForm}) — ${key.meaning}',
    );
  }

  void walk(List<FormatKey> keys, String parent) {
    for (final key in keys) {
      final dotted = parent.isEmpty ? key.name : '$parent.${key.name}';
      line(dotted, key);
      walk(key.children, dotted);
      for (final variant in key.variants) {
        walk(variant.children, dotted);
      }
      for (final change in _changeKeysOf(key.shape) ?? const <FormatKey>[]) {
        line('$dotted.${change.name}', change);
      }
    }
  }

  walk(table, '');
}
