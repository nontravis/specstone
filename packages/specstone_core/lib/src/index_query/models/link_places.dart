import 'package:specstone_core/src/index_query/models/link_place.dart';
import 'package:specstone_core/src/index_query/models/link_text.dart';

/// The links of a doc: the doc links, which resolve to a `.md` doc other than
/// the doc itself, the file links, every other relative link, the self links,
/// which name the doc itself, a bare `#anchor` included; the [LinkText] of
/// each doc link and self link the scan placed whose text reads as an item ID,
/// and of those whose text reads as a doc address; and whether the scan and
/// `markdown` agree on them (see `readersAgree`), without which a move and the
/// see rule read no href of an inline link.
final class LinkPlaces {
  const new({
    required this.docLinks,
    required this.fileLinks,
    required this.selfLinks,
    required this.texts,
    required this.addressTexts,
    required this.readersAgree,
  });

  final List<LinkPlace> docLinks;
  final List<LinkPlace> fileLinks;
  final List<LinkPlace> selfLinks;
  final List<LinkText> texts;

  /// The links whose text reads as a typed doc address.
  final List<LinkText> addressTexts;

  final bool readersAgree;
}
