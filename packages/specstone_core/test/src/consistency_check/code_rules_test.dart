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
import '../../helpers/marketing.dart';
import '../../helpers/posix_modes.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/skill_doc_fixture.dart';
import '../../helpers/target_fixture.dart';
import '../../helpers/temp_tree.dart';

const _flutterTech = 'specs/flutter/TECH_STACK.md';
const _jasprTech = 'specs/jaspr/TECH_STACK.md';
const _flutterRecord = '.specstone/records/flutter/f01_login/IMPLEMENTATION.md';
const _jasprRecord = '.specstone/records/jaspr/f01_login/IMPLEMENTATION.md';
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
  loginRecord: _record([
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

/// The `config.yaml` text pinning `prd-core`, `marketing`, and [more], then
/// [rest].
String _marketingConfig(List<String> more, String rest) =>
    '${shippedPinsConfig(['prd-core', ...more, 'marketing'])}$rest';

/// Returns the project of a `campaign` doc covering [covers], with no record
/// and the files [content], under a config of [rest] after the pins.
///
/// A project with targets pins `software-tech` for its record doc type.
Future<Directory> _campaignProject(
  List<String> covers, {
  Map<String, String> content = const {},
  List<String> more = const [],
  String rest = '',
}) => writeCheckProject(
  extra: {
    '.specstone/config.yaml': _marketingConfig(more, rest),
    'docs/$campaignDocPath': campaignDocText(covers),
    ...content,
  },
  without: {loginRecord},
);

/// Writes the login project whose `code_root` is a folder beside it holding
/// [outside], with the code of the project's own `app/` folder left out.
///
/// Returns the project folder. [docs] replaces or adds a project file.
Future<Directory> _outsideRootProject({
  String? config,
  Map<String, String> docs = const {},
  Map<String, String> outside = const {},
  Set<String> without = const {},
}) async {
  final files = withApprovalHashes({...checkProjectFiles(), ...docs});
  final workspace = await writeTree({
    for (final MapEntry(:key, :value) in files.entries)
      if (!key.startsWith('app/') &&
          key != '.specstone/config.yaml' &&
          !without.contains(key))
        'project/$key': value,
    'project/.specstone/config.yaml':
        config ?? '${shippedPinsConfig()}code_root: ../stratum_ui/example\n',
    for (final MapEntry(:key, :value) in outside.entries)
      'stratum_ui/example/$key': value,
  });
  return Directory.fromUri(workspace.uri.resolve('project/'));
}

Future<CheckReport> _run(Directory project, {String? codeTarget}) async {
  final session = openSession(project);
  try {
    return await runCheck(session, codeTarget: codeTarget);
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

  test(
    'a file under the code root no covers entry reaches is code_uncovered',
    () async {
      final report = await checkOf(
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
    },
  );

  test('a ./ covers entry reaches the files of a ./ code entry', () async {
    final report = await checkOf(
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
    final report = await checkOf(
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
    ]);
    expect(
      [
        for (final f in report.findings)
          if (f.kind == FindingKind.codeUncovered) f.toJson()['path'],
      ],
      ['app/lib/login.dart', 'app/lib/x.dart'],
    );
  });

  test('covers and code roots resolve against a code_root outside the project '
      'root', () async {
    final project = await _outsideRootProject(
      docs: {
        loginRecord: _record([_implemented]),
        ...doc(
          loginArchitecture,
          '  - app/lib/\n',
          '  - app/lib/\n  - app/lib/gone/\n',
        ),
        ...doc(techStack, '  - app/lib/\n', '  - app/lib/\n  - api/lib/\n'),
      },
      outside: {
        'app/lib/login.dart': checkProjectFiles()['app/lib/login.dart']!,
      },
    );

    final report = await _run(project);

    expect(_of(report, FindingKind.coversPathMissing), [
      '$loginArchitecture: app/lib/gone/',
    ]);
    expect(_of(report, FindingKind.codeRootMissing), ['$techStack: api/lib/']);
  });

  test('the files listed under a code_root outside the project root are '
      'named from that code root', () async {
    final project = await _outsideRootProject(
      docs: {
        ...doc(techStack, '  - app/lib/\n', '  - lib/\n'),
        ...doc(loginArchitecture, '  - app/lib/\n', '  - lib/a.dart\n'),
      },
      outside: {'lib/a.dart': '', 'lib/b.dart': ''},
      without: {loginRecord},
    );

    final report = await _run(project);

    expect(_of(report, FindingKind.codeUncovered), ['$techStack: lib/b.dart']);
    expect(report.findings.single.message, startsWith('lib/b.dart '));
  });

  test('an uncovered generated file still gives code_uncovered, as no exclude '
      'list exists', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: {...narrow('app/lib/login.dart'), 'app/lib/a.g.dart': ''},
      ),
    );

    expect(_of(report, FindingKind.codeUncovered), [
      '$techStack: app/lib/a.g.dart',
    ]);
  });

  test('with no code field the check does not run', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: {
          ...narrow('app/lib/src/'),
          ...doc(techStack, '---\ncode:\n  - app/lib/\n---\n\n', ''),
        },
      ),
    );
    expect(spots(report, FindingKind.codeUncovered), isEmpty);
  });

  test(
    'dot names and links are skipped; generated files have no exclude',
    skip: Platform.isWindows
        ? 'a symbolic link needs a privilege on Windows'
        : null,
    () async {
      final outside = await writeTree({'x.dart': ''});
      final project = await writeCheckProject(
        extra: {...narrow('app/lib/login.dart'), 'app/lib/.DS_Store': ''},
      );
      Link('${project.path}/app/lib/linked').createSync(outside.path);
      expect(spots(await checkOf(project), FindingKind.codeUncovered), isEmpty);
      final generated = await checkOf(
        await writeCheckProject(extra: {'app/lib/login.g.dart': ''}),
      );
      expect(spots(generated, FindingKind.codeUncovered), isEmpty);
    },
  );

  test(
    'a folder entry reaches only the files inside it, by path segment',
    () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: {...narrow('app/lib/src'), 'app/lib/srcx/a.dart': ''},
        ),
      );
      expect([
        for (final f in report.findings) f.toJson()['path'],
      ], contains('app/lib/srcx/a.dart'));
    },
  );

  test('a check on one feature leaves uncovered code out', () async {
    final project = await writeCheckProject(
      extra: {...narrow('app/lib/src/'), 'app/lib/main.dart': ''},
    );
    expect(
      spots(await checkOf(project, target: 'login'), FindingKind.codeUncovered),
      isEmpty,
    );
  });

  test(
    'a missing root is code_root_missing; the other root is still listed',
    () async {
      final report = await checkOf(
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
    },
  );

  test('a covers entry names a file or a folder, with or without a final slash; one that moved names nothing', () async {
    for (final entry in ['app/lib/login.dart', 'app/lib']) {
      expect(
        spots(
          await checkOf(await writeCheckProject(extra: narrow(entry))),
          FindingKind.coversPathMissing,
        ),
        isEmpty,
      );
    }
    final moved = await checkOf(
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
            await checkOf(await writeCheckProject(extra: narrow(entry))),
            FindingKind.coversPathMissing,
          ),
          isEmpty,
          reason: entry,
        );
      }
      final moved = await checkOf(
        await writeCheckProject(extra: narrow('app/lib/login/ 9a1c03be55d2')),
      );
      expect(_of(moved, FindingKind.coversPathMissing), [
        '$loginArchitecture: app/lib/login/',
      ]);
    },
  );

  test('an upper-case token stays part of the covers path', () async {
    final report = await checkOf(
      await writeCheckProject(extra: narrow('app/lib/ 9A1C03BE55D2')),
    );

    expect(_of(report, FindingKind.coversPathMissing), [
      '$loginArchitecture: app/lib/ 9A1C03BE55D2',
    ]);
  });

  test(
    'a file under a covers folder that ends in a fingerprint is covered',
    () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: {...narrow('app/lib/ 9a1c03be55d2'), 'app/lib/main.dart': ''},
        ),
      );

      expect(spots(report, FindingKind.codeUncovered), isEmpty);
    },
  );

  test('a file under two roots is reported once, under the first root that lists it', () async {
    final report = await checkOf(
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
      final report = await checkOf(project);
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
      final uncovered = await checkOf(
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
        final waiting = await checkOf(
          await writeCheckProject(
            extra: {..._planned(), ...narrow('app/lib/login/')},
          ),
        );
        expect(spots(waiting, FindingKind.coversPathMissing), isEmpty);
        final done = await checkOf(
          await writeCheckProject(
            extra: {
              loginRecord: _record([
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
      final report = await checkOf(
        await writeCheckProject(
          extra: {
            ..._planned(),
            ...narrow('app/lib/login/'),
            'docs/prds/features/f02_shop/FEATURE.md':
                checkProjectFiles()['docs/$loginFeature']!,
            'docs/prds/features/f02_shop/us01_email_login/USER_STORY.md':
                checkProjectFiles()['docs/$loginStory']!,
            'docs/specs/f02_shop/ARCHITECTURE.md': _arch('app/lib/shop/'),
            '.specstone/records/f02_shop/IMPLEMENTATION.md': _record([
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
      final report = await checkOf(
        await writeCheckProject(
          extra: {
            ..._planned(),
            ...narrow('app/lib/login/'),
            'docs/prds/features/f01_login/f01_remember/FEATURE.md':
                checkProjectFiles()['docs/$loginFeature']!,
            'docs/prds/features/f01_login/f01_remember/us01_remember_me/USER_STORY.md':
                checkProjectFiles()['docs/$loginStory']!,
            '.specstone/records/f01_login/f01_remember/IMPLEMENTATION.md':
                _record(['remember_me:implemented']),
          },
        ),
      );
      expect(_of(report, FindingKind.coversPathMissing), [
        '$loginArchitecture: app/lib/login/',
      ]);
    });

    test('a code root waits for any entry of the target; once one is implemented it is missing', () async {
      final roots = doc(
        techStack,
        '  - app/lib/\n',
        '  - app/lib/\n  - api/lib/\n',
      );
      final waiting = await checkOf(
        await writeCheckProject(extra: {..._planned(), ...roots}),
      );
      expect(spots(waiting, FindingKind.codeRootMissing), isEmpty);
      final done = await checkOf(await writeCheckProject(extra: roots));
      expect(_of(done, FindingKind.codeRootMissing), ['$techStack: api/lib/']);
    });

    test('a topic covers entry waits for any entry of the target', () async {
      const topic =
          '---\ncovers:\n  - lib/gone/\n---\n\n# Doc model\n\n## Purpose\n\n'
          'One rule set.\n\n## Scope\n\nThe gone folder.\n';
      final waiting = await checkOf(
        await writeCheckProject(
          extra: {..._planned(), 'docs/specs/topics/doc_model.md': topic},
        ),
      );
      expect(spots(waiting, FindingKind.coversPathMissing), isEmpty);
      final done = await checkOf(
        await writeCheckProject(
          extra: {'docs/specs/topics/doc_model.md': topic},
        ),
      );
      expect(_of(done, FindingKind.coversPathMissing), [
        'specs/topics/doc_model.md: lib/gone/',
      ]);
    });

    test('a code root folder that is missing makes each covers entry and code root of an implemented target missing', () async {
      final report = await checkOf(
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

  test('a shared doc with covers in a one-target project is no shared_doc_code_path', () async {
    final report = await checkOf(
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
          _flutterRecord: _record([_implemented]),
          _jasprRecord: _record([_implemented]),
          'flutter_ws/app/lib/extra/x.dart': '',
          'docs/$flutterArchitecture': _arch('app/lib/extra/'),
          'docs/$jasprArchitecture': _arch('app/lib/extra/'),
          'docs/$_flutterTech': _tech(['app/lib/', 'app/extra/']),
          'docs/$_jasprTech': _tech(['app/lib/', 'app/extra/']),
          'jaspr_ws/app/extra/y.dart': '',
        },
      );
      final report = await _run(project);
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
          _flutterRecord: _record([_implemented]),
          _jasprRecord: _record(['email_login/check_password:planned']),
          'docs/$flutterArchitecture': _arch('app/lib/gone/'),
          'docs/$jasprArchitecture': _arch('app/lib/gone/'),
          'docs/$_flutterTech': _tech(['app/lib/', 'api/']),
          'docs/$_jasprTech': _tech(['app/lib/', 'api/']),
        },
      );
      final report = await _run(project);
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
      final report = await _run(project);
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
        expect(_of(await _run(project), FindingKind.codeUncovered), [
          '$_flutterTech: app/lib/main.dart',
        ]);
      },
    );

    test(
      'a target with no code yet lists nothing and raises no missing root',
      () async {
        final project = await _twin(
          extra: {
            _flutterRecord: _record([_implemented]),
            'docs/$_jasprTech': _tech(['web/']),
            'docs/$flutterArchitecture': _arch('app/lib/'),
            'docs/$jasprArchitecture': _arch('web/'),
          },
          without: {'jaspr_ws/app/lib/login.dart'},
        );
        final report = await _run(project);
        expect(_of(report, FindingKind.codeUncovered), isEmpty);
        expect(_of(report, FindingKind.codeRootMissing), isEmpty);
        expect(_of(report, FindingKind.coversPathMissing), isEmpty);
      },
    );

    test('a shared doc with covers in a project of two targets is shared_doc_code_path, once, at the key line', () async {
      final project = await _twin(extra: {'docs/$_sharedTopic': _sharedTopic1});
      final report = await _run(project);
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

    test(
      'a shared doc with an empty covers key is no shared_doc_code_path',
      () async {
        final report = await _run(
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
      },
    );

    test('a per-target doc with covers is no shared_doc_code_path', () async {
      final report = await _run(await _twin());
      expect(
        report.findings.where((f) => f.kind == FindingKind.sharedDocCodePath),
        isEmpty,
      );
    });

    test('the paths of a shared doc resolve against no code root and cover no '
        'file', () async {
      const topic =
          '---\ncovers:\n  - app/lib/\n  - app/lib/gone/\n---\n\n# Doc model\n\n'
          '## Purpose\n\nOne rule set.\n\n## Scope\n\nThe lib folder.\n';
      final project = await _twin(
        extra: {
          _flutterRecord: _record([_implemented]),
          _jasprRecord: _record([_implemented]),
          'docs/$_sharedTopic': topic,
          'flutter_ws/app/lib/main.dart': '',
          'jaspr_ws/app/lib/main.dart': '',
          'docs/$flutterArchitecture': _arch('app/lib/login.dart'),
          'docs/$jasprArchitecture': _arch('app/lib/login.dart'),
        },
      );

      final report = await _run(project);

      expect(_of(report, FindingKind.coversPathMissing), isEmpty);
      expect(_of(report, FindingKind.codeUncovered), [
        '$_flutterTech: app/lib/main.dart',
        '$_jasprTech: app/lib/main.dart',
      ]);
    });

    test('a shared doc with covers beside one named target is no '
        'shared_doc_code_path', () async {
      final project = await writeTwinProject(
        without: {
          'docs/$_jasprTech',
          'docs/$jasprArchitecture',
          'jaspr_ws/app/lib/login.dart',
        },
        extra: {
          '.specstone/config.yaml':
              '${shippedPinsConfig()}targets:\n  flutter:\n'
              '    code_root: flutter_ws\n',
          '.specstone/templates/topic.yaml': 'id: topic\nper_target: false\n',
          'docs/$_flutterTech': _tech(['app/lib/']),
          'docs/$_sharedTopic': _sharedTopic1,
        },
      );

      final report = await _run(project);

      expect(spots(report, FindingKind.sharedDocCodePath), isEmpty);
    });

    test('each doc of no target that holds a code entry is one '
        'shared_doc_code_path', () async {
      final project = await writeTwinProject(
        without: {'docs/$_flutterTech', 'docs/$_jasprTech'},
        extra: {
          '.specstone/templates/topic.yaml': 'id: topic\nper_target: false\n',
          '.specstone/templates/tech_stack.yaml':
              'id: tech_stack\nper_target: false\n',
          'docs/$_sharedTopic': _sharedTopic1,
        },
      );
      File('${project.path}/docs/$techStack').writeAsStringSync(
        withApprovalHashes(checkProjectFiles())['docs/$techStack']!,
      );

      final report = await _run(project);

      expect(
        [
          for (final f in report.findings)
            if (f.kind == FindingKind.sharedDocCodePath) f.path,
        ],
        [techStack, _sharedTopic],
      );
    });

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
        _of(
          await _run(project, codeTarget: 'jaspr'),
          FindingKind.codeUncovered,
        ),
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
      expect(_of(await _run(project), FindingKind.codeUncovered), [
        '$_flutterTech: lib/a.dart',
        '$_jasprTech: lib/b.dart',
      ]);
    });
  });

  group('a campaign covers entry', () {
    const gone = 'posts/gone/';
    const present = 'posts/launch/';
    const post = {'posts/launch/one.md': 'Launch day.\n'};

    test('naming a missing content folder is covers_path_missing at the '
        "entry's line, in a project with no record", () async {
      final project = await _campaignProject([gone]);

      final line = lineOfFirst(project, campaignDocPath, gone);

      expect(spots(await _run(project), FindingKind.coversPathMissing), [
        '$campaignDocPath:$line: covers_path_missing',
      ]);
    });

    test('with two targets gives no shared_doc_code_path, whether its folder '
        'is missing or present', () async {
      const targets =
          'targets:\n  app:\n    code_root: app_ws\n'
          '  site:\n    code_root: site_ws\n';

      for (final (entry, missing) in [(gone, 1), (present, 0)]) {
        final report = await _run(
          await _campaignProject(
            [entry],
            content: post,
            more: ['software-tech'],
            rest: targets,
          ),
        );

        expect(spots(report, FindingKind.sharedDocCodePath), isEmpty);
        expect(
          spots(report, FindingKind.coversPathMissing),
          hasLength(missing),
          reason: entry,
        );
      }
    });

    test('in a project whose one code_root is the project root gives one '
        'result for a missing folder and none for a present one', () async {
      final report = await _run(
        await _campaignProject(
          [gone, present],
          content: post,
          rest: 'code_root: .\n',
        ),
      );

      expect(_of(report, FindingKind.coversPathMissing), [
        '$campaignDocPath: $gone',
      ]);
    });
  });

  group('a root: project covers entry', () {
    const gone = '.claude/skills/gone/SKILL.md';

    test('naming nothing from the project root is covers_path_missing, with '
        'an implemented record and with none', () async {
      Future<Directory> project(Set<String> without) => writeCheckProject(
        extra: {
          '.specstone/config.yaml': '${skillPinsConfig()}code_root: code\n',
          'code/app/lib/login.dart': checkProjectFiles()['app/lib/login.dart']!,
          ...skillDocFile([skillFile, gone]),
          skillFile: skillText,
        },
        without: {'app/lib/login.dart', ...without},
      );

      for (final without in [
        <String>{},
        {loginRecord},
      ]) {
        final report = await checkOf(await project(without));
        expect(_of(report, FindingKind.coversPathMissing), [
          '$skillDoc: $gone',
        ], reason: 'without $without');
      }
    });

    test(
      'an agent covers entry naming nothing is covers_path_missing',
      () async {
        const goneAgent = '.claude/agents/gone.md';
        final report = await checkOf(
          await writeCheckProject(
            extra: {
              '.specstone/config.yaml': skillPinsConfig(),
              ...agentDocFile([agentFile, goneAgent]),
              agentFile: agentText,
            },
          ),
        );

        expect(_of(report, FindingKind.coversPathMissing), [
          '$agentDoc: $goneAgent',
        ]);
      },
    );

    test('with two targets gives no shared_doc_code_path, while a missing '
        'entry and a changed file of the same doc still report', () async {
      final project = await _twin(
        extra: {
          '.specstone/config.yaml':
              '${skillPinsConfig()}targets:\n'
              '  flutter:\n    code_root: flutter_ws\n'
              '  jaspr:\n    code_root: jaspr_ws\n',
          ...skillDocFile(['$skillFile 0123456789ab', gone]),
          skillFile: skillText,
        },
      );

      final report = await _run(project);

      expect(spots(report, FindingKind.sharedDocCodePath), isEmpty);
      expect(_of(report, FindingKind.coversPathMissing), ['$skillDoc: $gone']);
      expect(_of(report, FindingKind.codeSuspect), ['$skillDoc: $skillFile']);
    });

    group(
      'a project-root covers entry covers a skill file under a code root',
      () {
        const skillUnderRoot = 'skills/review/SKILL.md';

        test('with one target', () async {
          final report = await checkOf(
            await writeCheckProject(
              extra: {
                '.specstone/config.yaml': skillPinsConfig(),
                ...doc(
                  techStack,
                  '  - app/lib/\n',
                  '  - app/lib/\n  - skills/\n',
                ),
                ...skillDocFile([skillUnderRoot]),
                skillUnderRoot: skillText,
              },
            ),
          );

          expect(_of(report, FindingKind.codeUncovered), isEmpty);
        });

        test('with two targets', () async {
          final project = await _twin(
            extra: {
              '.specstone/config.yaml':
                  '${skillPinsConfig()}targets:\n  flutter:\n    code_root: .\n'
                  '  jaspr:\n    code_root: jaspr_ws\n',
              'docs/$_flutterTech': _tech(['skills/']),
              ...skillDocFile([skillUnderRoot]),
              skillUnderRoot: skillText,
            },
          );

          final report = await _run(project);

          expect(spots(report, FindingKind.sharedDocCodePath), isEmpty);
          expect(_of(report, FindingKind.codeUncovered), isEmpty);
        });
      },
    );

    test('a file under the code root no entry of either kind reaches stays '
        'code_uncovered', () async {
      const reached = 'skills/review/SKILL.md';
      const other = 'skills/other/SKILL.md';
      final report = await checkOf(
        await writeCheckProject(
          extra: {
            '.specstone/config.yaml': skillPinsConfig(),
            ...doc(techStack, '  - app/lib/\n', '  - app/lib/\n  - skills/\n'),
            ...skillDocFile([reached]),
            reached: skillText,
            other: skillText,
          },
        ),
      );

      expect(_of(report, FindingKind.codeUncovered), ['$techStack: $other']);
    });

    test('a project-root entry never reaches a code root outside the '
        'project', () async {
      const skillUnderRoot = 'skills/review/SKILL.md';
      final project = await _outsideRootProject(
        config: '${skillPinsConfig()}code_root: ../stratum_ui/example\n',
        docs: {
          ...doc(techStack, '  - app/lib/\n', '  - skills/\n'),
          ...skillDocFile([skillUnderRoot]),
          skillUnderRoot: skillText,
        },
        outside: {skillUnderRoot: skillText},
        without: {loginRecord},
      );

      final report = await _run(project);

      expect(_of(report, FindingKind.codeUncovered), [
        '$techStack: $skillUnderRoot',
      ]);
    });

    test('a code root below the project root is reached by the entry written '
        'from the project root only', () async {
      const reached = 'code/skills/x/a.md';
      Future<List<String>> uncovered(String entry) async {
        final report = await checkOf(
          await writeCheckProject(
            extra: {
              '.specstone/config.yaml': '${skillPinsConfig()}code_root: code\n',
              'code/app/lib/login.dart':
                  checkProjectFiles()['app/lib/login.dart']!,
              ...doc(
                techStack,
                '  - app/lib/\n',
                '  - app/lib/\n  - skills/\n',
              ),
              ...skillDocFile([entry]),
              reached: skillText,
            },
            without: {'app/lib/login.dart'},
          ),
        );
        return _of(report, FindingKind.codeUncovered);
      }

      expect(await uncovered('code/skills/x/'), isEmpty);
      expect(await uncovered('skills/x/'), ['$techStack: skills/x/a.md']);
    });

    test('a project-root entry needs whole segments to match', () async {
      const entry = 'skills/rev';
      const longer = 'skills/review/SKILL.md';
      final report = await checkOf(
        await writeCheckProject(
          extra: {
            '.specstone/config.yaml': skillPinsConfig(),
            ...doc(techStack, '  - app/lib/\n', '  - app/lib/\n  - skills/\n'),
            ...skillDocFile([entry]),
            entry: skillText,
            longer: skillText,
          },
        ),
      );

      expect(_of(report, FindingKind.codeUncovered), ['$techStack: $longer']);
    });

    test('an entry naming the project root reaches nothing', () async {
      const other = 'skills/other/SKILL.md';
      final report = await checkOf(
        await writeCheckProject(
          extra: {
            '.specstone/config.yaml': skillPinsConfig(),
            ...doc(techStack, '  - app/lib/\n', '  - app/lib/\n  - skills/\n'),
            ...skillDocFile(['./']),
            other: skillText,
          },
        ),
      );

      expect(_of(report, FindingKind.codeUncovered), ['$techStack: $other']);
    });
  });

  test('a code-root entry naming the code root reaches nothing', () async {
    final report = await checkOf(await writeCheckProject(extra: narrow('./')));

    expect(_of(report, FindingKind.codeUncovered), [
      '$techStack: app/lib/login.dart',
    ]);
  });

  test('an empty covers entry gives covers_entry_empty alone, in each empty '
      'form', () async {
    const forms = ['', '.', './', '/', './.', './/', 'lib/..', './lib/../'];
    for (final form in forms) {
      final project = await writeCheckProject(
        extra: narrow(form.isEmpty ? "'$form'" : form),
      );
      final report = await checkOf(project);

      final line = lineOfFirst(project, loginArchitecture, '- ');
      expect(spots(report, FindingKind.coversEntryEmpty), [
        '$loginArchitecture:$line: covers_entry_empty',
      ], reason: form);
      expect(_of(report, FindingKind.coversPathMissing), isEmpty, reason: form);
      // The empty entry covers no file, so every listed code file stays
      // uncovered beside it.
      expect(_of(report, FindingKind.codeUncovered), [
        '$techStack: app/lib/login.dart',
      ], reason: form);
    }
  });

  test('an empty covers entry with a fingerprint gives covers_entry_empty '
      'alone, key entry the prefix', () async {
    final report = await checkOf(
      await writeCheckProject(extra: narrow('./ 9a1c03be55d2')),
    );

    final finding = report.findings.singleWhere(
      (f) => f.kind == FindingKind.coversEntryEmpty,
    );
    expect(finding.keys['entry'], './');
    expect(finding.waitsFor, WaitsFor.owner);
    expect(finding.textLines.single, endsWith(' (waits for the Owner)'));
    expect(_of(report, FindingKind.coversPathMissing), isEmpty);
    expect(_of(report, FindingKind.codeUncovered), [
      '$techStack: app/lib/login.dart',
    ]);
  });

  test(
    'a project-root empty covers entry gives covers_entry_empty alone',
    () async {
      for (final form in ['.', './', 'lib/..']) {
        final project = await writeCheckProject(
          extra: {
            '.specstone/config.yaml': skillPinsConfig(),
            ...skillDocFile([form]),
          },
        );
        final report = await checkOf(project);

        final line = lineOfFirst(project, skillDoc, '- ');
        expect(spots(report, FindingKind.coversEntryEmpty), [
          '$skillDoc:$line: covers_entry_empty',
        ], reason: form);
        expect(
          _of(report, FindingKind.coversPathMissing),
          isEmpty,
          reason: form,
        );
        expect(_of(report, FindingKind.codeUnconfirmed), isEmpty, reason: form);
      }
    },
  );

  test(
    'an empty covers entry of a waiting target gives covers_entry_empty',
    () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: {
            ...narrow('./'),
            loginRecord: _record(['email_login:planned']),
          },
          unstamped: {loginRecord},
        ),
      );

      expect(_of(report, FindingKind.coversEntryEmpty), [
        '$loginArchitecture: ./',
      ]);
      expect(_of(report, FindingKind.coversPathMissing), isEmpty);
    },
  );

  test('a shared doc whose only covers entry is empty gives '
      'covers_entry_empty alone', () async {
    const topic =
        '---\ncovers:\n  - ./\n---\n\n# Doc model\n\n## Purpose\n\n'
        'One rule set.\n\n## Scope\n\nThe src folder.\n';
    final report = await _run(
      await _twin(extra: {'docs/$_sharedTopic': topic}),
    );

    expect(_of(report, FindingKind.coversEntryEmpty), ['$_sharedTopic: ./']);
    expect(spots(report, FindingKind.sharedDocCodePath), isEmpty);
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
