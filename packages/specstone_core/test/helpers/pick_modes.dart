import 'package:specstone_core/src/index_query/bundle.dart';

/// The modes that pick docs; `sync` and `review` bundle none.
final List<BundleMode> pickModes = [
  for (final mode in BundleMode.values)
    if (mode != BundleMode.sync && mode != BundleMode.review) mode,
];
