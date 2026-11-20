import 'package:specstone_core/src/setup_migration/agent_files.dart';
import 'package:specstone_core/src/version.dart';
import 'package:test/test.dart';

/// The AGENT.md text: the FR gives its meanings, the asset its wording.
const _agentMd =
    '# Specstone\n'
    '\n'
    'PRD and spec are Specstone docs.\n'
    '\n'
    '## Rules\n'
    '- Rank choices by project vision served; for work serving none, against '
    "one, or in PROJECT's Out-of-scope, ask Owner, or flag and go on if "
    'asked.\n'
    '- code ⊆ spec ⊆ PRD over observable behavior: specify each behavior '
    'users, callers, or features see, only as the\n'
    '  PRD asks; when code adds or changes one, ask the Owner. Code and '
    'tests name no doc, path, or item ID.\n'
    '- Read docs with `specstone context <target> --for <mode> --out`; '
    'search saved files before any `specstone get`; in design work ground a '
    'doc they lack with `specstone context <doc> --for design --out`, never '
    '`get`; never open doc files.\n'
    '- With 2+ code targets, add `--target <code target>` (not with '
    '`context --code`).\n'
    '- Change docs only with `specstone set`, `new`, `move`, `rename`; '
    "drafts await Owner's `specstone approve` (main session's when clean "
    'under `auto`).\n'
    '- Before writing a doc, have `specstone guide <type>` or this '
    "run's saved guide; write items in its shape,\n"
    '  once, short, complete.\n'
    "- Before a story's plan, tickets, or tests, run "
    '`specstone context <story> --for implement --out`; before editing a '
    'covered skill/agent file, run '
    '`specstone context --code <path> --for implement --out`.\n'
    '- Cite by markdown link, never a number label '
    '(`F-<nn> US-<nn>`).\n'
    '- Before reporting done, run `specstone check <doc> --out '
    '<folder>/reports/check.done.<XXXXXX>.txt` per changed doc until every '
    'finding ends `(waits for the Owner)` (`--json`: `waitsFor` `owner`).\n'
    '- Off PATH, run `~/.specstone/bin/specstone`.\n';

const _agentMdWordBound = 240;
const _targetClauseWordBound = 13;
const _targetFlag = '--target <code target>';

final _asciiSpace = RegExp(r'[ \t\n\r\f\v]+');

/// The words of [text] as `wc -w` counts them: ASCII-whitespace separated.
int _wordsOf(String text) =>
    text.split(_asciiSpace).where((word) => word.isNotEmpty).length;

/// The `## Rules` bullets of [text], each folded onto one line.
List<String> _rules(String text) => text
    .split(RegExp(r'\n(?=- )'))
    .map((rule) => rule.replaceAll(_asciiSpace, ' '))
    .toList();

const _projectRule = '- Run `specstone get project` before any task.';
const _goalRule = '- Run `specstone get goal` before any task.';
const _begin = '<!-- BEGIN specstone v$specstoneVersion -->';
const _end = '<!-- END specstone -->';

String _lines(List<String> lines) => '${lines.join('\n')}\n';

String _crlf(String lf) => lf.replaceAll('\n', '\r\n');

String _importBlock() => importBlock(
  cliVersion: specstoneVersion,
  agentMdPath: '.specstone/AGENT.md',
  projectDocPath: 'docs/prds/PROJECT.md',
  goalDocPath: 'docs/prds/GOAL.md',
);

String _inlineBlock() => inlineBlock(cliVersion: specstoneVersion);

void main() {
  group('texts', () {
    test('agentMdText equals the FR AGENT.md text byte for byte', () {
      expect(agentMdText, _agentMd);
    });

    test('the AGENT.md text counts at most $_agentMdWordBound words', () {
      expect(_wordsOf(agentMdText), lessThanOrEqualTo(_agentMdWordBound));
    });

    test('the vision rule holds its pinned literals', () {
      for (final text in [agentMdText, _inlineBlock()]) {
        final rule = _rules(text).singleWhere((r) => r.startsWith('- Rank'));

        for (final literal in ['vision', 'Owner', 'Out-of-scope', 'go on']) {
          expect(rule, contains(literal));
        }
      }
    });

    test('one clause adds the target flag, at most '
        '$_targetClauseWordBound words, naming no target', () {
      final clauses = [
        for (final line in agentMdText.split('\n'))
          if (line.contains('--target')) line,
      ];

      expect(clauses, hasLength(1));
      expect(clauses.single, contains('`$_targetFlag`'));
      expect(
        _wordsOf(clauses.single),
        lessThanOrEqualTo(_targetClauseWordBound),
      );
      expect(clauses.single, isNot(contains('flutter')));
      expect(clauses.single, isNot(contains('jaspr')));
    });

    test('AGENT.md and the inline block name no specstone:<name> skill', () {
      final skillName = RegExp('`specstone:[a-z0-9-]+`');
      expect(skillName.hasMatch(agentMdText), isFalse);
      expect(skillName.hasMatch(_inlineBlock()), isFalse);
    });

    test('the check rule names the tag and waitsFor, no prose rule', () {
      expect(agentMdText, contains('`(waits for the Owner)`'));
      expect(agentMdText, contains('`waitsFor`'));
      expect(agentMdText, isNot(contains('says it waits')));
      expect(_inlineBlock(), contains('`(waits for the Owner)`'));
      expect(_inlineBlock(), contains('`waitsFor`'));
    });

    test('the check rule saves to the done file and runs until every '
        'finding waits', () {
      for (final text in [agentMdText, _inlineBlock()]) {
        final rule = _rules(text)
            .singleWhere((r) => r.startsWith('- Before reporting done'));

        expect(rule, contains('`specstone check <doc> --out '));
        expect(rule, contains('<folder>/reports/check.done.<XXXXXX>.txt`'));
        expect(rule, contains('`(waits for the Owner)`'));
        expect(rule, contains('`waitsFor`'));
      }
    });

    test('the draft rule names set, new, move, rename, and the approver', () {
      for (final text in [agentMdText, _inlineBlock()]) {
        final rule = _rules(text)
            .singleWhere((r) => r.startsWith('- Change docs'));

        expect(rule, contains('`specstone set`'));
        for (final command in ['new', 'move', 'rename']) {
          expect(rule, contains('`$command`'));
        }
        expect(rule, contains('`specstone approve`'));
      }
    });

    test('the guide rule names the guide command and a guide file this '
        'run saved', () {
      for (final text in [agentMdText, _inlineBlock()]) {
        final rule = _rules(text)
            .singleWhere((r) => r.startsWith('- Before writing a doc'));

        expect(rule, contains('`specstone guide <type>`'));
        expect(rule, contains('saved guide'));
        expect(rule, contains('this run'));
      }
    });

    test('the PATH rule names the home binary', () {
      for (final text in [agentMdText, _inlineBlock()]) {
        final rule = _rules(text)
            .singleWhere((r) => r.startsWith('- Off PATH'));

        expect(rule, contains('`~/.specstone/bin/specstone`'));
      }
    });

    test(
      "Ground another plugin's plan, ticket, or test work in the story first "
      'verification: one rule names the implement grounding for a plan, '
      'tickets, and tests, in AGENT.md and in the inline block',
      () {
        for (final text in [agentMdText, _inlineBlock()]) {
          final rules = _rules(text)
              .where((r) => r.contains('--for implement'));
          expect(rules, hasLength(1));
          expect(
            rules.single,
            allOf(
              contains('`specstone context <story> --for implement --out`'),
              contains('plan'),
              contains('tickets'),
              contains('tests'),
            ),
          );
        }
      },
    );

    test('the read rule names a bare --out last in its '
        'command and a search of the saved file before any get', () {
      for (final text in [agentMdText, _inlineBlock()]) {
        final rule = _rules(text)
            .singleWhere((r) => r.startsWith('- Read docs with'));

        expect(
          rule,
          contains('`specstone context <target> --for <mode> --out`'),
        );
        expect(
          rule.indexOf('search saved files before any `specstone get`'),
          greaterThan(rule.indexOf('--out`')),
        );
      }
    });

    test('AGENT.md grounds a newly reached doc in design with context '
        '--for design', () {
      for (final text in [agentMdText, _inlineBlock()]) {
        final rule = _rules(text)
            .singleWhere((r) => r.startsWith('- Read docs with'));

        expect(
          rule,
          contains(
            'in design work ground a doc they lack '
            'with `specstone context <doc> --for design --out`, never `get`',
          ),
        );
        expect(rule, isNot(contains('design mode')));
        expect(rule, contains('before any `specstone get`'));
      }
    });

    test(
      "Ground another plugin's plan, ticket, or test work in the story first "
      'verification: the plan rule names a bare --out last in its command',
      () {
        for (final text in [agentMdText, _inlineBlock()]) {
          final rule = _rules(text)
              .singleWhere((r) => r.contains('--for implement'));

          expect(rule, endsWith('--for implement --out`.'));
        }
      },
    );

    test('the plan rule also grounds a covered file by its code path', () {
      for (final text in [agentMdText, _inlineBlock()]) {
        final rule = _rules(text)
            .singleWhere((r) => r.contains('<story> --for implement'));

        expect(
          rule,
          endsWith('`specstone context --code <path> --for implement --out`.'),
        );
      }
    });

    test('the citation rule names a markdown link', () {
      for (final text in [agentMdText, _inlineBlock()]) {
        final rule = _rules(text).singleWhere((r) => r.startsWith('- Cite'));

        expect(rule, contains('markdown link'));
        expect(rule, isNot(contains('by its name')));
      }
    });

    test('the import block holds the goal line before END', () {
      expect(
        _importBlock(),
        _lines([
          _begin,
          '@.specstone/AGENT.md',
          '@docs/prds/PROJECT.md',
          '@docs/prds/GOAL.md',
          _end,
        ]),
      );
    });

    test('the import block paths run from the file folder', () {
      final block = importBlock(
        cliVersion: '9.8.7',
        agentMdPath: '../.specstone/AGENT.md',
        projectDocPath: '../docs/prds/PROJECT.md',
        goalDocPath: '../docs/prds/GOAL.md',
      );

      expect(
        block,
        _lines([
          '<!-- BEGIN specstone v9.8.7 -->',
          '@../.specstone/AGENT.md',
          '@../docs/prds/PROJECT.md',
          '@../docs/prds/GOAL.md',
          _end,
        ]),
      );
    });

    test('the inline block ends with the project and goal rules', () {
      expect(
        _inlineBlock(),
        '$_begin\n$_agentMd$_projectRule\n$_goalRule\n$_end\n',
      );
    });

    test('the cursor rules file is frontmatter then the inline block', () {
      expect(
        cursorRulesText(cliVersion: specstoneVersion),
        '---\nalwaysApply: true\n---\n${_inlineBlock()}',
      );
    });
  });

  group('scanMarkers', () {
    test('a text without markers scans clean', () {
      final scan = scanMarkers('Owner text\nmore\n');

      expect(scan.beginLine, isNull);
      expect(scan.endLine, isNull);
      expect(scan.firstMarkerLine, isNull);
      expect(scan.isMalformed, isFalse);
    });

    test('one BEGIN then one END gives their 1-based lines', () {
      final scan = scanMarkers('top\n$_begin\nbody\n$_end\nbottom\n');

      expect(scan.beginLine, 2);
      expect(scan.endLine, 4);
      expect(scan.firstMarkerLine, 2);
      expect(scan.isMalformed, isFalse);
    });

    test('a BEGIN with no END is malformed', () {
      final scan = scanMarkers('a\n$_begin\nb\n');

      expect(scan.isMalformed, isTrue);
      expect(scan.firstMarkerLine, 2);
    });

    test('an END with no BEGIN before it is malformed', () {
      final scan = scanMarkers('a\nb\n$_end\n');

      expect(scan.isMalformed, isTrue);
      expect(scan.firstMarkerLine, 3);
    });

    test('an END before the BEGIN is malformed', () {
      final scan = scanMarkers('$_end\n$_begin\n');

      expect(scan.isMalformed, isTrue);
      expect(scan.firstMarkerLine, 1);
    });

    test('two BEGIN lines are malformed', () {
      final scan = scanMarkers('$_begin\n$_begin\n$_end\n');

      expect(scan.isMalformed, isTrue);
      expect(scan.firstMarkerLine, 1);
    });

    test('two END lines are malformed', () {
      final scan = scanMarkers('$_begin\n$_end\nx\n$_end\n');

      expect(scan.isMalformed, isTrue);
      expect(scan.firstMarkerLine, 1);
    });

    test('a BEGIN with no version is the Owner text', () {
      final scan = scanMarkers('<!-- BEGIN specstone -->\n$_end\n');

      expect(scan.beginLine, isNull);
      expect(scan.endLine, 2);
      expect(scan.isMalformed, isTrue);
    });

    test('a BEGIN naming a pre-release version is a marker', () {
      final scan = scanMarkers(
        '<!-- BEGIN specstone v1.2.0-beta.1 -->\n$_end\n',
      );

      expect(scan.beginLine, 1);
      expect(scan.endLine, 2);
      expect(scan.isMalformed, isFalse);
    });

    for (final version in ['1.2.0-beta.01', '1.2', '1.2.0+build.5']) {
      test('a BEGIN naming "$version" is the Owner text', () {
        final scan = scanMarkers('<!-- BEGIN specstone v$version -->\n$_end\n');

        expect(scan.beginLine, isNull);
        expect(scan.endLine, 2);
        expect(scan.isMalformed, isTrue);
      });
    }

    test('a BEGIN line holding a 3 MB version is read', () {
      final preRelease = List.filled(1600000, 'a').join('.');
      final core = '1' * 3000000;

      for (final version in ['1.0.0-$preRelease', '$core.0.0']) {
        final scan = scanMarkers('<!-- BEGIN specstone v$version -->\n$_end\n');

        expect(scan.beginLine, 1);
        expect(scan.isMalformed, isFalse);
      }
    });

    test('a BEGIN line holding a 3 MB non-version is Owner text', () {
      for (final token in ['a' * 3000000, '1.0.0-${'a.' * 1600000}!']) {
        final scan = scanMarkers('<!-- BEGIN specstone v$token -->\n$_end\n');

        expect(scan.beginLine, isNull);
        expect(scan.isMalformed, isTrue);
      }
    });

    test('a marker with other text on its line is the Owner text', () {
      final scan = scanMarkers('x $_begin\n$_end y\n');

      expect(scan.firstMarkerLine, isNull);
      expect(scan.isMalformed, isFalse);
    });

    test('a marker inside a fenced code block is the Owner text', () {
      final scan = scanMarkers('```\n$_begin\nx\n```\n$_begin\n$_end\n');

      expect(scan.beginLine, 5);
      expect(scan.endLine, 6);
      expect(scan.isMalformed, isFalse);
    });

    test('CRLF line ends do not hide a marker', () {
      final scan = scanMarkers(_crlf('a\n$_begin\nb\n$_end\n'));

      expect(scan.beginLine, 2);
      expect(scan.endLine, 4);
      expect(scan.isMalformed, isFalse);
    });

    test('an unclosed fence is malformed at its opening line', () {
      final scan = scanMarkers('intro\n```dart\ncode\n');

      expect(scan.isMalformed, isTrue);
      expect(scan.firstMarkerLine, 2);
    });

    test('an unclosed tilde fence is malformed at its opening line, beside a '
        'well-formed block above it', () {
      final scan = scanMarkers('$_begin\nb\n$_end\n~~~dart\ncode\n');

      expect(scan.isMalformed, isTrue);
      expect(scan.firstMarkerLine, 4);
    });

    test('a tilde fence closed by tildes holds a marker as Owner text', () {
      final scan = scanMarkers('~~~\n$_begin\nx\n~~~\n$_begin\n$_end\n');

      expect(scan.isMalformed, isFalse);
      expect(scan.beginLine, 5);
    });

    test('a BOM then a fence opens the fence on line 1', () {
      final scan = scanMarkers('\uFEFF```\n$_begin\n$_end\n');

      expect(scan.isMalformed, isTrue);
      expect(scan.firstMarkerLine, 1);
      expect(scan.beginLine, isNull);
    });

    test('a closed fence earlier does not hide the open one', () {
      final scan = scanMarkers('```\nx\n```\ntext\n```\nopen\n');

      expect(scan.isMalformed, isTrue);
      expect(scan.firstMarkerLine, 5);
    });

    test('a BOM before the first marker does not hide it', () {
      final scan = scanMarkers('\uFEFF$_begin\nb\n$_end\n');

      expect(scan.beginLine, 1);
      expect(scan.isMalformed, isFalse);
    });
  });

  group('upsertBlock', () {
    test('an empty file becomes the block alone', () {
      expect(upsertBlock('', _inlineBlock()), _inlineBlock());
    });

    test('a CRLF file takes the blank line in CRLF', () {
      const owner = '# Mine\nText.\n';

      expect(
        upsertBlock(_crlf(owner), _importBlock()),
        '${_crlf(owner)}\r\n${_crlf(_importBlock())}',
      );
    });

    test('the block is appended and every earlier byte stays', () {
      const owner = '# My project\n\nOwner text.\n';

      expect(upsertBlock(owner, _importBlock()), '$owner\n${_importBlock()}');
    });

    test('no final line feed takes one before the blank line', () {
      const owner = '# My project\n\nOwner text.';

      expect(upsertBlock(owner, _importBlock()), '$owner\n\n${_importBlock()}');
    });

    test('an empty file takes the block with no blank line', () {
      expect(upsertBlock('', _importBlock()), _importBlock());
    });

    test('a blank last line adds no second blank line', () {
      const owner = '# My project\n\nOwner text.\n\n';

      expect(upsertBlock(owner, _importBlock()), '$owner${_importBlock()}');
    });

    test('a differing body is replaced in place', () {
      final old = _lines([
        '<!-- BEGIN specstone v0.0.1 -->',
        'an older rule',
        _end,
      ]);
      final file = 'before\n${old}after\n';

      expect(
        upsertBlock(file, _importBlock()),
        'before\n${_importBlock()}after\n',
      );
    });

    test('a hand-edited rule line is replaced', () {
      final edited = _inlineBlock().replaceFirst('Owner', 'Boss');
      final file = 'top\n${edited}bottom\n';

      expect(
        upsertBlock(file, _inlineBlock()),
        'top\n${_inlineBlock()}bottom\n',
      );
    });

    test('a matching body under another version changes nothing', () {
      final file =
          'x\n${_importBlock().replaceFirst(specstoneVersion, '0.0.1')}y\n';

      expect(upsertBlock(file, _importBlock()), isNull);
    });

    test('a file already holding the block gives null', () {
      expect(upsertBlock('x\n${_inlineBlock()}', _inlineBlock()), isNull);
    });

    test('a CRLF file takes the block with CRLF', () {
      final owner = _crlf('# Mine\nText.\n');

      expect(
        upsertBlock(owner, _importBlock()),
        '$owner\r\n${_crlf(_importBlock())}',
      );
    });

    test('a CRLF block matches its LF block', () {
      final file = _crlf('x\n${_importBlock()}');

      expect(upsertBlock(file, _importBlock()), isNull);
    });

    test('a CRLF block with a differing body is replaced in CRLF', () {
      final old = _crlf(
        _lines(['<!-- BEGIN specstone v0.0.1 -->', 'old', _end]),
      );
      final file = '${_crlf('top\n')}$old${_crlf('bottom\n')}';

      expect(
        upsertBlock(file, _importBlock()),
        '${_crlf('top\n')}${_crlf(_importBlock())}${_crlf('bottom\n')}',
      );
    });

    test('a UTF-8 BOM stays when the block is appended', () {
      const owner = '\uFEFFOwner text.\n';

      expect(upsertBlock(owner, _importBlock()), '$owner\n${_importBlock()}');
    });

    test('a UTF-8 BOM stays when the first line is the BEGIN line', () {
      final old = _lines([
        '\uFEFF<!-- BEGIN specstone v0.0.1 -->',
        'old',
        _end,
      ]);

      expect(
        upsertBlock('${old}tail\n', _importBlock()),
        '\uFEFF${_importBlock()}tail\n',
      );
    });

    test('an END line without a final line feed stays without one', () {
      final old = ['<!-- BEGIN specstone v0.0.1 -->', 'old', _end].join('\n');

      expect(
        upsertBlock(old, _importBlock()),
        _importBlock().substring(0, _importBlock().length - 1),
      );
    });

    test('a malformed text is a caller error', () {
      expect(
        () => upsertBlock('$_begin\n', _importBlock()),
        throwsArgumentError,
      );
    });
    test('a stray fence refuses, naming the line not the text', () {
      expect(
        () => upsertBlock('Owner secret\n```\ncode\n', _importBlock()),
        throwsA(
          isA<ArgumentError>()
              .having((e) => e.invalidValue, 'invalidValue', 2)
              .having((e) => e.toString(), 'text', isNot(contains('secret'))),
        ),
      );
    });

    test('a stray tilde fence refuses, naming the line not the text', () {
      expect(
        () => upsertBlock('Owner secret\n~~~\ncode\n', _importBlock()),
        throwsA(
          isA<ArgumentError>()
              .having((e) => e.invalidValue, 'invalidValue', 2)
              .having((e) => e.toString(), 'text', isNot(contains('secret'))),
        ),
      );
    });

    test('a closed fence upserts and a second run changes 0 bytes', () {
      const owner = '```\ncode\n```\n';
      final first = upsertBlock(owner, _importBlock());

      expect(first, '$owner\n${_importBlock()}');
      expect(upsertBlock(first!, _importBlock()), isNull);
    });

    test('the code rule says code and tests name no doc, path, or item ID', () {
      final codeRule = _rules(agentMdText)
          .singleWhere((rule) => rule.startsWith('- code ⊆ spec'));

      expect(codeRule, contains('Code and tests name no doc, path, or item'));
      expect(codeRule, contains('ID.'));
    });
  });
}
