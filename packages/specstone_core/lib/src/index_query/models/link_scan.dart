import 'package:specstone_core/src/doc_model/models/text_range.dart';
import 'package:specstone_core/src/index_query/models/link_source.dart';
import 'package:specstone_core/src/index_query/models/scanned_destination.dart';

/// What one link scan of a body reads: its link sources, its prose, and the
/// range of each link destination as written, and the range of each link
/// reference definition label.
///
/// `prose` is the body with every code unit that is no prose blanked to a
/// space, line ends and length kept: what `markdown` never reads as inline
/// text (see `leafTextOf`), and in the inline text each code span, autolink,
/// GFM bare URL or email, raw HTML run, and inline link's parenthesized
/// destination and title. Link text, a full reference's label, and a
/// definition's label stay. `destinations` hold each inline link's
/// destination and each definition's.
final class LinkScan {
  const new({
    required this.sources,
    required this.prose,
    required this.destinations,
    required this.definitionLabels,
  });

  final List<LinkSource> sources;
  final String prose;
  final List<ScannedDestination> destinations;
  final List<TextRange> definitionLabels;
}
