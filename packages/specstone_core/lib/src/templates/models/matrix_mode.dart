/// The Verification matrix mode the config's `verification_coverage:` names.
enum MatrixMode {
  off,
  fr,
  edgeCase;

  /// Whether the matrix is on: any mode but [off].
  bool get isOn => this != off;
}
