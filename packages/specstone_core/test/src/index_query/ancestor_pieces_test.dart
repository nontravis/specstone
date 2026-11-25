// The test titles are plan values kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/index_query/ancestor_pieces.dart';
import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/bundle_render.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/models/ancestor_piece.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';
import '../../helpers/nested_fixture.dart';

/// From the FR or the story, a spec doc of `shop`, up to the docs root.
const _specs = '../../../../../specs/f02_shop';
const _toDomain = '$_specs/DOMAIN.md';
const _toArchitecture = '$_specs/ARCHITECTURE.md';

/// From a spec doc of `shop`, the FR of the target story.
const _toFr =
    '../../prds/features/f02_shop/f01_cart/us01_add_item/fr01_check_stock.md';

/// The API doc with no link, so a test sees the pieces it writes alone.
const _quietApi = '# Shop API\n\n## Operations\nNone.\n';

const _flowBlock =
    '$shopArchitecture#component_details id=null heading=checkout-flow';

String _lines(List<String> lines) => '${lines.join('\n')}\n';

String _fr(String statement) =>
    _lines(['# Check the stock', '', '## Statement', statement]);

Map<String, String> _files({
  String? fr,
  String? story,
  String? domain,
  String? architecture,
  String? api,
}) => {
  'docs/$shopApi': api ?? _quietApi,
  'docs/$cartAddFr': ?fr,
  'docs/$cartAdd': ?story,
  'docs/$shopDomain': ?domain,
  'docs/$shopArchitecture': ?architecture,
};

/// Opens the nested project with [files] written as given, so a file line of
/// a doc is the line its text puts it on.
///
/// A key in [stamped] keeps the approval frontmatter the fixture writes.
Future<DocIndex> _indexWith(
  Map<String, String> files, {
  Set<String> stamped = const {},
}) async {
  final session = openSession(
    await writeCheckProject(
      extra: {...nestedFiles(), ...files},
      unstamped: files.keys.toSet().difference(stamped),
    ),
  );
  addTearDown(session.close);
  return session.index;
}

Future<List<AncestorPiece>> _piecesOf(
  Map<String, String> files, {
  Set<String> stamped = const {},
  String target = 'shop/cart/add_item',
  BundleMode mode = BundleMode.design,
}) async {
  final index = await _indexWith(files, stamped: stamped);
  return ancestorPiecesOf(
    index,
    pickBundle(index, [target], mode, noProject: false),
  );
}

String _show(AncestorPiece piece) =>
    '${piece.doc.docPath}#${piece.sectionKey} id=${piece.itemId} '
    'heading=${piece.heading} ${piece.direction.name} '
    '${piece.first}-${piece.last}';

void main() {
  test('an item link from the fr gives that item with its nested items as an outbound piece', () async {
    final pieces = await _piecesOf(
      _files(
        fr: _fr('Holds [INV-1]($_toDomain#invariants).'),
        domain: _lines([
          '# Shop domain',
          '',
          '## Invariants',
          '- **INV-1** An order holds at least one line.',
          '  - A line holds one item.',
          '  - Nested detail.',
          '- **INV-2** A paid order never changes.',
        ]),
      ),
    );
    expect(pieces.map(_show), [
      '$shopDomain#invariants id=INV-1 heading=null outbound 4-6',
    ]);
    expect(pieces.single.text.split('\n'), [
      '- **INV-1** An order holds at least one line.',
      '  - A line holds one item.',
      '  - Nested detail.',
    ]);
  });

  test(
    'a table row linking the fr is an inbound piece under its table head',
    () async {
      final pieces = await _piecesOf(
        _files(
          api: _lines([
            '# Shop API',
            '',
            '## FR trace',
            '| FR | Operation |',
            '|----|-----------|',
            '| [check stock]($_toFr) | `addItem` |',
            '| other | `dropItem` |',
          ]),
        ),
      );
      expect(pieces.map(_show), [
        '$shopApi#fr_trace id=null heading=null inbound 6-6',
      ]);
      expect(pieces.single.text.split('\n'), [
        '| FR | Operation |',
        '|----|-----------|',
        '| [check stock]($_toFr) | `addItem` |',
      ]);
    },
  );

  test('an item range from the fr gives each item it spans its own outbound piece, nested lines included', () async {
    final pieces = await _piecesOf(
      _files(
        fr: _fr(
          'Holds [INV-1]($_toDomain#invariants) to [INV-3]($_toDomain#invariants).',
        ),
        domain: _lines([
          '# Shop domain',
          '',
          '## Invariants',
          '- **INV-1** One.',
          '  - Nested detail.',
          '- **INV-2** Two.',
          '- **INV-3** Three.',
          '- **INV-4** Four.',
        ]),
      ),
    );
    expect(pieces.map(_show), [
      '$shopDomain#invariants id=INV-1 heading=null outbound 4-5',
      '$shopDomain#invariants id=INV-2 heading=null outbound 6-6',
      '$shopDomain#invariants id=INV-3 heading=null outbound 7-7',
    ]);
  });

  test('an item linked in and out is one outbound piece', () async {
    final pieces = await _piecesOf(
      _files(
        fr: _fr('Holds [INV-1]($_toDomain#invariants).'),
        domain: _lines([
          '# Shop domain',
          '',
          '## Invariants',
          '- **INV-1** An order holds a line, see [the fr]($_toFr).',
          '- **INV-2** Another.',
        ]),
      ),
    );
    expect(pieces.map(_show), [
      '$shopDomain#invariants id=INV-1 heading=null outbound 4-4',
    ]);
    expect(pieces.single.text.split('\n'), [
      '- **INV-1** An order holds a line, see [the fr]($_toFr).',
    ]);
  });

  test('an unlinked spec doc gives nothing', () async {
    final pieces = await _piecesOf(
      _files(
        fr: _fr('Holds [INV-1]($_toDomain#invariants).'),
        domain: _lines([
          '# Shop domain',
          '',
          '## Invariants',
          '- **INV-1** One.',
        ]),
      ),
    );
    expect(pieces.map((piece) => piece.doc.docPath).toSet(), {shopDomain});
  });

  test('a whole-doc link gives nothing', () async {
    final pieces = await _piecesOf(
      _files(
        story: _lines([
          '# Agent adds an item',
          '',
          '## Use Case',
          'See [the architecture]($_toArchitecture).',
        ]),
      ),
    );
    expect(pieces, isEmpty);
  });

  test('a block, a bullet, and a paragraph that link the fr each give their own inbound piece', () async {
    final pieces = await _piecesOf(
      _files(
        architecture: _lines([
          '# Shop architecture',
          '',
          '## Component details',
          '### Checkout flow',
          'The flow asks [the fr]($_toFr).',
          'It then pays.',
          '',
          '## Concerns',
          '- Errors: see [the fr]($_toFr),',
          '  wrapped here.',
          '  - Nested bullet.',
          '- Auth: N/A — one local user',
          '',
          '## Interaction',
          'A lone paragraph that cites [the fr]($_toFr)',
          'and wraps.',
          '',
          'Other paragraph.',
        ]),
      ),
    );
    expect(pieces.map(_show), [
      '$_flowBlock inbound 4-6',
      '$shopArchitecture#concerns id=null heading=null inbound 9-11',
      '$shopArchitecture#interaction id=null heading=null inbound 15-16',
    ]);
    expect(pieces.map((piece) => piece.text.split('\n')), [
      ['### Checkout flow', 'The flow asks [the fr]($_toFr).', 'It then pays.'],
      [
        '- Errors: see [the fr]($_toFr),',
        '  wrapped here.',
        '  - Nested bullet.',
      ],
      ['A lone paragraph that cites [the fr]($_toFr)', 'and wraps.'],
    ]);
  });

  test(
    'a range, a block, and a section link each give outbound pieces',
    () async {
      final pieces = await _piecesOf(
        _files(
          fr: _fr(
            'Holds [INV-1]($_toDomain#invariants) to '
            '[INV-3]($_toDomain#invariants), see '
            '[the flow]($_toArchitecture#checkout-flow) and '
            '[the limits]($_toDomain#known-limits).',
          ),
          domain: _lines([
            '# Shop domain',
            '',
            '## Invariants',
            '- **INV-1** First.',
            '- **INV-2** Second.',
            '- **INV-3** Third.',
            '- **INV-4** Fourth.',
            '',
            '## Known limits',
            'Nothing is refunded.',
            'No partial orders.',
          ]),
          architecture: _lines([
            '# Shop architecture',
            '',
            '## Component details',
            '### Checkout flow',
            'It pays.',
          ]),
        ),
      );
      expect(pieces.map(_show), [
        '$_flowBlock outbound 4-5',
        '$shopDomain#invariants id=INV-1 heading=null outbound 4-4',
        '$shopDomain#invariants id=INV-2 heading=null outbound 5-5',
        '$shopDomain#invariants id=INV-3 heading=null outbound 6-6',
        '$shopDomain#known_limits id=null heading=null outbound 9-11',
      ]);
      expect(pieces.map((piece) => piece.text.split('\n')), [
        ['### Checkout flow', 'It pays.'],
        ['- **INV-1** First.'],
        ['- **INV-2** Second.'],
        ['- **INV-3** Third.'],
        ['## Known limits', 'Nothing is refunded.', 'No partial orders.'],
      ]);
    },
  );

  test('an item linking the fr one way is an inbound piece', () async {
    final pieces = await _piecesOf(
      _files(
        domain: _lines([
          '# Shop domain',
          '',
          '## Invariants',
          '- **INV-1** First.',
          '- **INV-2** Second.',
          '  - Checked by [the fr]($_toFr).',
          '- **INV-3** Third.',
        ]),
      ),
    );
    expect(pieces.map(_show), [
      '$shopDomain#invariants id=INV-2 heading=null inbound 5-6',
    ]);
    expect(pieces.single.text.split('\n'), [
      '- **INV-2** Second.',
      '  - Checked by [the fr]($_toFr).',
    ]);
  });

  test('a nested piece prints within its outer piece alone', () async {
    final section = await _piecesOf(
      _files(
        fr: _fr('Holds [the invariants]($_toDomain#invariants).'),
        domain: _lines([
          '# Shop domain',
          '',
          '## Invariants',
          '- **INV-1** First, see [the fr]($_toFr).',
          '- **INV-2** Second.',
        ]),
      ),
    );
    expect(section.map(_show), [
      '$shopDomain#invariants id=null heading=null outbound 3-5',
    ]);
    expect(section.single.text.split('\n'), [
      '## Invariants',
      '- **INV-1** First, see [the fr]($_toFr).',
      '- **INV-2** Second.',
    ]);

    final block = await _piecesOf(
      _files(
        fr: _fr('Holds [INV-1]($_toDomain#invariants).'),
        domain: _lines([
          '# Shop domain',
          '',
          '## Invariants',
          '### Order rules',
          'Orders obey [the fr]($_toFr).',
          '- **INV-1** An order holds a line.',
          '- **INV-2** Another.',
        ]),
      ),
    );
    expect(block.map(_show), [
      '$shopDomain#invariants id=null heading=order-rules inbound 4-7',
    ]);
    expect(block.single.text.split('\n'), [
      '### Order rules',
      'Orders obey [the fr]($_toFr).',
      '- **INV-1** An order holds a line.',
      '- **INV-2** Another.',
    ]);
  });

  test('a link to an anchor no section places gives no piece', () async {
    final pieces = await _piecesOf(
      _files(
        fr: _fr(
          'Wrong [anchor]($_toDomain#nowhere), [title]($_toDomain#shop-domain), '
          'and [INV-9]($_toDomain#invariants).',
        ),
        domain: _lines([
          '# Shop domain',
          '',
          '## Invariants',
          '- **INV-1** One.',
        ]),
      ),
    );
    expect(pieces, isEmpty);
  });

  test('a piece cut from a CRLF doc holds the same lines', () async {
    final domain = _lines([
      '# Shop domain',
      '',
      '## Invariants',
      '- **INV-1** First.',
      '  - Nested.',
      '- **INV-2** Second, see [the fr]($_toFr).',
    ]);
    final fr = _fr('Holds [INV-1]($_toDomain#invariants).');
    const stamped = {'docs/$shopDomain'};
    final lf = await _piecesOf(
      _files(fr: fr, domain: domain),
      stamped: stamped,
    );
    final crlf = await _piecesOf(
      _files(fr: fr, domain: domain.replaceAll('\n', '\r\n')),
      stamped: stamped,
    );
    final frontmatterLines = lf.first.first - 4;
    expect(frontmatterLines, greaterThan(0));
    final (a, b, c) = (
      4 + frontmatterLines,
      5 + frontmatterLines,
      6 + frontmatterLines,
    );
    expect(lf.map(_show), [
      '$shopDomain#invariants id=INV-1 heading=null outbound $a-$b',
      '$shopDomain#invariants id=INV-2 heading=null inbound $c-$c',
    ]);
    expect(crlf.map(_show), lf.map(_show));
    expect(crlf.map((piece) => piece.text), lf.map((piece) => piece.text));
    expect(crlf.any((piece) => piece.text.contains('\r')), isFalse);
  });

  test('a lead paragraph linking the fr gives an inbound paragraph piece with an empty section key', () async {
    final pieces = await _piecesOf(
      _files(
        domain: _lines([
          '# Shop domain',
          '',
          'This doc backs [the fr]($_toFr)',
          'and its order rules.',
          '',
          '## Invariants',
          '- **INV-1** One.',
        ]),
      ),
    );
    expect(pieces.map(_show), [
      '$shopDomain# id=null heading=null inbound 3-4',
    ]);
    expect(pieces.single.text.split('\n'), [
      'This doc backs [the fr]($_toFr)',
      'and its order rules.',
    ]);

    final bullet = await _piecesOf(
      _files(
        domain: _lines([
          '# Shop domain',
          '',
          '- Backs [the fr]($_toFr).',
          '- Other.',
          '',
          '## Invariants',
          '- **INV-1** One.',
        ]),
      ),
    );
    expect(bullet.map(_show), [
      '$shopDomain# id=null heading=null inbound 3-3',
    ]);
    expect(bullet.single.sectionKey, isEmpty);
  });

  test('sibling spec docs of a spec doc target give ancestor pieces and cited-by lines', () async {
    const target = 'architecture:shop';
    final index = await _indexWith({
      ..._files(
        architecture: _lines([
          '# Shop architecture',
          '',
          '## Components',
          'Holds [INV-1](DOMAIN.md#invariants).',
        ]),
        domain: _lines([
          '# Shop domain',
          '',
          '## Invariants',
          '- **INV-1** An order holds a line.',
          '- **INV-2** Checked by [the components](ARCHITECTURE.md#components).',
        ]),
      ),
      'docs/$payCard': _lines([
        '# Agent pays by card',
        '',
        '## Use Case',
        'Pays, by [INV-1]($_toDomain#invariants).',
      ]),
    });
    final bundle = pickBundle(
      index,
      [target],
      BundleMode.design,
      noProject: false,
    );
    expect(ancestorPiecesOf(index, bundle).map(_show), [
      '$shopDomain#invariants id=INV-1 heading=null outbound 4-4',
      '$shopDomain#invariants id=INV-2 heading=null inbound 5-5',
    ]);
    final refs = answerContext(
      index,
      bundle,
      targets: [target],
      split: true,
    ).refs!.text;
    expect(
      refs,
      contains(
        '==> shop (rulebook) · $shopDomain#invariants · item INV-1 · cited by <==\n'
        '  · cited by shop/pay/card (user_story) — #use_case\n',
      ),
    );
    expect(refs, isNot(contains('cited by shop (architecture)')));
  });

  test('no piece without ancestor spec docs', () async {
    final files = _files(
      fr: _fr('Holds [INV-1]($_toDomain#invariants).'),
      domain: _lines([
        '# Shop domain',
        '',
        '## Invariants',
        '- **INV-1** One, see [the fr]($_toFr).',
      ]),
    );
    expect(await _piecesOf(files, target: 'shop'), isEmpty);
    expect(await _piecesOf(files, mode: BundleMode.implement), isEmpty);
  });
}
