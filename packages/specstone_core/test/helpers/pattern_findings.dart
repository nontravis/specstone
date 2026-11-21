import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';

import 'check_fixture.dart';

/// Returns the lines of [docPath] that hold a `pattern_banned` finding of
/// [pattern] in the fixture project with [files] added, each once, in file
/// order.
Future<List<String>> bannedLines(
  Map<String, String> files,
  String docPath,
  String pattern,
) async {
  final project = await writeCheckProject(extra: files);
  final report = await checkOf(project);
  final lines = File('${project.path}/docs/$docPath').readAsLinesSync();
  final flagged = {
    for (final f in report.findings)
      if (f.kind == FindingKind.patternBanned &&
          f.path == docPath &&
          f.toJson()['pattern'] == pattern)
        f.line,
  }.toList()..sort();
  return [for (final line in flagged) lines[line - 1]];
}

/// Returns the `pattern_missing` ids of [docPath] in the fixture project with
/// [files] added, a per-subsection finding as `<id> @ <subsection>`, in file
/// order.
Future<List<String>> missingPatterns(
  Map<String, String> files,
  String docPath,
) async {
  final report = await checkOf(await writeCheckProject(extra: files));
  return [
    for (final f in report.findings)
      if (f.kind == FindingKind.patternMissing && f.path == docPath)
        switch (f.toJson()) {
          {'pattern': final id, 'subsection': final subsection} =>
            '$id @ $subsection',
          {'pattern': final id} => '$id',
          _ => throw StateError('pattern_missing holds no pattern: $f'),
        },
  ];
}
