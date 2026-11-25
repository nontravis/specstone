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
import '../../helpers/rulebook_fixture.dart';
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

/// Returns a record holding the one-line [statuses] and the [covers]
/// entries.
String _record(
  List<String> statuses, {
  List<String> covers = const ['app/lib/'],
}) =>
    '---\n'
    '${statuses.isEmpty ? '' : 'statuses:\n${[for (final s in statuses) "  - '$s'\n"].join()}'}'
    '${covers.isEmpty ? '' : 'covers:\n${[for (final c in covers) '  - $c\n'].join()}'}'
    '---\n\n# Record\n';

/// The charter layer of the shared-doc tests: no per-target key, so its doc
/// belongs to no target.
final String _sharedCharter = charterLayer.replaceFirst(
  'per_target: true',
  'per_target: false',
);

/// Returns a `tech_stack` doc whose code roots are [roots].
String _tech(List<String> roots) => doc(
  techStack,
  '  - app/lib/\n',
  [for (final r in roots) '  - $r\n'].join(),
).values.single;

/// Returns the login story and FR as written by a project that has not
/// implemented either.
Map<String, String> _planned() => {loginRecord: _record(_plannedStatuses)};

/// The statuses of a login story and FR not yet implemented.
const _plannedStatuses = [
  'email_login:planned',
  'email_login/check_password:planned',
];

/// Writes the two-target project with one `tech_stack` doc per target.
Future<Directory> _twin({
  Map<String, String> extra = const {},
  Set<String> without = const {},
}) => writeTwinProject(
  without: {'docs/$techStack', ...without},
  extra: {
    // The shared topic of the shared-doc tests: a layer takes it back from
    // the shipped per-target pack.
    charterLayerFile: _sharedCharter,
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

const _projectArchitecture = 'specs/ARCHITECTURE.md';

/// Returns the check project whose `project_architecture` doc covers
/// [covers] as written, with `tool/build.dart` at the project root.
Future<Directory> _architectureProject(
  List<String> covers, {
  Map<String, String> extra = const {},
  Set<String> without = const {},
}) => writeCheckProject(
  extra: {
    'docs/$_projectArchitecture':
        '---\ncovers:\n${[for (final c in covers) '  - $c\n'].join()}---\n\n'
        '# Login demo architecture\n',
    'tool/build.dart': 'void main() {}\n',
    ...extra,
  },
  without: without,
  unstamped: {'docs/$_projectArchitecture'},
  unfingerprinted: {'docs/$_projectArchitecture'},
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

/// Returns the kind of each finding of [report] at [docPath].
List<FindingKind> _kindsAt(CheckReport report, String docPath) => [
  for (final f in report.findings)
    if (f.path == docPath) f.kind,
];

/// Returns `<path>: <entry or path>` per finding of [kind].
List<String> _of(CheckReport report, FindingKind kind) => [
  for (final f in report.findings)
    if (f.kind == kind) '${f.path}: ${f.keys['entry'] ?? f.keys['codePath']}',
];

void main() {
  /// Sets the fixture record's one `covers` entry.
  Map<String, String> narrow(String covers) =>
      doc(loginRecord, '  - app/lib/\n', '  - $covers\n');

  test('code_root: covers and code resolve under the code folder', () async {
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
    expect(spots(report), isEmpty);
  });

  test('covers and code roots resolve against a code_root outside the project '
      'root', () async {
    final project = await _outsideRootProject(
      docs: {
        loginRecord: _record(
          [_implemented],
          covers: ['app/lib/', 'app/lib/gone/'],
        ),
        ...doc(techStack, '  - app/lib/\n', '  - app/lib/\n  - api/lib/\n'),
      },
      outside: {
        'app/lib/login.dart': checkProjectFiles()['app/lib/login.dart']!,
      },
    );

    final report = await _run(project);

    expect(_of(report, FindingKind.coversPathMissing), [
      '$loginRecord: app/lib/gone/',
    ]);
    expect(_of(report, FindingKind.codeRootMissing), ['$techStack: api/lib/']);
  });

  test(
    'a missing root is code_root_missing; the other root gives no finding',
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
      expect(spots(report), ['$techStack:5: code_root_missing']);
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
      '$loginRecord:12: covers_path_missing',
    ]);
    expect(
      moved.findings
          .firstWhere((f) => f.kind == FindingKind.coversPathMissing)
          .textLine,
      '$loginRecord:12: covers_path_missing: app/lib/login/ names nothing on disk',
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
        '$loginRecord: app/lib/login/',
      ]);
    },
  );

  test('an upper-case token stays part of the covers path', () async {
    final report = await checkOf(
      await writeCheckProject(extra: narrow('app/lib/ 9A1C03BE55D2')),
    );

    expect(_of(report, FindingKind.coversPathMissing), [
      '$loginRecord: app/lib/ 9A1C03BE55D2',
    ]);
  });

  group('the wait for the first implemented entry of a target', () {
    test(
      'a record waits for an entry of its own feature, then reports',
      () async {
        final waiting = await checkOf(
          await writeCheckProject(
            extra: {
              loginRecord: _record(
                _plannedStatuses,
                covers: ['app/lib/login/'],
              ),
            },
          ),
        );
        expect(spots(waiting, FindingKind.coversPathMissing), isEmpty);
        final done = await checkOf(
          await writeCheckProject(
            extra: {
              loginRecord: _record(
                [
                  'email_login:implemented',
                  'email_login/check_password:planned',
                ],
                covers: ['app/lib/login/'],
              ),
            },
          ),
        );
        expect(_of(done, FindingKind.coversPathMissing), [
          '$loginRecord: app/lib/login/',
        ]);
      },
    );

    test(
      'an entry of another feature does not end the wait of a record',
      () async {
        final report = await checkOf(
          await writeCheckProject(
            extra: {
              loginRecord: _record(
                _plannedStatuses,
                covers: ['app/lib/login/'],
              ),
              'docs/prds/features/f02_shop/FEATURE.md':
                  checkProjectFiles()['docs/$loginFeature']!,
              'docs/prds/features/f02_shop/us01_email_login/USER_STORY.md':
                  checkProjectFiles()['docs/$loginStory']!,
              '.specstone/records/f02_shop/IMPLEMENTATION.md': _record(
                ['email_login:implemented'],
                covers: ['app/lib/shop/'],
              ),
            },
          ),
        );
        expect(_of(report, FindingKind.coversPathMissing), [
          '.specstone/records/f02_shop/IMPLEMENTATION.md: app/lib/shop/',
        ]);
      },
    );

    test('an entry of a nested feature ends the wait of the record above', () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: {
            loginRecord: _record(_plannedStatuses, covers: ['app/lib/login/']),
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
        '$loginRecord: app/lib/login/',
      ]);
    });

    test('an entry of a sibling sub-feature does not end the wait of a nested record', () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: {
            'docs/prds/features/f01_login/f01_remember/FEATURE.md':
                checkProjectFiles()['docs/$loginFeature']!,
            'docs/prds/features/f01_login/f01_remember/us01_remember_me/USER_STORY.md':
                checkProjectFiles()['docs/$loginStory']!,
            '.specstone/records/f01_login/f01_remember/IMPLEMENTATION.md':
                _record(['remember_me:planned'], covers: ['app/lib/remember/']),
            'docs/prds/features/f01_login/f02_other/FEATURE.md':
                checkProjectFiles()['docs/$loginFeature']!,
            'docs/prds/features/f01_login/f02_other/us01_email_login/USER_STORY.md':
                checkProjectFiles()['docs/$loginStory']!,
            '.specstone/records/f01_login/f02_other/IMPLEMENTATION.md': _record(
              ['email_login:implemented'],
            ),
          },
        ),
      );
      expect(_of(report, FindingKind.coversPathMissing), isEmpty);
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
        '$loginRecord: app/lib/',
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
          _flutterRecord: _record([_implemented], covers: ['app/lib/extra/']),
          _jasprRecord: _record([_implemented], covers: ['app/lib/extra/']),
          'flutter_ws/app/lib/extra/x.dart': '',
          'docs/$_flutterTech': _tech(['app/lib/', 'app/extra/']),
          'docs/$_jasprTech': _tech(['app/lib/', 'app/extra/']),
          'jaspr_ws/app/extra/y.dart': '',
        },
      );
      final report = await _run(project);
      expect(_of(report, FindingKind.coversPathMissing), [
        '$_jasprRecord: app/lib/extra/',
      ]);
      expect(_of(report, FindingKind.codeRootMissing), [
        '$_flutterTech: app/extra/',
      ]);
    });

    test('a target with an implemented entry resolves its paths and a target with none raises nothing', () async {
      final project = await _twin(
        extra: {
          _flutterRecord: _record([_implemented], covers: ['app/lib/gone/']),
          _jasprRecord: _record(
            ['email_login/check_password:planned'],
            covers: ['app/lib/gone/'],
          ),
          'docs/$_flutterTech': _tech(['app/lib/', 'api/']),
          'docs/$_jasprTech': _tech(['app/lib/', 'api/']),
        },
      );
      final report = await _run(project);
      expect(_of(report, FindingKind.coversPathMissing), [
        '$_flutterRecord: app/lib/gone/',
      ]);
      expect(_of(report, FindingKind.codeRootMissing), ['$_flutterTech: api/']);
    });

    test('a target with no code yet raises no missing root', () async {
      final project = await _twin(
        extra: {
          _flutterRecord: _record([_implemented], covers: ['app/lib/']),
          'docs/$_jasprTech': _tech(['web/']),
          _jasprRecord: _record(const [], covers: ['web/']),
        },
        without: {'jaspr_ws/app/lib/login.dart'},
      );
      final report = await _run(project);
      expect(_of(report, FindingKind.codeRootMissing), isEmpty);
      expect(_of(report, FindingKind.coversPathMissing), isEmpty);
    });

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

    test('the paths of a shared doc resolve against no code root', () async {
      const topic =
          '---\ncovers:\n  - app/lib/\n  - app/lib/gone/\n---\n\n# Doc model\n\n'
          '## Purpose\n\nOne rule set.\n\n## Scope\n\nThe lib folder.\n';
      final project = await _twin(
        extra: {
          _flutterRecord: _record(
            [_implemented],
            covers: ['app/lib/login.dart'],
          ),
          _jasprRecord: _record([_implemented], covers: ['app/lib/login.dart']),
          'docs/$_sharedTopic': topic,
        },
      );

      final report = await _run(project);

      expect(_of(report, FindingKind.coversPathMissing), isEmpty);
    });

    test('a shared doc with covers beside one named target is no '
        'shared_doc_code_path', () async {
      final project = await writeTwinProject(
        without: {
          'docs/$_jasprTech',
          'docs/$jasprArchitecture',
          jasprRecord,
          'jaspr_ws/app/lib/login.dart',
        },
        extra: {
          '.specstone/config.yaml':
              '${shippedPinsConfig()}targets:\n  flutter:\n'
              '    code_root: flutter_ws\n',
          charterLayerFile: _sharedCharter,
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
          charterLayerFile: _sharedCharter,
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

    test('a shared doc whose code root is empty is still one '
        'shared_doc_code_path', () async {
      final project = await writeTwinProject(
        without: {'docs/$_flutterTech', 'docs/$_jasprTech'},
        extra: {
          '.specstone/templates/tech_stack.yaml':
              'id: tech_stack\nper_target: false\n',
        },
      );
      File('${project.path}/docs/$techStack').writeAsStringSync(
        withApprovalHashes({
          ...checkProjectFiles(),
          ...doc(techStack, '  - app/lib/\n', '  - ./\n'),
        })['docs/$techStack']!,
      );

      final report = await _run(project);

      expect(_kindsAt(report, techStack), [FindingKind.sharedDocCodePath]);
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

  group('a project architecture covers entry', () {
    const reached = 'tool/build.dart';
    const gone = 'tool/gone.dart';

    test('naming nothing from the project root is covers_path_missing at its '
        'line, as an implementation entry is, and no field_undeclared', () async {
      final project = await _architectureProject([reached, gone]);
      final report = await checkOf(project);
      final line = lineOfFirst(project, _projectArchitecture, gone);

      expect(spots(report, FindingKind.coversPathMissing), [
        '$_projectArchitecture:$line: covers_path_missing',
      ]);
      expect(_of(report, FindingKind.coversPathMissing), [
        '$_projectArchitecture: $gone',
      ]);
      expect(
        report.findings
            .firstWhere((f) => f.kind == FindingKind.coversPathMissing)
            .textLine,
        '$_projectArchitecture:$line: covers_path_missing: $gone names nothing on disk',
      );
      expect(spots(report, FindingKind.fieldUndeclared), isEmpty);
    });

    test(
      'resolves from the project root when the config sets a code_root',
      () async {
        final report = await checkOf(
          await _architectureProject(
            [reached, 'code/$reached'],
            extra: {
              '.specstone/config.yaml':
                  '${shippedPinsConfig()}code_root: code\n',
              'code/app/lib/login.dart':
                  checkProjectFiles()['app/lib/login.dart']!,
            },
            without: {'app/lib/login.dart'},
          ),
        );

        expect(_of(report, FindingKind.coversPathMissing), [
          '$_projectArchitecture: code/$reached',
        ]);
      },
    );

    test('a folder entry naming no folder is covers_path_missing', () async {
      final report = await checkOf(
        await _architectureProject(['tool/', 'tool/gone/']),
      );

      expect(_of(report, FindingKind.coversPathMissing), [
        '$_projectArchitecture: tool/gone/',
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

    test(
      'a skill file under a code root gives no shared_doc_code_path with two '
      'targets',
      () async {
        const skillUnderRoot = 'skills/review/SKILL.md';
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
      },
    );
  });

  test('an empty covers entry gives covers_entry_empty alone, in each empty '
      'form', () async {
    const forms = ['', '.', './', '/', './.', './/', 'lib/..', './lib/../'];
    for (final form in forms) {
      final project = await writeCheckProject(
        extra: narrow(form.isEmpty ? "'$form'" : form),
      );
      final report = await checkOf(project);

      final line =
          File('${project.path}/$loginRecord')
              .readAsLinesSync()
              .indexOf('covers:') +
          2;
      expect(spots(report, FindingKind.coversEntryEmpty), [
        '$loginRecord:$line: covers_entry_empty',
      ], reason: form);
      expect(
        report.findings
            .where((f) => f.kind == FindingKind.coversEntryEmpty)
            .single
            .message,
        startsWith('"$form" names no path of its own'),
        reason: form,
      );
      expect(_kindsAt(report, loginRecord), [
        FindingKind.coversEntryEmpty,
      ], reason: form);
      expect(_of(report, FindingKind.coversPathMissing), isEmpty, reason: form);
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
        expect(_kindsAt(report, skillDoc), [
          FindingKind.coversEntryEmpty,
        ], reason: form);
      }
    },
  );

  test(
    'an empty covers entry of a waiting target gives covers_entry_empty',
    () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: {
            loginRecord: _record(['email_login:planned'], covers: ['./']),
          },
          unstamped: {loginRecord},
        ),
      );

      expect(_of(report, FindingKind.coversEntryEmpty), ['$loginRecord: ./']);
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

  test('an empty code root is still a code root: code_root_missing once the '
      'code root folder is gone', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: {
          '.specstone/config.yaml':
              '${shippedPinsConfig()}code_root: nowhere\n',
          ...doc(techStack, '  - app/lib/\n', '  - ./\n'),
        },
      ),
    );

    expect(_of(report, FindingKind.codeRootMissing), ['$techStack: ./']);
    expect(_of(report, FindingKind.coversEntryEmpty), isEmpty);
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
