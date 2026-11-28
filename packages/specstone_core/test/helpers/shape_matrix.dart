import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/document_writing/approval_writes.dart'
    show addressOf;
import 'package:specstone_core/src/document_writing/approve_drafts.dart';
import 'package:specstone_core/src/document_writing/delete_doc.dart';
import 'package:specstone_core/src/document_writing/models/path_move.dart';
import 'package:specstone_core/src/document_writing/models/seen_draft.dart';
import 'package:specstone_core/src/document_writing/move_doc.dart';
import 'package:specstone_core/src/document_writing/new_doc.dart';
import 'package:specstone_core/src/document_writing/owner_confirmation.dart';
import 'package:specstone_core/src/document_writing/set_doc.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/format_run.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart'
    show GeneratorRegistry;
import 'package:specstone_core/src/rendering/models/opened_resolver.dart';
import 'package:specstone_core/src/setup_migration/migrate_run.dart';
import 'package:specstone_core/src/shipped_generators.dart'
    show shippedGenerators;
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import 'check_fixture.dart' show checkOf;
import 'git_repo.dart';
import 'index_fixture.dart' show openSession;
import 'no_generators.dart';
import 'project_shapes.dart';
import 'shipped_pins.dart';
import 'temp_tree.dart';
import 'write_fixture.dart' show getDoc, testHome, treeBytes, writeIn;

/// The write commands the matrix runs.
const writeCommands = [
  'new',
  'set',
  'move',
  'rename',
  'format',
  'migrate',
  'approve',
  'delete',
  'reorder',
];

/// The finding kinds a command may add on a project of any shape: the content
/// waits its own doc names, each a thing the Owner or the Agent fills after
/// the write.
///
/// A wait only one command earns never hides the same kind after another. A
/// wait tied to a doc the command made or moved is not here: it is waived on
/// that doc alone, as [skeletonKinds] and [isMovedFrRow] give.
// D8: the allowed content waits per command.
const Map<String, Set<FindingKind>> allowedKinds = {
  'new': {},
  'set': {},
  'move': {},
  'move_within': {},
  'rename': {},
  'format': {},
  // A pack upgrade leaves the sections it re-guided waiting for a trim.
  'migrate': {FindingKind.retrimDue},
  'approve': {},
  'delete': {},
  'reorder': {},
};

/// What a new doc's skeleton keeps for the Agent to fill: template lines, the
/// empty vision and goals fields, the `<Role>` placeholder, the `BR-01`
/// mention. `new` waives them on the doc it created only.
const Set<FindingKind> skeletonKinds = {
  FindingKind.templateTextLeft,
  FindingKind.fieldGroupMissing,
  FindingKind.roleUnresolved,
  FindingKind.itemMentionMissing,
};

/// Whether [f] is the row of an FR of the moved story left on an `api` doc of
/// the source's top feature: [leftApis] holds those docs' paths, [movedFrCells]
/// the moved FRs' whole Names relative to that feature.
// D8: rewrite_moved_story_references E01 names this wait.
bool isMovedFrRow(Finding f, Set<String> leftApis, Set<String> movedFrCells) =>
    f.kind == FindingKind.frTraceUnresolved &&
    leftApis.contains(f.path) &&
    movedFrCells.contains('${f.keys['fr']}');

const _renamedSlug = 'renamed_probe';

/// The generators the CLI passes every write command.
final GeneratorRegistry<DocIndex> _generators = shippedGenerators();

/// Writes [shape] to a temp tree and makes it a git work tree with one commit.
Future<Directory> writeShapeTree(ProjectShape shape) async =>
    makeWorkTree(await writeTree(shape.allFiles));

/// Makes [root] a git work tree holding one commit of every file, the
/// `.specstone/.gitignore` a first session writes included, and returns it.
Directory makeWorkTree(Directory root) {
  initTestRepo(root);
  try {
    openSession(root).close();
  } on TemplateFault catch (fault) {
    // A pack pinned below the shipped one opens no session, so writes no file.
    if (fault.code != FaultCode.packPinOlder) rethrow;
  }
  commitAll(root, 'shape');
  return root;
}

/// Whether [command] runs on [shape]: a project pinned below the shipped packs
/// is refused by every command but `migrate`.
bool runsOn(ProjectShape shape, String command) =>
    shape.name != 'floor_pins' || command == 'migrate';

/// Runs [command] once on [root], a committed work tree, and returns the
/// findings `check` holds after it and not before.
///
/// A finding is the same finding when its kind, mapped path, and keys but the
/// measured `actual` match, so a moved line or a longer over-limit item is no
/// new finding.
// D8: one cell of the shape-by-command matrix.
Future<List<Finding>> newFindingsOf(Directory root, String command) async {
  final setUp = switch (command) {
    'move' => _createDestination(root),
    'move_within' => _createSubFeature(root),
    'approve' => _addressOfDoc(_newStory(root, 'draft_probe')),
    'delete' => _addressOfDoc(_newStory(root, 'doomed_probe')),
    'reorder' => _addressOfDoc(_newStory(root, 'reordered_probe')),
    _ => null,
  };
  if (setUp != null) commitAll(root, 'set up $command');
  final before = await _checkBefore(root, command);
  final leftApis = command == 'move'
      ? _apiDocsOfFirstStoryTop(root)
      : <String>{};
  final movedFrCells = command == 'move' ? _movedFrCells(root) : <String>{};
  final story = const {'move', 'move_within', 'rename'}.contains(command)
      ? writeIn(root, (s) => _storyOf(s.index))
      : null;
  String? createdPath;
  var moves = const <PathMove>[];
  switch (command) {
    case 'new':
      createdPath = _newStory(root, 'probe')['path']! as String;
    case 'set':
      _runSet(root);
    case 'move' || 'move_within':
      moves = _runMove(root, setUp!);
    case 'rename':
      moves = _runRename(root);
    case 'format':
      _expectNoRefusal(_formatOnce(root));
      _expectFormatSettled(root);
    case 'migrate':
      await _runMigrate(root);
    case 'approve':
      _runApprove(root, setUp!);
    case 'delete':
      _runDelete(root, setUp!);
    case 'reorder':
      moves = _runReorder(root, setUp!);
    default:
      throw ArgumentError.value(command, 'command', 'is no write command');
  }
  final carry = story == null
      ? _Carry(moves: moves)
      : _carryOf(root, story, moves);
  final added = _addedFindings(before, (await checkOf(root)).findings, carry);
  return [
    for (final f in added)
      if (!(f.path == createdPath && skeletonKinds.contains(f.kind)) &&
          !isMovedFrRow(f, leftApis, movedFrCells))
        f,
  ];
}

/// Runs [write] on [root], a committed work tree, and returns the findings
/// `check` holds after it and not before.
Future<List<Finding>> findingsAddedBy(
  Directory root,
  void Function() write,
) async {
  final before = (await checkOf(root)).findings;
  write();
  return _addedFindings(before, (await checkOf(root)).findings, const _Carry());
}

List<Finding> _addedFindings(
  List<Finding> before,
  List<Finding> after,
  _Carry carry,
) {
  final known = <String, int>{};
  for (final f in before) {
    known.update(_identityOf(f, carry), (n) => n + 1, ifAbsent: () => 1);
  }
  final added = <Finding>[];
  for (final f in after) {
    final id = _identityOf(f, const _Carry());
    final left = known[id] ?? 0;
    if (left == 0) {
      added.add(f);
    } else {
      known[id] = left - 1;
    }
  }
  return added;
}

/// What a move or a rename changed in the names a finding holds: the docs'
/// paths, the story's Name and slug, and the record the story's entries leave
/// and land in (carry_story_records_to_new_feature E01 and E02).
final class _Carry {
  const new({
    this.moves = const [],
    this.fromName = '',
    this.toName = '',
    this.sourceRecord,
    this.destRecord,
  });

  final List<PathMove> moves;
  final String fromName;
  final String toName;
  final String? sourceRecord;
  final String? destRecord;

  String get _fromSlug => fromName.split('/').last;
  String get _toSlug => toName.split('/').last;

  String pathOf(String path) {
    for (final move in moves) {
      if (path == move.from) return move.to;
      if (path.startsWith('${move.from}/')) {
        return '${move.to}${path.substring(move.from.length)}';
      }
    }
    return path;
  }

  /// Whether the finding's relative names read against the moved story.
  bool isScoped(String path) => path == sourceRecord || pathOf(path) != path;

  /// Replaces a whole old Name, or the old slug on a scoped finding, by the
  /// new one; a value that only contains it stays.
  String valueOf(String value, {required bool scoped}) {
    // A key may name a moved doc by its path from the project root.
    const docsPrefix = 'docs/';
    if (value.startsWith(docsPrefix)) {
      return '$docsPrefix${pathOf(value.substring(docsPrefix.length))}';
    }
    if (fromName.isEmpty) return value;
    final colon = value.indexOf(':');
    final prefix = colon > 0 && !value.substring(0, colon).contains('/')
        ? value.substring(0, colon + 1)
        : '';
    final name = value.substring(prefix.length);
    final byName = _swap(name, fromName, toName);
    if (byName != null) return '$prefix$byName';
    if (!scoped) return value;
    final bySlug = _swap(name, _fromSlug, _toSlug);
    return bySlug == null ? value : '$prefix$bySlug';
  }

  bool namesStory(String value) =>
      fromName.isNotEmpty &&
      (_swap(value, _fromSlug, _toSlug) != null ||
          _swap(value, fromName, toName) != null);

  static String? _swap(String value, String from, String to) {
    if (value == from) return to;
    if (value.startsWith('$from/')) return '$to${value.substring(from.length)}';
    return null;
  }
}

/// The keys of a finding kind that hold a measured value, left out of its
/// identity; a kind not here measures `actual` alone, so a new measured key
/// fails red.
// D8: bundle_size_rule.dart names the largest file, which moves as docs grow.
const Map<FindingKind, Set<String>> _measuredKeys = {
  FindingKind.bundleOverLimit: {'actual', 'doc'},
};

const Set<String> _defaultMeasured = {'actual'};

/// The findings of [after] that [before] does not hold, by identity.
List<Finding> addedFindings(List<Finding> before, List<Finding> after) =>
    _addedFindings(before, after, const _Carry());

String _identityOf(Finding f, _Carry carry) {
  final scoped = carry.isScoped(f.path);
  var path = carry.pathOf(f.path);
  if (f.path == carry.sourceRecord &&
      carry.destRecord != null &&
      f.keys.values.any((value) => carry.namesStory('$value'))) {
    path = carry.destRecord!;
  }
  final keys = [
    for (final MapEntry(:key, :value) in f.keys.entries)
      if (!(_measuredKeys[f.kind] ?? _defaultMeasured).contains(key))
        '$key=${carry.valueOf('$value', scoped: scoped)}',
  ]..sort();
  return '${f.kind.wire} $path ${keys.join(' ')}';
}

/// The first story, and the first record doc of its feature, if any.
IndexedDoc _storyOf(DocIndex index) => _firstOf(index, 'user_story');

IndexedDoc? _recordOf(DocIndex index, String? featurePath) {
  for (final doc in index.docs) {
    if (doc.docTypeId == 'implementation' && doc.parentPath == featurePath) {
      return doc;
    }
  }
  return null;
}

_Carry _carryOf(Directory root, IndexedDoc story, List<PathMove> moves) {
  final carry = _Carry(moves: moves);
  final landed = carry.pathOf(story.docPath);
  return writeIn(root, (s) {
    final now = s.index.docs.firstWhere((doc) => doc.docPath == landed);
    return _Carry(
      moves: moves,
      fromName: story.name,
      toName: now.name,
      sourceRecord: _recordOf(s.index, story.parentPath)?.docPath,
      destRecord: _recordOf(s.index, now.parentPath)?.docPath,
    );
  });
}

/// The whole Names, relative to the story's top feature, of the FRs under the
/// first story.
Set<String> _movedFrCells(Directory root) => writeIn(root, (s) {
  final story = _storyOf(s.index);
  final top = _topOf(s.index, story);
  return {
    for (final doc in s.index.docs)
      if (doc.docTypeId == 'fr' && doc.parentPath == story.docPath)
        doc.name.substring('${top.name}/'.length),
  };
});

/// The docPaths of the `api` docs of the top feature the first story sits
/// under.
Set<String> _apiDocsOfFirstStoryTop(Directory root) => writeIn(root, (s) {
  final top = _topOf(s.index, _firstOf(s.index, 'user_story'));
  return {
    for (final doc in s.index.docs)
      if (doc.docTypeId == 'api' && _topOf(s.index, doc).docPath == top.docPath)
        doc.docPath,
  };
});

IndexedDoc _topOf(DocIndex index, IndexedDoc doc) {
  var top = doc;
  while (top.parentPath != null) {
    top = index.docs.firstWhere((d) => d.docPath == top.parentPath);
  }
  return top;
}

/// Creates a sub-feature of the top feature the first story sits under, so a
/// move stays inside that top feature; returns its address.
String _createSubFeature(Directory root) => writeIn(root, (s) {
  final top = _topOf(s.index, _firstOf(s.index, 'user_story'));
  return _addressIn(
    answerNew(
      s,
      docTypeId: 'feature',
      parent: addressOf(top),
      slug: 'sibling',
      generators: _generators,
    ),
  );
});

/// The findings `check` holds before [command].
///
/// `migrate` on a project pinned below the shipped packs, which no other
/// command reads, takes the findings of the same docs pinned at the shipped
/// packs, so only what the migration changes counts.
Future<List<Finding>> _checkBefore(Directory root, String command) async {
  try {
    return (await checkOf(root)).findings;
  } on TemplateFault catch (fault) {
    if (command != 'migrate' || fault.code != FaultCode.packPinOlder) rethrow;
    final shipped = await writeTree({
      for (final MapEntry(:key, :value) in treeBytes(root).entries)
        if (value.isNotEmpty) key: utf8.decode(value),
      '.specstone/config.yaml': shippedPinsConfig(),
    });
    return (await checkOf(shipped)).findings;
  }
}

/// Returns the lines of [findings] whose kind [command] does not allow, nor
/// [alsoAllowed], as `kind path:line`.
List<String> unallowedLines(
  String command,
  List<Finding> findings, {
  Set<FindingKind> alsoAllowed = const {},
}) => [
  for (final f in findings)
    if (!allowedKinds[command]!.contains(f.kind) &&
        !alsoAllowed.contains(f.kind))
      '${f.kind.wire} ${f.path}:${f.line}',
];

String _withoutSlash(String path) =>
    path.endsWith('/') ? path.substring(0, path.length - 1) : path;

/// The paths [answer] reports moved.
List<PathMove> _movesIn(ReadAnswer answer) => [
  for (final move in answer.json['moved']! as List)
    PathMove(
      from: _withoutSlash((move as Map<String, Object?>)['from']! as String),
      to: _withoutSlash(move['to']! as String),
    ),
];

/// The first typed doc of [docTypeId] in `session`'s tree order.
IndexedDoc _firstOf(DocIndex index, String docTypeId) => index.docs.firstWhere(
  (doc) => doc.docTypeId == docTypeId,
  orElse: () => throw StateError('the shape holds no $docTypeId'),
);

IndexedDoc _parentOf(DocIndex index, IndexedDoc doc) =>
    index.docs.firstWhere((d) => d.docPath == doc.parentPath);

/// Creates a story named [slug] under the feature of the shape's first story,
/// and returns the doc object `new` replies with.
Map<String, Object?> _newStory(Directory root, String slug) =>
    writeIn(root, (s) {
      final story = _firstOf(s.index, 'user_story');
      return _docIn(
        answerNew(
          s,
          docTypeId: 'user_story',
          parent: addressOf(_parentOf(s.index, story)),
          slug: slug,
          generators: _generators,
        ),
      );
    });

Map<String, Object?> _docIn(ReadAnswer answer) =>
    (answer.json['docs']! as List).single as Map<String, Object?>;

String _addressOfDoc(Map<String, Object?> doc) =>
    '${doc['docType']}:${doc['name']}';

String _addressIn(ReadAnswer answer) => _addressOfDoc(_docIn(answer));

/// Writes the Use Case of the first story back as it stands, else a short
/// one, so the text adds no finding of its own.
void _runSet(Directory root, {String? text}) {
  final story = writeIn(
    root,
    (s) => addressOf(_firstOf(s.index, 'user_story')),
  );
  final target = '$story#use_case';
  final doc = getDoc(root, target);
  final held = (doc['text'] as String?) ?? '';
  writeIn(
    root,
    (s) => answerSet(
      s,
      SetRequest.parse(target, base: doc['base']! as String),
      text ?? (held.trim().isEmpty ? 'Sign in with an email.\n' : held),
      generators: _generators,
    ),
  );
}

/// Creates a top feature beside the shape's first one, holding the vision and
/// goals of the feature the first story sits in, so a story has a feature to
/// move to that keeps its vision and goals; returns its address.
String _createDestination(Directory root) {
  final address = writeIn(root, (s) {
    final top = s.index.docs.firstWhere(
      (doc) => doc.docTypeId == 'feature' && doc.parentPath == null,
    );
    final parts = top.name.split('/');
    final slug = [...parts.take(parts.length - 1), 'destination'].join('/');
    return _addressIn(
      answerNew(s, docTypeId: 'feature', slug: slug, generators: _generators),
    );
  });
  final source = writeIn(
    root,
    (s) => _parentOf(s.index, _firstOf(s.index, 'user_story')),
  );
  for (final field in ['vision', 'goals']) {
    final values = source.valuesOf(field);
    if (values.isEmpty) continue;
    final bases = getDoc(root, address)['bases']! as Map;
    final base = (bases['fields']! as Map)[field]! as String;
    writeIn(
      root,
      (s) => answerSet(
        s,
        SetRequest.parse(address, field: field, base: base),
        [for (final value in values) '- $value\n'].join(),
        generators: _generators,
      ),
    );
  }
  return address;
}

List<PathMove> _runMove(Directory root, String destination) =>
    writeIn(root, (s) {
      final story = _firstOf(s.index, 'user_story');
      return _movesIn(
        answerMove(
          s,
          [addressOf(story)],
          under: destination,
          generators: _generators,
        ),
      );
    });

List<PathMove> _runRename(Directory root) => writeIn(root, (s) {
  final story = _firstOf(s.index, 'user_story');
  return _movesIn(
    answerRename(
      s,
      addressOf(story),
      slug: _renamedSlug,
      generators: _generators,
    ),
  );
});

FormatReport _formatOnce(Directory root) {
  final project = DocsProject.open(
    templates: TemplateResolver(),
    workingDirectory: root,
    homeDirectory: testHome(),
  );
  final generators = GeneratorRun<DocIndex>(
    registry: shippedGenerators(),
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
  );
  return runFormat<DocIndex>(
    project,
    project.resolveTarget(
      null,
      workingDirectory: root,
      defaultsToDocsRoot: true,
      includeRecordsRoot: true,
    ),
    check: false,
    homeDirectory: testHome(),
    generators: generators,
  );
}

void _expectNoRefusal(FormatReport report) => expect(
  [
    for (final file in report.files)
      if (file.status == FileStatus.refused) file.path,
  ],
  isEmpty,
  reason: 'format refuses no doc',
);

void _expectFormatSettled(Directory root) {
  final second = _formatOnce(root);
  _expectNoRefusal(second);
  expect(
    [
      for (final file in second.files)
        if (file.status == FileStatus.formatted ||
            file.status == FileStatus.created ||
            file.status == FileStatus.deleted)
          '${file.path}: ${file.status}',
    ],
    isEmpty,
    reason: 'a second format changes nothing',
  );
}

Future<void> _runMigrate(Directory root) async {
  Future<int> run({required bool dryRun}) {
    var read = 0;
    return runMigrate(
      MigrateRequest(
        workingDirectory: root,
        homeDirectory: testHome(),
        templates: TemplateResolver(),
        dryRun: dryRun,
        confirmation: OwnerConfirmation.prompt,
        readLine: () => read++ == 0 ? 'y' : null,
        out: StringBuffer(),
        warn: (_) {},
        say: (_) {},
        generators: shippedGenerators(),
      ),
    );
  }

  await run(dryRun: true);
  await run(dryRun: false);
}

/// Deletes the story [address] names, which nothing cites.
void _runDelete(Directory root, String address) => writeIn(
  root,
  (s) => answerDelete(
    s,
    [address],
    confirmation: OwnerConfirmation.prompt,
    readLine: () => null,
    prompts: StringBuffer(),
    generators: _generators,
  ),
);

/// Moves the story [address] names to the first place among its siblings.
List<PathMove> _runReorder(Directory root, String address) => writeIn(
  root,
  (s) =>
      _movesIn(answerReorder(s, address, place: '1', generators: _generators)),
);

void _runApprove(Directory root, String address) {
  final hash = getDoc(root, address)['base']! as String;
  writeIn(
    root,
    (s) => approveNamed(s, [
      SeenDraft(name: address, hash: hash),
    ], generators: _generators),
  );
}

/// The commit [root] is at.
String headOf(Directory root) =>
    '${git(root, ['rev-parse', 'HEAD']).stdout}'.trim();

/// The operands of a project that holds the flat shape's docs.
const String _flatStory = 'user_story:login/email_login';

/// Runs the core call of [command] on [root] with fixed operands, with no
/// set-up and no check before it.
///
/// On a project the packs refuse, each call stops at its session open, as the
/// command does; `migrate` is no such command.
// D8: the refusal of a project pinned below the shipped packs.
void callCommand(Directory root, String command) {
  switch (command) {
    case 'new':
      writeIn(
        root,
        (s) => answerNew(
          s,
          docTypeId: 'user_story',
          parent: 'feature:login',
          slug: 'probe',
          generators: noGenerators,
        ),
      );
    case 'set':
      writeIn(
        root,
        (s) => answerSet(
          s,
          SetRequest.parse('$_flatStory#use_case', base: 'abc'),
          'Text.\n',
          generators: noGenerators,
        ),
      );
    case 'move':
      writeIn(
        root,
        (s) => answerMove(
          s,
          [_flatStory],
          under: 'feature:signup',
          generators: noGenerators,
        ),
      );
    case 'rename':
      writeIn(
        root,
        (s) => answerRename(
          s,
          _flatStory,
          slug: _renamedSlug,
          generators: noGenerators,
        ),
      );
    case 'format':
      _formatOnce(root);
    case 'approve':
      writeIn(
        root,
        (s) => approveNamed(s, [
          const SeenDraft(name: _flatStory, hash: 'abc'),
        ], generators: noGenerators),
      );
    case 'delete':
      _runDelete(root, _flatStory);
    case 'reorder':
      _runReorder(root, _flatStory);
    default:
      throw ArgumentError.value(command, 'command', 'is not refused at a pin');
  }
}

/// Writes [text] as the Use Case of the first story of [root].
void setFirstStoryUseCase(Directory root, String text) =>
    _runSet(root, text: text);
