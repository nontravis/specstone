import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';

const _sectionSeparator = '#';

/// Returns the text of each doc [address] names, or of one of its sections.
///
/// [address] is a name as `resolve` takes it, then `#` and a section key to
/// keep that section of each doc that holds it. A whole doc prints as written.
/// Throws an [IndexFault] when no doc carries the name, or when no resolved
/// doc holds a section with the key.
ReadAnswer answerGet(DocIndex index, String address) {
  final hash = address.indexOf(_sectionSeparator);
  final name = hash < 0 ? address : address.substring(0, hash);
  final key = hash < 0 ? null : address.substring(hash + 1);

  final blocks = <(IndexedDoc, String)>[];
  for (final doc in index.resolve(name)) {
    final content = index.contentOf(doc);
    if (key == null) {
      blocks.add((doc, content.text));
      continue;
    }
    final held = [
      for (final section in content.sections)
        if (section.key == key) '${section.text}\n',
    ];
    if (held.isNotEmpty) blocks.add((doc, held.join()));
  }
  if (blocks.isEmpty) {
    throw IndexFault(
      IndexFaultCode.sectionNotFound,
      'no doc named $name holds a section with the key $key',
    );
  }

  return ReadAnswer(
    text: [for (final (doc, text) in blocks) '${namingLine(doc)}\n$text']
        .join('\n'),
    json: {
      'docs': [
        for (final (doc, text) in blocks)
          {
            'name': doc.name,
            'docType': ?doc.docTypeId,
            'path': doc.docPath,
            'section': ?key,
            'text': text,
          },
      ],
    },
  );
}
