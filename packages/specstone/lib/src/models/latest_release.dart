import 'package:specstone_core/release_version.dart';

/// The Version of the latest full release, or null with the reason the read
/// failed.
final class LatestRelease {
  const new({required this.version, required this.failure});

  final ReleaseVersion? version;
  final String? failure;
}
