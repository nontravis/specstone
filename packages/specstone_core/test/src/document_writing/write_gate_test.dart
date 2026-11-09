import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/document_writing/journal_bounds.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/new_doc.dart';
import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/rendering/build_output.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/relative_link.dart';
import '../../helpers/temp_tree.dart';
import '../../helpers/write_fixture.dart';

const _gate = 'document_writing/delete_doc_subtree/finish_interrupted_move';

final String? _linksUnavailable = Platform.isWindows
    ? 'a link needs a privilege on Windows'
    : null;

/// Returns every entry under [root] as text: a file by its bytes, a link by
/// its target, a folder by its name; nothing is followed.
Map<String, String> _snapshot(Directory root) {
  final prefix = '${root.path}${Platform.pathSeparator}';
  return {
    for (final entity in root.listSync(recursive: true, followLinks: false))
      entity.path.substring(prefix.length): switch (entity) {
        File() => 'file:${base64Encode(entity.readAsBytesSync())}',
        Link() => 'link:${entity.targetSync()}',
        _ => 'dir',
      },
  };
}

Matcher _refuses(String path, String reason) => throwsA(
  isA<RenderFault>()
      .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
      .having((f) => f.exitStatus, 'exit', 73)
      .having((f) => f.file, 'file', path)
      .having((f) => f.message, 'message', 'cannot write $path: $reason'),
);

const _leaves = 'it leads outside the project';
const _underGit = 'it lies under .git';

void main() {
  group('$_gate: writeRefusalOf', () {
    late Directory base;
    late Directory project;
    late Directory outside;

    setUp(() async {
      base = Directory(
        (await writeTree({
          'proj/docs/a.md': 'a\n',
          'proj/.git/config': '[core]\n',
          'proj/src/x.dart': '',
          'outside/victim.txt': 'mine\n',
          'ext/prds/b.md': 'b\n',
        })).resolveSymbolicLinksSync(),
      );
      project = Directory('${base.path}/proj');
      outside = Directory('${base.path}/outside');
      if (_linksUnavailable == null) {
        createRelativeLink('${project.path}/out', '../outside');
        createRelativeLink('${project.path}/lnk.txt', '../outside/victim.txt');
        createRelativeLink('${project.path}/keep', 'src');
        createRelativeLink('${project.path}/gone.txt', '../outside/gone.txt');
        createRelativeLink('${project.path}/gone-dir', '../outside/gone');
        createRelativeLink('${project.path}/loop-a', 'loop-b');
        createRelativeLink('${project.path}/loop-b', 'loop-a');
      }
    });

    String? refusal(String relative, {Directory? docsRoot}) => writeRefusalOf(
      '${project.path}/$relative',
      projectRoot: project,
      docsRoot: docsRoot,
    );

    for (final path in [
      'docs/a.md',
      'docs/new/deeper/b.md',
      '.specstone/index.sqlite',
      'src/x.dart',
      'docs/.github/x',
    ]) {
      test('$path may be written', () {
        expect(refusal(path), isNull);
      });
    }

    for (final path in [
      '../outside/victim.txt',
      'docs/../../outside/victim.txt',
      '../new.txt',
    ]) {
      test('$path leads outside the project', () {
        expect(refusal(path), _leaves);
      });
    }

    for (final path in [
      '.git/config',
      '.GIT/config',
      'docs/.git/hooks/x',
      '.git:stream/config',
      r'.git::$INDEX_ALLOCATION/x',
      'git~1/config',
      '.git./config',
    ]) {
      test('$path lies under .git', () {
        expect(refusal(path), _underGit);
      });
    }

    test('a link to a folder outside the project leads outside, for a '
        'file below it and for a file not made yet', () {
      expect(refusal('out/victim.txt'), _leaves);
      expect(refusal('out/new/deeper.txt'), _leaves);
    }, skip: _linksUnavailable);

    test('a file that is a link to a file outside the project leads '
        'outside', () {
      expect(refusal('lnk.txt'), _leaves);
    }, skip: _linksUnavailable);

    test('a link whose target does not exist yet leads where the target '
        'would be made, for a file and for a folder', () {
      expect(refusal('gone.txt'), _leaves);
      expect(refusal('gone-dir/new.txt'), _leaves);
      expect(outside.listSync().map((e) => e.path), [
        '${outside.path}/victim.txt',
      ]);
    }, skip: _linksUnavailable);

    test('links that loop stay as named, since the disk fails a write '
        'through them', () {
      expect(refusal('loop-a'), isNull);
      expect(
        () => File('${project.path}/loop-a').writeAsStringSync('x'),
        throwsA(isA<FileSystemException>()),
      );
    }, skip: _linksUnavailable);

    test('a link to a folder inside the project may be written through', () {
      expect(refusal('keep/x.dart'), isNull);
      expect(refusal('keep/y.dart'), isNull);
    }, skip: _linksUnavailable);

    test('a docs root outside the project is a root of its own', () {
      final docsRoot = Directory('${base.path}/ext');

      expect(refusal('../ext/prds/b.md', docsRoot: docsRoot), isNull);
      expect(refusal('../ext/prds/b.md'), _leaves);
      expect(refusal('../ext/.git/config', docsRoot: docsRoot), _underGit);
    });

    test('requireWritableTarget names the path from the project root, and a '
        'docs path as docs/...', () {
      expect(
        () => requireWritableTarget(
          '${project.path}/../outside/victim.txt',
          projectRoot: project,
        ),
        throwsA(isA<RenderFault>().having((f) => f.exitStatus, 'exit', 73)),
      );
      expect(
        () => requireWritableTarget(
          '${project.path}/.git/config',
          projectRoot: project,
        ),
        _refuses('.git/config', _underGit),
      );
      expect(
        () => requireWritableTarget(
          '${project.path}/docs/.git/x',
          projectRoot: project,
          docsRoot: Directory('${project.path}/docs'),
        ),
        _refuses('docs/.git/x', _underGit),
      );
      expect(outside.existsSync(), isTrue);
    });
  });

  group('$_gate: a write outside the journal that leads out is refused', () {
    late Directory outside;
    late Directory root;

    setUp(() async {
      root = await writeWriteProject();
      outside = await writeTree({'victim.txt': 'mine\n', 'doc/keep.md': 'k\n'});
    });

    Matcher refusesOpen(String path) => _refuses(path, _leaves);

    ReadSession open() => ReadSession.open(
      templates: TemplateResolver(),
      workingDirectory: root,
      homeDirectory: null,
    );

    test('a linked .specstone/index.sqlite whose target is missing refuses '
        'a read session and creates nothing there', () {
      final target = File('${outside.path}/not-yet.sqlite');
      Link('${root.path}/.specstone/index.sqlite').createSync(target.path);
      final before = _snapshot(outside);

      expect(open, refusesOpen('.specstone/index.sqlite'));

      expect(_snapshot(outside), before);
      expect(target.existsSync(), isFalse);
    }, skip: _linksUnavailable);

    test('a linked .specstone/index.sqlite whose target is a valid index '
        'refuses a read session and leaves its bytes', () {
      open().close();
      final index = File('${root.path}/.specstone/index.sqlite');
      final copy = index.copySync('${outside.path}/copy.sqlite');
      index.deleteSync();
      Link(index.path).createSync(copy.path);
      final before = _snapshot(outside);

      expect(open, refusesOpen('.specstone/index.sqlite'));

      expect(_snapshot(outside), before);
    }, skip: _linksUnavailable);

    test('a linked index sibling (-wal) refuses the open too', () {
      final victim = File('${outside.path}/victim.txt');
      Link('${root.path}/.specstone/index.sqlite-wal').createSync(victim.path);
      final before = _snapshot(outside);

      expect(
        () => IndexStore.open(root),
        _refuses('.specstone/index.sqlite-wal', _leaves),
      );

      expect(_snapshot(outside), before);
    }, skip: _linksUnavailable);

    test('a linked .specstone/.gitignore refuses the first index open and '
        'creates no index', () {
      final victim = File('${outside.path}/victim.txt');
      Link('${root.path}/.specstone/.gitignore').createSync(victim.path);
      final before = _snapshot(outside);

      expect(
        () => IndexStore.open(root),
        _refuses('.specstone/.gitignore', _leaves),
      );

      expect(_snapshot(outside), before);
      expect(
        File('${root.path}/.specstone/index.sqlite').existsSync(),
        isFalse,
      );
    }, skip: _linksUnavailable);

    test('a .specstone folder that is a link out of the project refuses the '
        'open and leaves the folder behind it', () {
      final real = Directory('${outside.path}/specstone')..createSync();
      File('${root.path}/.specstone/config.yaml')
          .copySync('${real.path}/config.yaml');
      Directory('${root.path}/.specstone').deleteSync(recursive: true);
      Link('${root.path}/.specstone').createSync(real.path);
      final before = _snapshot(outside);

      expect(open, refusesOpen('.specstone/index.sqlite'));

      expect(_snapshot(outside), before);
    }, skip: _linksUnavailable);

    test('a migrate journal behind a linked .specstone is never read: the '
        'run is refused as a write that leads out, not as migrate_pending', () {
      final real = Directory('${outside.path}/specstone')..createSync();
      File('${root.path}/.specstone/config.yaml')
          .copySync('${real.path}/config.yaml');
      Directory('${root.path}/.specstone').deleteSync(recursive: true);
      Link('${root.path}/.specstone').createSync(real.path);
      writeJournal(root, [
        const CommitStep(message: 'm', paths: ['docs/x.md'], base: 'abc'),
      ]);
      final before = _snapshot(outside);

      expect(
        () => writeIn(root, (session) {}),
        refusesOpen('.specstone/index.sqlite'),
      );

      expect(_snapshot(outside), before);
    }, skip: _linksUnavailable);

    test('the default build output below a linked .specstone/build is '
        'refused and nothing lands outside', () {
      Link('${root.path}/.specstone/build').createSync(outside.path);
      final project = openProject(root);
      final target = project.resolveTarget(
        'prds/FEATURES.md',
        workingDirectory: Directory('${root.path}/docs'),
        defaultsToDocsRoot: false,
      );
      final output = defaultOutputFile(project, target, OutputFormat.html);
      final before = _snapshot(outside);

      expect(
        () => writeBuildOutput(
          output,
          utf8.encode('<html></html>'),
          displayPath: '.specstone/build/docs/prds/FEATURES.md.html',
          within: project,
        ),
        throwsA(
          isA<RenderFault>()
              .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
              .having((f) => f.exitStatus, 'exit', 73)
              .having(
                (f) => f.message,
                'message',
                contains('it leads outside the project'),
              ),
        ),
      );

      expect(_snapshot(outside), before);
    }, skip: _linksUnavailable);

    test('the default build output below a .specstone/build linked into '
        '.git is refused', () {
      Directory('${root.path}/.git/hooks').createSync(recursive: true);
      Link('${root.path}/.specstone/build').createSync('../.git/hooks');
      final project = openProject(root);
      final target = project.resolveTarget(
        'prds/FEATURES.md',
        workingDirectory: Directory('${root.path}/docs'),
        defaultsToDocsRoot: false,
      );
      final output = defaultOutputFile(project, target, OutputFormat.html);

      expect(
        () => writeBuildOutput(
          output,
          utf8.encode('<html></html>'),
          displayPath: '.specstone/build/docs/prds/FEATURES.md.html',
          within: project,
        ),
        throwsA(
          isA<RenderFault>()
              .having((f) => f.exitStatus, 'exit', 73)
              .having(
                (f) => f.message,
                'message',
                contains('it lies under .git'),
              ),
        ),
      );

      expect(Directory('${root.path}/.git/hooks').listSync(), isEmpty);
    }, skip: _linksUnavailable);

    test('an output the Owner names outside the project is not judged', () {
      final output = File('${outside.path}/out.html');

      writeBuildOutput(
        output,
        utf8.encode('<html></html>'),
        displayPath: output.path,
      );

      expect(output.readAsStringSync(), '<html></html>');
    });

    test('new refuses a doc folder linked out of the project and creates '
        'nothing there', () {
      writeIn(root, (session) => session.project);
      const folder = 'prds/features/f01_login/us04_forgot_email';
      Link('${root.path}/docs/$folder').createSync('${outside.path}/doc');
      final before = _snapshot(outside);

      expect(
        () => writeIn(
          root,
          (s) => answerNew(
            s,
            docTypeId: 'user_story',
            parent: 'login',
            slug: 'forgot_email',
          ),
        ),
        _refuses('docs/$folder/USER_STORY.md', _leaves),
      );

      expect(_snapshot(outside), before);
    }, skip: _linksUnavailable);

    test('set refuses a doc whose folder was swapped for a link out of the '
        'project, and the folder behind it keeps its text', () {
      final folder = story2.substring(0, story2.lastIndexOf('/'));
      writeIn(root, (session) {
        final real = Directory('${root.path}/docs/$folder');
        final moved = Directory('${outside.path}/swapped');
        real.renameSync(moved.path);
        Link(real.path).createSync(moved.path);
        final before = _snapshot(outside);

        expect(
          () => session.writeDoc(story2, '# Changed\n', LineEnding.lf),
          _refuses('docs/$story2', _leaves),
        );

        expect(_snapshot(outside), before);
      });
    }, skip: _linksUnavailable);

    test('set into a doc folder behind a link to a folder inside the project '
        'still writes', () {
      final folder = story2.substring(0, story2.lastIndexOf('/'));
      writeIn(root, (session) {
        final real = Directory('${root.path}/docs/$folder');
        final moved = Directory('${root.path}/docs/prds/elsewhere');
        real.renameSync(moved.path);
        Link(real.path).createSync(moved.path);

        session.writeDoc(story2, '# Changed\n', LineEnding.lf);
      });

      expect(
        File('${root.path}/docs/prds/elsewhere/USER_STORY.md')
            .readAsStringSync(),
        contains('Changed'),
      );
    }, skip: _linksUnavailable);

    test('set refuses a doc folder linked into .git', () {
      final folder = story2.substring(0, story2.lastIndexOf('/'));
      Directory('${root.path}/.git/objects').createSync(recursive: true);
      writeIn(root, (session) {
        final real = Directory('${root.path}/docs/$folder')
          ..renameSync('${root.path}/.git/objects/swapped');
        Link(real.path).createSync('${root.path}/.git/objects/swapped');

        expect(
          () => session.writeDoc(story2, '# Changed\n', LineEnding.lf),
          _refuses('docs/$story2', _underGit),
        );
      });
    }, skip: _linksUnavailable);
  });

  group('$_gate: a docs link to a folder not made yet', () {
    Future<Directory> projectWithoutDocs() => writeWriteProject(
      without: {
        for (final key in writeProject.keys)
          if (key.startsWith('docs/')) key,
      },
    );

    test('a dangling docs link to a missing folder outside the project '
        'refuses new, and nothing is created', () async {
      final root = await projectWithoutDocs();
      final outside = await writeTree({'keep.txt': 'mine\n'});
      Link('${root.path}/docs').createSync('${outside.path}/made/here');
      final before = _snapshot(outside);

      expect(
        () =>
            writeIn(root, (s) => answerNew(s, docTypeId: 'persona', slug: 'x')),
        throwsA(
          isA<RenderFault>()
              .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
              .having((f) => f.exitStatus, 'exit', 73)
              .having(
                (f) => f.message,
                'message',
                endsWith('it leads outside the project'),
              ),
        ),
      );

      expect(_snapshot(outside), before);
    }, skip: _linksUnavailable);

    test('a dangling docs link to a missing folder inside the project '
        'still writes there', () async {
      final root = await projectWithoutDocs();
      Link('${root.path}/docs').createSync('inner/missing');

      writeIn(root, (s) => answerNew(s, docTypeId: 'persona', slug: 'x'));

      expect(
        File('${root.path}/inner/missing/prds/personas/x/PERSONA.md')
            .existsSync(),
        isTrue,
      );
    }, skip: _linksUnavailable);
  });

  group('$_gate: the layouts that lead out by design still write', () {
    test('a project whose docs link leads to a folder outside it writes into '
        'that docs folder', () async {
      final base = await writeTree({
        '.keep': '',
        for (final MapEntry(:key, :value) in writeProject.entries)
          if (key.startsWith('docs/'))
            'ext/${key.substring(5)}': value
          else
            'proj/$key': value,
      });
      createRelativeLink('${base.path}/proj/docs', '../ext');
      final project = Directory('${base.path}/proj');

      writeIn(project, (session) {
        session.writeDoc(story2, '# Changed\n', LineEnding.lf);
      });

      expect(
        File('${base.path}/ext/$story2').readAsStringSync(),
        contains('Changed'),
      );
      expect(
        File('${base.path}/proj/.specstone/index.sqlite').existsSync(),
        isTrue,
      );
    }, skip: _linksUnavailable);

    test('new in a project whose docs link leads to a folder beside it '
        'creates the doc in that folder', () async {
      final base = await writeTree({
        '.keep': '',
        for (final MapEntry(:key, :value) in writeProject.entries)
          if (key.startsWith('docs/'))
            'ext/${key.substring(5)}': value
          else
            'proj/$key': value,
      });
      createRelativeLink('${base.path}/proj/docs', '../ext');

      writeIn(
        Directory('${base.path}/proj'),
        (s) => answerNew(
          s,
          docTypeId: 'user_story',
          parent: 'login',
          slug: 'forgot_email',
        ),
      );

      expect(
        Directory('${base.path}/ext/prds/features/f01_login')
            .listSync()
            .map((e) => e.uri.pathSegments.lastWhere((s) => s.isNotEmpty)),
        contains(contains('forgot_email')),
      );
    }, skip: _linksUnavailable);
  });
}
