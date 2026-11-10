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
            'block, or none. Takes no doc address and no --base; reads no '
            'stdin.',
      )
      ..addFlag('json', negatable: false, help: 'Print JSON instead of text.');
  }

  @override
  String get name => 'set';

  @override
  String get description =>
      'Replace a section, a field, or the title of a doc with stdin, or write '
      'a file of `get` blocks with --batch.';

  @override
  String get invocation =>
      'specstone set <doc address>(#<section key> | '
      '--field <field id> | --title) --base <hash> [--json]\n'
      '       specstone set --batch <file> [--json]';

  @override
  Future<int> run() async {
    final args = argResults!;
    final asJson = args.flag('json');
    final rest = args.rest;
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
        ),
        text,
      ),
      asJson: asJson,
    );
  }

  /// Writes the blocks of the batch file at [path] in one write session.
  ///
  /// The file is read before the session opens. Stdin is never read: a harness
  /// may leave it an open pipe nobody closes.
  Future<int> _runBatch(String path, {required bool asJson}) async {
    final String text;
    try {
      _requireBatchAlone();
      text = readBatchFile(
        path,
        workingDirectory: specstoneRunner.workingDirectory,
      );
    } on SpecstoneFault catch (fault) {
      return fail(fault, asJson: asJson);
    }
    return runWrite(
      (session) => answerSetBatch(session, batchPath: path, text: text),
      asJson: asJson,
    );
  }

  /// Throws [IndexFault] `argument_conflict` when a doc address, `--base`,
  /// `--field`, or `--title` goes beside `--batch`, the file being the only
  /// target.
  void _requireBatchAlone() {
    final args = argResults!;
    if (args.rest.isEmpty &&
        args.option('base') == null &&
        args.option('field') == null &&
        !args.flag('title')) {
      return;
    }
    throw IndexFault(
      IndexFaultCode.argumentConflict,
      '--batch takes no doc address, --base, --field, or --title',
    );
  }
}
