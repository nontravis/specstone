// Each Decided test cites its D-line in a comment.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/document_writing/doc_placement.dart';
import 'package:specstone_core/src/document_writing/models/path_move.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart'
    show CreateStep;
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:test/test.dart';

import '../../helpers/grouped_fixture.dart';
import '../../helpers/target_fixture.dart'
    show jasprArchitecture, writeTwinProject;
import '../../helpers/write_fixture.dart';

Matcher _refusal(String message) => isA<IndexFault>()
    .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
    .having((f) => f.message, 'message', message);

void main() {
  // D7
  test(
    'a landed doc whose path no doc type matches is refused naming the DocPath',
    () async {
      final root = await writeWriteProject();
      expect(
        () => writeIn(
          root,
          (s) => requirePlaced(s, const [
            LandedDoc(docPath: 'specs/zz/NOTE.md', docTypeId: 'architecture'),
          ]),
        ),
        throwsA(_refusal('specs/zz/NOTE.md matches no doc type')),
      );
    },
  );

  // D7
  test(
    'a landed doc whose path two doc types match is refused listing both ids',
    () async {
      final root = await writeGroupedProject(
        extra: {
          '.specstone/templates/api.yaml':
              'path: specs/{slug}/f{nn}_recipes/SECURITY.md\n',
        },
      );
      expect(
        () => writeIn(
          root,
          (s) => requirePlaced(s, const [
            LandedDoc(
              docPath: 'specs/kitchen/f01_recipes/SECURITY.md',
              docTypeId: 'security',
            ),
          ]),
        ),
        throwsA(
          _refusal(
            'specs/kitchen/f01_recipes/SECURITY.md matches api, security',
          ),
        ),
      );
    },
  );

  // D7
  test('a landed doc whose path another doc type matches is refused, never retyped', () async {
    final root = await writeWriteProject();
    expect(
      () => writeIn(
        root,
        (s) => requirePlaced(s, const [
          LandedDoc(docPath: loginArch, docTypeId: 'user_story'),
        ]),
      ),
      throwsA(_refusal('$loginArch matches architecture, not user_story')),
    );
  });

  // D7
  test(
    'landed docs are judged in tree order and an untyped entry takes no test',
    () async {
      final root = await writeWriteProject();
      expect(
        () => writeIn(
          root,
          (s) => requirePlaced(s, const [
            LandedDoc(docPath: 'specs/zz/B.md', docTypeId: 'architecture'),
            LandedDoc(docPath: 'specs/zz/untyped.md', docTypeId: null),
            LandedDoc(docPath: 'specs/aa/A.md', docTypeId: 'architecture'),
          ]),
        ),
        throwsA(_refusal('specs/aa/A.md matches no doc type')),
      );
      writeIn(
        root,
        (s) => requirePlaced(s, const [
          LandedDoc(docPath: 'specs/zz/untyped.md', docTypeId: null),
          LandedDoc(docPath: loginArch, docTypeId: 'architecture'),
        ]),
      );
    },
  );

  // D7
  test('landedDocsOf names each doc under a move at its new path with its own doc type and target', () async {
    final root = await writeTwinProject();
    final landed = writeIn(
      root,
      (s) => landedDocsOf(s, const [
        PathMove(from: 'specs/flutter/', to: 'specs/web/'),
        PathMove(
          from: '.specstone/records/flutter/',
          to: '.specstone/records/web/',
        ),
      ]),
    );
    expect(
      [
        for (final doc in landed)
          '${doc.docPath} ${doc.docTypeId} ${doc.target}',
      ],
      [
        'specs/web/TECH_STACK.md tech_stack flutter',
        'specs/web/f01_login/ARCHITECTURE.md architecture flutter',
        '.specstone/records/web/f01_login/IMPLEMENTATION.md implementation flutter',
      ],
    );
  });

  // D7
  test('a per-target doc landed on the path of its type for another target is refused naming both targets', () async {
    final root = await writeTwinProject();
    final before = treeBytes(root)
      ..removeWhere((k, _) => !k.startsWith('docs'));
    expect(
      () => writeIn(
        root,
        (s) => requirePlaced(s, const [
          LandedDoc(
            docPath: jasprArchitecture,
            docTypeId: 'architecture',
            target: 'flutter',
          ),
        ]),
      ),
      throwsA(
        _refusal(
          '$jasprArchitecture matches architecture for jaspr, '
          'not architecture for flutter',
        ),
      ),
    );
    expect(
      treeBytes(root)..removeWhere((k, _) => !k.startsWith('docs')),
      before,
    );
  });

  // D6
  group('path length', () {
    // A character outside the Basic Multilingual Plane, two UTF-16 units.
    const astral = '\u{1F600}';

    /// Returns an untyped DocPath whose project path holds [units] code units
    /// and one astral character.
    String astralPath(int units) {
      const head = 'specs/';
      const tail = '/NOTE.md';
      final fill = units - 'docs/'.length - head.length - tail.length - 2;
      return '$head$astral${'a' * fill}$tail';
    }

    Matcher tooLong(String docPath, int units) => _refusal(
      'docs/$docPath would have $units characters; the limit is 200',
    );

    test('an untyped landed doc at 200 code units passes and at 201 is refused naming its project path and count', () async {
      final root = await writeWriteProject();
      writeIn(
        root,
        (s) => requirePlaced(s, [
          LandedDoc(docPath: 'specs/${'a' * 186}.md', docTypeId: null),
        ]),
      );
      final longer = 'specs/${'a' * 187}.md';
      expect(
        () => writeIn(
          root,
          (s) =>
              requirePlaced(s, [LandedDoc(docPath: longer, docTypeId: null)]),
        ),
        throwsA(tooLong(longer, 201)),
      );
    });

    test('a character outside the BMP counts two units, so 199 characters pass and 200 are refused', () async {
      final root = await writeWriteProject();
      final fits = astralPath(200);
      expect(fits.length + 'docs/'.length, 200);
      expect(fits.runes.length + 'docs/'.length, 199);
      writeIn(
        root,
        (s) => requirePlaced(s, [LandedDoc(docPath: fits, docTypeId: null)]),
      );
      final over = astralPath(201);
      expect(over.runes.length + 'docs/'.length, 200);
      expect(
        () => writeIn(
          root,
          (s) => requirePlaced(s, [LandedDoc(docPath: over, docTypeId: null)]),
        ),
        throwsA(tooLong(over, 201)),
      );
    });

    test('a record is counted from its own path, not from docs/', () async {
      final root = await writeWriteProject();
      const head = '.specstone/records/f01_';
      const tail = '/IMPLEMENTATION.md';
      String record(int units) =>
          '$head${'a' * (units - head.length - tail.length)}$tail';
      writeIn(
        root,
        (s) => requirePlaced(s, [
          LandedDoc(docPath: record(200), docTypeId: null),
        ]),
      );
      expect(
        () => writeIn(
          root,
          (s) => requirePlaced(s, [
            LandedDoc(docPath: record(201), docTypeId: null),
          ]),
        ),
        throwsA(
          _refusal(
            '${record(201)} would have 201 characters; the limit is 200',
          ),
        ),
      );
    });

    test('the length is judged before the type test of any entry', () async {
      final root = await writeWriteProject();
      final longer = 'specs/zz/${'a' * 190}.md';
      expect(
        () => writeIn(
          root,
          (s) => requirePlaced(s, [
            const LandedDoc(
              docPath: 'specs/aa/A.md',
              docTypeId: 'architecture',
            ),
            LandedDoc(docPath: longer, docTypeId: null),
          ]),
        ),
        throwsA(tooLong(longer, 'docs/$longer'.length)),
      );
    });

    test('of two over-long entries the first in tree order is named, a numbered segment compared by its number', () async {
      final root = await writeWriteProject();
      final fill = 'a' * 170;
      final ninetyNine = 'prds/features/f99_$fill/FEATURE.md';
      final hundred = 'prds/features/f100_$fill/FEATURE.md';
      expect(
        () => writeIn(
          root,
          (s) => requirePlaced(s, [
            LandedDoc(docPath: hundred, docTypeId: null),
            LandedDoc(docPath: ninetyNine, docTypeId: null),
          ]),
        ),
        throwsA(tooLong(ninetyNine, 'docs/$ninetyNine'.length)),
      );
    });

    test('a move judges the length of each record it creates', () async {
      final root = await writeWriteProject();
      const head = '.specstone/records/f01_';
      const tail = '/IMPLEMENTATION.md';
      final record = '$head${'a' * (201 - head.length - tail.length)}$tail';
      expect(
        () => writeIn(
          root,
          (s) =>
              requireMovePlaced(s, const [], creates: [CreateStep(record, '')]),
        ),
        throwsA(
          _refusal('$record would have 201 characters; the limit is 200'),
        ),
      );
    });

    // D6: "the first such path in tree order", the order the index walks.
    test('of an over-long doc and record the doc is named, the docs root coming first in tree order', () async {
      final root = await writeWriteProject();
      final fill = 'a' * 180;
      final doc = 'specs/f01_$fill/ARCHITECTURE.md';
      final record = '.specstone/records/f01_$fill/IMPLEMENTATION.md';
      expect(
        () => writeIn(
          root,
          (s) => requirePlaced(s, [
            LandedDoc(docPath: record, docTypeId: null),
            LandedDoc(docPath: doc, docTypeId: null),
          ]),
        ),
        throwsA(tooLong(doc, 'docs/$doc'.length)),
      );
    });

    test('of an over-long file and a doc in a subfolder beside it the file is named, as tree order puts a file first', () async {
      final root = await writeWriteProject();
      final folder = 'specs/${'a' * 190}';
      final file = '$folder/zz.md';
      final nested = '$folder/b/a.md';
      expect(
        () => writeIn(
          root,
          (s) => requirePlaced(s, [
            LandedDoc(docPath: nested, docTypeId: null),
            LandedDoc(docPath: file, docTypeId: null),
          ]),
        ),
        throwsA(tooLong(file, 'docs/$file'.length)),
      );
    });
  });
}
