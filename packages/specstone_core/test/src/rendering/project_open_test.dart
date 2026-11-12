import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/document_writing/owner_confirmation.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/setup_migration/init_project.dart';
import 'package:specstone_core/src/setup_migration/migrate_run.dart';
import 'package:specstone_core/src/templates/project_config.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/relative_link.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/temp_tree.dart';
import '../../helpers/write_fixture.dart';

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

Matcher _refusesSpecstone() => throwsA(
  isA<TemplateFault>()
      .having((f) => f.code, 'code', FaultCode.unknownValue)
      .having((f) => f.exitStatus, 'exit', 78)
      .having((f) => f.file, 'file', '.specstone')
      .having(
        (f) => f.message,
        'message',
        '.specstone must be a real folder inside the project root, '
            'not a link or a file',
      ),
);

DocsProject _open(Directory root) => DocsProject.open(
  templates: TemplateResolver(),
  workingDirectory: root,
  homeDirectory: null,
);

ReadSession _read(Directory root) => ReadSession.open(
  templates: TemplateResolver(),
  workingDirectory: root,
  homeDirectory: null,
);

MigrateRequest _migrate(Directory root, {bool dryRun = false}) =>
    MigrateRequest(
      workingDirectory: root,
      homeDirectory: testHome(),
      templates: TemplateResolver(),
      dryRun: dryRun,
      confirmation: OwnerConfirmation.prompt,
      readLine: () => throw StateError('must not ask'),
      out: StringBuffer(),
    );

InitRequest _init(Directory root) => InitRequest(
  workingDirectory: root,
  homeDirectory: testHome(),
  templates: TemplateResolver(),
  confirmation: OwnerConfirmation.prompt,
  readLine: () => throw StateError('must not ask'),
  out: StringBuffer(),
);

void main() {
  group('project open: .specstone must be a real folder', () {
    late Directory base;
    late Directory project;

    setUp(() async {
      base = await writeTree({
        'x/config.yaml': shippedPinsConfig(),
        'x/keep.txt': 'mine\n',
        'proj/docs/prds/PROJECT.md': 'x\n',
      });
      project = Directory('${base.path}/proj');
      Link('${project.path}/.specstone').createSync('../x');
    });

    void refusesUnchanged(void Function() run) {
      final before = _snapshot(base);

      expect(run, _refusesSpecstone());

      expect(_snapshot(base), before);
    }

    test('ProjectConfig.read refuses a linked .specstone', () {
      refusesUnchanged(() => ProjectConfig.read(project));
    });

    test('opening the project refuses it', () {
      refusesUnchanged(() => _open(project));
    });

    test('a read session refuses it before it writes an index', () {
      refusesUnchanged(() => _read(project));
    });

    test('a write command refuses it before it writes an index', () {
      refusesUnchanged(() => writeIn(project, (session) => session.project));
    });

    test('a bare migrate refuses it', () {
      refusesUnchanged(() => runMigrate(_migrate(project)));
    });

    test('a migrate dry run refuses it', () {
      refusesUnchanged(() => runMigrate(_migrate(project, dryRun: true)));
    });

    test('guide resolution refuses it', () {
      refusesUnchanged(
        () => TemplateResolver().resolve(
          workingDirectory: project,
          homeDirectory: null,
        ),
      );
    });
  }, skip: _linksUnavailable);

  group('project init: .specstone must be a real folder', () {
    test('init refuses a linked .specstone before it scaffolds through '
        'it', () async {
      final base = await writeTree({
        'x/keep.txt': 'mine\n',
        'proj/keep.txt': 'mine\n',
      });
      final project = Directory('${base.path}/proj');
      Link('${project.path}/.specstone').createSync('../x');
      final before = _snapshot(base);

      expect(() => runInit(_init(project)), _refusesSpecstone());

      expect(_snapshot(base), before);
    }, skip: _linksUnavailable);

    test('init refuses a .specstone file before it scaffolds', () async {
      final base = await writeTree({'proj/.specstone': 'not a folder\n'});
      final before = _snapshot(base);

      expect(
        () => runInit(_init(Directory('${base.path}/proj'))),
        _refusesSpecstone(),
      );

      expect(_snapshot(base), before);
    });

    test('init still scaffolds a folder with no .specstone', () async {
      final base = await writeTree({'proj/keep.txt': 'mine\n'});

      expect(runInit(_init(Directory('${base.path}/proj'))), 0);

      expect(
        File('${base.path}/proj/.specstone/config.yaml').existsSync(),
        isTrue,
      );
    });
  });

  group('project open: the docs-link layout stays', () {
    test('a project reached through a docs link, with a .specstone link '
        'beside the docs link, opens at the real project', () async {
      final base = await writeTree({
        for (final MapEntry(:key, :value) in writeProject.entries)
          'ws/$key': value,
        'ws/code/lib/a.dart': '// a\n',
      });
      createRelativeLink('${base.path}/ws/code/docs', '../docs');
      createRelativeLink('${base.path}/ws/code/.specstone', '../.specstone');
      final code = Directory('${base.path}/ws/code');

      final opened = _open(code);
      final session = _read(code);
      addTearDown(session.store.close);

      expect(
        opened.projectRoot.path,
        Directory('${base.path}/ws').resolveSymbolicLinksSync(),
      );
      expect(session.project.projectRoot.path, opened.projectRoot.path);
    }, skip: _linksUnavailable);

    test('a docs link to a folder outside any project opens the folder with '
        'its own real .specstone', () async {
      final base = await writeTree({
        for (final MapEntry(:key, :value) in writeProject.entries)
          if (key == '.specstone/config.yaml') 'proj/$key': value,
        'ext/prds/PROJECT.md': 'x\n',
      });
      createRelativeLink('${base.path}/proj/docs', '../ext');
      final project = Directory('${base.path}/proj');

      final opened = _open(project);

      expect(opened.projectRoot.path, project.resolveSymbolicLinksSync());
    }, skip: _linksUnavailable);
  });
}
