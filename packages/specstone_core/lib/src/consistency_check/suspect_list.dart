import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/tracked_links.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/list_docs.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/index_query/read_session.dart';

/// Returns the docs [answerList] lists that hold a `suspect` link, in order.
///
/// An `unconfirmed` link does not count. [answerList]'s faults come first.
ReadAnswer answerListSuspect(
  ReadSession session,
  String docTypeId,
  ListFilters filters,
) {
  final listed = answerList(session.index, docTypeId, filters);
  final context = CheckContext(session);
  final kept = <IndexedDoc>[
    for (final entry in listed.json['docs']! as List)
      if (session.index.at((entry as Map)['path']! as String) case final doc?
          when context.isChecked(doc) &&
              !context.hasNoParent(doc) &&
              hasSuspectLink(context, doc))
        doc,
  ];
  return ReadAnswer(
    text: [for (final doc in kept) '${docLine(session.index, doc)}\n'].join(),
    json: {
      'docs': [for (final doc in kept) docJson(session.index, doc)],
    },
  );
}
