import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:specstone_core/src/templates/generator_kinds.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/fixture_doc_types.dart';

const _note = '''
id: note
description: A note with generated blocks.
path: notes/{slug}.md
generators: [note_toc, note_end]
sections:
  - id: contents
    header: Contents
  - id: steps
    header: Steps
''';

Future<MergedDocType> _noteType() async {
  final project = await fixtureProject({});
  final merged = TemplateResolver(
    shippedFiles: fixturePackFiles(extra: {'note.yaml': _note}),
    generatorKinds: {...shippedGeneratorKinds, 'note_toc', 'note_end'},
  ).resolve(workingDirectory: project, homeDirectory: null);
  return merged.lookup('note')!;
}

final String _toc = generatedOpenMarker('note_toc');
const String _end = generatedEndMarker;

GeneratedBlock _block(
  String text, {
  String kind = 'note_toc',
  String sectionId = 'contents',
  BlockPlace place = const SectionTop(),
}) =>
    GeneratedBlock(kind: kind, sectionId: sectionId, place: place, text: text);

String _write(String text, MergedDocType type, List<GeneratedBlock> blocks) {
  final result = writeGeneratedBlocks(text, type, blocks);
  expect(result, isA<BlocksWritten>());
  return (result as BlocksWritten).lfText;
}

void main() {
  group('generated blocks', () {
    test('f05/us03/fr02: a marker is one whole line', () {
      expect(
        generatedOpenMarker('note_toc'),
        '<!-- specstone:generated note_toc (do not edit) -->',
      );
      expect(generatedEndMarker, '<!-- specstone:generated end -->');
    });

    test('f05/us03/fr02/e02: a missing SectionTop block is inserted with '
        'both markers', () async {
      final type = await _noteType();

      expect(
        _write('## Contents\n', type, [_block('A\n')]),
        '## Contents\n$_toc\nA\n$_end\n',
      );
    });

    test('f05/us03/fr02: a stale block is rewritten and every byte outside '
        'it is kept', () async {
      final type = await _noteType();
      const before = '---\nstatus: x\n---\n\n# T\n\n## Contents\n';
      final disk = '$before$_toc\nB\n$_end\nintro\n\n## Steps\nbody';

      expect(
        _write(disk, type, [_block('A')]),
        '$before$_toc\nA\n$_end\nintro\n\n## Steps\nbody',
      );
    });

    test('f05/us03/fr02/e03: a hand edit inside a block is replaced by the '
        "generator's text", () async {
      final type = await _noteType();
      final disk = '## Contents\n$_toc\nA\nhand edit\n$_end\n';

      expect(
        _write(disk, type, [_block('A')]),
        '## Contents\n$_toc\nA\n$_end\n',
      );
    });

    test('f05/us03/fr02: a BelowBodyLine block lands under its line, and a '
        'second write finds it there', () async {
      final type = await _noteType();
      const disk = '## Steps\nanchor\n\n### Next\nx\n';
      final blocks = [
        _block('A', sectionId: 'steps', place: const BelowBodyLine(0)),
      ];

      final once = _write(disk, type, blocks);

      expect(once, '## Steps\nanchor\n$_toc\nA\n$_end\n\n### Next\nx\n');
      expect(_write(once, type, blocks), once);
    });

    test('f05/us03/fr02/e04: a pair of a kind the doc type does not list '
        'stays as text', () async {
      final type = await _noteType();
      final other = generatedOpenMarker('other_kind');
      final disk = '## Contents\n$other\nold\n$_end\n';

      expect(
        _write(disk, type, [_block('A')]),
        '## Contents\n$_toc\nA\n$_end\n$other\nold\n$_end\n',
      );
    });

    test('f05/us03/fr02/e05: a pair whose place gets no block stays as it '
        'stands', () async {
      final type = await _noteType();
      final disk = '## Contents\n$_toc\nold\n$_end\n';

      expect(_write(disk, type, const []), disk);
      expect(_write(disk, type, [_block('A', sectionId: 'nowhere')]), disk);
    });

    test('f05/us03/fr02/e06: an opening marker with no end before the next '
        'opening marker is OpenBlock', () async {
      final type = await _noteType();
      final next = generatedOpenMarker('note_end');
      final disk = '## Contents\n$_toc\nA\n$next\nB\n$_end\n';

      final result = writeGeneratedBlocks(disk, type, [_block('A')]);

      expect(result, isA<OpenBlock>());
      expect((result as OpenBlock).kind, 'note_toc');
      expect(result.marker, generatedOpenMarker('note_toc'));
      expect(
        writeGeneratedBlocks('## Contents\n$_toc\nA\n', type, const []),
        isA<OpenBlock>(),
      );
    });

    test('f05/us03/fr02: a marker line in a code fence or in the '
        'frontmatter is text', () async {
      final type = await _noteType();
      final fenced = '## Contents\n```\n$_toc\nA\n```\n';
      final frontmatter = '---\nnote: |\n  x\n$_toc\n---\n\n## Contents\n';

      expect(
        writeGeneratedBlocks(fenced, type, const []),
        isA<BlocksWritten>(),
      );
      expect(
        writeGeneratedBlocks(frontmatter, type, const []),
        isA<BlocksWritten>(),
      );
    });

    test('f05/us03/fr02/e01: writing blocks leaves the frontmatter bytes, '
        'draft and confirmed, as they were', () async {
      final type = await _noteType();
      for (final flag in ['draft: true', 'confirmed: 2026-10-31']) {
        final head = '---\n# keep\n$flag\nzeta:   1\n---\n\n';

        expect(
          _write('$head## Contents\n', type, [_block('A')]),
          '$head## Contents\n$_toc\nA\n$_end\n',
        );
      }
    });

    test(
      'f05/us03/fr01: runGenerators runs the listed kinds in list order',
      () async {
        final type = await _noteType();
        final log = <String>[];
        final registry = GeneratorRegistry<int>({
          'note_end': (doc, docType, resolver) {
            log.add('note_end');
            return [_block('E', kind: 'note_end')];
          },
          'note_toc': (doc, docType, resolver) {
            log.add('note_toc');
            return [_block('T')];
          },
        });

        final blocks = runGenerators(
          Doc.parse('## Contents\n'),
          type,
          registry,
          7,
        );

        expect(log, ['note_toc', 'note_end']);
        expect([for (final b in blocks) b.kind], ['note_toc', 'note_end']);
        expect(registry.kinds, {'note_end', 'note_toc'});
        expect(registry['absent'], isNull);
      },
    );

    test('f05/us03/fr01/e03: a generator that returns no block for a place '
        'leaves that place', () async {
      final type = await _noteType();
      final registry = GeneratorRegistry<int>({
        'note_toc': (doc, docType, resolver) => const [],
      });
      final disk = '## Contents\n$_toc\nold\n$_end\n';

      final blocks = runGenerators(Doc.parse(disk), type, registry, 0);

      expect(blocks, isEmpty);
      expect(_write(disk, type, blocks), disk);
    });

    test('f05/us03/fr02: generatedBlockLines marks the marker and inner '
        'lines of the given kinds only', () {
      final other = generatedOpenMarker('other_kind');
      final lines = ['a', _toc, 'x', _end, 'b', other, 'y', _end, 'c'];

      expect(generatedBlockLines(lines, {'note_toc'}), [
        false,
        true,
        true,
        true,
        false,
        false,
        false,
        false,
        false,
      ]);
    });

    test(
      'f05/us03/fr02: two kinds at one place settle after one write',
      () async {
        final type = await _noteType();
        final tocAndEnd = [_block('T'), _block('E', kind: 'note_end')];
        final below = [
          _block('T', sectionId: 'steps', place: const BelowBodyLine(0)),
          _block(
            'E',
            kind: 'note_end',
            sectionId: 'steps',
            place: const BelowBodyLine(0),
          ),
        ];

        final top = _write('## Contents\nbody\n', type, tocAndEnd);
        expect(_write(top, type, tocAndEnd), top);

        final under = _write('## Steps\nanchor\n\n### N\n', type, below);
        expect(_write(under, type, below), under);
        expect(
          _write('## Contents\n$_toc\nold\n$_end\n\n', type, tocAndEnd),
          _write(
            _write('## Contents\n$_toc\nold\n$_end\n\n', type, tocAndEnd),
            type,
            tocAndEnd,
          ),
        );
      },
    );

    test('f05/us03/fr02: generatedBlockLines marks a closed pair after an '
        'open block', () {
      final end = generatedOpenMarker('note_end');
      final lines = [_toc, 'x', end, 'y', _end];

      expect(generatedBlockLines(lines, {'note_toc', 'note_end'}), [
        false,
        false,
        true,
        true,
        true,
      ]);
    });

    test('f05/us03/fr02: two blocks of one kind at one place write the '
        'first only', () async {
      final type = await _noteType();
      final blocks = [_block('A'), _block('B')];

      final once = _write('## Contents\n', type, blocks);

      expect(once, '## Contents\n$_toc\nA\n$_end\n');
      expect(_write(once, type, blocks), once);
    });

    test(
      'f05/us03/fr02: sectionIndexOf matches headers by headerKey',
      () async {
        final type = await _noteType();
        final doc = Doc.parse('## steps  \nx\n\n##   Contents\n');

        expect(sectionIndexOf(doc, type, 'contents'), 1);
        expect(sectionIndexOf(doc, type, 'steps'), 0);
        expect(sectionIndexOf(doc, type, 'nowhere'), isNull);
        expect(sectionIndexOf(Doc.parse('# T\n'), type, 'contents'), isNull);
      },
    );
  });
}
