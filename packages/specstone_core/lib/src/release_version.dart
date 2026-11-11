/// The form of a Specstone version, unanchored so each reader composes it.
///
/// Semver 2.0.0 without build metadata, ASCII classes only.
const String releaseVersionPattern =
    r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'
    '(-(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)'
    r'(\.(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*)?';

final RegExp _form = RegExp('^$releaseVersionPattern\$');
final RegExp _digitsOnly = RegExp(r'^[0-9]+$');

/// A version in the [releaseVersionPattern] form, ordered by semver precedence.
final class ReleaseVersion implements Comparable<ReleaseVersion> {
  new _(this._text, this._fields, this._preRelease);

  /// Parses [text] when the whole text is the form, else returns null.
  static ReleaseVersion? tryParse(String text) {
    if (!_form.hasMatch(text)) return null;
    final dash = text.indexOf('-');
    final core = dash < 0 ? text : text.substring(0, dash);
    final preRelease = dash < 0 ? '' : text.substring(dash + 1);
    return ReleaseVersion._(text, [
      for (final field in core.split('.')) BigInt.parse(field),
    ], preRelease.isEmpty ? const [] : preRelease.split('.'));
  }

  final String _text;
  final List<BigInt> _fields;
  final List<String> _preRelease;

  /// Whether a pre-release part follows the three numeric fields.
  bool get isPreRelease => _preRelease.isNotEmpty;

  @override
  int compareTo(ReleaseVersion other) {
    for (var i = 0; i < _fields.length; i++) {
      final order = _fields[i].compareTo(other._fields[i]);
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
  if (aIsNumber && bIsNumber) return BigInt.parse(a).compareTo(BigInt.parse(b));
  if (aIsNumber != bIsNumber) return aIsNumber ? -1 : 1;
  return a.compareTo(b);
}
