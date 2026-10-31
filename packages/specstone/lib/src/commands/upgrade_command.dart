import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone/src/commands/specstone_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Where the install scripts are fetched from, ending in `/`.
const String installScriptBase =
    'https://raw.githubusercontent.com/nontravis/specstone/main/';

/// A fault code of `specstone upgrade` from the `s05_errors.md` catalog.
///
/// [wire] is the snake_case code printed in the error envelope; [exitStatus]
/// is the process exit status for the fault.
enum UpgradeFaultCode {
  installNotManaged('install_not_managed', 78),
  installScriptFailed('install_script_failed', 69);

  new(this.wire, this.exitStatus);

  /// The snake_case code printed in the error envelope.
  final String wire;

  /// The process exit status for the fault.
  final int exitStatus;
}

/// The one fault `specstone upgrade` raises for a refused or failed run.
///
/// [message] is plain text with no location prefix.
final class UpgradeFault implements SpecstoneFault {
  new(this.code, this.message);

  /// The catalog code of this fault.
  final UpgradeFaultCode code;

  /// Plain human text with no location prefix.
  final String message;

  @override
  int get exitStatus => code.exitStatus;

  @override
  Map<String, Object> toJson() => {
    'error': {'code': code.wire, 'message': message},
  };

  @override
  String toText() => message;
}

/// Returns the folder [executable] runs from when it is not the managed one.
///
/// The managed folder is `<home>/.specstone/bin`. Returns null when
/// [executable] runs from it; returns its folder as given when it runs from
/// elsewhere or when [home] is null, since no home names no managed folder.
/// Both folders are compared with symlinks resolved, and without case when
/// [windows].
String? unmanagedBinFolder(
  String executable,
  Directory? home, {
  required bool windows,
}) {
  final binFolder = File(executable).parent;
  if (home == null) return binFolder.path;
  final managed = Directory(
    '${home.path}${Platform.pathSeparator}.specstone'
    '${Platform.pathSeparator}bin',
  );
  final same =
      _comparable(binFolder, windows: windows) ==
      _comparable(managed, windows: windows);
  return same ? null : binFolder.path;
}

// Resolves symlinks of an existing folder, so macOS `/var` and `/private/var`
// compare equal; a missing folder falls back to its normalized absolute path.
String _comparable(Directory folder, {required bool windows}) {
  final path = folder.existsSync()
      ? folder.resolveSymbolicLinksSync()
      : folder.absolute.uri.normalizePath().toFilePath(windows: windows);
  final bare = path.length > 1 && path.endsWith(Platform.pathSeparator)
      ? path.substring(0, path.length - 1)
      : path;
  return windows ? bare.toLowerCase() : bare;
}

/// Upgrades the CLI and the plugin to the latest release.
///
/// Refuses unless the running binary sits in `<home>/.specstone/bin`.
class UpgradeCommand extends SpecstoneCommand {
  /// Creates the command; each argument defaults to the running process.
  ///
  /// - [scriptBase]: where the install scripts are fetched from.
  /// - [executable]: the path of the running binary.
  /// - [environment]: the environment `HOME` is read from.
  /// - [windows]: whether to compare paths without case.
  new({
    Uri? scriptBase,
    String? executable,
    Map<String, String>? environment,
    bool? windows,
  }) : scriptBase = scriptBase ?? Uri.parse(installScriptBase),
       executable = executable ?? Platform.resolvedExecutable,
       environment = environment ?? Platform.environment,
       windows = windows ?? Platform.isWindows;

  /// Where the install scripts are fetched from.
  final Uri scriptBase;

  /// The path of the running binary.
  final String executable;

  /// The environment the home folder is read from.
  final Map<String, String> environment;

  /// Whether paths compare without case.
  final bool windows;

  @override
  String get name => 'upgrade';

  @override
  String get description =>
      'Upgrade the CLI and the plugin to the latest release.';

  @override
  bool get takesArguments => false;

  @override
  Future<int> run() async {
    final folder = unmanagedBinFolder(
      executable,
      homeFrom(environment),
      windows: windows,
    );
    if (folder != null) {
      return fail(
        UpgradeFault(
          UpgradeFaultCode.installNotManaged,
          'specstone upgrade updates only a CLI installed in '
          '~/.specstone/bin; this one runs from $folder',
        ),
        asJson: false,
      );
    }
    return 0;
  }
}
