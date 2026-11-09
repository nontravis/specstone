import 'dart:io';

import 'package:specstone_core/src/document_writing/owner_confirmation.dart';
import 'package:specstone_core/src/document_writing/root_trust.dart';
import 'package:specstone_core/src/setup_migration/project_root.dart';

/// What `specstone trust` runs on.
final class TrustRequest {
  const new({
    required this.workingDirectory,
    required this.homeDirectory,
    required this.confirmation,
    required this.readLine,
    required this.out,
  });

  /// Folder the project is looked up from.
  final Directory workingDirectory;

  /// The user's home folder, which keeps the record; null keeps none.
  final Directory? homeDirectory;

  /// How the Owner confirms: only a terminal prompt is accepted.
  final OwnerConfirmation confirmation;

  /// Reads the Owner's answer line, or null at the end of input.
  final String? Function() readLine;

  /// Receives the roots, the prompt, and the result.
  final StringSink out;
}

/// Runs `specstone trust` and returns its exit status.
///
/// Prints the project root and docs root it would trust, found as the write
/// commands, `migrate`, and `init` find them, so the Owner can trust before a
/// config exists ([locateSetupTrust]). A project whose
/// roots need no record (see [RootTrust.needsRecord]) is told so and the run
/// ends with 0. Otherwise it asks `trust these folders for writes? [y/N]` and,
/// on `y`, writes the record under the home folder.
///
/// Throws `owner_terminal_required` unless the Owner answers at a terminal,
/// and `output_not_writable` when there is no home folder to keep the record
/// in.
int runTrust(TrustRequest request) {
  final trust = locateSetupTrust(
    request.workingDirectory,
    homeDirectory: request.homeDirectory,
  );
  if (!trust.needsRecord) {
    request.out.writeln(
      'no record needed: the docs folder ${trust.docsRoot.path} lies inside '
      'the project folder ${trust.projectRoot.path}',
    );
    return 0;
  }
  request.out
    ..writeln('project root: ${trust.projectRoot.path}')
    ..writeln('docs root: ${trust.docsRoot.path}');
  request.confirmation.requireTerminal('trust runs only');
  trust.requireHome();
  request.out.write('trust these folders for writes? [y/N] ');
  if (request.readLine() != 'y') return 0;
  trust.record();
  request.out.writeln('trusted');
  return 0;
}
