import 'package:specstone_core/src/index_query/bare_id_owner.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/models/bare_item_id.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart' show loginFr;
import '../../helpers/index_fixture.dart';
import '../../helpers/target_fixture.dart';

const _fr =
    'prds/features/f01_login/us01_email_login/fr01_validate_credentials.md';
const _domain = 'specs/f01_login/DOMAIN.md';
const _domainFromFr = '../../../../specs/f01_login/DOMAIN.md';
const _readmeFromFr = '../../../../README.md';

const _domainWithInvariants = {
  'docs/$_domain':
      '# Login domain\n\n## Entities\n- Account\n\n'
      '## Invariants\n\n- **INV-6** An account holds one email.\n',
};

BareItemId _id(String id, [BareIdCitation? citation]) =>
    BareItemId(line: 1, column: 0, id: id, citation: citation);

/// The owner of [id] written in the FR, as `ownerDocOf` judges it.
OwnerDoc? _ownerInFr(DocIndex index, BareItemId id) =>
    ownerDocOf(index, id, holderDocPath: _fr, ownDoc: index.at(_fr)!);

void main() {
  test('bare id with two possible owners has no sure owner', () async {
    const flutterDomain = 'specs/flutter/f01_login/DOMAIN.md';
    const jasprDomain = 'specs/jaspr/f01_login/DOMAIN.md';
    const domain =
        '# Login domain\n\n## Entities\n\n- Account\n\n'
        '## Invariants\n\n- **INV-6** An account holds one email.\n';
    final session = openSession(
      await writeTwinProject(
        extra: {'docs/$flutterDomain': domain, 'docs/$jasprDomain': domain},
      ),
    );
    addTearDown(session.close);
    final index = session.index;
    final id = _id('INV-6', const CiteCitation(written: 'rulebook:login'));
    OwnerDoc? ownerIn(String holder) =>
        ownerDocOf(index, id, holderDocPath: holder, ownDoc: index.at(holder)!);
    expect(ownerIn(loginFr), isNull, reason: 'a shared doc names both twins');
    expect(ownerIn(flutterArchitecture)?.doc.docPath, flutterDomain);
  });

  group('ownerDocOf', () {
    test('an ID in the run of a link to a typed doc with its prefix belongs to '
        'that doc', () async {
      final index = await indexWith(_domainWithInvariants);
      final owner = _ownerInFr(
        index,
        _id('INV-6', const LinkCitation(destination: _domainFromFr)),
      );
      expect(owner?.doc.docPath, _domain);
      expect(owner?.isOwnDoc, isFalse);
    });

    test('an ID in the run of a link to a typed doc without its prefix is '
        'judged in its own doc', () async {
      final index = await indexWith(_domainWithInvariants);
      final owner = _ownerInFr(
        index,
        _id(
          'E03',
          const LinkCitation(destination: '$_domainFromFr#invariants'),
        ),
      );
      expect(owner?.doc.docPath, _fr);
      expect(owner?.isOwnDoc, isTrue);
    });

    test('an uncited ID whose prefix its own doc type holds is owned by that '
        'doc', () async {
      final owner = _ownerInFr(await indexWith(), _id('E03'));
      expect(owner?.doc.docPath, _fr);
      expect(owner?.isOwnDoc, isTrue);
    });

    test(
      'an uncited ID whose prefix its own doc type lacks gets null',
      () async {
        expect(_ownerInFr(await indexWith(), _id('PG-1')), isNull);
      },
    );

    test(
      'an ID after a .md link to no doc, or to an untyped doc, gets null',
      () async {
        final index = await indexWith(_domainWithInvariants);
        for (final destination in [_readmeFromFr, '../missing.md']) {
          expect(
            _ownerInFr(
              index,
              _id('E03', LinkCitation(destination: destination)),
            ),
            isNull,
            reason: destination,
          );
        }
      },
    );

    test(
      'an ID after a link that is no doc link belongs to its own doc',
      () async {
        final index = await indexWith(_domainWithInvariants);
        for (final destination in [
          'https://example.com/',
          '../../../../diagram.png',
          '../../../../../packages/specstone_core/lib/a.dart',
          '../../../../specs/f01_login/',
          '#edge-cases',
        ]) {
          final owner = _ownerInFr(
            index,
            _id('E03', LinkCitation(destination: destination)),
          );
          expect(owner?.doc.docPath, _fr, reason: destination);
          expect(owner?.isOwnDoc, isTrue, reason: destination);
        }
      },
    );

    test(
      'an ID after a code-span cite of one typed doc belongs to that doc',
      () async {
        final index = await indexWith(_domainWithInvariants);
        final owner = _ownerInFr(
          index,
          _id('INV-6', const CiteCitation(written: 'rulebook:login')),
        );
        expect(owner?.doc.docPath, _domain);
        expect(owner?.isOwnDoc, isFalse);
      },
    );
  });
}
