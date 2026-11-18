import 'package:specstone_core/src/index_query/models/link_place.dart';
import 'package:specstone_core/src/index_query/models/link_text.dart';

/// The links of a doc: the doc links, which resolve to a `.md` doc other than
/// the doc itself, the file links, every other relative link, the self links,
/// which name the doc itself, a bare `#anchor` included; the [LinkText] of
/// each doc link and self link the scan placed; and whether the scan and
/// `markdown` agree on them (see `readersAgree`), without which a move, the
/// see rule, and the renumber pass read no href of an inline link.
final class LinkPlaces {
  const new({
    required this.docLinks,
    required this.fileLinks,
    required this.selfLinks,
    required this.texts,
    required this.readersAgree,
  });

  final List<LinkPlace> docLinks;
  final List<LinkPlace> fileLinks;
  final List<LinkPlace> selfLinks;
  final List<LinkText> texts;
  final bool readersAgree;
}
