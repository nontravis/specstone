import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/atomic_write.dart';
import 'package:specstone_core/src/canonical_path.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart' show docsFolderName;
import 'package:specstone_core/src/document_writing/home_record.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/project_config.dart';

// MARK: - Constants

/// The folder of the records under the home folder, `/`-separated.
const _recordsFolder = '.specstone/trusted';

const _projectRootKey = 'projectRoot';
const _docsRootKey = 'docsRoot';

/// Ends every refusal: the one way to lift it.
const _trustHint = 'run specstone trust at a terminal to allow it';

// MARK: - RootTrust

/// The roots a command works on, and whether this machine's Owner trusts them
/// for writes.
///
/// A committed `docs` link can lead a clone's writes out of the project: the
/// docs root may lie outside the project root, and the project root may be
/// another project the link names, outside [folder]. Such roots are trusted
/// only when a record under `<home>/.specstone/trusted/` holds both, keyed by
/// the canonical [folder] the walk found the project from. A git clone cannot
/// carry the record: a home folder that is not absolute, or that lies inside
/// [folder], the project root, or the docs root, holds none.
///
/// A layout whose docs root lies inside its project root, with the project
/// root the [folder] itself or below it, needs no record.
final class RootTrust {
  new _({
    required this.folder,
    required this.projectRoot,
    required this.docsRoot,
    required this.homeDirectory,
  });

  /// Finds the project holding [workingDirectory] and its roots.
  ///
  /// [homeDirectory] keeps the records; null keeps none. Throws [RenderFault]
  /// `project_not_found` when no folder from [workingDirectory] upward holds
  /// `.specstone/config.yaml`.
  factory locate(
    Directory workingDirectory, {
    required Directory? homeDirectory,
  }) {
    final match = matchProjectRoot(workingDirectory);
    if (match == null) {
      throw RenderFault(
        RenderFaultCode.projectNotFound,
        'no Specstone project: no folder from the working directory upward '
        'holds $projectConfigPath',
      );
    }
    return RootTrust.at(
      folder: match.folder,
      root: match.root,
      homeDirectory: homeDirectory,
    );
  }

  /// Returns the trust of the project root [root], found from [folder].
  ///
  /// [folder] is where a `docs` link led to [root], or [root] itself; both
  /// are canonical. Setup commands, which run before a config exists, use it
  /// with the roots they would write into.
  factory at({
    required Directory folder,
    required Directory root,
    required Directory? homeDirectory,
  }) {
    final projectRoot = Directory(root.resolveSymbolicLinksSync());
    return RootTrust._(
      folder: folder,
      projectRoot: projectRoot,
      docsRoot: Directory(
        canonicalPath(
          '${projectRoot.path}${Platform.pathSeparator}$docsFolderName',
        ),
      ),
      homeDirectory: homeDirectory,
    );
  }

  /// The canonical folder the walk stood in when it found the project: the
  /// key of the record.
  final Directory folder;

  /// The canonical project root.
  final Directory projectRoot;

  /// The canonical `<project root>/docs/`, which may not exist.
  final Directory docsRoot;

  /// The user's home folder, or null when the environment names none.
  final Directory? homeDirectory;

  /// Whether the roots are trusted only on the Owner's record: the docs root
  /// lies outside the project root, or the project root lies outside [folder],
  /// as a `docs` link that leaves it makes it.
  bool get needsRecord => _isDocsOutside || _isRootLinked;

  /// Whether the roots may be written: they need no record, or the Owner
  /// recorded both as they resolve now.
  bool get isTrusted => !needsRecord || _isRecorded;

  /// Returns why a write must be refused, or null when [isTrusted].
  ///
  /// The text follows `cannot write <path>: `.
  String? get refusal {
    if (isTrusted) return null;
    final what = _isDocsOutside
        ? 'the docs folder ${docsRoot.path} lies outside the project'
        : 'the project folder ${projectRoot.path} lies outside ${folder.path}';
    return '$what; $_trustHint';
  }

  /// Throws [RenderFault] `output_not_writable`, naming [file], unless
  /// [isTrusted].
  ///
  /// [file] is the first target of the refused write, from the project root.
  void requireTrusted(String file) {
    final reason = refusal;
    if (reason == null) return;
    throw RenderFault(
      RenderFaultCode.outputNotWritable,
      'cannot write $file: $reason',
      file: file,
    );
  }

  /// Throws [RenderFault] `output_not_writable` when there is no usable home
  /// folder to keep the record in.
  void requireHome() => _recordFile();

  /// Writes the record that trusts the roots as they resolve now.
  ///
  /// Throws [RenderFault] `output_not_writable` when there is no usable home
  /// folder or the record cannot be written.
  void record() {
    final file = _recordFile();
    try {
      final folder = file.parent..createSync(recursive: true);
      restrictToOwner(folder);
      writeFileAtomic(
        file,
        utf8.encode(
          jsonEncode({
            _projectRootKey: projectRoot.path,
            _docsRootKey: docsRoot.path,
          }),
        ),
      );
    } on FileSystemException catch (error) {
      throw RenderFault(
        RenderFaultCode.outputNotWritable,
        'cannot write ${file.path}: ${error.osError?.message ?? error.message}',
      );
    }
  }

  bool get _isDocsOutside =>
      !docsRoot.path.startsWith('${projectRoot.path}${Platform.pathSeparator}');

  bool get _isRootLinked => !_isInside(projectRoot.path, folder.path);

  /// Whether [path] is [folder] or lies below it, cut at whole names.
  static bool _isInside(String path, String folder) {
    if (path == folder) return true;
    final prefix = folder.endsWith(Platform.pathSeparator)
        ? folder
        : '$folder${Platform.pathSeparator}';
    return path.startsWith(prefix);
  }

  late final bool _isRecorded = _readRecord();

  bool _readRecord() {
    try {
      final file = _fileOrNull();
      if (file == null) return false;
      return switch (jsonDecode(file.readAsStringSync())) {
        {
          _projectRootKey: final String project,
          _docsRootKey: final String docs,
        } =>
          project == projectRoot.path && docs == docsRoot.path,
        _ => false,
      };
    } on FileSystemException {
      return false;
    } on FormatException {
      return false;
    }
  }

  File _recordFile() =>
      _fileOrNull() ??
      (throw RenderFault(
        RenderFaultCode.outputNotWritable,
        'cannot record the trust: no home folder to keep it in',
      ));

  File? _fileOrNull() => homeRecordFile(
    homeDirectory,
    folder: _recordsFolder,
    key: () => folder.path,
    keepOut: () => [folder.path, projectRoot.path, docsRoot.path],
  );
}
