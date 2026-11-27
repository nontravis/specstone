import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/code_fingerprint.dart';
import 'package:specstone_core/src/document_writing/approve_auto.dart';
import 'package:specstone_core/src/document_writing/approve_drafts.dart';
import 'package:specstone_core/src/document_writing/batch_file.dart'
    show parseBatchFile;
import 'package:specstone_core/src/document_writing/delete_doc.dart';
import 'package:specstone_core/src/document_writing/generated_block_steps.dart';
import 'package:specstone_core/src/document_writing/models/path_move.dart';
import 'package:specstone_core/src/document_writing/models/seen_draft.dart';
import 'package:specstone_core/src/document_writing/move_doc.dart';
import 'package:specstone_core/src/document_writing/move_plan.dart';
import 'package:specstone_core/src/document_writing/move_plan_engine.dart';
import 'package:specstone_core/src/document_writing/new_doc.dart';
import 'package:specstone_core/src/document_writing/owner_confirmation.dart';
import 'package:specstone_core/src/document_writing/set_batch.dart';
import 'package:specstone_core/src/document_writing/set_doc.dart';
import 'package:specstone_core/src/document_writing/set_dry_run.dart';
import 'package:specstone_core/src/document_writing/set_sync.dart';
import 'package:specstone_core/src/document_writing/sync_lines.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/get_docs.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/format_run.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart'
    show GeneratorRegistry;
import 'package:specstone_core/src/rendering/models/opened_resolver.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/shipped_generators.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/grouped_fixture.dart';
import '../../helpers/index_fixture.dart' show openSession;
import '../../helpers/no_generators.dart';
import '../../helpers/posix_modes.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/temp_tree.dart';
import '../../helpers/write_fixture.dart'
    show getDoc, testHome, treeBytes, writeIn;

const _mapPath = 'prds/FEATURES.md';
const _groupPath = 'prds/features/kitchen/FEATURES.md';
const _login = 'feature:login';
const _story = 'user_story:login/email_login';
const _codePath = 'app/lib/login.dart';

final GeneratorRegistry<DocIndex> _generators = shippedGenerators();

/// Runs `format` over the docs root and returns the DocPath of each doc it
/// lists as changing, or writes them when [check] is false.
List<String> _format(Directory root, {required bool check}) {
  final project = DocsProject.open(
    templates: TemplateResolver(),
    workingDirectory: root,
    homeDirectory: testHome(),
  );
  final report = runFormat<DocIndex>(
    project,
    project.resolveTarget(
      null,
      workingDirectory: root,
      defaultsToDocsRoot: true,
      includeRecordsRoot: true,
    ),
    check: check,
    homeDirectory: testHome(),
    generators: GeneratorRun<DocIndex>(
      registry: _generators,
      open: () {
        final session = ReadSession.open(
          templates: TemplateResolver(),
          workingDirectory: root,
          homeDirectory: testHome(),
        );
        return OpenedResolver(
          resolver: session.index,
          close: session.close,
          lockWrites: (write) => session.writeIndex((_) => write()),
        );
      },
    ),
  );
  return [
    for (final file in report.files)
      if (file.status == FileStatus.formatted ||
          file.status == FileStatus.deleted)
        file.path.replaceFirst('docs/', ''),
  ];
}

/// Writes [files], formats them once, and returns the root, every doc current.
Future<Directory> _settled(Map<String, String> files) async {
  final root = await writeTree(files);
  _format(root, check: false);
  expect(_format(root, check: true), isEmpty, reason: 'the fixture settles');
  return root;
}

/// The check fixture, settled; a key in [extra] replaces or adds a file.
Future<Directory> _project({
  Map<String, String> extra = const {},
  Set<String> loose = const {},
}) async {
  final root = await writeCheckProject(
    extra: extra,
    unstamped: loose,
    unfingerprinted: loose,
  );
  _format(root, check: false);
  expect(_format(root, check: true), isEmpty, reason: 'the fixture settles');
  return root;
}

List<String> _rewritten(ReadAnswer answer) => [
  for (final path in answer.json['rewritten']! as List) path as String,
];

/// Asserts that `format --check` lists no doc after the write, and that
/// [answer] names each doc of [refreshed] as rewritten, in text and JSON.
void _expectRefreshed(
  Directory root,
  ReadAnswer answer,
  List<String> refreshed,
) {
  expect(_format(root, check: true), isEmpty);
  expect(_rewritten(answer), containsAll(refreshed));
  for (final docPath in refreshed) {
    expect(answer.text, contains('rewrote $docPath\n'));
  }
}

/// The docs and records of [root] as bytes, the index left out.
Map<String, List<int>> _docBytes(Directory root) => {
  for (final MapEntry(:key, :value) in treeBytes(root).entries)
    if (key.startsWith('docs/') || key.startsWith('.specstone/records/'))
      key: value,
};

String _fieldBase(Directory root, String address, String field) {
  final bases = getDoc(root, address)['bases']! as Map;
  return (bases['fields']! as Map)[field]! as String;
}

String _getText(Directory root, String address) {
  final session = openSession(root);
  try {
    return answerGet(session.index, [address]).text;
  } finally {
    session.close();
  }
}

String _newFeature(Directory root, String slug) => writeIn(
  root,
  (s) =>
      answerNew(s, docTypeId: 'feature', slug: slug, generators: _generators),
).text;

/// Creates a story under login with no generators, so the feature map lags,
/// and returns its address.
String _laggingDraft(Directory root) {
  writeIn(
    root,
    (s) => answerNew(
      s,
      docTypeId: 'user_story',
      parent: _login,
      slug: 'reset_password',
      generators: noGenerators,
    ),
  );
  expect(_format(root, check: true), [_mapPath]);
  return 'user_story:login/reset_password';
}

void main() {
  group('a write rewrites the generated blocks it makes stale', () {
    // D17: each command refreshes the feature map its own change reaches.
    test('new feature adds its row to the feature map', () async {
      final root = await _project();

      final answer = writeIn(
        root,
        (s) => answerNew(
          s,
          docTypeId: 'feature',
          slug: 'billing',
          generators: _generators,
        ),
      );

      _expectRefreshed(root, answer, [_mapPath]);
    });

    test('new user_story updates the counts of its feature row', () async {
      // D17: a story and its planned record line reach the row's counts.
      final root = await _project();

      final answer = writeIn(
        root,
        (s) => answerNew(
          s,
          docTypeId: 'user_story',
          parent: _login,
          slug: 'reset_password',
          generators: _generators,
        ),
      );

      _expectRefreshed(root, answer, [_mapPath]);
    });

    test('set of a feature summary rewrites its row', () async {
      // D17: a field the row shows.
      final root = await _project();

      final answer = writeIn(
        root,
        (s) => answerSet(
          s,
          SetRequest.parse(
            _login,
            field: 'summary',
            base: _fieldBase(root, _login, 'summary'),
          ),
          'Lets a person sign in.\n',
          generators: _generators,
        ),
      );

      _expectRefreshed(root, answer, [_mapPath]);
    });

    test('set --batch of a feature summary rewrites its row', () async {
      // D17: the batch write joins the refresh.
      final root = await _project();
      final batch = _getText(
        root,
        _login,
      ).replaceFirst('Lets an agent sign in.', 'Lets a person sign in.');

      final answer = writeIn(
        root,
        (s) => answerSetBatch(
          s,
          parseBatchFile('batch.md', batch),
          generators: _generators,
        ),
      );

      _expectRefreshed(root, answer, [_mapPath]);
    });

    test('set --sync of a record status rewrites the row counts', () async {
      // D17: a record status the row counts.
      final root = await _project(
        extra: {
          loginRecord:
              "---\nstatuses:\n  - 'email_login:planned'\n"
              "  - 'email_login/check_password:implemented'\nimplements:\n"
              "  - 'email_login:$_codePath:SignInPage'\n"
              "  - 'email_login/check_password:$_codePath:checkPassword'\n"
              "tests:\n  - 'email_login/check_password:$_codePath'\n"
              'covers:\n  - app/lib/\n'
              '---\n\n# Login implementation\n',
        },
        loose: {loginRecord},
      );
      final fingerprint = fileCodeFingerprint(
        utf8.encode(checkProjectFiles()[_codePath]!),
        path: _codePath,
      );

      final answer = writeIn(
        root,
        (s) => answerSetSync(
          s,
          parseSyncFile(
            'sync.txt',
            'match implementation:login '
                'email_login:$_codePath:SignInPage $fingerprint\n',
          ),
          generators: _generators,
        ),
      );

      _expectRefreshed(root, answer, [_mapPath]);
    });

    test('a feature move by argv drops its row from the top', () async {
      // D17: the moved feature leaves the top rows.
      final root = await _project();
      _newFeature(root, 'billing');

      final answer = writeIn(
        root,
        (s) => answerMove(
          s,
          [_login],
          under: 'feature:billing',
          generators: _generators,
        ),
      );

      _expectRefreshed(root, answer, [_mapPath]);
    });

    test('a story move by plan moves its count to the new feature', () async {
      // D17: the plan engine joins the refresh.
      final root = await _project();
      _newFeature(root, 'billing');

      final answer = writeIn(
        root,
        (s) => answerPlanMove(
          s,
          parseMovePlan('$_story -> feature:billing\n', path: 'plan.txt'),
          dryRun: false,
          generators: _generators,
        ),
      );

      _expectRefreshed(root, answer, [_mapPath]);
    });

    test('rename of a feature rewrites its row whole', () async {
      // D17: the row counts a link rewrite leaves stale.
      final root = await _project();
      _laggingDraft(root);

      final answer = writeIn(
        root,
        (s) =>
            answerRename(s, _login, slug: 'sign_in', generators: _generators),
      );

      _expectRefreshed(root, answer, [_mapPath]);
    });

    test('approve of one draft rewrites a block a write left stale', () async {
      // D17: a block stale before the write is rewritten too.
      final root = await _project();
      final draft = _laggingDraft(root);
      final hash = getDoc(root, draft)['base']! as String;

      final answer = writeIn(
        root,
        (s) => approveNamed(s, [
          SeenDraft(name: draft, hash: hash),
        ], generators: _generators),
      );

      _expectRefreshed(root, answer, [_mapPath]);
    });

    test('a new feature in a group rewrites the grouped features doc and '
        'its group features doc', () async {
      // D17: write_generated_blocks E07, the group doc in the same write.
      final root = await _settled({
        ...featureGroupedFiles(),
        'docs/$_mapPath': '# Feature map\n\n## Features\n',
      });

      final answer = writeIn(
        root,
        (s) => answerNew(
          s,
          docTypeId: 'feature',
          slug: 'kitchen/desserts',
          generators: _generators,
        ),
      );

      _expectRefreshed(root, answer, [_mapPath, _groupPath]);
    });
  });

  group('a dry run lists the docs the refresh would rewrite', () {
    // D17: `--dry-run` lists the same docs and writes none.
    Future<void> expectDryRun(
      Directory root,
      Future<ReadAnswer> Function() run,
    ) async {
      final before = _docBytes(root);
      final answer = await run();
      expect(answer.text, contains('rewrites $_mapPath\n'));
      expect(_docBytes(root), before);
    }

    test('set --dry-run lists the feature map a lagging write left', () async {
      final root = await _project();
      _laggingDraft(root);
      final base = getDoc(root, '$_login#problem')['base']! as String;
      final session = openSession(root);
      addTearDown(session.close);

      await expectDryRun(
        root,
        () => answerSetDryRun(
          session,
          DryRunRequest.parse(
            '$_login#problem',
            base: base,
            index: session.index,
          ),
          'Users forget their passwords.\n',
          homeDirectory: testHome(),
          generators: _generators,
        ),
      );
    });

    test('move --dry-run of a story lists the feature map', () async {
      final root = await _project();
      _newFeature(root, 'billing');

      await expectDryRun(
        root,
        () async => writeIn(
          root,
          (s) => answerMove(
            s,
            [_story],
            under: 'feature:billing',
            dryRun: true,
            generators: _generators,
          ),
        ),
      );
    });

    test('rename --dry-run of a story lists the feature map a lagging write '
        'left', () async {
      final root = await _project();
      _laggingDraft(root);

      await expectDryRun(
        root,
        () async => writeIn(
          root,
          (s) => answerRename(
            s,
            _story,
            slug: 'sign_in',
            dryRun: true,
            generators: _generators,
          ),
        ),
      );
    });

    test('approve --dry-run lists the feature map', () async {
      final root = await _project();
      _laggingDraft(root);

      await expectDryRun(
        root,
        () async =>
            writeIn(root, (s) => approveDryRun(s, generators: _generators)),
      );
    });

    test('delete --dry-run of a story lists the feature map', () async {
      final root = await _project();
      writeIn(
        root,
        (s) => answerNew(
          s,
          docTypeId: 'user_story',
          parent: _login,
          slug: 'reset_password',
          generators: _generators,
        ),
      );

      await expectDryRun(
        root,
        () async => writeIn(
          root,
          (s) => answerDeleteDryRun(s, [
            'user_story:login/reset_password',
          ], generators: _generators),
        ),
      );
    });

    test('reorder --dry-run of a feature lists the feature map', () async {
      final root = await _project();
      _newFeature(root, 'billing');

      await expectDryRun(
        root,
        () async => writeIn(
          root,
          (s) => answerReorder(
            s,
            'feature:billing',
            place: '1',
            dryRun: true,
            generators: _generators,
          ),
        ),
      );
    });
  });

  test(
    'a read-only feature map refuses the set and the target keeps its bytes',
    () async {
      // D17: the refresh joins the one all-or-nothing write.
      final root = await _project();
      final map = File('${root.path}/docs/$_mapPath');
      Process.runSync('chmod', ['444', map.path]);
      addTearDown(() => Process.runSync('chmod', ['644', map.path]));
      final before = _docBytes(root);

      expect(
        () => writeIn(
          root,
          (s) => answerSet(
            s,
            SetRequest.parse(
              _login,
              field: 'summary',
              base: _fieldBase(root, _login, 'summary'),
            ),
            'Lets a person sign in.\n',
            generators: _generators,
          ),
        ),
        throwsA(
          isA<RenderFault>().having(
            (fault) => fault.code,
            'code',
            RenderFaultCode.outputNotWritable,
          ),
        ),
      );
      expect(_docBytes(root), before);
    },
    skip: unreadablePathSkipReason() ?? false,
  );

  test('a read-only feature map refuses the new feature and leaves no file or '
      'folder of it', () async {
    // Anti-goal: the refresh refuses after `new` claimed its file and folders.
    final root = await _project();
    final map = File('${root.path}/docs/$_mapPath');
    Process.runSync('chmod', ['444', map.path]);
    addTearDown(() => Process.runSync('chmod', ['644', map.path]));
    final before = _docBytes(root);
    final folders = Directory('${root.path}/docs/prds/features')
        .listSync()
        .map((entry) => entry.path)
        .toSet();

    expect(
      () => _newFeature(root, 'billing'),
      throwsA(
        isA<RenderFault>().having(
          (fault) => fault.code,
          'code',
          RenderFaultCode.outputNotWritable,
        ),
      ),
    );
    expect(_docBytes(root), before);
    expect(
      Directory('${root.path}/docs/prds/features')
          .listSync()
          .map((entry) => entry.path)
          .toSet(),
      folders,
    );
  }, skip: unreadablePathSkipReason() ?? false);

  group('a CRLF doc with a byte order mark keeps both through the refresh', () {
    // D17: the refresh rewrites the block in the form the file has.
    const bom = [0xef, 0xbb, 0xbf];

    /// Rewrites the file at [docPath] in CRLF with a byte order mark.
    File crlfWithBom(Directory root, String docPath) {
      final file = File('${root.path}/docs/$docPath');
      file.writeAsBytesSync([
        ...bom,
        ...utf8.encode(file.readAsStringSync().replaceAll('\n', '\r\n')),
      ]);
      return file;
    }

    void expectCrlfWithBom(File file) {
      final bytes = file.readAsBytesSync();
      expect(bytes.take(3), bom);
      final text = utf8.decode(bytes.skip(3).toList());
      expect(text.replaceAll('\r\n', ''), isNot(contains('\n')));
    }

    test('a feature map rewritten beside a new feature', () async {
      final root = await _project();
      final map = crlfWithBom(root, _mapPath);

      final answer = writeIn(
        root,
        (s) => answerNew(
          s,
          docTypeId: 'feature',
          slug: 'billing',
          generators: _generators,
        ),
      );

      _expectRefreshed(root, answer, [_mapPath]);
      expect(map.readAsStringSync(), contains('billing'));
      expectCrlfWithBom(map);
      expect(answer.warnings, isEmpty);
    });

    test('a draft approved beside a stale feature map', () async {
      final root = await _project();
      final draft = _laggingDraft(root);
      final story = crlfWithBom(
        root,
        'prds/features/f01_login/us02_reset_password/USER_STORY.md',
      );
      final map = crlfWithBom(root, _mapPath);
      final hash = getDoc(root, draft)['base']! as String;

      final answer = writeIn(
        root,
        (s) => approveNamed(s, [
          SeenDraft(name: draft, hash: hash),
        ], generators: _generators),
      );

      _expectRefreshed(root, answer, [_mapPath]);
      expect(answer.json['approved'], [draft]);
      expectCrlfWithBom(story);
      expectCrlfWithBom(map);
      expect(answer.warnings, isEmpty);
    });
  });

  test('a read-only moved doc whose block only the refresh changes refuses the '
      'move before it starts', () async {
    // D17: the journal would skip the read-only file and leave its block
    // stale, so the write refuses whole.
    final root = await _project();
    final feature = File('${root.path}/docs/$loginFeature');
    Process.runSync('chmod', ['444', feature.path]);
    addTearDown(() => Process.runSync('chmod', ['644', feature.path]));
    const moves = [
      PathMove(
        from: 'prds/features/f01_login/',
        to: 'prds/features/f09_login/',
      ),
    ];
    const refresh = BlockRefresh(
      steps: [],
      ownTexts: {'prds/features/f09_login/FEATURE.md': '# Login page\n'},
      docPaths: [],
      deletedPaths: [],
      refused: [],
    );

    expect(
      () => writeIn(root, (s) => withOwnTexts(s, refresh, moves)),
      throwsA(
        isA<RenderFault>().having(
          (fault) => fault.code,
          'code',
          RenderFaultCode.outputNotWritable,
        ),
      ),
    );
  }, skip: unreadablePathSkipReason() ?? false);

  test('a feature map format refuses keeps its bytes and names itself among '
      'the warnings', () async {
    // D17: a doc format refuses keeps its bytes, as migrate leaves it.
    final root = await _project();
    final map = File('${root.path}/docs/$_mapPath');
    map.writeAsStringSync('${map.readAsStringSync()}\n## Unknown\n\nText.\n');
    final before = map.readAsBytesSync();

    final answer = writeIn(
      root,
      (s) => answerNew(
        s,
        docTypeId: 'feature',
        slug: 'billing',
        generators: _generators,
      ),
    );

    expect(map.readAsBytesSync(), before);
    expect(_rewritten(answer), isNot(contains(_mapPath)));
    expect(
      answer.warnings,
      contains(startsWith('docs/$_mapPath cannot be written by format: ')),
    );
  });

  test('a group features doc no group lists that is not UTF-8 keeps its bytes '
      'and names itself among the warnings', () async {
    // D17: a doc `format` skips unread warns in the write's reply as `format`
    // warns of it.
    const gardenPath = 'prds/features/garden/FEATURES.md';
    final root = await _settled({
      ...featureGroupedFiles(),
      'docs/$_mapPath': '# Feature map\n\n## Features\n',
    });
    final garden = File('${root.path}/docs/$gardenPath')
      ..createSync(recursive: true);
    final bytes = [...utf8.encode('# Garden features\n'), 0xff];
    garden.writeAsBytesSync(bytes);

    final answer = writeIn(
      root,
      (s) => answerNew(
        s,
        docTypeId: 'feature',
        slug: 'kitchen/desserts',
        generators: _generators,
      ),
    );

    expect(garden.readAsBytesSync(), bytes);
    expect(_rewritten(answer), isNot(contains(gardenPath)));
    expect(answer.warnings, contains(contains(gardenPath)));
  });

  group('the other write commands rewrite the blocks they make stale', () {
    test('delete of a story takes its count off its feature row', () async {
      // D17: delete names the feature map it rewrites.
      final root = await _project();
      writeIn(
        root,
        (s) => answerNew(
          s,
          docTypeId: 'user_story',
          parent: _login,
          slug: 'reset_password',
          generators: _generators,
        ),
      );

      final answer = writeIn(
        root,
        (s) => answerDelete(
          s,
          ['user_story:login/reset_password'],
          confirmation: OwnerConfirmation.prompt,
          readLine: () => null,
          prompts: StringBuffer(),
          generators: _generators,
        ),
      );

      _expectRefreshed(root, answer, [_mapPath]);
    });

    test('reorder of a feature moves its row', () async {
      // D17: reorder rewrites the row order a link rewrite leaves.
      final root = await _project();
      _newFeature(root, 'billing');

      final answer = writeIn(
        root,
        (s) => answerReorder(
          s,
          'feature:billing',
          place: '1',
          generators: _generators,
        ),
      );

      _expectRefreshed(root, answer, [_mapPath]);
    });
  });

  group('a features doc the refresh deletes is named as a delete', () {
    // D17: the refresh deletes what `format` deletes, an emptied group's
    // features doc, and names it `deletes`/`deleted`, never `rewrote`.
    const gardenPath = 'prds/features/garden/FEATURES.md';
    Future<Directory> gardenProject() async {
      final root = await _settled({
        ...featureGroupedFiles(),
        'docs/prds/features/garden/f01_beds/FEATURE.md': '# Beds\n',
        'docs/$_mapPath': '# Feature map\n\n## Features\n',
      });
      expect(File('${root.path}/docs/$gardenPath').existsSync(), isTrue);
      return root;
    }

    void expectDeleted(ReadAnswer answer, {required bool dryRun}) {
      expect(answer.json['deleted'], [gardenPath]);
      expect(_rewritten(answer), isNot(contains(gardenPath)));
      expect(
        answer.text,
        contains('${dryRun ? 'deletes' : 'deleted'} $gardenPath\n'),
      );
      expect(answer.text, isNot(contains('rewrote $gardenPath')));
    }

    ReadAnswer moveBeds(Directory root, {bool dryRun = false}) => writeIn(
      root,
      (s) => answerMove(
        s,
        ['feature:garden/beds'],
        under: 'feature:kitchen/menus',
        dryRun: dryRun,
        generators: _generators,
      ),
    );

    test('a move that leaves a group empty', () async {
      final root = await gardenProject();

      final answer = moveBeds(root);

      expectDeleted(answer, dryRun: false);
      expect(_rewritten(answer), contains(_mapPath));
      expect(_format(root, check: true), isEmpty);
      expect(File('${root.path}/docs/$gardenPath').existsSync(), isFalse);
    });

    test('its dry run', () async {
      final root = await gardenProject();
      final before = _docBytes(root);

      expectDeleted(moveBeds(root, dryRun: true), dryRun: true);
      expect(_docBytes(root), before);
    });

    // `delete` refuses a feature a catalog row links to, so the delete cases
    // take a group features doc that lags: it lists the beds no more.
    Future<Directory> unlistedBeds() async {
      final root = await gardenProject();
      final file = File('${root.path}/docs/$gardenPath');
      final lines = file.readAsLinesSync();
      final kept = [
        for (final line in lines)
          if (!line.contains('f01_beds')) line,
      ];
      expect(kept.length, lessThan(lines.length));
      file.writeAsStringSync('${kept.join('\n')}\n');
      return root;
    }

    String deleteDryRunPlan(Directory root) {
      final dry = writeIn(
        root,
        (s) => answerDeleteDryRun(s, [
          'feature:garden/beds',
        ], generators: _generators),
      );
      expectDeleted(dry, dryRun: true);
      return dry.json['plan']! as String;
    }

    ReadAnswer deleteBeds(
      Directory root, {
      required OwnerConfirmation confirmation,
      String? planHash,
      String? answer,
      StringSink? prompts,
    }) => writeIn(
      root,
      (s) => answerDelete(
        s,
        ['feature:garden/beds'],
        confirmation: confirmation,
        readLine: () => answer,
        prompts: prompts ?? StringBuffer(),
        planHash: planHash,
        generators: _generators,
      ),
    );

    test('a delete names it in its dry run and its reply', () async {
      final root = await unlistedBeds();
      final plan = deleteDryRunPlan(root);

      final answer = deleteBeds(
        root,
        confirmation: OwnerConfirmation.given,
        planHash: plan,
      );

      expectDeleted(answer, dryRun: false);
      expect(File('${root.path}/docs/$gardenPath').existsSync(), isFalse);
    });

    test('a delete counts it among the files its plan hash covers', () async {
      final root = await unlistedBeds();
      final plan = deleteDryRunPlan(root);
      final garden = File('${root.path}/docs/$gardenPath');
      garden.writeAsStringSync('${garden.readAsStringSync()}\nOwner note.\n');

      expect(
        () => deleteBeds(
          root,
          confirmation: OwnerConfirmation.given,
          planHash: plan,
        ),
        throwsA(
          isA<WriteFault>().having(
            (fault) => fault.code,
            'code',
            WriteFaultCode.planMismatch,
          ),
        ),
      );
      expect(garden.existsSync(), isTrue);
    });

    // The refresh plans against the tree the write leaves: the moved features
    // doc is the group's doc at its new path, never one to delete.
    group('a rename of a group moves its features doc and deletes none', () {
      ReadAnswer renameGarden(Directory root, {bool dryRun = false}) => writeIn(
        root,
        (s) => answerRename(
          s,
          'group_features:garden',
          slug: 'yard',
          dryRun: dryRun,
          generators: _generators,
        ),
      );

      void expectNoDelete(ReadAnswer answer) {
        expect(answer.json['deleted'], isEmpty);
        expect(answer.text, isNot(contains(gardenPath)));
      }

      test('its write', () async {
        final root = await gardenProject();

        final answer = renameGarden(root);

        expectNoDelete(answer);
        expect(
          File('${root.path}/docs/prds/features/yard/FEATURES.md').existsSync(),
          isTrue,
        );
        expect(_format(root, check: true), isEmpty);
      });

      test('its dry run', () async {
        final root = await gardenProject();

        expectNoDelete(renameGarden(root, dryRun: true));
      });
    });

    test('a delete lists it at the Owner prompt', () async {
      final root = await unlistedBeds();
      final prompts = StringBuffer();

      deleteBeds(
        root,
        confirmation: OwnerConfirmation.prompt,
        answer: 'n',
        prompts: prompts,
      );

      expect(prompts.toString(), contains('deletes $gardenPath\n'));
      expect(prompts.toString(), endsWith('delete 2 files? [y/N] '));
      expect(File('${root.path}/docs/$gardenPath').existsSync(), isTrue);
    });
  });

  group('approve rewrites a block stale before it', () {
    // D17: a block a hand edit left stale is rewritten by the next write.
    Future<Directory> staleDraft() async {
      final root = await _project(
        extra: edit(loginStory, [('goals:\n', 'draft: true\ngoals:\n')]),
      );
      final map = File('${root.path}/docs/$_mapPath');
      map.writeAsStringSync(
        map.readAsStringSync().replaceFirst(
          'Lets an agent sign in.',
          'An old summary.',
        ),
      );
      expect(_format(root, check: true), [_mapPath]);
      return root;
    }

    test('approve --auto rewrites it beside the clean draft', () async {
      final root = await staleDraft();

      final answer = await WriteSession.runAsync(
        (s) => approveAuto(
          s,
          AutoApproveCall(
            names: const [_story],
            auditPaths: const [],
            authorPaths: const [],
            noAudit: true,
            workingDirectory: root,
            approveModeVariable: 'auto',
          ),
          generators: _generators,
        ),
        templates: TemplateResolver(),
        workingDirectory: root,
        homeDirectory: testHome(),
      );

      expect(answer.json['approved'], hasLength(1));
      _expectRefreshed(root, answer, [_mapPath]);
    });

    test('the approve walk rewrites it at the y of the Owner', () async {
      final root = await staleDraft();
      final out = StringBuffer();
      final answers = ['y'];

      writeIn(
        root,
        (s) => approveDrafts(
          s,
          names: const [_story],
          readLine: () => answers.isEmpty ? null : answers.removeAt(0),
          out: out,
          generators: _generators,
        ),
      );

      expect(_format(root, check: true), isEmpty);
      expect(out.toString(), contains('rewrote $_mapPath\n'));
    });

    test('the approve walk warns of a feature map format refuses', () async {
      final root = await staleDraft();
      final map = File('${root.path}/docs/$_mapPath');
      map.writeAsStringSync('${map.readAsStringSync()}\n## Unknown\n\nText.\n');
      final answers = ['y'];

      final warnings = writeIn(root, (s) {
        approveDrafts(
          s,
          names: const [_story],
          readLine: () => answers.isEmpty ? null : answers.removeAt(0),
          out: StringBuffer(),
          generators: _generators,
        );
        return [...s.warnings];
      });

      expect(
        warnings,
        contains(startsWith('docs/$_mapPath cannot be written by format: ')),
      );
    });
  });

  test('the first feature of a project with no feature map rewrites no doc and '
      'leaves `format --check` clean', () async {
    // D17: no doc lists a generator, so the refresh plans nothing.
    final root = await writeTree({
      '.specstone/config.yaml': shippedPinsConfig(),
    });

    final answer = writeIn(
      root,
      (s) => answerNew(
        s,
        docTypeId: 'feature',
        slug: 'billing',
        generators: _generators,
      ),
    );

    expect(_rewritten(answer), isEmpty);
    expect(answer.json['deleted'], isEmpty);
    expect(answer.warnings, isEmpty);
    expect(_format(root, check: true), isEmpty);
  });

  test('a write leaves a doc whose only drift is layout as it is', () async {
    // D17: the refresh rewrites the stale block and only that block.
    final root = await _project();
    final map = File('${root.path}/docs/$_mapPath');
    map.writeAsStringSync(
      map.readAsStringSync().replaceFirst('## Systems\n\n', '## Systems\n\n\n'),
    );
    expect(_format(root, check: true), [_mapPath]);
    final before = map.readAsBytesSync();
    final useCase = getDoc(root, '$_story#use_case');

    final answer = writeIn(
      root,
      (s) => answerSet(
        s,
        SetRequest.parse('$_story#use_case', base: useCase['base']! as String),
        useCase['text']! as String,
        generators: _generators,
      ),
    );

    expect(map.readAsBytesSync(), before);
    expect(_rewritten(answer), isEmpty);
  });

  test(
    'set --dry-run refuses a read-only feature map it would rewrite',
    () async {
      // D17: a dry run refuses as the write does.
      final root = await _project();
      _laggingDraft(root);
      final map = File('${root.path}/docs/$_mapPath');
      Process.runSync('chmod', ['444', map.path]);
      addTearDown(() => Process.runSync('chmod', ['644', map.path]));
      final base = getDoc(root, '$_login#problem')['base']! as String;
      final session = openSession(root);
      addTearDown(session.close);

      await expectLater(
        answerSetDryRun(
          session,
          DryRunRequest.parse(
            '$_login#problem',
            base: base,
            index: session.index,
          ),
          'Users forget their passwords.\n',
          homeDirectory: testHome(),
          generators: _generators,
        ),
        throwsA(
          isA<RenderFault>().having(
            (fault) => fault.code,
            'code',
            RenderFaultCode.outputNotWritable,
          ),
        ),
      );
    },
    skip: unreadablePathSkipReason() ?? false,
  );
}
