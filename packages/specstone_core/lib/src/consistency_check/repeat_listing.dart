import 'package:specstone_core/src/consistency_check/check_scope.dart';
import 'package:specstone_core/src/index_query/item_words.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';

/// The fewest normalized words a shared run holds.
const minRepeatRunWords = 8;

/// One item that holds a repeated run.
typedef RepeatItem = ({String docPath, String name, int line, String? item});

/// One maximal run of normalized words and the items of two or more typed
/// docs that hold it.
typedef RepeatGroup = ({String run, List<RepeatItem> items});

/// Returns the repeat groups of the rule-bearing items the index stores.
///
/// Each window of [minRepeatRunWords] words maps to the places (item, word
/// offset) that hold it; a run grows from such a map one word at a time over
/// those places, so the work is linear in the places it reads. A run is listed
/// with every item that holds it whole, when no word extends it for all of
/// those items, so a longer run fewer items hold prints beside the shorter
/// run more items hold. A run the merged pack's template or guide text holds
/// is left out, judged on each call, so a pack change needs no reindex.
/// [scope] keeps each group that holds an item of one of its docs, and drops
/// the items of another code target's docs.
List<RepeatGroup> listRepeats(ReadSession session, CheckScope scope) {
  final names = {for (final doc in session.index.docs) doc.docPath: doc.name};
  final items = [
    for (final item in session.index.ruleItemWords())
      if (scope.inTargets(item.docPath) && names.containsKey(item.docPath))
        item,
  ];
  final finder = _RunFinder(
    [for (final item in items) item.words],
    [for (final item in items) item.docPath],
  );
  final template = _templateWindows(session);
  final groups = <String, RepeatGroup>{};
  for (final run in finder.runs()) {
    if (_windowsOf(run.words).every(template.contains)) continue;
    if (!run.items.any((i) => scope.contains(items[i].docPath))) continue;
    final text = run.words.join(' ');
    groups.putIfAbsent(
      '$text\u0000${run.items.join(',')}',
      () => (
        run: text,
        items: _sortedItems([
          for (final i in run.items)
            (
              docPath: items[i].docPath,
              name: names[items[i].docPath] ?? items[i].docPath,
              line: items[i].line,
              item: items[i].itemId,
            ),
        ]),
      ),
    );
  }
  return groups.values.toList()..sort(_compareGroups);
}

List<String> _windowsOf(List<String> words) => [
  for (var p = 0; p + minRepeatRunWords <= words.length; p++)
    words.sublist(p, p + minRepeatRunWords).join(' '),
];

typedef _Run = ({List<String> words, List<int> items});

/// Finds the maximal runs of the words of many items.
///
/// A place is one int, the item index above [_offsetBits] and the word offset
/// of a run's first word below.
final class _RunFinder {
  const new(this._words, this._paths);

  final List<List<String>> _words;
  final List<String> _paths;

  static const _offsetBits = 24;
  static const int _offsetMask = (1 << _offsetBits) - 1;

  int _itemOf(int place) => place >> _offsetBits;

  int _offsetOf(int place) => place & _offsetMask;

  /// Returns each run that two or more docs hold, once, with the items that
  /// hold it whole.
  Iterable<_Run> runs() sync* {
    final held = <String, List<int>>{};
    for (var item = 0; item < _words.length; item++) {
      final words = _words[item];
      for (var at = 0; at + minRepeatRunWords <= words.length; at++) {
        held
            .putIfAbsent(
              words.sublist(at, at + minRepeatRunWords).join(' '),
              () => [],
            )
            .add(item << _offsetBits | at);
      }
    }
    for (final places in held.values) {
      if (_spansDocs(places) && !_sharePrevious(places)) yield* _grow(places);
    }
  }

  Iterable<_Run> _grow(List<int> start) sync* {
    final pending = [(places: start, length: minRepeatRunWords)];
    while (pending.isNotEmpty) {
      final (:places, length: startLength) = pending.removeLast();
      var length = startLength;
      while (_allFollowedBySameWord(places, length)) {
        length++;
      }
      final next = <String, List<int>>{};
      for (final place in places) {
        final words = _words[_itemOf(place)];
        final end = _offsetOf(place) + length;
        if (end < words.length) {
          next.putIfAbsent(words[end], () => []).add(place);
        }
      }
      final items = _itemsOf(places);
      final extendsRight = next.values.any(
        (bucket) => _itemsOf(bucket).length == items.length,
      );
      if (!extendsRight && _spansDocs(places) && !_extendsLeft(places)) {
        final first = places.first;
        yield (
          words: _words[_itemOf(first)].sublist(
            _offsetOf(first),
            _offsetOf(first) + length,
          ),
          items: items,
        );
      }
      for (final bucket in next.values) {
        if (_spansDocs(bucket)) {
          pending.add((places: bucket, length: length + 1));
        }
      }
    }
  }

  /// Whether one same word follows the first [length] words at every place,
  /// so the run grows for all of them.
  bool _allFollowedBySameWord(List<int> places, int length) {
    String? following;
    for (final place in places) {
      final words = _words[_itemOf(place)];
      final end = _offsetOf(place) + length;
      if (end >= words.length) return false;
      if (following != null && following != words[end]) return false;
      following = words[end];
    }
    return true;
  }

  /// Whether every place is preceded by one same word.
  bool _sharePrevious(List<int> places) {
    String? previous;
    for (final place in places) {
      final offset = _offsetOf(place);
      if (offset == 0) return false;
      final word = _words[_itemOf(place)][offset - 1];
      if (previous != null && previous != word) return false;
      previous = word;
    }
    return true;
  }

  /// Whether one word precedes the run in every item that holds it.
  bool _extendsLeft(List<int> places) {
    Set<String>? common;
    var at = 0;
    while (at < places.length) {
      final item = _itemOf(places[at]);
      final before = <String>{};
      for (; at < places.length && _itemOf(places[at]) == item; at++) {
        final offset = _offsetOf(places[at]);
        if (offset > 0) before.add(_words[item][offset - 1]);
      }
      common = common == null ? before : (common..retainAll(before));
      if (common.isEmpty) return false;
    }
    return common != null;
  }

  List<int> _itemsOf(List<int> places) => [
    for (var at = 0; at < places.length; at++)
      if (at == 0 || _itemOf(places[at]) != _itemOf(places[at - 1]))
        _itemOf(places[at]),
  ];

  bool _spansDocs(List<int> places) {
    final first = _paths[_itemOf(places.first)];
    return places.any((place) => _paths[_itemOf(place)] != first);
  }
}

/// Returns the windows of every doc type's template and guide text, worded as
/// the items are.
Set<String> _templateWindows(ReadSession session) {
  final docTypes = session.project.set.docTypes;
  final idPrefixes = itemIdPrefixesOf(docTypes);
  return {
    for (final type in docTypes)
      ..._windowsOf(
        normalizedWordsOf(type.renderGuide(), idPrefixes: idPrefixes),
      ),
  };
}

List<RepeatItem> _sortedItems(List<RepeatItem> items) =>
    items..sort(_compareItems);

int _compareItems(RepeatItem a, RepeatItem b) {
  final byPath = compareCodePoints(a.docPath, b.docPath);
  return byPath != 0 ? byPath : a.line.compareTo(b.line);
}

int _compareGroups(RepeatGroup a, RepeatGroup b) {
  final byFirst = _compareItems(a.items.first, b.items.first);
  return byFirst != 0 ? byFirst : compareCodePoints(a.run, b.run);
}

/// The repeat groups of one `check --repeats` run.
final class RepeatReport {
  const new(this.groups, {this.warnings = const []});

  /// The groups, sorted by their first item.
  final List<RepeatGroup> groups;

  /// The read session's warnings; no finding states any of them.
  final List<String> warnings;

  /// Each group's lines, then the count line; every line ends in `\n`.
  String get text => [
    for (final group in groups) ...[
      'repeat: "${group.run}"',
      for (final item in group.items)
        '${item.docPath}:${item.line}: ${item.name} ${item.item ?? '—'}',
    ],
    if (groups.length == 1)
      '1 repeat group'
    else
      '${groups.length} repeat groups',
  ].map((line) => '$line\n').join();

  /// The JSON object: `repeats`, `count`, and `warnings` when non-empty.
  Map<String, Object> get json => {
    'repeats': [
      for (final group in groups)
        {
          'run': group.run,
          'items': [
            for (final item in group.items)
              {
                'docPath': item.docPath,
                'name': item.name,
                'line': item.line,
                'item': item.item,
              },
          ],
        },
    ],
    'count': groups.length,
    if (warnings.isNotEmpty) 'warnings': warnings,
  };
}
