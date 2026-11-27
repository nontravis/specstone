import 'dart:io';

import 'package:test/test.dart';

/// A kept hand-written read: `file` is relative to `packages/`, `snippet` is
/// the exact source text the sweep reports, `reason` says why it reads no
/// reference.
typedef _Allowed = ({String file, String snippet, String reason});

const _grammarFile = 'specstone_core/lib/src/doc_model/reference_grammar.dart';

_Allowed _core(String file, String snippet, String reason) =>
    (file: 'specstone_core/lib/src/$file', snippet: snippet, reason: reason);

/// The kept sites, each with the reason it reads no reference (ledger P6).
final _allowed = <_Allowed>[
  // File name mapping.
  _core(
    'index_query/out_file.dart',
    r"""RegExp(r'[/\\:#@<>"|?*\u0000-\u001f\u007f]'""",
    'Maps file-name-unsafe characters to `-`, reads no reference.',
  ),
  // Markdown syntax: heading, table, blockquote, and definition shapes.
  _core(
    'consistency_check/fr_trace_rows.dart',
    r"""RegExp(r'^:?-+:?$'""",
    'Table delimiter cell, no reference.',
  ),
  _core(
    'consistency_check/catalog_rules.dart',
    r"""RegExp(r'^:?-{3,}:?$'""",
    'Table delimiter cell, no reference.',
  ),
  _core(
    'consistency_check/section_rules.dart',
    """RegExp('^#{1,6} '""",
    'ATX heading marker, no reference.',
  ),
  _core(
    'consistency_check/section_rules.dart',
    """RegExp('^> [A-Za-z-]+: '""",
    'Blockquote label such as `> Note:`, no reference.',
  ),
  _core(
    'index_query/item_facts.dart',
    r"""RegExp(r'^([ \t]*(?:>[ \t]?)+)[a-z]{2}:[ \t]*'""",
    'Quote line language marker such as `> en:`, no reference.',
  ),
  _core(
    'consistency_check/section_fields.dart',
    r"""RegExp(r'^\*\*(.+?)\:\*\*\s*(.*)$'""",
    'Matches a `- **<field>:** <text>` label, no reference.',
  ),
  _core(
    'consistency_check/goal_measurement_rules.dart',
    r"""RegExp(r'^(?:- )?\*\*Metric:\*\*'""",
    'Matches the `**Metric:**` label; its links are read apart.',
  ),
  _core(
    'consistency_check/trace_rules.dart',
    r"""RegExp(r'^(?:- )?\*\*Serves:\*\*(.*)$'""",
    'Matches the `**Serves:**` label; its IDs are read apart.',
  ),
  _core(
    'consistency_check/tree_rules.dart',
    r"""RegExp(r'^(.*[^/]): cannot be read; skipped$'""",
    'Reads a tree-walk warning message, no reference.',
  ),
  _core(
    'consistency_check/diagram_rules.dart',
    """RegExp(':::[A-Za-z0-9_]+'""",
    'Mermaid class shorthand `:::name`, no reference.',
  ),
  _core(
    'consistency_check/diagram_rules.dart',
    r"""RegExp( '^($_sequenceId)\\s*(?:-->>|->>|--x|-x|--\\)|-\\)|-->|->)\\s*[+-]?\\s*' '($_sequenceId)\\s*:'""",
    'Mermaid sequence message line `A->>B: text`, no reference.',
  ),
  _core(
    'doc_model/doc.dart',
    r"""RegExp(r'^ {0,3}##(?:[ \t]|$)'""",
    'Level-2 heading line splitting a doc into sections.',
  ),
  _core(
    'doc_model/markdown_body.dart',
    r"""RegExp(r'[\[<@]|://|www\.'""",
    'Block gate: text that cannot start any inline syntax skips the pass.',
  ),
  _core(
    'doc_model/doc_anchors.dart',
    """RegExp( '&(?:[a-zA-Z][a-zA-Z0-9]*|#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6});'""",
    'HTML character reference such as `&#38;`, no reference.',
  ),
  // Report lines of `approve --auto`: label and heading shapes of a report.
  _core(
    'document_writing/report_grammar.dart',
    r"""RegExp(r'^## Round [0-9]+[ \t]*$'""",
    'Round heading line of an audit report, no reference.',
  ),
  _core(
    'document_writing/report_grammar.dart',
    r"""RegExp(r'^(Audited|Styled): ([^\s@]+)@([0-9a-f]{12})$'""",
    'Report label line; the name in it is read by readDocAddress.',
  ),
  _core(
    'document_writing/report_grammar.dart',
    r"""RegExp( r'^(Findings|Outside the drafts|Outside the round):(?:[ \t]+(.*))?$'""",
    'Report section label line, no reference.',
  ),
  _core(
    'document_writing/report_grammar.dart',
    r"""RegExp(r'^Queued: (.+)$'""",
    'Report label line; the name in it is read by leadNameOf.',
  ),
  _core(
    'document_writing/report_grammar.dart',
    """RegExp('^(?:NOT ADDRESSED: )?(?:check: )?`?'""",
    'Report item lead labels, dropped before the name is read.',
  ),
  _core(
    'document_writing/report_grammar.dart',
    r"""RegExp(r'^Verdicts:$'""",
    'Report section label line, no reference.',
  ),
  _core(
    'document_writing/report_grammar.dart',
    r'''RegExp(r"^[A-Z][A-Za-z ']*:(?: |$)"''',
    'Report label line such as `Lenses:`, no reference.',
  ),
  _core(
    'document_writing/report_grammar.dart',
    r"""RegExp(r'^#{1,6}(?:[ \t]|$)'""",
    'ATX heading line of a report, no reference.',
  ),
  _core(
    'document_writing/report_grammar.dart',
    r"""RegExp(r'^D([0-9]+)(?=[ :(]|$)'""",
    'Decision key `D<n>` of a report line, not a doc reference.',
  ),
  // Frontmatter key block: the key line, not a reference.
  _core(
    'document_writing/key_block_values.dart',
    """.indexOf(':'""",
    'Finds the colon after the key name; values go to the grammar.',
  ),
  // Mentions: prose paths, read by design (no grammar form for prose).
  _core(
    'document_writing/rewrite_mentions.dart',
    """.indexOf('#'""",
    'Mention reader: cuts a prose path token at its `#`.',
  ),
  // A file-system path segment, not a doc reference.
  _core(
    'document_writing/journal_bounds.dart',
    """.indexOf(':'""",
    'Cuts an NTFS alternate-stream suffix off a path segment.',
  ),
  // A code path with a line, not a doc reference.
  _core(
    'index_query/code_bundle.dart',
    """.indexOf(':'""",
    'Cuts the `path:line` of an `implements` entry, a code path.',
  ),
  // A record entry line, not a doc reference.
  _core(
    'index_query/record_entries.dart',
    """.indexOf(':'""",
    'Cuts a record entry line at its `:` marks, no reference.',
  ),
  // A task ref entry (`<item>:<task id>`), not a doc reference.
  _core(
    'doc_model/task_ref.dart',
    """.lastIndexOf(':'""",
    'Cuts a task ref entry at its last `:`, a task id, no doc reference.',
  ),
  _core(
    'index_query/link_blocks.dart',
    r"""RegExp(r'^#+$'""",
    'Empty ATX heading, no reference.',
  ),
  _core(
    'index_query/link_scan.dart',
    r"""RegExp(r'(?:https?|ftp)://|www\.'""",
    'Bare web address autolink, no doc reference.',
  ),
  _core(
    'journeys/journey_steps.dart',
    r"""RegExp(r'^### ([0-9]+[a-z]*)\. (.+)$'""",
    '`_stepHeading`: a StepNumber is no item ID.',
  ),
  _core(
    'setup_migration/upgrade_plan.dart',
    r"""RegExp('^${RegExp.escape(block.key)}(?=\\s*:)'""",
    'Upgrade reader: finds a frontmatter key line by name.',
  ),
  _core(
    'setup_migration/merge_doc_step.dart',
    ".indexOf(':'",
    'Merge reader: takes the text after a YAML key colon, no reference.',
  ),
  // File-system paths, not references.
  _core(
    'templates/project_config.dart',
    """RegExp('^[A-Za-z]:'""",
    'Windows drive letter of a file-system path.',
  ),
  _core(
    'templates/reference_entry.dart',
    r"""RegExp(r'^[A-Za-z][A-Za-z0-9+.\-]*:'""",
    'Scheme or drive prefix of a template file path.',
  ),
  _core(
    'executable_lookup.dart',
    ".split(':'",
    'Splits the POSIX PATH variable into folders.',
  ),
  _core(
    'executable_lookup.dart',
    r"""RegExp(r'^(?:[A-Za-z]:[\\/]|\\\\)'""",
    'Windows drive or UNC prefix of a PATH folder.',
  ),
  // Finding message text read by the test-time guard, not a doc.
  _core(
    'consistency_check/message_key_guard.dart',
    r"""RegExp(r'\[[^\]]*\]\([^)\s]*\)'""",
    'Finds a markdown link a finding message prints, not read from a doc.',
  ),
  _core(
    'consistency_check/message_key_guard.dart',
    """.split('#'""",
    'Splits a joined `item#edge` value a finding message prints.',
  ),
  // Sync file and commit message grammar, not a doc reference.
  _core(
    'document_writing/sync_lines.dart',
    r"""RegExp(r'^(\S+) (\S(?:.*?\S)?): (\S.*)$'""",
    'Splits a `set --sync` mismatch line, no doc reference.',
  ),
  _core(
    'index_query/sync_task_closes.dart',
    r"""RegExp( '(?<!$_word)(?:$_closingWords)(?!$_word):?[ \\t]+'""",
    'Finds a closing word in a commit message, no doc reference.',
  ),
  _core(
    'index_query/sync_task_closes.dart',
    r"""RegExp( '#(?:$_closingWords|done)(?!$_word)'""",
    'Finds a `#close` command in a commit message, no doc reference.',
  ),
];

/// A `split`, `indexOf`, or `lastIndexOf` call whose argument is `#` or `:`.
final _splitCall = RegExp(
  r'''\.(?:split|indexOf|lastIndexOf)\(\s*(?:'[#:]'|"[#:]")''',
);

/// A `RegExp(` call with its adjacent string literals.
final _regExpCall = RegExp(
  r'''RegExp\(\s*(?:r?'(?:[^'\\]|\\.)*'|r?"(?:[^"\\]|\\.)*")'''
  r'''(?:\s*(?:r?'(?:[^'\\]|\\.)*'|r?"(?:[^"\\]|\\.)*"))*''',
);

/// A pattern text that reads `#`, `:`, a step number, `Scenario`, an ID's
/// digits after its prefix's `-`, or a link's `](`.
final _referenceShaped = RegExp(
  r'#|:|S\[0-9\]|S\\d|Scenario|-\\d|-\[0-9\]|\]\\?\(',
);

/// Regex group syntax `(?:`, `(?=`, `(?!`, `(?<` holds a `:` and reads nothing.
final _groupSyntax = RegExp(r'\(\?[:=!<]');

/// Every Dart file under `lib/` of the two packages, in path order.
List<File> _sources() {
  final packages = _packagesDir();
  return [
    for (final name in const ['specstone_core', 'specstone'])
      for (final entity in Directory.fromUri(
        packages.uri.resolve('$name/lib/'),
      ).listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart')) entity,
  ]..sort((a, b) => a.path.compareTo(b.path));
}

/// Returns the `packages/` folder, found by walking up from the test's
/// working directory.
Directory _packagesDir() {
  var dir = Directory.current;
  while (!Directory.fromUri(dir.uri.resolve('packages/')).existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('packages/ not found above ${Directory.current.path}');
    }
    dir = parent;
  }
  return Directory.fromUri(dir.uri.resolve('packages/'));
}

String _withoutComments(String text) => text
    .split('\n')
    .map((line) => line.trimLeft().startsWith('//') ? '' : line)
    .join('\n');

/// Returns [file]'s path relative to `packages/`, with `/` separators.
String _relative(File file) => file.path
    .substring(_packagesDir().uri.toFilePath().length)
    .replaceAll(r'\', '/');

/// Returns `<relative file>: <snippet>` for each reference-shaped read.
List<({String file, String snippet})> _sites(File file) {
  final relative = _relative(file);
  if (relative == _grammarFile) return const [];
  final text = _withoutComments(file.readAsStringSync());
  return [
    for (final m in _splitCall.allMatches(text))
      (file: relative, snippet: m.group(0)!.replaceAll(RegExp(r'\s+'), ' ')),
    for (final m in _regExpCall.allMatches(text))
      if (_referenceShaped.hasMatch(m.group(0)!.replaceAll(_groupSyntax, '')))
        (file: relative, snippet: m.group(0)!.replaceAll(RegExp(r'\s+'), ' ')),
  ];
}

/// One group 3 rule: `pattern` matches a read or write that only the
/// `exempt` files may hold; any other match in a source `appliesTo` fails
/// unless `allowed` lists it.
typedef _Rule = ({
  String name,
  String remedy,
  RegExp pattern,
  Set<String> exempt,
  List<_Allowed> allowed,
  bool Function(String text) appliesTo,
});

String _lib(String file) => 'specstone_core/lib/src/$file';

const _indexQueryImport = 'package:specstone_core/src/index_query/';

/// A `RegExp(` call whose first string literal holds [inner], a regex source.
RegExp _regExpLiteralWith(String inner) => RegExp(
  "RegExp\\(\\s*r?(?:'[^'\\n]*(?:$inner)[^'\\n]*'"
  '|"[^"\\n]*(?:$inner)[^"\\n]*")',
);

bool _everySource(String text) => true;

/// Whether [text] reads number labels, through `number_label.dart`.
bool _readsLabels(String text) => text.contains('number_label.dart');

final String _approvalFile = _lib('document_writing/approval.dart');

/// A `RegExp` literal that reads a number label: `F-`, `US-`, or `FR-` as
/// literal text or a group (`(F|US|FR)-`, `[FU]S?-`), or `us`/`fr` before a
/// digit class, a capture group included (`us(\d+)`), in a raw string or
/// not.
final RegExp _labelRead = _regExpLiteralWith(
  r'\b(?:F|US|FR)\b[|)\]?]*-|\[FU\]S\?-|[Uu][Ss]\(?\\{1,2}d|[Ff][Rr]\(?\\{1,2}d',
);

/// A `WaitsFor.owner` or `WaitsFor.agent` value, or the `waitsFor` JSON key.
final RegExp _waitsForWrite = RegExp(
  r'''\bWaitsFor\.(?:owner|agent)\b|\x27waitsFor\x27|"waitsFor"''',
);

/// The `TBR` marker text (`TBR`, then an em dash) or the bare `'TBR'` word as
/// a string literal.
final RegExp _tbrMarkerRead = RegExp(
  r'''TBR[ ]?(?:—|\\u\{?2014)|\x27TBR\x27|"TBR"''',
);

/// A sentence split: a character class or set holding `.`, `?`, and `!`, or a
/// `'. '` literal.
final RegExp _sentenceSplit = RegExp(
  r'''\[[.?!\\]{3,6}\]'''
  r'''|\{(?=[^}]*0x2[Ee])(?=[^}]*0x3[Ff])(?=[^}]*0x21)[^}]*\}'''
  r'''|\x27\. \x27|"\. "''',
);

/// A read of a naming line: `startsWith('==>')`, `endsWith(' <==')`,
/// `contains(' <==')`, or a `RegExp` literal holding `==>`.
final RegExp _namingLineRead = RegExp(
  r'''startsWith\(\s*[\x27"]==>|endsWith\(\s*[\x27"] <==[\x27"]'''
  r'''|contains\(\s*[\x27"] <==[\x27"]|'''
  '${_regExpLiteralWith('==>').pattern}',
);

final _rules = <_Rule>[
  (
    name: 'a number label is read only by number_label',
    remedy: 'Read the label through doc_model/number_label.dart.',
    pattern: _labelRead,
    exempt: {_lib('doc_model/number_label.dart')},
    allowed: [],
    appliesTo: _everySource,
  ),
  (
    name: 'a label reader parses no fence or code span of its own',
    remedy:
        'Use blockScan, fenceScan, or codeSpansOf; they are the one fence '
        'and code-span parser.',
    pattern: RegExp(
      r'''\x27`\x27|"`"|\x27~~~\x27|"~~~"|`{3}|0x60\b|0x7[Ee]\b''',
    ),
    exempt: {},
    allowed: [],
    appliesTo: _readsLabels,
  ),
  (
    name: 'an approved: line is written only by withApprovalHash',
    remedy: 'Write the stamp through withApprovalHash in approval.dart.',
    pattern: RegExp(
      r'''\x27[^\x27\n]*\bapproved:[^\x27\n]*\x27|"[^"\n]*\bapproved:[^"\n]*"''',
    ),
    exempt: {_approvalFile},
    allowed: [],
    appliesTo: _everySource,
  ),
  (
    name: 'the approved value is read only by approval and the index',
    remedy: 'Read it through ApprovalFields in approval.dart.',
    pattern: RegExp(
      r'''\[\s*(?:\x27approved\x27|"approved"|_approvedKey)\s*\]'''
      r'''|loadYaml\w*\([^;)]*[aA]pproved''',
    ),
    exempt: {_approvalFile, _lib('index_query/indexed_doc.dart')},
    allowed: [],
    appliesTo: _everySource,
  ),
  (
    name: 'a waitsFor value is written only by its four owners',
    remedy:
        'Set it in finding.dart (the kind default), tracked_links.dart, '
        'agent_block_rules.dart, or clean_draft_judge.dart (an approve --auto '
        'ask); no other rule names owner or agent.',
    pattern: _waitsForWrite,
    exempt: {
      _lib('consistency_check/finding.dart'),
      _lib('consistency_check/tracked_links.dart'),
      _lib('consistency_check/agent_block_rules.dart'),
      _lib('document_writing/clean_draft_judge.dart'),
    },
    allowed: [],
    appliesTo: _everySource,
  ),
  (
    name: 'the TBR marker is read only by tbr_marker',
    remedy: 'Read the marker through tbrMarkerLinesIn in doc_model/tbr_marker.dart.',
    pattern: _tbrMarkerRead,
    exempt: {_lib('doc_model/tbr_marker.dart')},
    allowed: [],
    appliesTo: _everySource,
  ),
  (
    name: 'items are read only by item_facts',
    remedy:
        'Read an item through DocContent.itemFacts in '
        'index_query/item_facts.dart.',
    pattern: RegExp(r'\b(?:itemsOf|sectionItemsOf)\('),
    exempt: {
      _lib('doc_model/doc_items.dart'),
      _lib('index_query/item_facts.dart'),
      // The one context accessor every check rule reads items by.
      _lib('consistency_check/check_context.dart'),
      // Walks the item structure only, to span an item; an item's
      // ID is read by item_facts' `itemKeyOfHead`, never here.
      _lib('index_query/item_links.dart'),
    },
    allowed: [],
    appliesTo: _everySource,
  ),
  (
    name: 'a sentence is split only by sentences',
    remedy: 'Cut sentences through sentencesOf in doc_model/sentences.dart.',
    pattern: _sentenceSplit,
    exempt: {_lib('doc_model/sentences.dart')},
    allowed: [],
    appliesTo: _everySource,
  ),
  (
    name: 'a naming line is read only by read_answer',
    remedy: 'Read it through readNamingLine in index_query/read_answer.dart.',
    pattern: _namingLineRead,
    exempt: {_lib('index_query/read_answer.dart')},
    allowed: [],
    appliesTo: _everySource,
  ),
];

/// Returns `<file>: <snippet>` for each match of [rule] outside its exempt
/// files that its allow list does not name, and the allow entries it uses.
({List<String> unlisted, Set<_Allowed> used}) _hitsOf(_Rule rule) {
  final unlisted = <String>[];
  final used = <_Allowed>{};
  for (final file in _sources()) {
    final relative = _relative(file);
    if (rule.exempt.contains(relative)) continue;
    final source = file.readAsStringSync();
    if (!rule.appliesTo(source)) continue;
    final text = _withoutComments(source);
    for (final m in rule.pattern.allMatches(text)) {
      final snippet = m.group(0)!.replaceAll(RegExp(r'\s+'), ' ');
      final entry = rule.allowed.where(
        (a) => a.file == relative && a.snippet == snippet,
      );
      if (entry.isEmpty) {
        unlisted.add('$relative: $snippet');
      } else {
        used.add(entry.first);
      }
    }
  }
  return (unlisted: unlisted, used: used);
}

void main() {
  for (final rule in _rules) {
    test(rule.name, () {
      final (:unlisted, :used) = _hitsOf(rule);
      if (unlisted.isNotEmpty) {
        fail('${rule.remedy}\n${unlisted.toSet().join('\n')}');
      }
      final stale = [
        for (final a in rule.allowed)
          if (!used.contains(a)) '${a.file}: ${a.snippet}',
      ];
      if (stale.isNotEmpty) {
        fail(
          'Remove the allow-list entries no site hits:\n${stale.join('\n')}',
        );
      }
    });
  }

  test('the label rule catches a label read in each spelling, groups '
      'included', () {
    for (final source in [
      r"RegExp(r'FR-\d')",
      r"RegExp(r'^(F|US|FR)-(\d+)')",
      r"RegExp(r'[FU]S?-\d')",
      r"RegExp(r'^us(\d+)_')",
      r"RegExp(r'fr(\d+)')",
      r"RegExp('us\\d')",
    ]) {
      expect(_labelRead.hasMatch(source), isTrue, reason: source);
    }
    expect(_labelRead.hasMatch(r"RegExp(r'^[a-z]+-\d')"), isFalse);
  });

  test('the waitsFor rule catches each way to write a value', () {
    for (final source in [
      'WaitsFor.owner',
      'x == WaitsFor.agent',
      "'waitsFor': 'owner'",
      '"waitsFor"',
    ]) {
      expect(_waitsForWrite.hasMatch(source), isTrue, reason: source);
    }
    expect(_waitsForWrite.hasMatch('WaitsFor? waitsFor'), isFalse);
  });

  test('the TBR rule catches the marker and the bare word', () {
    for (final source in [
      "const m = 'TBR — ';",
      r"'TBR \u2014 '",
      "contains('TBR')",
    ]) {
      expect(_tbrMarkerRead.hasMatch(source), isTrue, reason: source);
    }
    expect(_tbrMarkerRead.hasMatch("'the TBR section is open'"), isFalse);
  });

  test('the sentence rule catches each way to cut a sentence', () {
    for (final source in [
      "RegExp(r'(?<=[.?!]) ')",
      "RegExp(r'[^.!?]+[.!?]')",
      r"RegExp(r'[\.\?!]')",
      'const t = {0x2E, 0x3F, 0x21};',
      'const t = {0x21, 0x2E, 0x3F};',
      "text.split('. ')",
    ]) {
      expect(_sentenceSplit.hasMatch(source), isTrue, reason: source);
    }
    expect(_sentenceSplit.hasMatch("RegExp(r'[a-z]+')"), isFalse);
    expect(_sentenceSplit.hasMatch('const t = {0x2E, 0x3F};'), isFalse);
  });

  test('the naming line rule catches each way to read a naming line', () {
    for (final source in [
      "line.startsWith('==> ')",
      'line.startsWith("==> ")',
      "line.endsWith(' <==')",
      "line.startsWith('==>')",
      "line.contains(' <==')",
      r"RegExp(r'^==> (.*) <==$')",
      'RegExp("==> ")',
    ]) {
      expect(_namingLineRead.hasMatch(source), isTrue, reason: source);
    }
    expect(_namingLineRead.hasMatch(r"'==> bundle: $n docs <==\n'"), isFalse);
    expect(_namingLineRead.hasMatch("line.startsWith('## ')"), isFalse);
  });

  test('no doc_model file imports index_query', () {
    final offenders = [
      for (final file in _sources())
        if (_relative(file).startsWith(_lib('doc_model/')) &&
            file.readAsStringSync().contains(_indexQueryImport))
          _relative(file),
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'doc_model sits below index_query; move what a doc_model file '
          'needs into doc_model.',
    );
  });

  test('no hand-written reference parser sits outside reference_grammar', () {
    final unlisted = <String>[];
    final used = <_Allowed>{};
    for (final file in _sources()) {
      for (final site in _sites(file)) {
        final entry = _allowed.where(
          (a) => a.file == site.file && a.snippet == site.snippet,
        );
        if (entry.isEmpty) {
          unlisted.add('${site.file}: ${site.snippet}');
        } else {
          used.add(entry.first);
        }
      }
    }
    if (unlisted.isNotEmpty) {
      fail(
        'Move each read into doc_model/reference_grammar.dart, or add it to '
        '_allowed with a one-line reason:\n${unlisted.join('\n')}',
      );
    }
    final stale = [
      for (final a in _allowed)
        if (!used.contains(a)) '${a.file}: ${a.snippet}',
    ];
    if (stale.isNotEmpty) {
      fail('Remove the allow-list entries no site hits:\n${stale.join('\n')}');
    }
  });
}
