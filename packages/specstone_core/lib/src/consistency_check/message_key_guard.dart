const _valueExtensions = ['.md', '.yaml', '.dart'];
const _trimmedCharacters = ".,;:!?()[]{}<>'`…";

final _quotedSpan = RegExp('"[^"]*"');

/// A `<word>` placeholder: a form the message prints to write, not a value.
final _placeholder = RegExp('<[A-Za-z][A-Za-z0-9_-]*>');
final _markdownLink = RegExp(r'\[[^\]]*\]\([^)\s]*\)');

/// Returns each value [message] names that no part of [path], [name], or a
/// value in [keys] holds.
List<String> unheldMessageValues({
  required String message,
  required String path,
  String? name,
  required Map<String, Object> keys,
}) {
  final holders = [path, ?name, ..._keyTexts(keys)];
  return [
    for (final value in _messageValues(message))
      if (!_isHeld(value, holders)) value,
  ];
}

Iterable<String> _keyTexts(Map<String, Object> keys) sync* {
  for (final value in keys.values) {
    if (value is Iterable<Object?>) {
      for (final element in value) {
        yield '$element';
      }
    } else {
      yield '$value';
    }
  }
}

List<String> _messageValues(String message) {
  final unquoted = message.replaceAll(_quotedSpan, ' ');
  final links = [
    for (final m in _markdownLink.allMatches(unquoted))
      if (!_isPlaceholderForm(m[0]!)) m[0]!,
  ];
  final words = unquoted
      .replaceAll(_markdownLink, ' ')
      .split(RegExp(r'\s+'))
      .where((token) => !_isPlaceholderForm(token))
      .map(_trim)
      .where(_isValueShaped);
  return [...links, ...words];
}

bool _isPlaceholderForm(String token) => _placeholder.hasMatch(token);

String _trim(String token) {
  var start = 0;
  var end = token.length;
  while (start < end && _trimmedCharacters.contains(token[start])) {
    start++;
  }
  while (end > start && _trimmedCharacters.contains(token[end - 1])) {
    end--;
  }
  return token.substring(start, end);
}

bool _isValueShaped(String token) =>
    token.contains('/') || _valueExtensions.any(token.endsWith);

bool _isHeld(String value, List<String> holders) => value
    .split('#')
    .where((part) => part.isNotEmpty)
    .every((part) => holders.any((holder) => holder.contains(part)));
