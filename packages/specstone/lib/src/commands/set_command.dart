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
      ..addOption(
        'sync',
        valueHelp: 'file',
        help:
            'A filled group file of sync lines; reads the lines after its '
            '`==> verdicts <==` line, or the whole file when it holds none. '
            'Takes no doc address, --base, --field, --title, --batch, '
            '--stamp, --remove-task, or --replace; reads no stdin.',
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help:
            'Prints the findings a write of the section or lead on stdin '
            'would add, and writes nothing. Takes a section target or '
            '#_lead alone, with no --field, --title, --batch, --replace, '
            '--sync, --stamp, or --remove-task; --base is optional.',
      )
      ..addFlag('json', negatable: false, help: 'Print JSON instead of text.');
    addTargetOption();
    addOutOption();
  }

  @override
  String get name => 'set';

  @override
  String get description =>
      'Replace a section, a field, or the title of a doc with stdin, replace '
      'one passage of a section with --replace, write a file of `get` blocks '
      'with --batch, remove a task from every doc with --remove-task, or end '
      'covers and implements entries with judged code fingerprints with '
      '--stamp, write a filled sync file with --sync, or judge a section or '
      'lead write without writing it with --dry-run.';

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
      '[--stamp <entry>=<fingerprint>] [--target <name>] [--json]\n'
      '       specstone set --sync <file> [--target <name>] [--json]\n'
      '       specstone set <doc address>(#<section key> | #_lead) '
      '[--base <hash>] --dry-run [--target <name>] [--json] '
      '[--out [<path>]]';

  @override
  Future<int> run() async {
    final args = argResults!;
    final asJson = args.flag('json');
    final rest = args.rest;
    if (args.flag('dry-run')) {
      return _runDryRun(rest.firstOrNull, asJson: asJson);
    }
    final sync = args.option('sync');
    if (sync != null) return _runSync(sync, asJson: asJson);
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

  /// Prints the findings a write of stdin to the section or lead at [address]
  /// would add, and writes nothing.
  ///
  /// Runs in a read session, so no trust record is read; the conflict, the
  /// target, and its section key or `#_lead` are checked before stdin, and
  /// stdin is read before any session opens.
  Future<int> _runDryRun(String? address, {required bool asJson}) async {
    final args = argResults!;
    final String text;
    try {
      _requireDryRunAlone();
      DryRunRequest.requireShape(address);
      if (args.rest.length > 1) {
        usageException('Expected one target, got ${args.rest.length}.');
      }
      text = await console.readAll();
    } on SpecstoneFault catch (fault) {
      return fail(fault, asJson: asJson);
    }
    final runner = specstoneRunner;
    var sessionWarnings = const <String>[];
    final ReadAnswer answer;
    try {
      answer = await ReadSession.runAsync(
        (session) async {
          sessionWarnings = session.warnings;
          return answerSetDryRun(
            session,
            DryRunRequest.parse(
              address,
              base: args.option('base'),
              index: session.index,
              codeTarget: targetOf(args),
            ),
            text,
            homeDirectory: runner.homeDirectory,
          );
        },
        templates: runner.templates,
        workingDirectory: runner.workingDirectory,
        homeDirectory: runner.homeDirectory,
        busyTimeout: runner.busyTimeout,
      );
    } on SpecstoneFault catch (fault) {
      return failWrite(fault, asJson: asJson, warnings: sessionWarnings);
    }
    // The answer's warnings already hold the session's, so none are added.
    return printAnswer(answer, const [], asJson: asJson);
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

  /// Writes the lines of the sync file at [path] in one write session.
  ///
  /// The file is read before any session opens, so a malformed file, or a
  /// conflict, refuses before any project is needed. Stdin is never read: a
  /// harness may leave it an open pipe nobody closes.
  Future<int> _runSync(String path, {required bool asJson}) async {
    final ParsedSync parsed;
    try {
      _requireSyncAlone();
      parsed = parseSyncFile(
        path,
        readBatchFile(path, workingDirectory: specstoneRunner.workingDirectory),
      );
    } on SpecstoneFault catch (fault) {
      return fail(fault, asJson: asJson);
    }
    return runWrite(
      (session) =>
          answerSetSync(session, parsed, codeTarget: targetOf(argResults!)),
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

  /// Throws [IndexFault] `argument_conflict` naming `--dry-run` and the first
  /// of `--field`, `--title`, `--batch`, `--replace`, `--sync`, `--stamp`, or
  /// `--remove-task` that goes beside it.
  void _requireDryRunAlone() {
    final args = argResults!;
    final beside = [
      if (args.option('field') != null) '--field',
      if (args.flag('title')) '--title',
      if (args.option('batch') != null) '--batch',
      if (args.flag('replace')) '--replace',
      if (args.option('sync') != null) '--sync',
      if (args.multiOption('stamp').isNotEmpty) '--stamp',
      if (args.multiOption('remove-task').isNotEmpty) '--remove-task',
    ];
    if (beside.isEmpty) return;
    throw IndexFault(
      IndexFaultCode.argumentConflict,
      '--dry-run takes no ${beside.first}',
    );
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
  /// `--field`, `--title`, `--batch`, `--stamp`, `--remove-task`, or
  /// `--replace` goes beside `--sync`.
  void _requireSyncAlone() {
    final args = argResults!;
    if (args.rest.isEmpty &&
        args.option('base') == null &&
        args.option('field') == null &&
        args.option('batch') == null &&
        args.multiOption('stamp').isEmpty &&
        args.multiOption('remove-task').isEmpty &&
        !args.flag('title') &&
        !args.flag('replace')) {
      return;
    }
    throw IndexFault(
      IndexFaultCode.argumentConflict,
      '--sync takes no doc address, --base, --field, --title, --batch, '
      '--stamp, --remove-task, or --replace',
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
