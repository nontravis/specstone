import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';

const _frType = 'fr';
const _nfType = 'nf';
const _gnfrType = 'gnfr';
const _tbrSection = 'tbr';
const _bulletLabel = '- **TBR:**';
const _noValue = 'none';
const _openValue = 'the value is still to be resolved';
const _openSection = 'the TBR section is open';
const _formKey = 'form';
const _markerForm = 'marker';
const _sectionForm = 'section';
const _bulletForm = 'bullet';

/// Returns the message of an open value; an empty [value] names none.
String _valueMessage(String value) =>
    value.isEmpty ? _openValue : '$_openValue: $value';

/// Returns one `tbr_open` finding per open TBR of [doc], a typed doc.
///
/// An open TBR is each `tbr` section an `fr` or `nf` doc holds, each
/// `**TBR:**` bullet of a `gnfr` doc whose value is not `none`, and each
/// stored marker that lies in neither; one inside a section or on a bullet is
/// that section's or bullet's one finding (`report_open_tbrs`).
Iterable<Finding> checkOpenTbrs(CheckContext context, IndexedDoc doc) sync* {
  final claimed = <int>{};
  for (final (:line, :message, :form) in _sectionsOf(context, doc, claimed)) {
    yield _finding(context, doc, line, message, form);
  }
  for (final (:line, :message, :form) in _bulletsOf(context, doc, claimed)) {
    yield _finding(context, doc, line, message, form);
  }
  for (final (:line, :rest) in context.contentOf(doc).lineFacts.tbrMarkers) {
    if (claimed.contains(line)) continue;
    yield _finding(context, doc, line, _valueMessage(rest), _markerForm);
  }
}

typedef _Open = ({int line, String message, String form});

Finding _finding(
  CheckContext context,
  IndexedDoc doc,
  int line,
  String message,
  String form,
) => context.finding(
  doc,
  FindingKind.tbrOpen,
  line: line,
  message: message,
  keys: {_formKey: form},
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
    yield (line: header, message: _openSection, form: _sectionForm);
  }
}

/// Returns a finding row per `**TBR:**` bullet of a `gnfr` [doc] whose value
/// is not `none`, and adds every such bullet's line to [claimed].
Iterable<_Open> _bulletsOf(
  CheckContext context,
  IndexedDoc doc,
  Set<int> claimed,
) sync* {
  if (doc.docTypeId != _gnfrType) return;
  for (var i = 0; i < context.contentOf(doc).sections.length; i++) {
    for (final (:text, :line, :fenced) in context.bodyLinesOf(doc, i)) {
      final bullet = text.trim();
      if (fenced || !bullet.startsWith(_bulletLabel)) continue;
      claimed.add(line);
      final value = bullet.substring(_bulletLabel.length).trim();
      if (value == _noValue) continue;
      yield (line: line, message: _valueMessage(value), form: _bulletForm);
    }
  }
}
