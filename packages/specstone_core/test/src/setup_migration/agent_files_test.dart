import 'package:specstone_core/src/setup_migration/agent_files.dart';
import 'package:specstone_core/src/version.dart';
import 'package:test/test.dart';

const _fr = 'setup_migration/set_up_new_project/write_agent_files';

/// The AGENT.md text: the FR gives its meanings, the asset its wording.
const _agentMd =
    '# Specstone\n'
    '\n'
    'This project keeps its PRD and spec as Specstone docs.\n'
    '\n'
    '## Rules\n'
    '- code ⊆ spec ⊆ PRD: build only what a spec states, specify only what '
    'the PRD asks for; when code needs\n'
    '  something no spec states, stop and ask the Owner. Code and tests name '
    'no doc, path, or item ID.\n'
    '- Read docs with `specstone context <target> --for <mode>` or '
    '`specstone get <name>`; never open doc files directly.\n'
    '- With 2+ code targets, add `--target <code target>`.\n'
    '- Change docs only with `specstone set`, `new`, `move`, or `rename`; '
    'agent drafts stay drafts until the Owner runs `specstone approve`.\n'
    "- Before writing a doc, read its type's guide with "
    '`specstone guide <type>`; write each item in its shape,\n'
    '  once, short, complete.\n'
    '- Before writing a plan, tickets, or tests for a story, ground them '
    'with `specstone context <story> --for implement`.\n'
    '- Cite a doc by its name (`<feature>/<story>`), never by a number label '
    '(`F-<nn> US-<nn>`).\n'
    '- Before reporting work done, run `specstone check <doc>` on each doc you '
    'changed until every finding ends `(waits for the Owner)` '
    '(`--json`: `waitsFor` is `owner`).\n'
    '- If the specstone command is not on PATH, run '
    '`~/.specstone/bin/specstone`.\n';

const _agentMdWordBound = 200;
const _targetClauseWordBound = 9;
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
const _begin = '<!-- BEGIN specstone v$specstoneVersion -->';
const _end = '<!-- END specstone -->';

String _lines(List<String> lines) => '${lines.join('\n')}\n';

String _crlf(String lf) => lf.replaceAll('\n', '\r\n');

String _importBlock() => importBlock(
  cliVersion: specstoneVersion,
  agentMdPath: '.specstone/AGENT.md',
  projectDocPath: 'docs/prds/PROJECT.md',
);

String _inlineBlock() => inlineBlock(cliVersion: specstoneVersion);

void main() {
  group('texts', () {
    test('$_fr: agentMdText equals the FR AGENT.md text byte for byte', () {
      expect(agentMdText, _agentMd);
    });

    test('$_fr: the AGENT.md text counts at most $_agentMdWordBound words', () {
      expect(_wordsOf(agentMdText), lessThanOrEqualTo(_agentMdWordBound));
    });

    test('$_fr: one clause adds the target flag, at most '
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

    test('$_fr: the check rule names the tag and waitsFor, no prose rule', () {
      expect(agentMdText, contains('`(waits for the Owner)`'));
      expect(agentMdText, contains('`waitsFor`'));
      expect(agentMdText, isNot(contains('says it waits')));
      expect(_inlineBlock(), contains('`(waits for the Owner)`'));
      expect(_inlineBlock(), contains('`waitsFor`'));
    });

    test('agent_plugin/ground_other_plugins_work/ground_the_story_first '
        'verification: one rule names the implement grounding for a plan, '
        'tickets, and tests, in AGENT.md and in the inline block', () {
      for (final text in [agentMdText, _inlineBlock()]) {
        final rules = _rules(text).where((r) => r.contains('--for implement'));
        expect(rules, hasLength(1));
        expect(
          rules.single,
          allOf(
            contains('`specstone context <story> --for implement`'),
            contains('plan'),
            contains('tickets'),
            contains('tests'),
          ),
        );
      }
    });

    test(
      '$_fr: the import block holds the two imports between the markers',
      () {
        expect(
          _importBlock(),
          _lines([
            _begin,
            '@.specstone/AGENT.md',
            '@docs/prds/PROJECT.md',
            _end,
          ]),
        );
      },
    );

    test('$_fr E15: the import block paths run from the file folder', () {
      final block = importBlock(
        cliVersion: '9.8.7',
        agentMdPath: '../.specstone/AGENT.md',
        projectDocPath: '../docs/prds/PROJECT.md',
      );

      expect(
        block,
        _lines([
          '<!-- BEGIN specstone v9.8.7 -->',
          '@../.specstone/AGENT.md',
          '@../docs/prds/PROJECT.md',
          _end,
        ]),
      );
    });

    test(
      '$_fr: the inline block holds AGENT.md plus the project rule last',
      () {
        expect(_inlineBlock(), '$_begin\n$_agentMd$_projectRule\n$_end\n');
      },
    );

    test(
      '$_fr E21: the cursor rules file is frontmatter then the inline block',
      () {
        expect(
          cursorRulesText(cliVersion: specstoneVersion),
          '---\nalwaysApply: true\n---\n${_inlineBlock()}',
        );
      },
    );
  });

  group('scanMarkers', () {
    test('$_fr: a text without markers scans clean', () {
      final scan = scanMarkers('Owner text\nmore\n');

      expect(scan.beginLine, isNull);
      expect(scan.endLine, isNull);
      expect(scan.firstMarkerLine, isNull);
      expect(scan.isMalformed, isFalse);
    });

    test('$_fr: one BEGIN then one END gives their 1-based lines', () {
      final scan = scanMarkers('top\n$_begin\nbody\n$_end\nbottom\n');

      expect(scan.beginLine, 2);
      expect(scan.endLine, 4);
      expect(scan.firstMarkerLine, 2);
      expect(scan.isMalformed, isFalse);
    });

    test('$_fr E05: a BEGIN with no END is malformed', () {
      final scan = scanMarkers('a\n$_begin\nb\n');

      expect(scan.isMalformed, isTrue);
      expect(scan.firstMarkerLine, 2);
    });

    test('$_fr E05: an END with no BEGIN before it is malformed', () {
      final scan = scanMarkers('a\nb\n$_end\n');

      expect(scan.isMalformed, isTrue);
      expect(scan.firstMarkerLine, 3);
    });

    test('$_fr E05: an END before the BEGIN is malformed', () {
      final scan = scanMarkers('$_end\n$_begin\n');

      expect(scan.isMalformed, isTrue);
      expect(scan.firstMarkerLine, 1);
    });

    test('$_fr E05: two BEGIN lines are malformed', () {
      final scan = scanMarkers('$_begin\n$_begin\n$_end\n');

      expect(scan.isMalformed, isTrue);
      expect(scan.firstMarkerLine, 1);
    });

    test('$_fr E05: two END lines are malformed', () {
      final scan = scanMarkers('$_begin\n$_end\nx\n$_end\n');

      expect(scan.isMalformed, isTrue);
      expect(scan.firstMarkerLine, 1);
    });

    test('$_fr E13: a BEGIN with no version is the Owner text', () {
      final scan = scanMarkers('<!-- BEGIN specstone -->\n$_end\n');

      expect(scan.beginLine, isNull);
      expect(scan.endLine, 2);
      expect(scan.isMalformed, isTrue);
    });

    test('$_fr E13: a BEGIN naming a pre-release version is a marker', () {
      final scan = scanMarkers(
        '<!-- BEGIN specstone v1.2.0-beta.1 -->\n$_end\n',
      );

      expect(scan.beginLine, 1);
      expect(scan.endLine, 2);
      expect(scan.isMalformed, isFalse);
    });

    for (final version in ['1.2.0-beta.01', '1.2', '1.2.0+build.5']) {
      test('$_fr E13: a BEGIN naming "$version" is the Owner text', () {
        final scan = scanMarkers('<!-- BEGIN specstone v$version -->\n$_end\n');

        expect(scan.beginLine, isNull);
        expect(scan.endLine, 2);
        expect(scan.isMalformed, isTrue);
      });
    }

    test('$_fr E13: a BEGIN line holding a 3 MB version is read', () {
      final preRelease = List.filled(1600000, 'a').join('.');
      final core = '1' * 3000000;

      for (final version in ['1.0.0-$preRelease', '$core.0.0']) {
        final scan = scanMarkers('<!-- BEGIN specstone v$version -->\n$_end\n');

        expect(scan.beginLine, 1);
        expect(scan.isMalformed, isFalse);
      }
    });

    test('$_fr E13: a BEGIN line holding a 3 MB non-version is Owner text', () {
      for (final token in ['a' * 3000000, '1.0.0-${'a.' * 1600000}!']) {
        final scan = scanMarkers('<!-- BEGIN specstone v$token -->\n$_end\n');

        expect(scan.beginLine, isNull);
        expect(scan.isMalformed, isTrue);
      }
    });

    test(
      '$_fr E13: a marker with other text on its line is the Owner text',
      () {
        final scan = scanMarkers('x $_begin\n$_end y\n');

        expect(scan.firstMarkerLine, isNull);
        expect(scan.isMalformed, isFalse);
      },
    );

    test('$_fr E13: a marker inside a fenced code block is the Owner text', () {
      final scan = scanMarkers('```\n$_begin\nx\n```\n$_begin\n$_end\n');

      expect(scan.beginLine, 5);
      expect(scan.endLine, 6);
      expect(scan.isMalformed, isFalse);
    });

    test('$_fr E14: CRLF line ends do not hide a marker', () {
      final scan = scanMarkers(_crlf('a\n$_begin\nb\n$_end\n'));

      expect(scan.beginLine, 2);
      expect(scan.endLine, 4);
      expect(scan.isMalformed, isFalse);
    });

    test('$_fr R47: an unclosed fence is malformed at its opening line', () {
      final scan = scanMarkers('intro\n```dart\ncode\n');

      expect(scan.isMalformed, isTrue);
      expect(scan.firstMarkerLine, 2);
    });

    test('$_fr R47: a BOM then a fence opens the fence on line 1', () {
      final scan = scanMarkers('\uFEFF```\n$_begin\n$_end\n');

      expect(scan.isMalformed, isTrue);
      expect(scan.firstMarkerLine, 1);
      expect(scan.beginLine, isNull);
    });

    test('$_fr R47: a closed fence earlier does not hide the open one', () {
      final scan = scanMarkers('```\nx\n```\ntext\n```\nopen\n');

      expect(scan.isMalformed, isTrue);
      expect(scan.firstMarkerLine, 5);
    });

    test('$_fr: a BOM before the first marker does not hide it', () {
      final scan = scanMarkers('\uFEFF$_begin\nb\n$_end\n');

      expect(scan.beginLine, 1);
      expect(scan.isMalformed, isFalse);
    });
  });

  group('upsertBlock', () {
    test('$_fr E01: an empty file becomes the block alone', () {
      expect(upsertBlock('', _inlineBlock()), _inlineBlock());
    });

    test('a CRLF file takes the blank line in CRLF', () {
      const owner = '# Mine\nText.\n';

      expect(
        upsertBlock(_crlf(owner), _importBlock()),
        '${_crlf(owner)}\r\n${_crlf(_importBlock())}',
      );
    });

    test('$_fr E02: the block is appended and every earlier byte stays', () {
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

    test('$_fr E03: a differing body is replaced in place', () {
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

    test('$_fr E03: a hand-edited rule line is replaced', () {
      final edited = _inlineBlock().replaceFirst('Owner', 'Boss');
      final file = 'top\n${edited}bottom\n';

      expect(
        upsertBlock(file, _inlineBlock()),
        'top\n${_inlineBlock()}bottom\n',
      );
    });

    test('$_fr E04: a matching body under another version changes nothing', () {
      final file =
          'x\n${_importBlock().replaceFirst(specstoneVersion, '0.0.1')}y\n';

      expect(upsertBlock(file, _importBlock()), isNull);
    });

    test('$_fr E09: a file already holding the block gives null', () {
      expect(upsertBlock('x\n${_inlineBlock()}', _inlineBlock()), isNull);
    });

    test('$_fr E14: a CRLF file takes the block with CRLF', () {
      final owner = _crlf('# Mine\nText.\n');

      expect(
        upsertBlock(owner, _importBlock()),
        '$owner\r\n${_crlf(_importBlock())}',
      );
    });

    test('$_fr E14: a CRLF block matches its LF block', () {
      final file = _crlf('x\n${_importBlock()}');

      expect(upsertBlock(file, _importBlock()), isNull);
    });

    test(
      '$_fr E14: a CRLF block with a differing body is replaced in CRLF',
      () {
        final old = _crlf(
          _lines(['<!-- BEGIN specstone v0.0.1 -->', 'old', _end]),
        );
        final file = '${_crlf('top\n')}$old${_crlf('bottom\n')}';

        expect(
          upsertBlock(file, _importBlock()),
          '${_crlf('top\n')}${_crlf(_importBlock())}${_crlf('bottom\n')}',
        );
      },
    );

    test('$_fr: a UTF-8 BOM stays when the block is appended', () {
      const owner = '\uFEFFOwner text.\n';

      expect(upsertBlock(owner, _importBlock()), '$owner\n${_importBlock()}');
    });

    test('$_fr: a UTF-8 BOM stays when the first line is the BEGIN line', () {
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

    test('$_fr: an END line without a final line feed stays without one', () {
      final old = ['<!-- BEGIN specstone v0.0.1 -->', 'old', _end].join('\n');

      expect(
        upsertBlock(old, _importBlock()),
        _importBlock().substring(0, _importBlock().length - 1),
      );
    });

    test('$_fr E05: a malformed text is a caller error', () {
      expect(
        () => upsertBlock('$_begin\n', _importBlock()),
        throwsArgumentError,
      );
    });
    test('$_fr R47: a stray fence refuses, naming the line not the text', () {
      expect(
        () => upsertBlock('Owner secret\n```\ncode\n', _importBlock()),
        throwsA(
          isA<ArgumentError>()
              .having((e) => e.invalidValue, 'invalidValue', 2)
              .having((e) => e.toString(), 'text', isNot(contains('secret'))),
        ),
      );
    });

    test(
      '$_fr R47: a closed fence upserts and a second run changes 0 bytes',
      () {
        const owner = '```\ncode\n```\n';
        final first = upsertBlock(owner, _importBlock());

        expect(first, '$owner\n${_importBlock()}');
        expect(upsertBlock(first!, _importBlock()), isNull);
      },
    );

    test(
      'the first rule says code and tests name no doc, path, or item ID',
      () {
        final firstRule = _rules(agentMdText)
            .singleWhere((rule) => rule.startsWith('- code ⊆ spec'));

        expect(
          firstRule,
          contains('Code and tests name no doc, path, or item'),
        );
        expect(firstRule, contains('ID.'));
      },
    );
  });
}
