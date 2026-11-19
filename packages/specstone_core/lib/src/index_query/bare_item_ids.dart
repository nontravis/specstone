import 'package:specstone_core/src/doc_model/models/item_id_at.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show itemIdRunAt, itemIdsInProse;
import 'package:specstone_core/src/document_writing/body_scan.dart';
import 'package:specstone_core/src/index_query/models/bare_item_id.dart';
import 'package:specstone_core/src/index_query/models/cite_form.dart';
import 'package:specstone_core/src/index_query/models/link_source.dart';

const _lineFeed = 0x0A;
const _space = 0x20;

/// Returns the bare item IDs of [lfText], a typed doc with LF line ends, in
/// file order.
///
/// A bare ID is a token of [idPrefixes] outside a code span, a link text,
/// frontmatter, and fenced code. Its citation is the cite of [citeForms] or the
/// link whose item-ID run holds it, as written; none when no run holds it.
List<BareItemId> bareItemIdsOf(
  String lfText, {
  required Set<String> idPrefixes,
  required List<CiteForm> citeForms,
}) {
  final body = BodyScan(lfText);
  final ids = itemIdsInProse(
    _outsideLinks(body.scan.prose, body.scan.sources),
    prefixes: idPrefixes,
  );
  if (ids.isEmpty) return const [];
  final citations = {
    ..._linkCitationsOf(body, idPrefixes),
    ..._citeCitationsOf(body, citeForms),
  };
  return [
    for (final ItemIdAt(:at, :id) in ids)
      BareItemId(
        line: body.fileLineOf(at),
        column: body.columnOf(at),
        id: id.written,
        citation: citations[at],
      ),
  ];
}

/// Returns the citation of each ID that follows a link in its run, by the
/// body offset of the ID.
Map<int, BareIdCitation> _linkCitationsOf(
  BodyScan body,
  Set<String> idPrefixes,
) {
  final lines = body.body.split('\n');
  final cited = <int, BareIdCitation>{};
  for (final LinkSource(:offset, :end, :shown) in body.scan.sources) {
    if (shown == null) continue;
    final lineIndex = body.fileLineOf(offset) - body.firstLine;
    final lineStart = body.starts[lineIndex];
    final run = itemIdRunAt(
      lines[lineIndex],
      end - lineStart,
      prefixes: idPrefixes,
    );
    for (final item in run) {
      cited.putIfAbsent(
        lineStart + item.at,
        () => LinkCitation(destination: shown),
      );
    }
  }
  return cited;
}

/// Returns the citation of each ID of a cite form's run, by the body offset of
/// the ID.
Map<int, BareIdCitation> _citeCitationsOf(
  BodyScan body,
  List<CiteForm> citeForms,
) {
  final cited = <int, BareIdCitation>{};
  for (final CiteForm(:candidate, :items) in citeForms) {
    final lineStart = body.starts[candidate.line - body.firstLine];
    for (final item in items) {
      cited.putIfAbsent(
        lineStart + item.column,
        () => CiteCitation(written: candidate.written),
      );
    }
  }
  return cited;
}

/// Returns [prose] with each of [sources] blanked, line ends kept.
String _outsideLinks(String prose, List<LinkSource> sources) {
  final units = prose.codeUnits.toList();
  for (final source in sources) {
    for (var at = source.offset; at < source.end && at < units.length; at++) {
      if (units[at] != _lineFeed) units[at] = _space;
    }
  }
  return String.fromCharCodes(units);
}
