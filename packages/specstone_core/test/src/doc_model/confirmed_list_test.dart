import 'package:specstone_core/src/doc_model/confirmed_list.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:test/test.dart';

String _added(String lf, List<String> entries) {
  final list = readConfirmedList(Doc.parse(lf))!;
  return withConfirmedEntries(lf, list, entries);
}

void main() {
  test('a quoted first entry gives the quotes of the entries added', () {
    const lf = "---\nconfirmed:\n  - 'S1 aaaaaaaaaaaa'\n---\n\n# T\n";

    expect(
      _added(lf, ['S2 bbbbbbbbbbbb']),
      "---\nconfirmed:\n  - 'S1 aaaaaaaaaaaa'\n  - 'S2 bbbbbbbbbbbb'\n"
      '---\n\n# T\n',
    );
  });

  test('a quoted key keeps its spelling, comments, and entry quotes', () {
    const lf =
        '---\n"confirmed":\n  # first\n  - "S1 aaaaaaaaaaaa"\n---\n\n# T\n';

    expect(
      _added(lf, ['S2 bbbbbbbbbbbb']),
      '---\n"confirmed":\n  # first\n  - "S1 aaaaaaaaaaaa"\n'
      '  - "S2 bbbbbbbbbbbb"\n---\n\n# T\n',
    );
  });

  test('a doc with no confirmed key gains one, entries plain', () {
    const lf = '---\ndraft: true\n---\n\n# T\n';

    expect(
      _added(lf, ['S1 aaaaaaaaaaaa']),
      '---\ndraft: true\nconfirmed:\n  - S1 aaaaaaaaaaaa\n---\n\n# T\n',
    );
  });
}
