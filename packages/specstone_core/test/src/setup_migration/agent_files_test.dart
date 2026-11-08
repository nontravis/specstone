import 'package:specstone_core/src/setup_migration/agent_files.dart';
import 'package:specstone_core/src/version.dart';
import 'package:test/test.dart';

const _fr = 'setup_migration/set_up_new_project/write_agent_files';

/// The AGENT.md text of the FR, copied from `specstone get`.
const _agentMd =
    '# Specstone\n'
    '\n'
    'This project keeps its PRD and spec as Specstone docs.\n'
    '\n'
    '## Rules\n'
    '- code ⊆ spec ⊆ PRD: build only what a spec states, and specify only what '
    'the PRD asks for. When code needs\n'
    '  something no spec states, stop and ask the Owner.\n'
    '- Read docs with `specstone context <target> --for <mode>` or '
    '`specstone get <name>`; never open doc files directly.\n'
    '- Change docs only with `specstone set`, `new`, `move`, or `rename`. What '
    'an agent writes stays a draft until the\n'
    '  Owner runs `specstone approve`.\n'
    '- Before writing any plan, ground it with '
    '`specstone context <story> --for implement`.\n'
    '- Cite a doc by its name (`<feature>/<story>`), never by a number label '
    '(`F-<nn> US-<nn>`).\n'
    '- Before reporting work done, run `specstone check <doc>` on each doc you '
    'changed until every finding it reports says it waits for the Owner.\n'
    '- If `specstone` is not on PATH, run `~/.specstone/bin/specstone`.\n';

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

    test('$_fr E02: the block is appended and every earlier byte stays', () {
      const owner = '# My project\n\nOwner text.\n';

      expect(upsertBlock(owner, _importBlock()), '$owner${_importBlock()}');
    });

    test('$_fr: a last line without a line feed gets the BEGIN on its own', () {
      const owner = '# My project\nOwner text.';

      expect(upsertBlock(owner, _importBlock()), '$owner\n${_importBlock()}');
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
        '$owner${_crlf(_importBlock())}',
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

      expect(upsertBlock(owner, _importBlock()), '$owner${_importBlock()}');
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

        expect(first, '$owner${_importBlock()}');
        expect(upsertBlock(first!, _importBlock()), isNull);
      },
    );
  });
}
