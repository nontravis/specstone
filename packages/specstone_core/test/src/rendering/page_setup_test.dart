import 'package:specstone_core/src/rendering/page_setup.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:test/test.dart';

Matcher _argumentInvalid(String message) => throwsA(
  isA<RenderFault>()
      .having((fault) => fault.code, 'code', RenderFaultCode.argumentInvalid)
      .having((fault) => fault.message, 'message', message),
);

void main() {
  test('f05/us02/fr05/e01, DP2: no options give A4 portrait with a 20mm '
      'margin', () {
    const rule = '@page { size: A4 portrait; margin: 20mm; }\n';

    expect(PageSetup.parse().pageRule, rule);
    expect(PageSetup.defaults.pageRule, rule);
  });

  test('f05/us02/fr05/e02: each paper and orientation names its CSS '
      'keyword', () {
    expect(
      PageSetup.parse(paper: 'letter', landscape: true, margin: '1in').pageRule,
      '@page { size: letter landscape; margin: 1in; }\n',
    );
    expect(
      PageSetup.parse(paper: 'a5').pageRule,
      '@page { size: A5 portrait; margin: 20mm; }\n',
    );
    expect(
      PageSetup.parse(paper: 'legal').pageRule,
      '@page { size: legal portrait; margin: 20mm; }\n',
    );
  });

  test('f05/us02/fr05/e03, DP1: an unknown paper is argument_invalid naming '
      'the four', () {
    for (final value in ['b5', 'A4', '', 'a4 ']) {
      expect(
        () => PageSetup.parse(paper: value),
        _argumentInvalid('--paper takes a4, a5, letter, or legal, not $value'),
        reason: 'paper "$value"',
      );
    }
  });

  test('f05/us02/fr05/e04, DP2: a margin outside the length rule is '
      'argument_invalid', () {
    for (final value in [
      '20',
      '-5mm',
      '+5mm',
      '20 mm',
      '20MM',
      '20px',
      '1e1mm',
      '5.mm',
      '',
      '٢٠mm',
    ]) {
      expect(
        () => PageSetup.parse(margin: value),
        _argumentInvalid(
          '--margin takes a length in mm, cm, or in, such as 20mm, '
          'not $value',
        ),
        reason: 'margin "$value"',
      );
    }
  });

  test('f05/us02/fr05/e06, DP2: zero, a leading dot, and leading zeros are '
      'taken as given', () {
    for (final value in ['0mm', '0in', '.5in', '1.5cm', '007mm']) {
      expect(
        PageSetup.parse(margin: value).pageRule,
        contains('margin: $value;'),
        reason: 'margin "$value"',
      );
    }
  });

  test('f05/us02/fr05/e05, s03/inv25, DP3: half the short side or more '
      'refuses, compared exactly', () {
    const cases = <(String, bool, String, bool)>[
      ('a4', false, '104.99mm', false),
      ('a4', false, '105mm', true),
      ('a4', false, '10.5cm', true),
      ('a4', false, '10.49cm', false),
      ('a4', true, '105mm', true),
      ('a4', true, '104mm', false),
      ('a5', false, '74mm', true),
      ('a5', false, '73.9mm', false),
      ('letter', false, '4.25in', true),
      ('letter', false, '4.24in', false),
      ('letter', false, '107.95mm', true),
      ('legal', true, '107.95mm', true),
      ('legal', false, '107.94mm', false),
      ('a4', false, '99999999999999999999mm', true),
    ];
    const limits = {
      'a4': '105mm',
      'a5': '74mm',
      'letter': '107.95mm',
      'legal': '107.95mm',
    };

    for (final (paper, landscape, margin, refused) in cases) {
      final reason = '$paper landscape=$landscape margin "$margin"';
      PageSetup parse() =>
          PageSetup.parse(paper: paper, landscape: landscape, margin: margin);
      if (refused) {
        expect(
          parse,
          _argumentInvalid(
            '--margin takes less than ${limits[paper]} on $paper, '
            'not $margin',
          ),
          reason: reason,
        );
      } else {
        expect(parse().margin, margin, reason: reason);
      }
    }
  });
}
