import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/atomic_write.dart';
import 'package:specstone_core/src/document_writing/new_doc.dart';
import 'package:specstone_core/src/git_process.dart';
import 'package:specstone_core/src/setup_migration/carried_packs.dart';
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/setup_migration/migrate_run.dart';
import 'package:specstone_core/src/setup_migration/project_files.dart';
import 'package:specstone_core/src/setup_migration/project_root.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/project_config.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';

/// What one `specstone init` call runs with.
final class InitRequest {
  const new({
    required this.workingDirectory,
    required this.homeDirectory,
    required this.templates,
    required this.interactive,
    required this.readLine,
    required this.out,
    this.runGit = runRealGit,
  });

  /// The folder the new project root is taken from.
  final Directory workingDirectory;

  /// The personal pack home, or null.
  final Directory? homeDirectory;

  /// Loads the carried packs.
  final TemplateResolver templates;

  /// Whether stdin and stdout are both terminals.
  final bool interactive;

  /// Reads one line of the Owner's answer, or null at the end of input.
  final String? Function() readLine;

  /// Where the run prints.
  final StringSink out;

  /// Starts `git`; replaced in tests.
  final RunGit runGit;
}

/// Runs `specstone init` and returns its exit status.
///
/// The root is [rootThroughDocsLink] of the working directory with no walk up,
/// so a nested project stays possible (INV-1). A root holding the config
/// refuses `config_exists`; a root holding the legacy context doc enters the
/// legacy migrate run at its git checks (F6-D15); otherwise the drafts are
/// written and the config last (F6-D23). Throws a `SpecstoneFault` for a
/// refused run.
int runInit(InitRequest request) {
  final root = rootThroughDocsLink(request.workingDirectory);
  if (File.fromUri(root.uri.resolve(projectConfigPath)).existsSync()) {
    throw MigrateFault(
      MigrateFaultCode.configExists,
      'this folder is already a Specstone project; run specstone migrate to '
      'upgrade its packs',
      file: projectConfigPath,
    );
  }
  if (File.fromUri(root.uri.resolve(legacyContextPath)).existsSync()) {
    return runLegacyAt(root, _migrateRequestOf(root, request));
  }
  return _scaffold(root, request);
}

/// Returns the migrate request `init` enters the legacy run with.
MigrateRequest _migrateRequestOf(Directory root, InitRequest request) =>
    MigrateRequest(
      workingDirectory: root,
      homeDirectory: request.homeDirectory,
      templates: request.templates,
      dryRun: false,
      interactive: request.interactive,
      readLine: request.readLine,
      out: request.out,
      runGit: request.runGit,
    );

/// Writes each singular draft, then the config last (PD16, F6-D23).
///
/// Keeps each draft that already exists and names it `kept`; starts no git
/// process, so the new files stay untracked (E06).
int _scaffold(Directory root, InitRequest request) {
  final (:set, :pins) = request.templates.resolveCarriedPinned(
    packNames: carriedPacks,
    homeDirectory: request.homeDirectory,
  );
  for (final docType in singularDocTypes(set)) {
    final file = File.fromUri(root.uri.resolve('docs/${docType.path}'));
    if (file.existsSync()) {
      request.out.writeln('kept docs/${docType.path}: exists');
      continue;
    }
    file.parent.createSync(recursive: true);
    writeFileAtomic(file, utf8.encode(skeletonOf(docType, docType.id)));
    request.out.writeln('created docs/${docType.path} (draft)');
  }
  final config = File.fromUri(root.uri.resolve(projectConfigPath));
  config.parent.createSync(recursive: true);
  writeFileAtomic(config, utf8.encode(configText(pins)));
  final list = [
    for (final name in pins.keys.toList()..sort(compareCodePoints))
      '$name ${pins[name]}',
  ].join(', ');
  request.out.writeln('created $projectConfigPath: $list');
  return 0;
}
