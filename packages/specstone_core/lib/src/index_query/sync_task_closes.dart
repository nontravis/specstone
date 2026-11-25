import 'dart:convert';

const _word = r'[\p{L}\p{N}_-]';
const _closingWords =
    'closes|closed|close|fixes|fixed|fix|resolves|resolved|resolve';

/// A whole-word closing word, an optional `:`, and the gap before the list.
final RegExp _keyword = RegExp(
  '(?<!$_word)(?:$_closingWords)(?!$_word):?[ \\t]+',
  caseSensitive: false,
  unicode: true,
);

/// A `#` and a closing word or `done` that no word character follows.
final RegExp _command = RegExp(
  '#(?:$_closingWords|done)(?!$_word)',
  caseSensitive: false,
  unicode: true,
);

/// What parts two tokens of a list: a `,`, `and`, or `, and`.
final RegExp _separator = RegExp(
  r'[ \t]*,[ \t]*(?:and[ \t]+)?|[ \t]+and[ \t]+',
);

final RegExp _wordChar = RegExp('^$_word', unicode: true);

/// Returns the candidates of [candidates] that [message] closes.
///
/// A candidate occurs where no letter, digit, `-`, or `_` stands right before
/// or after it, case-sensitive. An occurrence closes it when it starts a token
/// of a list that follows a closing word, or when a `#` and a closing word or
/// `done` follow it on the same line; any other occurrence is a mention.
Set<String> closedTasks(String message, Set<String> candidates) {
  if (candidates.isEmpty) return const {};
  final closed = <String>{};
  for (final line in const LineSplitter().convert(message)) {
    closed
      ..addAll(_closedByKeyword(line, candidates))
      ..addAll(_closedByCommand(line, candidates));
  }
  return closed;
}

Iterable<String> _closedByKeyword(String line, Set<String> candidates) sync* {
  for (final keyword in _keyword.allMatches(line)) {
    var at = keyword.end;
    while (true) {
      var tokenEnd = _tokenEnd(line, at);
      for (final task in candidates) {
        if (line.startsWith(task, at) && !_isWordAt(line, at + task.length)) {
          yield task;
          if (at + task.length > tokenEnd) tokenEnd = at + task.length;
        }
      }
      if (tokenEnd == at) break;
      final separator = _separator.matchAsPrefix(line, tokenEnd);
      if (separator == null) break;
      at = separator.end;
    }
  }
}

Iterable<String> _closedByCommand(String line, Set<String> candidates) sync* {
  for (final task in candidates) {
    final occurrence = RegExp(
      '(?<!$_word)${RegExp.escape(task)}(?!$_word)',
      unicode: true,
    );
    for (final match in occurrence.allMatches(line)) {
      if (_command.hasMatch(line.substring(match.end))) {
        yield task;
        break;
      }
    }
  }
}

/// Returns the index of the first space, tab, or `,` at or after [from].
int _tokenEnd(String line, int from) {
  var end = from;
  while (end < line.length && !' \t,'.contains(line[end])) {
    end++;
  }
  return end;
}

bool _isWordAt(String line, int index) =>
    index < line.length && _wordChar.hasMatch(line.substring(index));
