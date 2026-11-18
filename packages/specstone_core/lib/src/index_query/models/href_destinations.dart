import 'package:specstone_core/src/index_query/models/href_destination.dart';

/// The destinations of a link scan that have an href, and whether `markdown`
/// read the links: false when it fails on the body, which leaves every
/// destination without one, or the readers disagree (see `readersAgree`),
/// which leaves each inline link's without one; true when no destination
/// needed the read.
final class HrefDestinations {
  const new({required this.destinations, required this.linksRead});

  final List<HrefDestination> destinations;
  final bool linksRead;
}
