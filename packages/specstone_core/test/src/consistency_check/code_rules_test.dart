// The expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/code_rules.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';
import '../../helpers/posix_modes.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/target_fixture.dart';
import '../../helpers/temp_tree.dart';

const _flutterTech = 'specs/flutter/TECH_STACK.md';
const _jasprTech = 'specs/jaspr/TECH_STACK.md';
const _flutterRecord = 'specs/flutter/f01_login/IMPLEMENTATION.md';
const _jasprRecord = 'specs/jaspr/f01_login/IMPLEMENTATION.md';
const _implemented = 'email_login/check_password:implemented';
const _sharedTopic = 'specs/topics/doc_model.md';
const _sharedTopic1 =
    '---\ncovers:\n  - lib/src/\n---\n\n# Doc model\n\n## Purpose\n\n'
    'One rule set.\n\n## Scope\n\nThe src folder.\n';

/// Returns a record holding the one-line [statuses].
String _record(List<String> statuses) =>
    '---\nstatuses:\n${[for (final s in statuses) "  - '$s'\n"].join()}---\n\n'
    '# Record\n';

/// Returns an `architecture` doc covering [covers].
String _arch(String covers) =>
    doc(loginArchitecture, 'app/lib/', covers).values.single;

/// Returns a `tech_stack` doc whose code roots are [roots].
String _tech(List<String> roots) => doc(
  techStack,
  '  - app/lib/\n',
  [for (final r in roots) '  - $r\n'].join(),
).values.single;

/// Returns the login story and FR as written by a project that has not
/// implemented either.
Map<String, String> _planned() => {
  'docs/$loginRecord': _record([
    'email_login:planned',
    'email_login/check_password:planned',
  ]),
};

/// Writes the two-target project with one `tech_stack` doc per target.
Future<Directory> _twin({
  Map<String, String> extra = const {},
  Set<String> without = const {},
}) => writeTwinProject(
  without: {'docs/$techStack', ...without},
  extra: {
    // The shared topic of the shared-doc tests: a layer takes it back from
    // the shipped per-target pack.
    '.specstone/templates/topic.yaml': 'id: topic\nper_target: false\n',
    'docs/$_flutterTech': _tech(['app/lib/']),
    'docs/$_jasprTech': _tech(['app/lib/']),
    ...extra,
  },
);

CheckReport _run(Directory project, {String? codeTarget}) {
  final session = openSession(project);
  try {
    return runCheck(session, codeTarget: codeTarget);
  } finally {
    session.close();
  }
}

/// Returns `<path>: <entry or path>` per finding of [kind].
List<String> _of(CheckReport report, FindingKind kind) => [
  for (final f in report.findings)
    if (f.kind == kind) '${f.path}: ${f.keys['entry'] ?? f.keys['path']}',
];

void main() {
  /// Sets the fixture architecture's one `covers` entry.
  Map<String, String> narrow(String covers) =>
      doc(loginArchitecture, 'app/lib/', covers);

  test('f04/us02/s3, f04/us02/fr03/e01: a file under the code root no covers entry reaches is code_uncovered', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          ...narrow('app/lib/src/'),
          'app/lib/src/a.dart': '',
          'app/lib/main.dart': '',
        },
      ),
    );
    expect(spots(report), [
      '$techStack:4: code_uncovered',
      '$techStack:4: code_uncovered',
    ]);
    expect(
      report.findings.last.message,
      'app/lib/main.dart is under the code root app/lib/ and no covers entry reaches it',
    );
    expect(
      [for (final f in report.findings) f.toJson()['path']],
      ['app/lib/login.dart', 'app/lib/main.dart'],
    );
  });

  test('a ./ covers entry reaches the files of a ./ code entry', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          ...doc(techStack, '  - app/lib/\n', '  - ./app/lib/\n'),
          ...doc(loginArchitecture, '  - app/lib/\n', '  - ./app/lib/\n'),
          'app/lib/src/a.dart': '',
        },
      ),
    );
    expect(spots(report, FindingKind.codeUncovered), isEmpty);
    expect(spots(report, FindingKind.coversPathMissing), isEmpty);
  });

  test('code_root: covers and code resolve under the code folder; code_uncovered names a path from it', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          '.specstone/config.yaml': '${shippedPinsConfig()}code_root: code\n',
          ...narrow('app/lib/src/'),
          'code/app/lib/login.dart': checkProjectFiles()['app/lib/login.dart']!,
          'code/app/lib/x.dart': '',
          'code/app/lib/src/a.dart': '',
          'app/lib/stray.dart': '',
        },
        without: {'app/lib/login.dart'},
      ),
    );
    expect(spots(report), [
      '$techStack:4: code_uncovered',
      '$techStack:4: code_uncovered',
      '$loginArchitecture:4: code_unconfirmed',
      '$loginRecord:7: code_unconfirmed',
      '$loginRecord:8: code_unconfirmed',
    ]);
    expect(
      [
        for (final f in report.findings)
          if (f.kind == FindingKind.codeUncovered) f.toJson()['path'],
      ],
      ['app/lib/login.dart', 'app/lib/x.dart'],
    );
  });

  test(
    'f04/us02/s4, f04/us02/fr03/e02: with no code field the check does not run',
    () async {
      final report = checkOf(
        await writeCheckProject(
          extra: {
            ...narrow('app/lib/src/'),
            ...doc(techStack, '---\ncode:\n  - app/lib/\n---\n\n', ''),
          },
        ),
      );
      expect(spots(report, FindingKind.codeUncovered), isEmpty);
    },
  );

  test(
    'f04/us02/fr03/e03, f04/us02/fr03/e04: dot names and links are skipped; generated files have no exclude',
    skip: Platform.isWindows
        ? 'a symbolic link needs a privilege on Windows'
        : null,
    () async {
      final outside = await writeTree({'x.dart': ''});
      final project = await writeCheckProject(
        extra: {...narrow('app/lib/login.dart'), 'app/lib/.DS_Store': ''},
      );
      Link('${project.path}/app/lib/linked').createSync(outside.path);
      expect(spots(checkOf(project), FindingKind.codeUncovered), isEmpty);
      final generated = checkOf(
        await writeCheckProject(extra: {'app/lib/login.g.dart': ''}),
      );
      expect(spots(generated, FindingKind.codeUncovered), isEmpty);
    },
  );

  test(
    'a folder entry reaches only the files inside it, by path segment',
    () async {
      final report = checkOf(
        await writeCheckProject(
          extra: {...narrow('app/lib/src'), 'app/lib/srcx/a.dart': ''},
        ),
      );
      expect([
        for (final f in report.findings) f.toJson()['path'],
      ], contains('app/lib/srcx/a.dart'));
    },
  );

  test('f04/us02/s6, f04/us02/fr03/e06: a check on one feature leaves uncovered code out', () async {
    final project = await writeCheckProject(
      extra: {...narrow('app/lib/src/'), 'app/lib/main.dart': ''},
    );
    expect(
      spots(checkOf(project, target: 'login'), FindingKind.codeUncovered),
      isEmpty,
    );
  });

  test('f04/us02/fr02/e04, f04/us02/fr03/e07: a missing root is code_root_missing; the other root is still listed', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          ...doc(techStack, '  - app/lib/\n', '  - app/lib/\n  - api/lib/\n'),
          ...narrow('app/lib/src/'),
          'app/lib/src/a.dart': '',
        },
      ),
    );
    expect(spots(report), [
      '$techStack:4: code_uncovered',
      '$techStack:5: code_root_missing',
    ]);
  });

  test('f04/us02/s8, f04/us02/fr02/e01, f04/us02/fr02/e02, f04/us02/fr02/e03, f04/us02/fr02/e05: a covers entry '
      'names a file or a folder, with or without a final slash; one that moved names nothing', () async {
    for (final entry in ['app/lib/login.dart', 'app/lib']) {
      expect(
        spots(
          checkOf(await writeCheckProject(extra: narrow(entry))),
          FindingKind.coversPathMissing,
        ),
        isEmpty,
      );
    }
    final moved = checkOf(
      await writeCheckProject(extra: narrow('app/lib/login/')),
    );
    expect(spots(moved, FindingKind.coversPathMissing), [
      '$loginArchitecture:4: covers_path_missing',
    ]);
    expect(
      moved.findings
          .firstWhere((f) => f.kind == FindingKind.coversPathMissing)
          .textLine,
      '$loginArchitecture:4: covers_path_missing: app/lib/login/ names nothing on disk',
    );
  });

  test(
    'a covers entry ending in a fingerprint names what its prefix names',
    () async {
      for (final entry in [
        'app/lib/login.dart 9a1c03be55d2',
        'app/lib/ 9a1c03be55d2',
      ]) {
        expect(
          spots(
            checkOf(await writeCheckProject(extra: narrow(entry))),
            FindingKind.coversPathMissing,
          ),
          isEmpty,
          reason: entry,
        );
      }
      final moved = checkOf(
        await writeCheckProject(extra: narrow('app/lib/login/ 9a1c03be55d2')),
      );
      expect(_of(moved, FindingKind.coversPathMissing), [
        '$loginArchitecture: app/lib/login/',
      ]);
    },
  );

  test('an upper-case token stays part of the covers path', () async {
    final report = checkOf(
      await writeCheckProject(extra: narrow('app/lib/ 9A1C03BE55D2')),
    );

    expect(_of(report, FindingKind.coversPathMissing), [
      '$loginArchitecture: app/lib/ 9A1C03BE55D2',
    ]);
  });

  test(
    'a file under a covers folder that ends in a fingerprint is covered',
    () async {
      final report = checkOf(
        await writeCheckProject(
          extra: {...narrow('app/lib/ 9a1c03be55d2'), 'app/lib/main.dart': ''},
        ),
      );

      expect(spots(report, FindingKind.codeUncovered), isEmpty);
    },
  );

  test('cc-INV-10: a file under two roots is reported once, under the first root that lists it', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          ...doc(techStack, '  - app/lib/\n', '  - app/lib/\n  - app/\n'),
          ...narrow('app/lib/login.dart'),
          'app/lib/main.dart': '',
        },
      ),
    );
    expect(spots(report, FindingKind.codeUncovered), [
      '$techStack:4: code_uncovered',
    ]);
  });

  test(
    'a code root that cannot be listed gives a warning and no finding',
    skip: unreadablePathSkipReason(),
    () async {
      final project = await writeCheckProject(
        extra: {
          ...narrow('app/lib/src/'),
          'app/lib/src/b.dart': '',
          'app/lib/sealed/a.dart': '',
        },
      );
      final path = '${project.path}/app/lib/sealed';
      Process.runSync('chmod', ['000', path]);
      addTearDown(() => Process.runSync('chmod', ['755', path]));
      final report = checkOf(project);
      expect(spots(report, FindingKind.codeUncovered), [
        '$techStack:4: code_uncovered',
      ]);
      expect(report.warnings, [
        'app/lib/sealed: cannot list the folder; files under it are not checked for covers or fingerprints',
        'app/lib/sealed: cannot list the folder; files under it are not checked for doc names',
      ]);
    },
  );

  test(
    'a code entry that names a file is checked for covers as that file',
    () async {
      final uncovered = checkOf(
        await writeCheckProject(
          extra: {
            ...doc(techStack, '- app/lib/\n', '- app/lib/other.dart\n'),
            ...narrow('app/lib/login.dart'),
            'app/lib/other.dart': '',
          },
        ),
      );
      expect(
        [for (final f in uncovered.findings) f.toJson()['path']],
        ['app/lib/other.dart'],
      );
    },
  );

  group('the wait for the first implemented entry of a target', () {
    test(
      'an architecture doc waits for an entry of its own feature, then reports',
      () async {
        final waiting = checkOf(
          await writeCheckProject(
            extra: {..._planned(), ...narrow('app/lib/login/')},
          ),
        );
        expect(spots(waiting, FindingKind.coversPathMissing), isEmpty);
        final done = checkOf(
          await writeCheckProject(
            extra: {
              'docs/$loginRecord': _record([
                'email_login:implemented',
                'email_login/check_password:planned',
              ]),
              ...narrow('app/lib/login/'),
            },
          ),
        );
        expect(_of(done, FindingKind.coversPathMissing), [
          '$loginArchitecture: app/lib/login/',
        ]);
      },
    );

    test('an entry of another feature does not end the wait of an architecture doc', () async {
      final report = checkOf(
        await writeCheckProject(
          extra: {
            ..._planned(),
            ...narrow('app/lib/login/'),
            'docs/prds/features/f02_shop/FEATURE.md':
                checkProjectFiles()['docs/$loginFeature']!,
            'docs/prds/features/f02_shop/us01_email_login/USER_STORY.md':
                checkProjectFiles()['docs/$loginStory']!,
            'docs/specs/f02_shop/ARCHITECTURE.md': _arch('app/lib/shop/'),
            'docs/specs/f02_shop/IMPLEMENTATION.md': _record([
              'email_login:implemented',
            ]),
          },
        ),
      );
      expect(_of(report, FindingKind.coversPathMissing), [
        'specs/f02_shop/ARCHITECTURE.md: app/lib/shop/',
      ]);
    });

    test('an entry of a nested feature ends the wait of the architecture doc above', () async {
      final report = checkOf(
        await writeCheckProject(
          extra: {
            ..._planned(),
            ...narrow('app/lib/login/'),
            'docs/prds/features/f01_login/f01_remember/FEATURE.md':
                checkProjectFiles()['docs/$loginFeature']!,
            'docs/prds/features/f01_login/f01_remember/us01_remember_me/USER_STORY.md':
                checkProjectFiles()['docs/$loginStory']!,
            'docs/specs/f01_login/f01_remember/IMPLEMENTATION.md': _record([
              'remember_me:implemented',
            ]),
          },
        ),
      );
      expect(_of(report, FindingKind.coversPathMissing), [
        '$loginArchitecture: app/lib/login/',
      ]);
    });

    test('f04/us02/fr02/e09, f04/us02/fr03/e10: a code root waits for any entry of the target; once one is implemented it is missing', () async {
      final roots = doc(
        techStack,
        '  - app/lib/\n',
        '  - app/lib/\n  - api/lib/\n',
      );
      final waiting = checkOf(
        await writeCheckProject(extra: {..._planned(), ...roots}),
      );
      expect(spots(waiting, FindingKind.codeRootMissing), isEmpty);
      final done = checkOf(await writeCheckProject(extra: roots));
      expect(_of(done, FindingKind.codeRootMissing), ['$techStack: api/lib/']);
    });

    test('a topic covers entry waits for any entry of the target', () async {
      const topic =
          '---\ncovers:\n  - lib/gone/\n---\n\n# Doc model\n\n## Purpose\n\n'
          'One rule set.\n\n## Scope\n\nThe gone folder.\n';
      final waiting = checkOf(
        await writeCheckProject(
          extra: {..._planned(), 'docs/specs/topics/doc_model.md': topic},
        ),
      );
      expect(spots(waiting, FindingKind.coversPathMissing), isEmpty);
      final done = checkOf(
        await writeCheckProject(
          extra: {'docs/specs/topics/doc_model.md': topic},
        ),
      );
      expect(_of(done, FindingKind.coversPathMissing), [
        'specs/topics/doc_model.md: lib/gone/',
      ]);
    });

    test('a code root folder that is missing makes each covers entry and code root of an implemented target missing', () async {
      final report = checkOf(
        await writeCheckProject(
          extra: {
            '.specstone/config.yaml':
                '${shippedPinsConfig()}code_root: nowhere\n',
          },
        ),
      );
      expect(_of(report, FindingKind.coversPathMissing), [
        '$loginArchitecture: app/lib/',
      ]);
      expect(_of(report, FindingKind.codeRootMissing), [
        '$techStack: app/lib/',
      ]);
    });
  });

  test('cc-INV-47: a shared doc with covers in a one-target project is no shared_doc_code_path', () async {
    final report = checkOf(
      await writeCheckProject(extra: {'docs/$_sharedTopic': _sharedTopic1}),
    );
    expect(
      report.findings.where((f) => f.kind == FindingKind.sharedDocCodePath),
      isEmpty,
    );
  });

  group('two targets', () {
    test('each target resolves its covers and code roots against its own code root', () async {
      final project = await _twin(
        extra: {
          'docs/$_flutterRecord': _record([_implemented]),
          'docs/$_jasprRecord': _record([_implemented]),
          'flutter_ws/app/lib/extra/x.dart': '',
          'docs/$flutterArchitecture': _arch('app/lib/extra/'),
          'docs/$jasprArchitecture': _arch('app/lib/extra/'),
          'docs/$_flutterTech': _tech(['app/lib/', 'app/extra/']),
          'docs/$_jasprTech': _tech(['app/lib/', 'app/extra/']),
          'jaspr_ws/app/extra/y.dart': '',
        },
      );
      final report = _run(project);
      expect(_of(report, FindingKind.coversPathMissing), [
        '$jasprArchitecture: app/lib/extra/',
      ]);
      expect(_of(report, FindingKind.codeRootMissing), [
        '$_flutterTech: app/extra/',
      ]);
    });

    test('a target with an implemented entry resolves its paths and a target with none raises nothing', () async {
      final project = await _twin(
        extra: {
          'docs/$_flutterRecord': _record([_implemented]),
          'docs/$_jasprRecord': _record(['email_login/check_password:planned']),
          'docs/$flutterArchitecture': _arch('app/lib/gone/'),
          'docs/$jasprArchitecture': _arch('app/lib/gone/'),
          'docs/$_flutterTech': _tech(['app/lib/', 'api/']),
          'docs/$_jasprTech': _tech(['app/lib/', 'api/']),
        },
      );
      final report = _run(project);
      expect(_of(report, FindingKind.coversPathMissing), [
        '$flutterArchitecture: app/lib/gone/',
      ]);
      expect(_of(report, FindingKind.codeRootMissing), ['$_flutterTech: api/']);
    });

    test('each target lists its files under its own code root and matches its own covers only', () async {
      final project = await _twin(
        extra: {
          'flutter_ws/app/lib/main.dart': '',
          'jaspr_ws/app/lib/web.dart': '',
          'docs/$flutterArchitecture': _arch('app/lib/'),
          'docs/$jasprArchitecture': _arch('app/lib/login.dart'),
        },
      );
      final report = _run(project);
      expect(_of(report, FindingKind.codeUncovered), [
        '$_jasprTech: app/lib/web.dart',
      ]);
    });

    test(
      'a covers entry of one target never reaches the file of another',
      () async {
        final project = await _twin(
          extra: {
            'flutter_ws/app/lib/main.dart': '',
            'docs/$flutterArchitecture': _arch('app/lib/login.dart'),
            'docs/$jasprArchitecture': _arch('app/lib/'),
          },
        );
        expect(_of(_run(project), FindingKind.codeUncovered), [
          '$_flutterTech: app/lib/main.dart',
        ]);
      },
    );

    test(
      'a target with no code yet lists nothing and raises no missing root',
      () async {
        final project = await _twin(
          extra: {
            'docs/$_flutterRecord': _record([_implemented]),
            'docs/$_jasprTech': _tech(['web/']),
            'docs/$flutterArchitecture': _arch('app/lib/'),
            'docs/$jasprArchitecture': _arch('web/'),
          },
          without: {'jaspr_ws/app/lib/login.dart'},
        );
        final report = _run(project);
        expect(_of(report, FindingKind.codeUncovered), isEmpty);
        expect(_of(report, FindingKind.codeRootMissing), isEmpty);
        expect(_of(report, FindingKind.coversPathMissing), isEmpty);
      },
    );

    test('cc-INV-47: a shared doc with covers in a project of two targets is shared_doc_code_path, once, at the key line', () async {
      final project = await _twin(extra: {'docs/$_sharedTopic': _sharedTopic1});
      final report = _run(project);
      final line =
          File('${project.path}/docs/$_sharedTopic')
              .readAsLinesSync()
              .indexWhere((l) => l.startsWith('covers:')) +
          1;
      final found = report.findings.where(
        (f) => f.kind == FindingKind.sharedDocCodePath,
      );
      expect(found.map((f) => (f.path, f.line)), [(_sharedTopic, line)]);
      expect(
        found.single.message,
        'the doc carries code paths but belongs to no target; move them '
        'into a doc of the target they belong to',
      );
    });

    test('cc-INV-47: a shared doc with an empty covers key is no shared_doc_code_path', () async {
      final report = _run(
        await _twin(
          extra: {
            'docs/$_sharedTopic': _sharedTopic1.replaceFirst(
              'covers:\n  - lib/src/\n',
              'covers: []\n',
            ),
          },
        ),
      );
      expect(
        report.findings.where((f) => f.kind == FindingKind.sharedDocCodePath),
        isEmpty,
      );
    });

    test(
      'cc-INV-47: a per-target doc with covers is no shared_doc_code_path',
      () async {
        final report = _run(await _twin());
        expect(
          report.findings.where((f) => f.kind == FindingKind.sharedDocCodePath),
          isEmpty,
        );
      },
    );

    test('a --target run lists the files of that target only', () async {
      final project = await _twin(
        extra: {
          'flutter_ws/app/lib/main.dart': '',
          'jaspr_ws/app/lib/web.dart': '',
          'docs/$flutterArchitecture': _arch('app/lib/login.dart'),
          'docs/$jasprArchitecture': _arch('app/lib/login.dart'),
        },
      );
      expect(
        _of(_run(project, codeTarget: 'jaspr'), FindingKind.codeUncovered),
        ['$_jasprTech: app/lib/web.dart'],
      );
    });

    test('with nested code roots a file counts for the target of the longest root only', () async {
      final project = await _twin(
        extra: {
          '.specstone/config.yaml':
              '${shippedPinsConfig()}targets:\n'
              '  flutter:\n    code_root: ws\n'
              '  jaspr:\n    code_root: ws/web\n',
          'ws/lib/a.dart': '',
          'ws/web/lib/b.dart': '',
          'docs/$_flutterTech': _tech(['lib/', 'web/']),
          'docs/$_jasprTech': _tech(['lib/']),
          'docs/$flutterArchitecture': _arch('lib/login.dart'),
          'docs/$jasprArchitecture': _arch('lib/login.dart'),
        },
        without: {
          'flutter_ws/app/lib/login.dart',
          'jaspr_ws/app/lib/login.dart',
        },
      );
      expect(_of(_run(project), FindingKind.codeUncovered), [
        '$_flutterTech: lib/a.dart',
        '$_jasprTech: lib/b.dart',
      ]);
    });
  });

  test(
    'an entry with a backslash or a name Windows trims '
    'names nothing on any OS, though a POSIX disk holds such names',
    () async {
      final tree = await writeTree({'lib/a.dart': ''});
      for (final name in [r'co\de', 'trail ', 'dot.']) {
        File('${tree.path}/$name').writeAsStringSync('');
      }

      expect(namesFileOrFolderFrom(tree, 'lib/a.dart'), isTrue);
      for (final entry in [
        r'co\de',
        'trail ',
        'dot.',
        'lib/../trail ',
        r'x\y/..',
      ]) {
        expect(namesFileOrFolderFrom(tree, entry), isFalse, reason: entry);
      }
    },
    skip: Platform.isWindows ? 'Windows cannot hold such a name' : null,
  );
}
