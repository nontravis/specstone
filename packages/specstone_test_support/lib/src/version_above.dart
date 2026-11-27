/// Returns `'<major + 1>.0.0'` for a semver [version], pre-release or not.
///
/// Callers pass `specstoneVersion`, so this package imports no core.
String versionAbove(String version) {
  final major = int.parse(version.split(RegExp('[.-]')).first);
  return '${major + 1}.0.0';
}
