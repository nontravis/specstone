/// The form of a Specstone version, unanchored so the install scripts copy it.
///
/// Semver 2.0.0 without build metadata, ASCII classes only. Dart readers of
/// untrusted text parse through [ReleaseVersion.tryParse].
const String releaseVersionPattern =
    r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'
    '(-(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)'
    r'(\.(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*)?';

final RegExp _field = RegExp(r'^(0|[1-9][0-9]*)$');
final RegExp _identifier = RegExp(
  r'^(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)$',
);
final RegExp _digitsOnly = RegExp(r'^[0-9]+$');

/// A version in the [releaseVersionPattern] form, ordered by semver precedence.
///
/// The fields stay digit strings: a field or identifier of any length
/// compares in linear time, and no regex repeats a group over the text.
final class ReleaseVersion implements Comparable<ReleaseVersion> {
  new _(this._text, this._fields, this._preRelease);

  /// Parses [text] when the whole text is the form, else returns null.
  static ReleaseVersion? tryParse(String text) {
    final dash = text.indexOf('-');
    final fields = (dash < 0 ? text : text.substring(0, dash)).split('.');
    if (fields.length != 3 || !fields.every(_field.hasMatch)) return null;
    final preRelease = dash < 0
        ? const <String>[]
        : text.substring(dash + 1).split('.');
    if (!preRelease.every(_identifier.hasMatch)) return null;
    return ReleaseVersion._(text, fields, preRelease);
  }

  final String _text;
  final List<String> _fields;
  final List<String> _preRelease;

  /// Whether a pre-release part follows the three numeric fields.
  bool get isPreRelease => _preRelease.isNotEmpty;

  @override
  int compareTo(ReleaseVersion other) {
    for (var i = 0; i < _fields.length; i++) {
      final order = _compareNumbers(_fields[i], other._fields[i]);
      if (order != 0) return order;
    }
    if (isPreRelease != other.isPreRelease) return isPreRelease ? -1 : 1;
    final shared = _preRelease.length < other._preRelease.length
        ? _preRelease.length
        : other._preRelease.length;
    for (var i = 0; i < shared; i++) {
      final order = _compareIdentifier(_preRelease[i], other._preRelease[i]);
      if (order != 0) return order;
    }
    return _preRelease.length.compareTo(other._preRelease.length);
  }

  @override
  String toString() => _text;
}

int _compareIdentifier(String a, String b) {
  final aIsNumber = _digitsOnly.hasMatch(a);
  final bIsNumber = _digitsOnly.hasMatch(b);
  if (aIsNumber && bIsNumber) return _compareNumbers(a, b);
  if (aIsNumber != bIsNumber) return aIsNumber ? -1 : 1;
  return a.compareTo(b);
}

/// Compares two digit strings without a leading zero by value: the longer is
/// the greater, equal lengths compare digit by digit.
int _compareNumbers(String a, String b) =>
    a.length == b.length ? a.compareTo(b) : a.length.compareTo(b.length);
