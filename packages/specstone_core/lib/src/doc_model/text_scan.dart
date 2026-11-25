import 'package:specstone_core/src/doc_model/models/text_scan.dart';

const _lf = 0x0A;

/// Returns the `\n` count and the surrogate pair count of [text] in one pass.
///
/// The code points of [text] are its length minus the pairs.
TextScan scanText(String text) {
  var breaks = 0;
  var pairs = 0;
  var afterHigh = false;
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit == _lf) breaks++;
    if (afterHigh && unit >= 0xDC00 && unit <= 0xDFFF) pairs++;
    afterHigh = unit >= 0xD800 && unit <= 0xDBFF;
  }
  return TextScan(breaks: breaks, pairs: pairs);
}
