import 'package:specstone_core/src/index_query/models/link_cite.dart';
import 'package:specstone_core/src/index_query/models/link_text.dart';

/// A link with the cite `classifyLink` gives it.
final class ClassifiedLink {
  const new({required this.link, required this.cite});

  final LinkText link;
  final LinkCite cite;
}
