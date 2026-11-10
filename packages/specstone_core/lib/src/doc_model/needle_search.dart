import 'dart:collection';

const _unitBits = 16;

/// Returns the strings of [needles] that [text] contains, found in one pass.
///
/// A needle is found when `text.contains(needle)` holds, the empty needle
/// included. Aho-Corasick over UTF-16 code units: the cost is the length of
/// [text] plus the total length of the needles, however many needles there are,
/// where one `contains` per needle costs their count times the length of
/// [text].
Set<String> needlesFoundIn(Iterable<String> needles, String text) {
  final unique = {...needles};
  final found = <String>{};
  if (unique.remove('')) found.add('');
  if (unique.isEmpty || text.isEmpty) return found;
  final automaton = _Automaton([...unique]);
  return found..addAll(automaton.scan(text));
}

/// The trie of a list of needles with its failure and output links.
final class _Automaton {
  new(this._needles) {
    _addNeedles();
    _linkFailures();
  }

  final List<String> _needles;

  /// The child of a node by code unit, keyed `node << 16 | unit`.
  final _edges = HashMap<int, int>();

  /// The needle that ends at each node, or -1; node 0 is the root.
  final _ends = <int>[-1];
  final _parents = <int>[0];
  final _units = <int>[0];
  final _depths = <int>[0];
  late final List<int> _fail;

  /// The nearest node on the failure chain of each node where a needle ends,
  /// or 0.
  late final List<int> _outputLink;

  void _addNeedles() {
    for (final (index, needle) in _needles.indexed) {
      var node = 0;
      for (final unit in needle.codeUnits) {
        final key = (node << _unitBits) | unit;
        var next = _edges[key];
        if (next == null) {
          next = _ends.length;
          _edges[key] = next;
          _ends.add(-1);
          _parents.add(node);
          _units.add(unit);
          _depths.add(_depths[node] + 1);
        }
        node = next;
      }
      _ends[node] = index;
    }
  }

  /// Sets each node's failure link from those of shallower nodes.
  void _linkFailures() {
    final count = _ends.length;
    _fail = List.filled(count, 0);
    _outputLink = List.filled(count, 0);
    final byDepth = List.generate(count - 1, (i) => i + 1)
      ..sort((a, b) => _depths[a].compareTo(_depths[b]));
    for (final node in byDepth) {
      if (_depths[node] > 1) {
        var state = _fail[_parents[node]];
        int? next;
        while ((next = _edges[(state << _unitBits) | _units[node]]) == null &&
            state != 0) {
          state = _fail[state];
        }
        _fail[node] = next ?? 0;
      }
      final via = _fail[node];
      _outputLink[node] = _ends[via] >= 0 ? via : _outputLink[via];
    }
  }

  /// Returns the needles that occur in [text].
  Set<String> scan(String text) {
    final seen = List.filled(_needles.length, false);
    var remaining = _needles.length;
    var state = 0;
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      int? next;
      while ((next = _edges[(state << _unitBits) | unit]) == null &&
          state != 0) {
        state = _fail[state];
      }
      state = next ?? 0;
      for (
        var node = _ends[state] >= 0 ? state : _outputLink[state];
        node != 0;
        node = _outputLink[node]
      ) {
        final needle = _ends[node];
        if (seen[needle]) continue;
        seen[needle] = true;
        if (--remaining == 0) return _needles.toSet();
      }
    }
    return {
      for (final (index, needle) in _needles.indexed)
        if (seen[index]) needle,
    };
  }
}
