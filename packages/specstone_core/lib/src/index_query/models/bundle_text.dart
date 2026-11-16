import 'package:specstone_core/src/index_query/models/bundle_entry.dart';

/// One file's text of a bundle: the text, each doc and part it prints in
/// print order, and its est. token size as its closing line gives it.
final class BundleText {
  const new({required this.text, required this.entries, required this.tokens});

  final String text;
  final List<BundleEntry> entries;
  final int tokens;
}
