import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/git_process.dart';

/// Runs `runRealGit` with the git arguments after `--` in each folder named
/// before it, in one process, and prints one JSON list of outcomes.
///
/// A test spawns it to give the real git launch point an inherited environment
/// and a fresh once-per-process cache, neither of which a test process can set
/// for itself. An outcome is `{exit, stdout}` or `{threw}`.
void main(List<String> arguments) {
  final split = arguments.indexOf('--');
  final folders = arguments.sublist(0, split);
  final gitArguments = arguments.sublist(split + 1);
  final outcomes = <Map<String, Object?>>[];
  for (final folder in folders) {
    try {
      final result = runRealGit(gitArguments, workingDirectory: folder);
      outcomes.add({'exit': result.exitCode, 'stdout': result.stdout});
    } on Object catch (failure) {
      outcomes.add({'threw': '$failure'});
    }
  }
  stdout.write(jsonEncode(outcomes));
}
