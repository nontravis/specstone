// MARK: - Public

/// Returns the frontmatter key block [text] of [key] with each value token set
/// to what [rename] returns for it; [text] itself when none changes.
///
/// The key line is the first line that is not blank or a `#` comment, so
/// trivia above it stays. A value is read in a flow list (also one spanning
/// lines), a block list, or a scalar, bare or quoted; [rename] gets the value
/// without its quotes and returns null to keep it. Commas, brackets, list
/// markers, comments, and quotes stay as written. [key] is the key as
/// spelled in the block, quotes included.
String renameKeyBlockValues(
  String text,
  String key,
  String? Function(String value) rename,
) {
  final keyAt = _keyLineStart(text);
  if (keyAt < 0 || !text.startsWith(key, keyAt)) return text;
  final colon = text.indexOf(':', keyAt + key.length);
  if (colon < 0) return text;
  final out = StringBuffer(text.substring(0, colon + 1));
  var i = colon + 1;
  while (i < text.length) {
    final end = _skipFiller(text, i);
    if (end > i) {
      out.write(text.substring(i, end));
      i = end;
      continue;
    }
    final token = _tokenAt(text, i);
    final renamed = rename(token.value);
    out.write(
      renamed == null ? text.substring(i, token.end) : token.quoted(renamed),
    );
    i = token.end;
  }
  return out.toString();
}

// MARK: - Scanning

const _filler = ' \t\n,[]';

/// Returns the offset of the first line of [text] that is neither blank nor a
/// comment, or -1.
int _keyLineStart(String text) {
  var lineStart = 0;
  while (lineStart <= text.length) {
    var lineEnd = text.indexOf('\n', lineStart);
    if (lineEnd < 0) lineEnd = text.length;
    final line = text.substring(lineStart, lineEnd).trim();
    if (line.isNotEmpty && !line.startsWith('#')) return lineStart;
    lineStart = lineEnd + 1;
  }
  return -1;
}

/// Returns the offset past the separators, `- ` list markers, and `#` comment
/// that open at [from]; [from] itself when a value opens there.
int _skipFiller(String text, int from) {
  final char = text[from];
  if (char == '#') {
    final lineEnd = text.indexOf('\n', from);
    return lineEnd < 0 ? text.length : lineEnd;
  }
  if (_filler.contains(char)) return from + 1;
  final isMarker =
      char == '-' &&
      (from + 1 == text.length || ' \n'.contains(text[from + 1]));
  return isMarker ? from + 1 : from;
}

typedef _Token = ({String value, int end, String quote});

extension on _Token {
  String quoted(String renamed) => '$quote$renamed$quote';
}

/// Reads the value at [from]: a quoted run, or a bare run up to the next
/// separator.
_Token _tokenAt(String text, int from) {
  final first = text[from];
  if (first == '"' || first == "'") {
    final close = text.indexOf(first, from + 1);
    if (close >= 0) {
      return (
        value: text.substring(from + 1, close),
        end: close + 1,
        quote: first,
      );
    }
  }
  var end = from;
  while (end < text.length && !_filler.contains(text[end])) {
    end++;
  }
  return (value: text.substring(from, end), end: end, quote: '');
}
