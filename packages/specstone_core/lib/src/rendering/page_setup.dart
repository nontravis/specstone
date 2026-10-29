import 'dart:math';

import 'package:specstone_core/src/rendering/render_fault.dart';

/// A paper size `build` can print on.
///
/// [wire] is the `--paper` word and [cssName] the `@page` size keyword. The
/// portrait [width] and [height] are in hundredths of a millimetre, so the
/// margin bound compares whole numbers.
enum Paper {
  a4('a4', 'A4', 21000, 29700),
  a5('a5', 'A5', 14800, 21000),
  letter('letter', 'letter', 21590, 27940),
  legal('legal', 'legal', 21590, 35560);

  new(this.wire, this.cssName, this.width, this.height);

  /// The `--paper` word.
  final String wire;

  /// The `@page` size keyword.
  final String cssName;

  /// The portrait width in hundredths of a millimetre.
  final int width;

  /// The portrait height in hundredths of a millimetre.
  final int height;

  /// Returns the paper [value] names; null gives [a4].
  ///
  /// Values are case-sensitive. Throws `argument_invalid` when [value] names
  /// no paper.
  static Paper parse(String? value) {
    if (value == null) return a4;
    for (final paper in values) {
      if (paper.wire == value) return paper;
    }
    throw RenderFault(
      RenderFaultCode.argumentInvalid,
      '--paper takes a4, a5, letter, or legal, not $value',
    );
  }

  /// The shorter side in hundredths of a millimetre, in either orientation.
  int get shortSide => min(width, height);

  /// Half of [shortSide] in millimetres, without trailing zeros.
  String get marginLimit {
    final half = shortSide ~/ 2;
    final fraction = (half % 100).toString().padLeft(2, '0');
    final trimmed = fraction.replaceFirst(RegExp(r'0+$'), '');
    final whole = half ~/ 100;
    return trimmed.isEmpty ? '${whole}mm' : '$whole.${trimmed}mm';
  }
}

/// The printed page: its paper, orientation, and margin.
final class PageSetup {
  const new _(this.paper, this.landscape, this.margin);

  /// A4 portrait with a `20mm` margin.
  static const PageSetup defaults = PageSetup._(Paper.a4, false, '20mm');

  /// Returns the page setup the options name.
  ///
  /// A null [paper] gives A4 and a null [margin] gives `20mm`. The [margin]
  /// is a non-negative decimal followed by `mm`, `cm`, or `in`, and stays as
  /// given. It must be under half the paper's short side, in either
  /// orientation. Throws `argument_invalid` for a bad [paper] or [margin],
  /// checking the paper first.
  static PageSetup parse({
    String? paper,
    bool landscape = false,
    String? margin,
  }) {
    final chosen = Paper.parse(paper);
    final given = margin ?? defaults.margin;
    final length = _margin.firstMatch(given);
    if (length == null) {
      throw RenderFault(
        RenderFaultCode.argumentInvalid,
        '--margin takes a length in mm, cm, or in, such as 20mm, not $given',
      );
    }
    if (!_isUnderHalfShortSide(length, chosen)) {
      throw RenderFault(
        RenderFaultCode.argumentInvalid,
        '--margin takes less than ${chosen.marginLimit} on ${chosen.wire}, '
        'not $given',
      );
    }
    return PageSetup._(chosen, landscape, given);
  }

  /// The paper to print on.
  final Paper paper;

  /// Whether the page prints landscape.
  final bool landscape;

  /// The margin on every side, as given.
  final String margin;

  /// The `@page` rule that sets the paper, orientation, and margin.
  String get pageRule =>
      '@page { size: ${paper.cssName} '
      '${landscape ? 'landscape' : 'portrait'}; margin: $margin; }\n';
}

final _margin = RegExp(
  r'^(?<number>[0-9]+(?:\.[0-9]+)?|\.[0-9]+)(?<unit>mm|cm|in)$',
);

/// Hundredths of a millimetre in one of each unit.
const _hundredthsPerUnit = {'mm': 100, 'cm': 1000, 'in': 2540};

/// Whether twice the length in [match] is under the short side of [paper].
///
/// Exact in whole numbers: the digits are a `BigInt` scaled by ten to the
/// count of fraction digits, so no float rounds a value equal to the bound.
bool _isUnderHalfShortSide(RegExpMatch match, Paper paper) {
  final number = match.namedGroup('number')!;
  final dot = number.indexOf('.');
  final fractionDigits = dot == -1 ? 0 : number.length - dot - 1;
  final digits = BigInt.parse(number.replaceFirst('.', ''));
  final factor = BigInt.from(_hundredthsPerUnit[match.namedGroup('unit')]!);
  final scale = BigInt.from(10).pow(fractionDigits);
  return BigInt.two * digits * factor < BigInt.from(paper.shortSide) * scale;
}
