import 'package:specstone_core/src/document_writing/models/path_move.dart';
import 'package:specstone_core/src/document_writing/move_item.dart'
    show Renumbering;
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/stale_mentions.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';

/// How the reply of a move names its work.
enum MoveReplyShape {
  /// A move of docs given as arguments, or a reorder or rename.
  docs,

  /// A move of items given as arguments: `--json` holds `renumbered`.
  items,

  /// A plan: `--json` holds `renumbered` and `created`.
  plan,
}

/// One unit a move lands, as the write landed it: its DocPath and address
/// before and after. An item's address is its ID.
final class LandedUnit {
  const new({
    required this.fromDoc,
    required this.fromAddress,
    required this.toDoc,
    required this.toAddress,
    required this.isItem,
  });

  final String fromDoc;
  final String fromAddress;
  final String toDoc;
  final String toAddress;
  final bool isItem;

  /// `<DocPath>#<address>` before the move.
  String get from => '$fromDoc#$fromAddress';

  /// `<DocPath>#<address>` as the write landed it.
  String get to => '$toDoc#$toAddress';
}

/// Returns the reply to a move: one line per [created] doc, per doc move,
/// per unit of [landed], and per new number, a landed item's first and then
/// each of [renumberings], then the
/// written docs, [refreshed] among them, each doc of [deleted], and the
/// mentions; [warnings] go with it.
ReadAnswer moveReplyOf(
  WriteSession session, {
  required MoveReplyShape shape,
  List<String> created = const [],
  List<PathMove> moves = const [],
  List<LandedUnit> landed = const [],
  List<Renumbering> renumberings = const [],
  List<WriteStep> rewrites = const [],
  List<CreateStep> recordCreates = const [],
  List<StaleMention> mentions = const [],
  required bool dryRun,
  List<String> refreshed = const [],
  List<String> deleted = const [],
  List<String> warnings = const [],
}) {
  // A record the move creates is a file it writes, listed with the rewrites;
  // a doc the move rewrites and then deletes is listed as deleted alone.
  final gone = {for (final docPath in deleted) session.projectPathOf(docPath)};
  final written = {
    for (final step in rewrites) step.path,
    for (final step in recordCreates) step.path,
    for (final docPath in refreshed) session.projectPathOf(docPath),
  }.difference(gone).toList()..sort();
  final rewritten = [for (final path in written) session.listedPathOf(path)];
  final renumbered = [
    for (final unit in landed)
      if (unit.isItem && unit.toAddress != unit.fromAddress)
        _NewNumber(unit.toDoc, unit.fromAddress, unit.toAddress),
    for (final Renumbering(:docPath, :oldToNew) in renumberings)
      for (final MapEntry(key: from, value: to) in oldToNew.entries)
        _NewNumber(docPath, from, to),
  ];
  final createVerb = dryRun ? 'creates' : 'created';
  final moveVerb = dryRun ? 'moves' : 'moved';
  final renumberVerb = dryRun ? 'renumbers' : 'renumbered';
  return ReadAnswer(
    text: [
      for (final docPath in created) '$createVerb $docPath\n',
      for (final move in moves) '$moveVerb ${move.from} to ${move.to}\n',
      for (final unit in landed) '$moveVerb ${unit.from} to ${unit.to}\n',
      for (final number in renumbered)
        '$renumberVerb ${number.docPath} ${number.from} to ${number.to}\n',
      for (final path in rewritten)
        '${dryRun ? 'rewrites' : 'rewrote'} $path\n',
      for (final docPath in deleted)
        '${dryRun ? 'deletes' : 'deleted'} $docPath\n',
      for (final mention in mentions) mentionLineOf(mention),
      if (dryRun) _dryRunClosing,
    ].join(),
    json: {
      'moved': [
        for (final move in moves) {'from': move.from, 'to': move.to},
        for (final unit in landed) {'from': unit.from, 'to': unit.to},
      ],
      if (shape != MoveReplyShape.docs)
        'renumbered': [
          for (final number in renumbered)
            {'path': number.docPath, 'from': number.from, 'to': number.to},
        ],
      'rewritten': rewritten,
      'deleted': deleted,
      'mentions': mentionsJsonOf(mentions),
      if (shape == MoveReplyShape.plan) 'created': created,
      if (dryRun) 'dryRun': true,
    },
    warnings: warnings,
  );
}

/// One new number a move gives: the doc that holds the item, its ID before
/// and after.
final class _NewNumber {
  const new(this.docPath, this.from, this.to);

  final String docPath;
  final String from;
  final String to;
}

const _dryRunClosing = 'dry run: nothing moved\n';
