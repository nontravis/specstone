// The file contents are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'check_fixture.dart' show fingerprintFor;
import 'nested_fixture.dart';
import 'shipped_pins.dart' show shippedPinsConfig;

/// The edge case of `shop/cart/add_item/check_stock` that links the drop story.
const perFrDropEdge =
    '1. E01 — A sold-out item, as [drop](../us02_drop_item/USER_STORY.md) shows → refused.';

/// Returns the contract block of `check_stock` holding [edgeCase].
String perFrContractOf(String edgeCase) =>
    '## Statement\n\n$checkStockStatement\n\n## Edge cases\n\n$edgeCase';

/// Returns the per-FR row of `check_stock` recording [fingerprint].
String perFrRow(String fingerprint) =>
    '- add_item/check_stock: `refuses a sold-out item` $fingerprint';

/// Writes the nested project whose FR holds [perFrDropEdge] and whose cart
/// record holds one per-FR row stamped with the FR's contract block, under
/// `verification_coverage: fr`.
///
/// The record keeps its `drop_item` status unless [keepsDropStatus] is false;
/// a rename of the drop story then rewrites nothing the record holds but the
/// row's stamp.
Future<Directory> writePerFrProject({bool keepsDropStatus = true}) {
  final record = nestedRecords()[cartRecord]!;
  return writeNestedProject(
    extra: {
      'docs/$cartAddFr': nestedFiles()['docs/$cartAddFr']!.replaceFirst(
        '1. E01 — A sold-out item → refused.',
        perFrDropEdge,
      ),
      ...nestedRecords(),
      '.specstone/config.yaml':
          '${shippedPinsConfig()}verification_coverage: fr\n',
      cartRecord:
          '${keepsDropStatus ? record : record.replaceFirst("  - 'drop_item:implemented'\n", '')}'
          '\n## Verification matrix\n\n'
          '${perFrRow(fingerprintFor(perFrContractOf(perFrDropEdge)))}\n',
    },
  );
}
