import 'package:specstone_core/src/doc_model/models/item_id_at.dart';
import 'package:specstone_core/src/doc_model/models/text_range.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show itemIdRunAt, itemIdsInProse;
import 'package:specstone_core/src/document_writing/body_scan.dart';
import 'package:specstone_core/src/index_query/item_words.dart'
    show scenarioRefPrefix;
import 'package:specstone_core/src/index_query/models/bare_item_id.dart';
import 'package:specstone_core/src/index_query/models/cite_form.dart';
import 'package:specstone_core/src/index_query/models/link_scan.dart';
import 'package:specstone_core/src/index_query/models/link_source.dart';

const _lineFeed = 0x0A;
const _space = 0x20;

/// Returns the bare item IDs of [lfText], a typed doc with LF line ends, in
/// file order.
///
/// A bare ID is a token of [idPrefixes] outside a code span, a link text,
/// frontmatter, and fenced code. Its citation is the cite of [citeForms] or the
/// link whose item-ID run holds it, as written; none when no run holds it.
///
/// A run reads the scenario ref prefix as `citeFormsOf` does, but a scenario
/// ref is no ID unless [includeScenarioRefs]; the index stores none.
List<BareItemId> bareItemIdsOf(
  String lfText, {
  required Set<String> idPrefixes,
  required List<CiteForm> citeForms,
  bool includeScenarioRefs = false,
}) {
  final body = BodyScan(lfText);
  final ids = itemIdsInProse(
    _outsideLinks(body.scan),
    prefixes: includeScenarioRefs
        ? idPrefixes
        : idPrefixes.difference({scenarioRefPrefix}),
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

/// Returns the citation of each ID that follows a link in its run, read on the
/// line the link ends, by the body offset of the ID.
Map<int, BareIdCitation> _linkCitationsOf(
  BodyScan body,
  Set<String> idPrefixes,
) {
  final lines = body.body.split('\n');
  final cited = <int, BareIdCitation>{};
  for (final LinkSource(:end, :shown) in body.scan.sources) {
    if (shown == null) continue;
    final endIndex = body.fileLineOf(end) - body.firstLine;
    final lineStart = body.starts[endIndex];
    final run = itemIdRunAt(
      lines[endIndex],
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

/// Returns the prose of [scan] with each link source and each link reference
/// definition label blanked, line ends kept.
String _outsideLinks(LinkScan scan) {
  if (scan.sources.isEmpty && scan.definitionLabels.isEmpty) return scan.prose;
  final units = scan.prose.codeUnits.toList();
  void blank(int start, int end) {
    for (var at = start; at < end && at < units.length; at++) {
      if (units[at] != _lineFeed) units[at] = _space;
    }
  }

  for (final LinkSource(:offset, :end) in scan.sources) {
    blank(offset, end);
  }
  for (final TextRange(:start, :end) in scan.definitionLabels) {
    blank(start, end);
  }
  return String.fromCharCodes(units);
}
