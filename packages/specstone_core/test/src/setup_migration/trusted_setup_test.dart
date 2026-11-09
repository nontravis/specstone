import 'dart:io';

import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/owner_confirmation.dart';
import 'package:specstone_core/src/document_writing/root_trust.dart';
import 'package:specstone_core/src/git_process.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/setup_migration/init_project.dart';
import 'package:specstone_core/src/setup_migration/migrate_run.dart';
import 'package:specstone_core/src/setup_migration/project_root.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/git_repo.dart';
import '../../helpers/legacy_fixture.dart';
import '../../helpers/relative_link.dart';
import '../../helpers/temp_tree.dart';
import '../../helpers/write_fixture.dart' show testHome, writeJournal;

final String? _linksUnavailable = Platform.isWindows
    ? 'a link needs a privilege on Windows'
    : null;

/// Writes the docs of another folder, `victim/`, which holds no config, and a
/// clone whose committed `docs` link names them.
Future<({Directory base, Directory clone, Directory victim})> _clone() async {
  final base = Directory(
    (await writeTree({
      'victim/docs/prds/keep.md': '# Keep\n',
      'clone/keep.txt': '',
    })).resolveSymbolicLinksSync(),
  );
  createRelativeLink('${base.path}/clone/docs', '../victim/docs');
  return (
    base: base,
    clone: Directory('${base.path}/clone'),
    victim: Directory('${base.path}/victim'),
  );
}

/// Records the trust `trust` would, run from [folder] before any config.
void _trust(Directory folder) =>
    locateSetupTrust(folder, homeDirectory: testHome()).record();

/// Returns the bytes of every file under [root] outside `.git`, keyed by its
/// relative path, and every folder as an empty list.
///
/// Git rewrites its own files in the background, so none is read.
Map<String, List<int>> _bytesUnder(Directory root) {
  final prefix = '${root.path}${Platform.pathSeparator}';
  final tree = <String, List<int>>{};
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    final path = entity.path.substring(prefix.length);
    if (path == '.git' || path.startsWith('.git${Platform.pathSeparator}')) {
      continue;
    }
    tree[path] = entity is File ? entity.readAsBytesSync() : const [];
  }
  return tree;
}

int _init(Directory root, {RunGit runGit = runRealGit}) => runInit(
  InitRequest(
    workingDirectory: root,
    homeDirectory: testHome(),
    templates: TemplateResolver(),
    confirmation: OwnerConfirmation.missing,
    readLine: () => null,
    out: StringBuffer(),
    runGit: runGit,
  ),
);

int _migrate(Directory root, {bool dryRun = false, StringBuffer? out}) =>
    runMigrate(
      MigrateRequest(
        workingDirectory: root,
        homeDirectory: testHome(),
        templates: TemplateResolver(),
        dryRun: dryRun,
        confirmation: OwnerConfirmation.prompt,
        readLine: () => 'y',
        out: out ?? StringBuffer(),
      ),
    );

Matcher _refuses(String file, String what) => throwsA(
  isA<RenderFault>()
      .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
      .having((f) => f.exitStatus, 'exit', 73)
      .having((f) => f.file, 'file', file)
      .having(
        (f) => f.message,
        'message',
        allOf(
          startsWith('cannot write $file: $what'),
          endsWith('; run specstone trust at a terminal to allow it'),
        ),
      ),
);

void main() {
  group('init through a docs link', () {
    test('refuses 73 before any write when the link names another folder, '
        'and both folders keep their bytes', () async {
      final (:base, :clone, :victim) = await _clone();
      final before = _bytesUnder(base);

      expect(
        () => _init(clone),
        _refuses(
          '.specstone/config.yaml',
          'the project folder ${victim.path} was reached through the docs '
              'link in ${clone.path}',
        ),
      );

      expect(_bytesUnder(base), before);
    }, skip: _linksUnavailable);

    test('runs after the Owner trusts the roots, and the project it made is '
        'trusted for every write command', () async {
      final (:base, :clone, :victim) = await _clone();
      _trust(clone);

      expect(_init(clone), 0);

      expect(
        File('${victim.path}/.specstone/config.yaml').existsSync(),
        isTrue,
      );
      expect(File('${victim.path}/docs/prds/PROJECT.md').existsSync(), isTrue);
      expect(
        RootTrust.locate(clone, homeDirectory: testHome()).isTrusted,
        isTrue,
      );
    }, skip: _linksUnavailable);

    test('a trust of another folder does not lift the refusal', () async {
      final (:base, :clone, :victim) = await _clone();
      final other = Directory('${base.path}/other')..createSync();
      createRelativeLink('${other.path}/docs', '../victim/docs');
      _trust(other);
      final before = _bytesUnder(base);

      expect(() => _init(clone), throwsA(isA<RenderFault>()));

      expect(_bytesUnder(base), before);
    }, skip: _linksUnavailable);

    test('runs with no record when the link names a project below the folder '
        'holding it', () async {
      final base = Directory(
        (await writeTree({
          'outer/below/docs/prds/keep.md': '# Keep\n',
          'outer/keep.txt': '',
        })).resolveSymbolicLinksSync(),
      );
      createRelativeLink('${base.path}/outer/docs', 'below/docs');
      final outer = Directory('${base.path}/outer');

      expect(locateSetupTrust(outer, homeDirectory: null).needsRecord, isFalse);
      expect(_init(outer), 0);

      expect(
        File('${base.path}/outer/below/.specstone/config.yaml').existsSync(),
        isTrue,
      );
    }, skip: _linksUnavailable);

    test('in a plain folder needs no record', () async {
      final root = await writeTree({'keep.txt': 'x\n'});

      expect(locateSetupTrust(root, homeDirectory: null).needsRecord, isFalse);
      expect(_init(root), 0);

      expect(File('${root.path}/.specstone/config.yaml').existsSync(), isTrue);
    });
  });

  group('a legacy migrate through a docs link', () {
    Future<Directory> linkedTree() async {
      final tree = await writeTree(linkedAcme({'.gitignore': 'code/docs\n'}));
      if (!linkCodeDocs(tree)) return tree;
      commitRepo(Directory('${tree.path}/ws'));
      return Directory('${tree.resolveSymbolicLinksSync()}/ws');
    }

    test('refuses 73 before any write, and the tree keeps its bytes', () async {
      final ws = await linkedTree();
      final code = Directory('${ws.path}/code');
      final before = _bytesUnder(ws);

      expect(
        () => _migrate(code),
        _refuses(
          '.specstone/trash/journal.json',
          'the project folder ${ws.path} was reached through the docs '
              'link in ${code.path}',
        ),
      );

      expect(_bytesUnder(ws), before);
    }, skip: _linksUnavailable ?? (hasGit ? null : 'git is not available'));

    test(
      'a dry run from there still prints the plan and writes nothing',
      () async {
        final ws = await linkedTree();
        final before = _bytesUnder(ws);
        final out = StringBuffer();

        expect(
          _migrate(Directory('${ws.path}/code'), dryRun: true, out: out),
          0,
        );

        expect(out.toString(), contains('dry run: nothing written'));
        expect(_bytesUnder(ws), before);
      },
      skip: _linksUnavailable ?? (hasGit ? null : 'git is not available'),
    );

    test('a dry run on a pending journal refuses with the trust text, not the '
        'step path, and writes nothing', () async {
      final ws = await linkedTree();
      final code = Directory('${ws.path}/code');
      writeJournal(ws, [const WriteStep.unguarded('docs/prds/x.md', 'text')]);
      final before = _bytesUnder(ws);

      expect(
        () => _migrate(code, dryRun: true),
        _refuses(
          '.specstone/trash/journal.json',
          'the project folder ${ws.path} was reached through the docs '
              'link in ${code.path}',
        ),
      );

      expect(_bytesUnder(ws), before);
    }, skip: _linksUnavailable ?? (hasGit ? null : 'git is not available'));

    test('applies after the Owner trusts the roots', () async {
      final ws = await linkedTree();
      final code = Directory('${ws.path}/code');
      _trust(code);

      expect(_migrate(code), 0);

      expect(File('${ws.path}/.specstone/config.yaml').existsSync(), isTrue);
    }, skip: _linksUnavailable ?? (hasGit ? null : 'git is not available'));

    test('with a link to a project below the folder holding it needs no '
        'record', () async {
      final tree = Directory(
        (await writeTree({
          for (final MapEntry(:key, :value) in acmeLegacy.entries)
            'outer/below/$key': value,
          'outer/keep.txt': '',
        })).resolveSymbolicLinksSync(),
      );
      createRelativeLink('${tree.path}/outer/docs', 'below/docs');
      final below = Directory('${tree.path}/outer/below');
      commitRepo(below);
      final outer = Directory('${tree.path}/outer');

      expect(locateSetupTrust(outer, homeDirectory: null).needsRecord, isFalse);
      expect(_migrate(outer), 0);

      expect(File('${below.path}/.specstone/config.yaml').existsSync(), isTrue);
    }, skip: _linksUnavailable ?? (hasGit ? null : 'git is not available'));

    test('with no link needs no record', () async {
      final root = await gitFixture(acmeLegacy);

      expect(locateSetupTrust(root, homeDirectory: null).needsRecord, isFalse);
      expect(_migrate(root), 0);

      expect(File('${root.path}/.specstone/config.yaml').existsSync(), isTrue);
    }, skip: hasGit ? null : 'git is not available');
  });
}
