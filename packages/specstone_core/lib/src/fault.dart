/// A failure the CLI reports as an error envelope and a process exit status.
///
/// Every fault in the core package implements this, so the command runner
/// prints and exits on one shape.
abstract interface class SpecstoneFault implements Exception {
  /// The process exit status for this fault.
  int get exitStatus;

  /// Returns the JSON envelope `{'error': {...}}` printed under `--json`.
  Map<String, Object> toJson();

  /// Returns the stderr form `<file>[:<line>][: <key>]: <message>`.
  String toText();
}
