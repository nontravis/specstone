/// One listed file of a code folder: its path from the code root, and its
/// fingerprint.
final class FileFingerprint {
  const new({required this.path, required this.fingerprint});

  final String path;
  final String fingerprint;
}
