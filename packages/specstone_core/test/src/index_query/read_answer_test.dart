import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';

void main() {
  late DocIndex index;
  late IndexedDoc typed;
  late IndexedDoc untyped;
  setUpAll(() async {
    index = await indexWith();
    typed = index.resolve('feature:login').single;
    untyped = index.resolve('prds/d01_context.md').single;
  });

  const typedPath = 'prds/features/f01_login/FEATURE.md';
  const hash = 'abc123abc123';

  group('namingLine', () {
    test('a whole doc names its path, then its base', () {
      expect(
        namingLine(typed, base: hash),
        '==> login (feature) · $typedPath · base $hash <==',
      );
    });
    test('a section names <DocPath>#<key>, the lead #_lead', () {
      expect(
        namingLine(typed, sectionKey: 'problem', base: hash),
        '==> login (feature) · $typedPath#problem · base $hash <==',
      );
      expect(
        namingLine(typed, sectionKey: '_lead', base: hash),
        '==> login (feature) · $typedPath#_lead · base $hash <==',
      );
    });
    test('a field and the title follow the path, before the base', () {
      expect(
        namingLine(typed, fieldId: 'vision', base: hash),
        '==> login (feature) · $typedPath · field vision · base $hash <==',
      );
      expect(
        namingLine(typed, title: true, base: hash),
        '==> login (feature) · $typedPath · title · base $hash <==',
      );
    });
    test('unchanged follows the base, summary closes the line', () {
      expect(
        namingLine(typed, base: hash, unchanged: true),
        '==> login (feature) · $typedPath · base $hash · unchanged <==',
      );
      expect(
        namingLine(typed, unchanged: true),
        '==> login (feature) · $typedPath · unchanged <==',
      );
      expect(
        namingLine(typed, summary: true),
        '==> login (feature) · $typedPath · summary <==',
      );
    });
    test('a caller that passes no target prints as before', () {
      expect(namingLine(typed), '==> login (feature) · $typedPath <==');
      expect(
        namingLine(untyped),
        '==> prds/d01_context.md · prds/d01_context.md <==',
      );
    });
    test('two targets at once fail an assert', () {
      expect(
        () => namingLine(typed, sectionKey: 'problem', fieldId: 'vision'),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => namingLine(typed, fieldId: 'vision', title: true),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('readNamingLine', () {
    test('reads back each form namingLine writes', () {
      final cases = <(String, NamingLine)>[
        (
          namingLine(typed, base: hash),
          const NamingLine(path: typedPath, base: hash),
        ),
        (
          namingLine(typed, sectionKey: 'problem', base: hash),
          const NamingLine(path: '$typedPath#problem', base: hash),
        ),
        (
          namingLine(typed, sectionKey: '_lead', base: hash),
          const NamingLine(path: '$typedPath#_lead', base: hash),
        ),
        (
          namingLine(typed, fieldId: 'vision', base: hash),
          const NamingLine(path: typedPath, base: hash, fieldId: 'vision'),
        ),
        (
          namingLine(typed, title: true, base: hash),
          const NamingLine(path: typedPath, base: hash, isTitle: true),
        ),
        (
          namingLine(untyped, base: hash),
          const NamingLine(path: 'prds/d01_context.md', base: hash),
        ),
      ];
      for (final (line, expected) in cases) {
        final read = readNamingLine(line);
        expect(read, isNotNull, reason: line);
        expect(read!.path, expected.path, reason: line);
        expect(read.base, expected.base, reason: line);
        expect(read.fieldId, expected.fieldId, reason: line);
        expect(read.isTitle, expected.isTitle, reason: line);
      }
    });
    test('an unchanged or summary tail reads with base null', () {
      final unchanged = readNamingLine(
        namingLine(typed, base: hash, unchanged: true),
      );
      expect(unchanged!.path, typedPath);
      expect(unchanged.base, isNull);
      final summary = readNamingLine(namingLine(typed, summary: true));
      expect(summary!.path, typedPath);
      expect(summary.base, isNull);
    });
    test('a journey line and a guide line read with base null', () {
      final journey = readNamingLine(
        '==> sign_in (journey) · prds/journeys/sign_in/JOURNEY.md <==',
      );
      expect(journey!.path, 'prds/journeys/sign_in/JOURNEY.md');
      expect(journey.base, isNull);
      final guide = readNamingLine('==> feature <==');
      expect(guide!.path, 'feature');
      expect(guide.base, isNull);
    });
    test('trailing spaces and tabs are dropped', () {
      final read = readNamingLine('${namingLine(typed, base: hash)} \t ');
      expect(read!.base, hash);
    });
    test('an indented line and a line with no closing arrow read as none', () {
      expect(readNamingLine(' ${namingLine(typed, base: hash)}'), isNull);
      expect(readNamingLine('==> login (feature) · $typedPath'), isNull);
      expect(readNamingLine('login (feature) · $typedPath <=='), isNull);
      expect(readNamingLine('==> <=='), isNull);
      expect(readNamingLine(''), isNull);
    });
    test('a hash of 11 or 13 characters, or upper-case hex, has no base', () {
      for (final bad in ['abc123abc12', 'abc123abc1234', 'ABC123ABC123']) {
        final read = readNamingLine(namingLine(typed, base: bad));
        expect(read, isNotNull, reason: bad);
        expect(read!.base, isNull, reason: bad);
      }
    });
  });
}
