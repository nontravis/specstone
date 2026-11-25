import 'dart:typed_data';

const _root = 0;
const _none = -1;

/// The bits a code unit takes in a transition key.
const _unitBits = 16;

/// Finds which of a set of literals occur in a text, as [String.contains]
/// finds them, reading the text once.
///
/// The search runs over UTF-16 code units, as [String.contains] does; an empty
/// literal always occurs. It is an Aho-Corasick automaton: one state per
/// literal prefix, each with a fallback to the state of its longest suffix.
final class LiteralScan {
  new(Iterable<String> literals) {
    final searched = <String>{};
    for (final literal in literals) {
      if (literal.isEmpty) {
        _hasEmpty = true;
      } else {
        searched.add(literal);
      }
    }
    final most = searched.fold(1, (states, literal) => states + literal.length);
    _parents = Int32List(most);
    _units = Int32List(most);
    _depths = Int32List(most);
    _fallbacks = Int32List(most);
    _outputLinks = Int32List(most)..fillRange(0, most, _none);
    _collectedIn = Int32List(most)..fillRange(0, most, _none);
    _ends = List.filled(most, null);
    _children = _Transitions(most);
    searched.forEach(_insert);
    _link();
  }

  late final _Transitions _children;
  late final Int32List _parents;
  late final Int32List _units;
  late final Int32List _depths;
  late final Int32List _fallbacks;

  /// The next state on the fallback chain that ends a literal; [_none] when
  /// none does.
  late final Int32List _outputLinks;
  late final List<String?> _ends;
  var _states = 1;
  var _hasEmpty = false;

  /// The scan that last collected each state's literal.
  late final Int32List _collectedIn;
  var _scans = 0;

  /// Returns the literals that occur in [text].
  Set<String> foundIn(String text) {
    final scan = _scans++;
    final found = <String>{if (_hasEmpty) ''};
    var state = _root;
    for (var i = 0; i < text.length; i++) {
      state = _next(state, text.codeUnitAt(i));
      _collect(state, scan, found);
    }
    return found;
  }

  void _insert(String literal) {
    var state = _root;
    for (var i = 0; i < literal.length; i++) {
      final unit = literal.codeUnitAt(i);
      final key = _key(state, unit);
      final child = _children[key];
      if (child != _none) {
        state = child;
        continue;
      }
      final added = _states++;
      _parents[added] = state;
      _units[added] = unit;
      _depths[added] = _depths[state] + 1;
      _children[key] = added;
      state = added;
    }
    _ends[state] = literal;
  }

  /// Sets each state's fallback in order of depth, so a state's parent has
  /// its own first; a child of the root falls back to the root.
  void _link() {
    final byDepth = [for (var state = 1; state < _states; state++) state]
      ..sort((a, b) => _depths[a].compareTo(_depths[b]));
    for (final state in byDepth) {
      final parent = _parents[state];
      final fallback = parent == _root
          ? _root
          : _next(_fallbacks[parent], _units[state]);
      _fallbacks[state] = fallback;
      _outputLinks[state] = _ends[fallback] != null
          ? fallback
          : _outputLinks[fallback];
    }
  }

  int _next(int state, int unit) {
    var at = state;
    while (true) {
      final child = _children[_key(at, unit)];
      if (child != _none) return child;
      if (at == _root) return _root;
      at = _fallbacks[at];
    }
  }

  /// Adds every literal that ends at [state] to [found], each state's once per
  /// [scan].
  void _collect(int state, int scan, Set<String> found) {
    var at = _ends[state] != null ? state : _outputLinks[state];
    while (at != _none && _collectedIn[at] != scan) {
      _collectedIn[at] = scan;
      found.add(_ends[at]!);
      at = _outputLinks[at];
    }
  }

  static int _key(int state, int unit) => state << _unitBits | unit;
}

/// Each state's child on a code unit, keyed by state and unit, in one
/// open-addressing table: a scan looks one up per code unit, which a [Map]
/// makes the scan's main cost.
final class _Transitions {
  new(int most) : this._sized(_capacityFor(most));

  new _sized(int capacity)
    : _keys = Int64List(capacity)..fillRange(0, capacity, _none),
      _values = Int32List(capacity),
      _mask = capacity - 1;

  /// The multiplier that spreads keys over the table's slots.
  static const _spread = 0x9E3779B1;

  final Int64List _keys;
  final Int32List _values;
  final int _mask;

  /// Returns a power of two at least twice [most], the most keys the table
  /// takes, so a probe stays short.
  static int _capacityFor(int most) {
    var capacity = 16;
    while (capacity < most * 2) {
      capacity <<= 1;
    }
    return capacity;
  }

  /// Returns the child under [key]; [_none] when there is none.
  int operator [](int key) {
    for (var slot = _slotOf(key); ; slot = (slot + 1) & _mask) {
      final held = _keys[slot];
      if (held == key) return _values[slot];
      if (held == _none) return _none;
    }
  }

  void operator []=(int key, int child) {
    var slot = _slotOf(key);
    while (_keys[slot] != _none && _keys[slot] != key) {
      slot = (slot + 1) & _mask;
    }
    _keys[slot] = key;
    _values[slot] = child;
  }

  int _slotOf(int key) => ((key * _spread) >> _unitBits) & _mask;
}
