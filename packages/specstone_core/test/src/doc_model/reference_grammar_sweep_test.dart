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
  // Markdown syntax: heading, table, blockquote, and definition shapes.
  _core(
    'consistency_check/fr_trace_rows.dart',
    r"""RegExp(r'^:?-+:?$'""",
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
    'consistency_check/trace_rules.dart',
    r"""RegExp(r'^\*\*Serves:\*\*(.*)$'""",
    'Matches the `**Serves:**` label; its IDs are read apart.',
  ),
  _core(
    'consistency_check/tree_rules.dart',
    r"""RegExp(r'^(.*[^/]): cannot be read; skipped$'""",
    'Reads a tree-walk warning message, no reference.',
  ),
  _core(
    'doc_model/doc.dart',
    r"""RegExp(r'^ {0,3}##(?:[ \t]|$)'""",
    'Level-2 heading line splitting a doc into sections.',
  ),
  _core(
    'doc_model/doc_anchors.dart',
    """RegExp( '&(?:[a-zA-Z][a-zA-Z0-9]*|#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6});'""",
    'HTML character reference such as `&#38;`, no reference.',
  ),
  // The WHATWG URL parser mirrors the URL standard; the grammar calls it.
  _core(
    'doc_model/whatwg_url.dart',
    r"""RegExp(r'[A-Za-z][A-Za-z0-9+.\-]*:'""",
    'URL standard scheme step, called by the grammar.',
  ),
  _core(
    'doc_model/whatwg_url.dart',
    r"""RegExp(r'[/\\?#]'""",
    'URL standard path delimiters, called by the grammar.',
  ),
  _core(
    'doc_model/whatwg_url.dart',
    """RegExp('[/?#]'""",
    'URL standard path delimiters, called by the grammar.',
  ),
  _core(
    'doc_model/whatwg_url.dart',
    r"""RegExp(r'^[A-Za-z][:|]$'""",
    'URL standard Windows drive letter, called by the grammar.',
  ),
  // Frontmatter key block: the key line, not a reference.
  _core(
    'document_writing/key_block_values.dart',
    """.indexOf(':'""",
    'Finds the colon after the key name; values go to the grammar.',
  ),
  _core(
    'document_writing/link_destinations.dart',
    r"""RegExp(r'\](?:\(|:)\s*'""",
    'Finds where a link destination opens; the grammar reads it.',
  ),
  // Mentions: prose paths, read by design (no grammar form for prose).
  _core(
    'document_writing/rewrite_mentions.dart',
    """.indexOf('#'""",
    'Mention reader: cuts a prose path token at its `#`.',
  ),
  _core(
    'document_writing/rewrite_mentions.dart',
    r"""RegExp(r'[.,;:]$'""",
    'Mention reader: trailing sentence mark of a prose path.',
  ),
  _core(
    'document_writing/rewrite_mentions.dart',
    r"""RegExp(r'(?::\d+)+$'""",
    'Mention reader: `:12:5` line suffix of a prose path.',
  ),
  // A code path with a line, not a doc reference.
  _core(
    'index_query/code_bundle.dart',
    """.indexOf(':'""",
    'Cuts the `path:line` of an `implements` entry, a code path.',
  ),
  _core(
    'index_query/doc_mentions.dart',
    r"""RegExp(r'^ {0,3}\[[^\]]+\]:\s*(?:<[^>]*>|\S+)'""",
    'Markdown link reference definition line; the grammar reads its target.',
  ),
  _core(
    'index_query/link_blocks.dart',
    r"""RegExp( r'^[ ]{0,3}\|?([ \t]*:?\-+:?[ \t]*\|[ \t]*)+([ \t]|[ \t]*:?\-+:?[ \t]*)?$'""",
    'Table delimiter row, no reference.',
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
  // Legacy readers: they read the pre-1.2.0 layout on purpose.
  _core(
    'setup_migration/legacy_rewrites.dart',
    r"""RegExp(r'^- \*\*Human:\*\* (.+)$'""",
    'Legacy reader of the pre-1.2.0 `**Human:**` line.',
  ),
  _core(
    'setup_migration/legacy_rewrites.dart',
    r"""RegExp('^${RegExp.escape(block.key)}(?=\\s*:)'""",
    'Legacy reader: finds a frontmatter key line by name.',
  ),
  _core(
    'setup_migration/legacy_tree.dart',
    r"""RegExp(r'^:?-+:?$'""",
    'Legacy reader: table delimiter cell, no reference.',
  ),
  _core(
    'setup_migration/upgrade_plan.dart',
    r"""RegExp('^${RegExp.escape(block.key)}(?=\\s*:)'""",
    'Upgrade reader: finds a frontmatter key line by name.',
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

/// A pattern text that reads `#`, `:`, a step number, or `Scenario`.
final _referenceShaped = RegExp(r'#|:|S\[0-9\]|S\\d|Scenario');

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

/// Returns `<relative file>: <snippet>` for each reference-shaped read.
List<({String file, String snippet})> _sites(File file) {
  final packagesPath = _packagesDir().uri.toFilePath();
  final relative = file.path
      .substring(packagesPath.length)
      .replaceAll(r'\', '/');
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

void main() {
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
