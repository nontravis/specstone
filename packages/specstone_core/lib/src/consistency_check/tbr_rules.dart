import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/models/body_line.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/models/tbr_marker_place.dart';

const _frType = 'fr';
const _nfType = 'nf';
const _gnfrType = 'gnfr';
const _tbrSection = 'tbr';
const _bulletLabel = '- **TBR:**';
const _noValue = 'none';
const _openValue = 'the value is still to be resolved';
const _openSection = 'the TBR section is open';
const _formKey = 'form';
const _valueKey = 'value';
const _markerForm = 'marker';
const _sectionForm = 'section';
const _bulletForm = 'bullet';

/// The most characters of a value a message shows; the rest is cut off.
const tbrValueLimit = 80;

/// Returns the message of an open value; an empty [value] names none, and a
/// value past [tbrValueLimit] characters shows its first ones and an ellipsis.
String _valueMessage(String value) {
  if (value.isEmpty) return _openValue;
  final shown = value.runes.length > tbrValueLimit
      ? '${String.fromCharCodes(value.runes.take(tbrValueLimit))}\u2026'
      : value;
  return '$_openValue: $shown';
}

/// Returns one `tbr_open` finding per open TBR of [doc], a typed doc.
///
/// An open TBR is each `tbr` section an `fr` or `nf` doc holds, each
/// `**TBR:**` bullet of a gnfr doc whose value is not `none`, and each
/// stored marker that lies in neither; one inside a section or on a bullet is
/// that section's or bullet's one finding.
Iterable<Finding> checkOpenTbrs(CheckContext context, IndexedDoc doc) sync* {
  final claimed = <int>{};
  for (final _Open(:line, :message, :form, :value) in _sectionsOf(
    context,
    doc,
    claimed,
  )) {
    yield _finding(context, doc, line, message, form, value);
  }
  for (final _Open(:line, :message, :form, :value) in _bulletsOf(
    context,
    doc,
    claimed,
  )) {
    yield _finding(context, doc, line, message, form, value);
  }
  for (final TbrMarkerPlace(:line, :rest)
      in context.contentOf(doc).lineFacts.tbrMarkers) {
    if (claimed.contains(line)) continue;
    yield _finding(context, doc, line, _valueMessage(rest), _markerForm, rest);
  }
}

/// One open TBR: its file line, its message, the form that holds it, and the
/// uncut value its message names, if any.
final class _Open {
  const new({
    required this.line,
    required this.message,
    required this.form,
    this.value,
  });

  final int line;
  final String message;
  final String form;
  final String? value;
}

Finding _finding(
  CheckContext context,
  IndexedDoc doc,
  int line,
  String message,
  String form,
  String? value,
) => context.finding(
  doc,
  FindingKind.tbrOpen,
  line: line,
  message: message,
  keys: {
    _formKey: form,
    if (value != null && value.isNotEmpty) _valueKey: value,
  },
);

/// Returns a finding row per `tbr` section of an `fr` or `nf` [doc], and adds
/// the section's file lines to [claimed].
Iterable<_Open> _sectionsOf(
  CheckContext context,
  IndexedDoc doc,
  Set<int> claimed,
) sync* {
  if (doc.docTypeId != _frType && doc.docTypeId != _nfType) return;
  final facts = context.contentOf(doc).lineFacts;
  for (var i = 0; i < context.contentOf(doc).sections.length; i++) {
    if (context.templateSectionAt(doc, i)?.id != _tbrSection) continue;
    final header = facts.sectionLines[i];
    claimed
      ..add(header)
      ..addAll([for (final line in context.bodyLinesOf(doc, i)) line.line]);
    yield _Open(line: header, message: _openSection, form: _sectionForm);
  }
}

/// Returns a finding row per `**TBR:**` bullet of a gnfr [doc] whose value
/// is not `none`, and adds every such bullet's line to [claimed].
Iterable<_Open> _bulletsOf(
  CheckContext context,
  IndexedDoc doc,
  Set<int> claimed,
) sync* {
  if (doc.docTypeId != _gnfrType) return;
  for (var i = 0; i < context.contentOf(doc).sections.length; i++) {
    for (final BodyLine(:text, :line, :fenced) in context.bodyLinesOf(doc, i)) {
      final bullet = text.trim();
      if (fenced || !bullet.startsWith(_bulletLabel)) continue;
      claimed.add(line);
      final value = bullet.substring(_bulletLabel.length).trim();
      if (value == _noValue) continue;
      yield _Open(
        line: line,
        message: _valueMessage(value),
        form: _bulletForm,
        value: value,
      );
    }
  }
}
