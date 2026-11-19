import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/fault.dart';

/// One entry a `set --stamp` refused.
final class StampRefusal {
  const new({required this.entry, required this.code, required this.message});

  /// The entry text of the refused stamp, as given.
  final String entry;

  /// The catalog code of the refusal.
  final WriteFaultCode code;

  /// Plain human text with no location prefix.
  final String message;
}

/// The one fault a refused `set --stamp` raises, holding every refused entry.
final class StampFault implements SpecstoneFault {
  /// Returns the fault of a call whose [refusals], at least one, were refused.
  new(this.refusals)
    : assert(refusals.isNotEmpty, 'a refused stamp names at least one entry');

  static final int _clientStatus = WriteFaultCode.stampEntryUnknown.exitStatus;

  /// The refused entries in the order the call gave them.
  final List<StampRefusal> refusals;

  /// 64 when any refusal's code exits 64, else 75.
  @override
  int get exitStatus =>
      refusals.any((refusal) => refusal.code.exitStatus == _clientStatus)
      ? _clientStatus
      : WriteFaultCode.stampStale.exitStatus;

  /// Returns the envelope `{'error': {...}}`.
  ///
  /// `code` and `message` are the first refusal's; `refusals` lists each
  /// `{entry, code}`.
  @override
  Map<String, Object> toJson() => {
    'error': {
      'code': refusals.first.code.wire,
      'message': refusals.first.message,
      'refusals': [
        for (final StampRefusal(:entry, :code) in refusals)
          {'entry': entry, 'code': code.wire},
      ],
    },
  };

  /// Returns one `<code>: <message>` line per refused entry.
  @override
  String toText() => [
    for (final StampRefusal(:code, :message) in refusals)
      '${code.wire}: $message',
  ].join('\n');

  @override
  String toString() => toText();
}
