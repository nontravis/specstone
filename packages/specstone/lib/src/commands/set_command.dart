import 'package:specstone/src/commands/write_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Replaces one section, field, or title of a doc with the text on stdin, or
/// writes a file of `get` blocks with `--batch`.
class SetCommand extends WriteCommand {
  new() {
    argParser
      ..addOption(
        'base',
        help: 'The base hash of the target, as `get` prints it.',
      )
      ..addOption(
        'field',
        help:
            'The id of the field to write; stdin holds its YAML value, '
            'a list as `- item` lines.',
      )
      ..addFlag(
        'title',
        negatable: false,
        help: 'Write the doc title, one line.',
      )
      ..addOption(
        'batch',
        help:
            'A file of `get` text output, edited; writes every changed '
            'block, or none. Takes no doc address, --base, --field, --title, '
            'or --target; reads no stdin.',
      )
      ..addMultiOption(
        'remove-task',
        splitCommas: false,
        help:
            'Removes every entry of the task from every doc, in one write; '
            'repeat it for more tasks. Takes no doc address, --base, '
            '--field, --title, or --batch; reads no stdin.',
      )
      ..addFlag(
        'replace',
        negatable: false,
        help:
            'Replace one passage of a section: stdin holds `==> old <==`, '
            'the old passage, `==> new <==`, then the new passage. The old '
            'passage must occur once in the section body. Takes a section '
            'target alone.',
      )
      ..addMultiOption(
        'stamp',
        splitCommas: false,
        valueHelp: 'entry=fingerprint',
        help:
            'Ends a covers or implements entry of the doc with the code '
            'fingerprint you judged, as <entry>=<fingerprint>; repeat it for '
            'more entries. Takes a doc address alone, with no --base, --field, '
            '--title, --batch, --remove-task, --replace, or section key; '
            'reads no stdin.',
      )
      ..addFlag('json', negatable: false, help: 'Print JSON instead of text.');
    addTargetOption();
  }

  @override
  String get name => 'set';

  @override
  String get description =>
      'Replace a section, a field, or the title of a doc with stdin, replace '
      'one passage of a section with --replace, write a file of `get` blocks '
      'with --batch, remove a task from every doc with --remove-task, or end '
      'covers and implements entries with judged code fingerprints with '
      '--stamp.';

  @override
  String get invocation =>
      'specstone set <doc address>(#<section key> | '
      '--field <field id> | --title) --base <hash> [--target <name>] '
      '[--json]\n'
      '       specstone set <doc address>#<section key> --base <hash> '
      '--replace [--target <name>] [--json]\n'
      '       specstone set --batch <file> [--json]\n'
      '       specstone set --remove-task <task id> [--remove-task <task id>] '
      '[--target <name>] [--json]\n'
      '       specstone set <doc address> --stamp <entry>=<fingerprint> '
      '[--stamp <entry>=<fingerprint>] [--target <name>] [--json]';

  @override
  Future<int> run() async {
    final args = argResults!;
    final asJson = args.flag('json');
    final rest = args.rest;
    final stamps = args.multiOption('stamp');
    if (stamps.isNotEmpty) return _runStamp(stamps, asJson: asJson);
    final removeTasks = args.multiOption('remove-task');
    final replace = args.flag('replace');
    if (replace && (removeTasks.isNotEmpty || args.option('batch') != null)) {
      return fail(
        IndexFault(IndexFaultCode.argumentConflict, replaceConflictMessage),
        asJson: asJson,
      );
    }
    if (removeTasks.isNotEmpty) {
      return _runRemoveTasks(removeTasks, asJson: asJson);
    }
    final batch = args.option('batch');
    if (batch != null) return _runBatch(batch, asJson: asJson);
    if (rest.length > 1) {
      usageException('Expected one target, got ${rest.length}.');
    }
    final String text;
    try {
      SetRequest.requireShape(rest.firstOrNull, args.option('base'));
      text = await console.readAll();
    } on SpecstoneFault catch (fault) {
      return fail(fault, asJson: asJson);
    }
    return runWrite(
      (session) => answerSet(
        session,
        SetRequest.parse(
          rest.firstOrNull,
          field: args.option('field'),
          title: args.flag('title'),
          base: args.option('base'),
          index: session.index,
          codeTarget: targetOf(args),
          replace: replace,
        ),
        text,
      ),
      asJson: asJson,
    );
  }

  /// Writes the blocks of the batch file at [path] in one write session.
  ///
  /// The file is read and split before the session opens, so a file that holds
  /// no block refuses before any project is needed. Stdin is never read: a
  /// harness may leave it an open pipe nobody closes.
  Future<int> _runBatch(String path, {required bool asJson}) async {
    final ParsedBatch parsed;
    try {
      _requireBatchAlone();
      parsed = parseBatchFile(
        path,
        readBatchFile(path, workingDirectory: specstoneRunner.workingDirectory),
      );
    } on SpecstoneFault catch (fault) {
      return fail(fault, asJson: asJson);
    }
    return runWrite(
      (session) => answerSetBatch(session, parsed),
      asJson: asJson,
    );
  }

  /// Removes the entries of [tasks] from every doc in one write session.
  ///
  /// The conflict is checked before the values, and both before a session
  /// opens, so no project is needed to refuse. Stdin is never read.
  Future<int> _runRemoveTasks(
    List<String> tasks, {
    required bool asJson,
  }) async {
    try {
      _requireRemoveTaskAlone();
      requireTaskIds(tasks);
    } on SpecstoneFault catch (fault) {
      return fail(fault, asJson: asJson);
    }
    return runWrite(
      (session) =>
          answerRemoveTasks(session, tasks, codeTarget: targetOf(argResults!)),
      asJson: asJson,
    );
  }

  /// Stamps the judged code fingerprints [stamps] on one doc in one write
  /// session.
  ///
  /// The conflict is checked before the values, and both before a session
  /// opens, so no project is needed to refuse. Stdin is never read.
  Future<int> _runStamp(List<String> stamps, {required bool asJson}) async {
    final args = argResults!;
    final address = args.rest.firstOrNull;
    final StampRequest request;
    try {
      _requireStampAlone();
      if (args.rest.length > 1) {
        usageException('Expected one target, got ${args.rest.length}.');
      }
      request = StampRequest.parse(address, stamps, codeTarget: targetOf(args));
    } on SpecstoneFault catch (fault) {
      return fail(fault, asJson: asJson);
    }
    return runWrite((session) => answerStamp(session, request), asJson: asJson);
  }

  /// Throws [IndexFault] `argument_conflict` naming `--stamp` and the first of
  /// `--base`, `--field`, `--title`, `--batch`, `--remove-task`, `--replace`,
  /// or a section key that goes beside it.
  void _requireStampAlone() {
    final args = argResults!;
    final beside = [
      if (args.option('base') != null) '--base',
      if (args.option('field') != null) '--field',
      if (args.flag('title')) '--title',
      if (args.option('batch') != null) '--batch',
      if (args.multiOption('remove-task').isNotEmpty) '--remove-task',
      if (args.flag('replace')) '--replace',
      if (args.rest.any((address) => address.contains('#'))) 'a section key',
    ];
    if (beside.isEmpty) return;
    throw IndexFault(
      IndexFaultCode.argumentConflict,
      '--stamp takes no ${beside.first}',
    );
  }

  /// Throws [IndexFault] `argument_conflict` when a doc address, `--base`,
  /// `--field`, `--title`, or `--batch` goes beside `--remove-task`.
  void _requireRemoveTaskAlone() {
    final args = argResults!;
    if (args.rest.isEmpty &&
        args.option('base') == null &&
        args.option('field') == null &&
        args.option('batch') == null &&
        !args.flag('title')) {
      return;
    }
    throw IndexFault(
      IndexFaultCode.argumentConflict,
      '--remove-task takes no doc address, --base, --field, --title, or '
      '--batch',
    );
  }

  /// Throws [IndexFault] `argument_conflict` when a doc address, `--base`,
  /// `--field`, `--title`, or `--target` goes beside `--batch`, the file being
  /// the only target.
  void _requireBatchAlone() {
    final args = argResults!;
    if (args.rest.isEmpty &&
        args.option('base') == null &&
        args.option('field') == null &&
        args.option('target') == null &&
        !args.flag('title')) {
      return;
    }
    throw IndexFault(
      IndexFaultCode.argumentConflict,
      '--batch takes no doc address, --base, --field, --title, or --target',
    );
  }
}
