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
/// Windows of [minRepeatRunWords] words are hashed into one map from window
/// to items, so the work is linear in the stored words. Adjacent windows the
/// same items share merge into one maximal run. A run the merged pack's
/// template or guide text holds is left out, judged on each call so a pack
/// change needs no reindex. [scope] keeps each group that holds an item of one
/// of its docs, and drops the items of another code target's docs.
List<RepeatGroup> listRepeats(ReadSession session, CheckScope scope) {
  final names = {for (final doc in session.index.docs) doc.docPath: doc.name};
  final items = [
    for (final item in session.index.ruleItemWords())
      if (scope.inTargets(item.docPath) && names.containsKey(item.docPath))
        item,
  ];
  final windows = [for (final item in items) _windowsOf(item.words)];
  final sharers = _sharersOf(items.map((item) => item.docPath), windows);
  final template = _templateWindows(session);
  final groups = <String, RepeatGroup>{};
  for (var at = 0; at < items.length; at++) {
    for (final run in _runsOf(at, items[at].words, windows[at], sharers)) {
      if (run.windows.every(template.contains)) continue;
      final holders = run.sharers;
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

List<String> _windowsOf(List<String> words) => [
  for (var p = 0; p + minRepeatRunWords <= words.length; p++)
    words.sublist(p, p + minRepeatRunWords).join(' '),
];

/// Maps each window that items of two or more docs hold to those items, in
/// item order.
Map<String, List<int>> _sharersOf(
  Iterable<String> docPaths,
  List<List<String>> windows,
) {
  final paths = docPaths.toList();
  final held = <String, List<int>>{};
  for (var at = 0; at < windows.length; at++) {
    for (final window in windows[at]) {
      final holders = held.putIfAbsent(window, () => []);
      if (holders.isEmpty || holders.last != at) holders.add(at);
    }
  }
  held.removeWhere(
    (_, holders) => holders.every((i) => paths[i] == paths[holders.first]),
  );
  return held;
}

typedef _Run = ({String text, List<String> windows, List<int> sharers});

/// Returns the maximal runs of item [at] that other docs' items share, each
/// listed from the first item that holds it, so no run is listed twice.
List<_Run> _runsOf(
  int at,
  List<String> words,
  List<String> windows,
  Map<String, List<int>> sharers,
) {
  final runs = <_Run>[];
  var start = -1;
  List<int>? open;
  void close(int end) {
    if (open == null) return;
    runs.add((
      text: words.sublist(start, end + minRepeatRunWords).join(' '),
      windows: windows.sublist(start, end + 1),
      sharers: open!,
    ));
    open = null;
  }

  for (var p = 0; p < windows.length; p++) {
    final holders = sharers[windows[p]];
    final here = holders != null && holders.first == at ? holders : null;
    if (open != null && here != null && _sameItems(open!, here)) continue;
    close(p - 1);
    if (here != null) {
      start = p;
      open = here;
    }
  }
  close(windows.length - 1);
  return runs;
}

bool _sameItems(List<int> a, List<int> b) =>
    a.length == b.length &&
    Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);

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
  const new(this.groups);

  /// The groups, sorted by their first item.
  final List<RepeatGroup> groups;

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

  /// The JSON object: `repeats` and `count`.
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
  };
}
