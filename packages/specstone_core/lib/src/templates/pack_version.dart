import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:yaml/yaml.dart';

final _versionPattern = RegExp(r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$');

/// A pack version `major.minor.patch`, ordered by semver precedence.
final class PackVersion implements Comparable<PackVersion> {
  new _(this.major, this.minor, this.patch);

  /// Parses [text] as `major.minor.patch` with no leading zeros.
  ///
  /// Throws `pack_version_invalid` naming [file] and [key] otherwise.
  static PackVersion parse(
    String text, {
    required String file,
    required String key,
  }) {
    final match = _versionPattern.firstMatch(text);
    if (match == null) throw _invalid(text, file: file, key: key);
    final major = int.tryParse(match[1]!);
    final minor = int.tryParse(match[2]!);
    final patch = int.tryParse(match[3]!);
    if (major == null || minor == null || patch == null) {
      throw _invalid(text, file: file, key: key);
    }
    return PackVersion._(major, minor, patch);
  }

  /// Reads a version from a YAML [node] by its written text.
  ///
  /// A string is read as is; any other scalar, such as the double in `1.10`,
  /// is read from its source text so it keeps the form the author wrote. A
  /// list or a mapping is `pack_version_invalid`.
  static PackVersion fromYaml(
    YamlNode node, {
    required String file,
    required String key,
  }) => switch (node) {
    YamlScalar(:final String value) => parse(value, file: file, key: key),
    YamlScalar(:final span) => parse(span.text, file: file, key: key),
    _ => throw _invalid('a list or mapping', file: file, key: key),
  };

  /// The major number.
  final int major;

  /// The minor number.
  final int minor;

  /// The patch number.
  final int patch;

  @override
  int compareTo(PackVersion other) {
    final byMajor = major.compareTo(other.major);
    if (byMajor != 0) return byMajor;
    final byMinor = minor.compareTo(other.minor);
    if (byMinor != 0) return byMinor;
    return patch.compareTo(other.patch);
  }

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is PackVersion &&
      major == other.major &&
      minor == other.minor &&
      patch == other.patch;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

TemplateFault _invalid(
  String found, {
  required String file,
  required String key,
}) => TemplateFault(
  FaultCode.packVersionInvalid,
  'the version must be major.minor.patch with no leading zeros, '
  'such as 1.2.0; found $found',
  file: file,
  key: key,
);
