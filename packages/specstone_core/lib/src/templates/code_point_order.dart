/// Compares [a] and [b] by Unicode code point (INV-22).
///
/// Compares `runes` element by element; a strict prefix sorts first. Unlike
/// `String.compareTo`, which orders UTF-16 code units, this puts `U+FF01`
/// before `U+1F600`. Every sort in the engine and the generator uses it.
int compareCodePoints(String a, String b) {
  final aRunes = a.runes;
  final bRunes = b.runes;
  var index = 0;
  for (
    final aRunesIterator = aRunes.iterator, bRunesIterator = bRunes.iterator;
    ;
    index++
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
