import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/atomic_write.dart';
import 'package:specstone_core/src/document_writing/new_doc.dart';
import 'package:specstone_core/src/document_writing/owner_confirmation.dart';
import 'package:specstone_core/src/git_process.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/setup_migration/agent_targets.dart';
import 'package:specstone_core/src/setup_migration/carried_packs.dart';
import 'package:specstone_core/src/setup_migration/legacy_rewrites.dart'
    show docFileOf;
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/setup_migration/migrate_run.dart';
import 'package:specstone_core/src/setup_migration/project_files.dart';
import 'package:specstone_core/src/setup_migration/project_root.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/project_config.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:specstone_core/src/version.dart';

/// What one `specstone init` call runs with.
final class InitRequest {
  const new({
    required this.workingDirectory,
    required this.homeDirectory,
    required this.templates,
    required this.confirmation,
    required this.readLine,
    required this.out,
    this.planHash,
    this.runGit = runRealGit,
  });

  /// The folder the new project root is taken from.
  final Directory workingDirectory;

  /// The personal pack home, or null.
  final Directory? homeDirectory;

  /// Loads the carried packs.
  final TemplateResolver templates;

  /// How the Owner confirms the legacy migrate run: at the terminal's `y`, or
  /// `--yes`.
  final OwnerConfirmation confirmation;

  /// Reads one line of the Owner's answer, or null at the end of input.
  final String? Function() readLine;

  /// Where the run prints.
  final StringSink out;

  /// The hash on the `plan <hash>` line of the dry run the Owner saw; under
  /// `--yes` the legacy run applies only a plan with this hash.
  final String? planHash;

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
/// refused run, `output_not_writable` naming the file the disk refuses.
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
    return runLegacyAt(
      root,
      _migrateRequestOf(root, request),
      linkFolder: _linkFolderOf(request.workingDirectory, root),
    );
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
      confirmation: request.confirmation,
      readLine: request.readLine,
      out: request.out,
      planHash: request.planHash,
      runGit: request.runGit,
    );

/// Returns [folder], canonical, when it is not [root], else null.
///
/// [root] is `rootThroughDocsLink(folder)`, canonical, which differs from the
/// folder exactly when the folder's `docs` link led to it.
Directory? _linkFolderOf(Directory folder, Directory root) {
  final own = Directory(folder.resolveSymbolicLinksSync());
  return own.path == root.path ? null : own;
}

/// Plans the agent files, writes each singular draft, then the agent files,
/// then the config last (PD16, F6-D23).
///
/// Keeps each draft that already exists and names it `kept`; starts no git
/// process, so the new files stay untracked (E06). Throws
/// `agent_block_malformed` before the first write.
int _scaffold(Directory root, InitRequest request) {
  final (:set, :pins) = request.templates.resolveCarriedPinned(
    packNames: carriedPacks,
    homeDirectory: request.homeDirectory,
  );
  final agentPlan = _planAgentFiles(root, set);
  final docsRoot = Directory.fromUri(root.uri.resolve('docs/'));
  for (final docType in singularDocTypes(set)) {
    final path = docType.path;
    if (path == null) continue;
    final file = docFileOf(docsRoot, path);
    if (file.existsSync()) {
      request.out.writeln('kept docs/$path: exists');
      continue;
    }
    _writeNew(file, skeletonOf(docType, docType.id), shown: 'docs/$path');
    request.out.writeln('created docs/$path (draft)');
  }
  _writeAgentFiles(root, agentPlan, request.out);
  _writeNew(
    File.fromUri(root.uri.resolve(projectConfigPath)),
    configText(pins, agentFileRoots: agentPlan.agentFileRoots),
    shown: projectConfigPath,
  );
  final list = [
    for (final name in pins.keys.toList()..sort(compareCodePoints))
      '$name ${pins[name]}',
  ].join(', ');
  request.out.writeln('created $projectConfigPath: $list');
  return 0;
}

/// Returns the full agent file plan of a new project at [root].
AgentWritePlan _planAgentFiles(Directory root, MergedSet set) {
  final projectRoot = Directory(root.resolveSymbolicLinksSync());
  return planAgentWrites(
    AgentFileInputs(
      projectRoot: projectRoot,
      cliVersion: specstoneVersion,
      codeRootFolders: codeFoldersOf(projectRoot, set, codeRoot: '.'),
      agentFileRoots: const [],
    ),
    full: true,
  );
}

/// Writes each file of [plan] and prints `created <path>` or `updated <path>`.
///
/// A symbolic-link instruction file is written through to its target, so the
/// path stays a link.
void _writeAgentFiles(Directory root, AgentWritePlan plan, StringSink out) {
  for (final write in [...plan.rootWrites, ...plan.topWrites]) {
    _writeNew(
      docFileOf(root, write.path),
      write.text,
      shown: write.path,
      followLink: true,
    );
    out.writeln('${write.isNew ? 'created' : 'updated'} ${write.path}');
  }
}

/// Writes [text] to [file], creating its folders.
///
/// Writes through a symbolic link when [followLink]. Throws [RenderFault]
/// `output_not_writable` naming [shown], the file's ProjectPath, when the disk
/// refuses.
void _writeNew(
  File file,
  String text, {
  required String shown,
  bool followLink = false,
}) {
  try {
    file.parent.createSync(recursive: true);
    final target = followLink && _isLink(file)
        ? File(file.resolveSymbolicLinksSync())
        : file;
    writeFileAtomic(target, utf8.encode(text));
  } on FileSystemException catch (error) {
    throw RenderFault(
      RenderFaultCode.outputNotWritable,
      'cannot write $shown: ${error.osError?.message ?? error.message}',
    );
  }
}

bool _isLink(File file) =>
    FileSystemEntity.typeSync(file.path, followLinks: false) ==
    FileSystemEntityType.link;
