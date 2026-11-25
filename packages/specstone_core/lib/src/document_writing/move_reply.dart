import 'package:specstone_core/src/document_writing/keyed_units.dart'
    show KeyedLanding;
import 'package:specstone_core/src/document_writing/models/path_move.dart';
import 'package:specstone_core/src/document_writing/move_item.dart';
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

/// Returns the reply to a move: one line per [created] doc, per doc move,
/// per item of [landings], per block or row address of [keyed], and per new
/// number, a landed item's first and then each of [renumberings], then the
/// written docs and the mentions.
ReadAnswer moveReplyOf(
  WriteSession session, {
  required MoveReplyShape shape,
  List<String> created = const [],
  List<PathMove> moves = const [],
  List<ItemLanding> landings = const [],
  List<KeyedLanding> keyed = const [],
  List<Renumbering> renumberings = const [],
  List<WriteStep> rewrites = const [],
  List<CreateStep> recordCreates = const [],
  List<StaleMention> mentions = const [],
  required bool dryRun,
}) {
  // A record the move creates is a file it writes, listed with the rewrites.
  final written = [
    for (final step in rewrites) step.path,
    for (final step in recordCreates) step.path,
  ]..sort();
  final rewritten = [for (final path in written) session.listedPathOf(path)];
  final renumbered = [
    for (final landing in landings)
      if (landing.newId != landing.from.id)
        _NewNumber(landing.to.docPath, landing.from.id, landing.newId),
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
      for (final landing in landings)
        '$moveVerb ${_sourceOf(landing)} to ${_destinationOf(landing)}\n',
      for (final landing in keyed) _keyedLineOf(moveVerb, landing),
      for (final number in renumbered)
        '$renumberVerb ${number.docPath} ${number.from} to ${number.to}\n',
      for (final path in rewritten)
        '${dryRun ? 'rewrites' : 'rewrote'} $path\n',
      for (final mention in mentions) mentionLineOf(mention),
      if (dryRun) _dryRunClosing,
    ].join(),
    json: {
      'moved': [
        for (final move in moves) {'from': move.from, 'to': move.to},
        for (final landing in landings)
          {'from': _sourceOf(landing), 'to': _destinationOf(landing)},
        for (final landing in keyed)
          {'from': _keyedSourceOf(landing), 'to': _keyedDestinationOf(landing)},
      ],
      if (shape != MoveReplyShape.docs)
        'renumbered': [
          for (final number in renumbered)
            {'path': number.docPath, 'from': number.from, 'to': number.to},
        ],
      'rewritten': rewritten,
      'mentions': mentionsJsonOf(mentions),
      if (shape == MoveReplyShape.plan) 'created': created,
      if (dryRun) 'dryRun': true,
    },
  );
}

String _sourceOf(ItemLanding landing) =>
    '${landing.from.doc.docPath}#${landing.from.id}';

String _destinationOf(ItemLanding landing) =>
    '${landing.to.docPath}#${landing.newId}';

String _keyedLineOf(String verb, KeyedLanding landing) {
  final to = _keyedDestinationOf(landing);
  return '$verb ${_keyedSourceOf(landing)} to $to\n';
}

String _keyedSourceOf(KeyedLanding landing) =>
    '${landing.from.docPath}#${landing.address}';

String _keyedDestinationOf(KeyedLanding landing) =>
    '${landing.to.docPath}#${landing.address}';

/// One new number a move gives: the doc that holds the item, its ID before
/// and after.
final class _NewNumber {
  const new(this.docPath, this.from, this.to);

  final String docPath;
  final String from;
  final String to;
}

const _dryRunClosing = 'dry run: nothing moved\n';
