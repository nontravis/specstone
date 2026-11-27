import 'dart:io';

import 'package:specstone_core/src/consistency_check/code_rules.dart'
    show readPathOf, readsCoversCode, readsEntryCode;
import 'package:specstone_core/src/consistency_check/exact_case_path.dart';
import 'package:specstone_core/src/templates/models/record_status.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('specstone_exact_path_');
    addTearDown(() => root.deleteSync(recursive: true));
  });

  void touch(String path) => File('${root.path}/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync('');

  CodePathVerdict resolve(String entry) =>
      ExactCasePaths().resolve(root, entry);

  // D9: one resolver gives each entry form one verdict.
  test('resolve gives one verdict per entry form, and a .. anywhere is a '
      'parent segment', () {
    touch('lib/a.dart');
    Directory('${root.path}/other').createSync();
    if (!Platform.isWindows) {
      Link('${root.path}/lib/link').createSync('../other');
    }

    expect(resolve('lib/a.dart').kind, CodePathKind.file);
    expect(resolve('lib/').kind, CodePathKind.folder);
    expect(resolve('lib/./').kind, CodePathKind.folder);
    expect(resolve('./').kind, CodePathKind.empty);
    expect(resolve('lib/nope/../a.dart').kind, CodePathKind.parentSegment);
    expect(resolve('./lib/../').kind, CodePathKind.parentSegment);
    expect(resolve('../a.dart').kind, CodePathKind.parentSegment);
    final wrongCase = resolve('LIB/a.dart');
    expect(wrongCase.kind, CodePathKind.wrongCase);
    expect(wrongCase.diskPath, 'lib/a.dart');
    expect(wrongCase.exists, isFalse);
    expect(resolve('lib/b.dart').kind, CodePathKind.missing);
    expect(resolve(r'lib\a.dart').kind, CodePathKind.notPortable);
    expect(resolve('lib/a.dart').exists, isTrue);
    if (!Platform.isWindows) {
      expect(resolve('lib/link/../a.dart').kind, CodePathKind.parentSegment);
    }
  });

  // D9: a segment equals a disk name in Unicode NFC, whichever form either has.
  test('resolve matches an NFC segment to an NFD disk name, and an NFD '
      'segment to an NFC one', () {
    const cafeNfc = 'caf\u{E9}.dart';
    const cafeNfd = 'cafe\u{301}.dart';
    const naiveNfc = 'na\u{EF}ve.dart';
    const naiveNfd = 'nai\u{308}ve.dart';
    touch('lib/$cafeNfc');
    touch('lib/$naiveNfd');

    final fromNfd = resolve('lib/$cafeNfd');
    expect(fromNfd.kind, CodePathKind.file);
    expect(fromNfd.diskPath, 'lib/$cafeNfc');
    final fromNfc = resolve('lib/$naiveNfc');
    expect(fromNfc.kind, CodePathKind.file);
    expect(fromNfc.diskPath, 'lib/$naiveNfd');
  });

  // D9: a reader opens the disk's spelling, on a disk that compares bytes too.
  test('readsEntryCode and readsCoversCode hand the readers the disk '
      'spelling of an entry written in another Unicode form', () {
    touch('lib/cafe\u{301}.dart');
    final paths = ExactCasePaths();

    expect(
      readsEntryCode(
        paths,
        root,
        RecordStatus.implemented,
        'lib/caf\u{E9}.dart:Symbol',
      ),
      'lib/cafe\u{301}.dart',
    );
    expect(
      readsCoversCode(paths, root, 'lib/caf\u{E9}.dart', endsWait: true),
      'lib/cafe\u{301}.dart',
    );
    expect(
      readsEntryCode(paths, root, RecordStatus.skipped, 'lib/caf\u{E9}.dart'),
      isNull,
    );
    expect(
      readsCoversCode(paths, root, 'lib/caf\u{E9}.dart', endsWait: false),
      isNull,
    );
  });

  test('readPathOf keeps the written path unless the disk spells it '
      'differently', () {
    expect(readPathOf('lib/', 'lib'), 'lib/');
    expect(
      readPathOf('lib/caf\u{E9}.dart', 'lib/cafe\u{301}.dart'),
      'lib/cafe\u{301}.dart',
    );
  });
}
