import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/fingerprint.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show edgeCasesSectionKey;
import 'package:specstone_core/src/index_query/indexed_doc.dart';

const List<String> _contractSectionKeys = [
  'statement',
  'input_output',
  edgeCasesSectionKey,
];

final _headingMarks = RegExp(r'^#+\s*');

/// The sections of an FR a per-FR matrix row records its fingerprint against.
final class ContractBlock {
  const new({required this.text, required this.headings});

  /// The sections laid out as `format` lays them out, one blank line between
  /// them, the last ended by one line break.
  final String text;

  /// The headings present, in doc order, as `Input / Output`.
  final List<String> headings;
}

/// Returns the contract block of [fr]: its `statement`, `input_output`, and
/// `edge_cases` sections, each from its heading line to the next `## `
/// heading, in doc order.
///
/// A missing section adds nothing; null when [fr] holds none of the three.
ContractBlock? contractBlockOf(CheckContext context, IndexedDoc fr) {
  final held = [
    for (final key in _contractSectionKeys) ?context.heldIndexOf(fr, key),
  ]..sort();
  if (held.isEmpty) return null;
  final sections = [
    for (final index in held) context.contentOf(fr).sections[index],
  ];
  return ContractBlock(
    text: [for (final section in sections) upstreamText(section.text)]
        .join('\n'),
    headings: [
      for (final section in sections)
        section.headerLine.replaceFirst(_headingMarks, '').trim(),
    ],
  );
}
