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

/// Returns the repeat groups of the rule-bearing items the index stores
/// (`consistency_check/list_repeated_text/list_repeat_groups`).
///
/// Windows of [minRepeatRunWords] words, and of one word more, are hashed into
/// two maps from window to items; no two items are compared one by one. A run
/// is listed with every item that holds it whole, when no word extends it for
/// all of those items, so a longer run fewer items hold prints beside the
/// shorter run more items hold. A run the merged pack's template or guide text
/// holds is left out, judged on each call, so a pack change needs no reindex.
/// [scope] keeps each group that holds an item of one of its docs, and drops
/// the items of another code target's docs.
List<RepeatGroup> listRepeats(ReadSession session, CheckScope scope) {
  final names = {for (final doc in session.index.docs) doc.docPath: doc.name};
  final items = [
    for (final item in session.index.ruleItemWords())
      if (scope.inTargets(item.docPath) && names.containsKey(item.docPath))
        item,
  ];
  final paths = [for (final item in items) item.docPath];
  final windows = [for (final item in items) _windowsOf(item.words)];
  final longer = [
    for (final item in items) _windowsOf(item.words, minRepeatRunWords + 1),
  ];
  final held = _Held(
    paths: paths,
    shared: _holdersOf(windows, paths, keepOneDoc: false),
    chained: _holdersOf(longer, paths, keepOneDoc: true),
    windows: windows,
    longer: longer,
  );
  final template = _templateWindows(session);
  final groups = <String, RepeatGroup>{};
  for (var at = 0; at < items.length; at++) {
    for (final run in _runsOf(at, items[at].words, held)) {
      if (run.windows.every(template.contains)) continue;
      final holders = run.holders;
      if (!holders.any((i) => scope.contains(items[i].docPath))) continue;
      groups.putIfAbsent(
        '${run.text}\u0000${holders.join(',')}',
        () => (
          run: run.text,
          items: _sortedItems([
            for (final i in holders)
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
  }
  return groups.values.toList()..sort(_compareGroups);
}

List<String> _windowsOf(List<String> words, [int size = minRepeatRunWords]) => [
  for (var p = 0; p + size <= words.length; p++)
    words.sublist(p, p + size).join(' '),
];

/// Maps each window of [grams] to the items that hold it, in item order; with
/// [keepOneDoc] false, a window that items of one doc alone hold is left out.
Map<String, List<int>> _holdersOf(
  List<List<String>> grams,
  List<String> paths, {
  required bool keepOneDoc,
}) {
  final held = <String, List<int>>{};
  for (var at = 0; at < grams.length; at++) {
    for (final gram in grams[at]) {
      final holders = held.putIfAbsent(gram, () => []);
      if (holders.isEmpty || holders.last != at) holders.add(at);
    }
  }
  if (!keepOneDoc) {
    held.removeWhere(
      (_, holders) => holders.every((i) => paths[i] == paths[holders.first]),
    );
  }
  return held;
}

typedef _Run = ({String text, List<String> windows, List<int> holders});

/// The windows of every item, and which items hold each.
final class _Held {
  const new({
    required this.paths,
    required this.shared,
    required this.chained,
    required this.windows,
    required this.longer,
  });

  /// The DocPath of each item.
  final List<String> paths;

  /// The items that hold each window items of two or more docs hold.
  final Map<String, List<int>> shared;

  /// The items that hold each window of one word more: two windows that follow
  /// each other in an item follow each other in another only when it holds
  /// the longer window.
  final Map<String, List<int>> chained;

  /// The windows of each item, in word order.
  final List<List<String>> windows;

  /// The longer windows of each item, in word order.
  final List<List<String>> longer;

  /// Returns the items that hold the longer window [gram].
  List<int> holdersOfLonger(String gram) =>
      chained[gram] ?? (throw StateError('no item holds its own window'));

  /// Whether [items] hold text of two or more docs.
  bool spansDocs(List<int> items) =>
      items.isNotEmpty && items.any((i) => paths[i] != paths[items.first]);
}

/// Returns the runs that [held]'s item [at] starts, [at] being the first item
/// that holds each run, so no run is listed twice.
///
/// A run is every word an item holds whole in common with other docs' items,
/// listed with all items that hold it, when no word extends it, before or
/// after, for all of those items.
List<_Run> _runsOf(int at, List<String> words, _Held held) {
  final windows = held.windows[at];
  final longer = held.longer[at];
  final runs = <_Run>[];
  for (var i = 0; i < windows.length; i++) {
    final all = held.shared[windows[i]];
    if (all == null) continue;
    var group = all;
    final before = i == 0 ? null : held.holdersOfLonger(longer[i - 1]);
    bool extendsLeft(List<int> items) =>
        before != null && _within(items, before).length == items.length;
    if (!held.spansDocs(group) || extendsLeft(group)) continue;
    var j = i;
    while (true) {
      final next = j + 1 < windows.length
          ? _within(group, held.holdersOfLonger(longer[j]))
          : const <int>[];
      if (next.length != group.length) {
        if (group.first == at && held.spansDocs(group) && !extendsLeft(group)) {
          runs.add((
            text: words.sublist(i, j + minRepeatRunWords).join(' '),
            windows: windows.sublist(i, j + 1),
            holders: group,
          ));
        }
        if (!held.spansDocs(next)) break;
        group = next;
      }
      j++;
    }
  }
  return runs;
}

/// Returns the values both sorted lists hold.
List<int> _within(List<int> sorted, List<int> other) {
  final common = <int>[];
  var at = 0;
  for (final value in sorted) {
    while (at < other.length && other[at] < value) {
      at++;
    }
    if (at == other.length) break;
    if (other[at] == value) common.add(value);
  }
  return common;
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
