/// Compares [a] and [b] by Unicode code point.
///
/// Compares `runes` element by element; a strict prefix sorts first. Unlike
/// `String.compareTo`, which orders UTF-16 code units, this puts `U+FF01`
/// before `U+1F600`. Every sort in the engine and the generator uses it.
int compareCodePoints(String a, String b) {
  final shorter = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < shorter; i++) {
    final aUnit = a.codeUnitAt(i);
    final bUnit = b.codeUnitAt(i);
    if (aUnit == bUnit) continue;
    // Code units order as code points unless a surrogate differs.
    if (_isSurrogate(aUnit) || _isSurrogate(bUnit)) return _compareRunes(a, b);
    return aUnit.compareTo(bUnit);
  }
  return a.length.compareTo(b.length);
}

int _compareRunes(String a, String b) {
  for (
    final aRunesIterator = a.runes.iterator, bRunesIterator = b.runes.iterator;
    ;
  ) {
    final aHas = aRunesIterator.moveNext();
    final bHas = bRunesIterator.moveNext();
    if (!aHas && !bHas) return 0;
    if (!aHas) return -1;
    if (!bHas) return 1;
    final compare = aRunesIterator.current.compareTo(bRunesIterator.current);
    if (compare != 0) return compare;
  }
}

/// The bits a UTF-16 surrogate code unit, high or low, carries.
const _surrogateMask = 0xF800;
const _surrogateBits = 0xD800;

bool _isSurrogate(int unit) => unit & _surrogateMask == _surrogateBits;
