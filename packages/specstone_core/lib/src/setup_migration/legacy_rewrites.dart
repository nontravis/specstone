import 'dart:convert';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/rendering/doc_reader.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/setup_migration/legacy_moves.dart';

final _numberedTitle = RegExp(r'^[A-Z][A-Z0-9]*-\d+ — ');
final _humanLine = RegExp(r'^- \*\*Human:\*\* (.+)$', multiLine: true);

const _featureNameHeader = 'Feature name';
const _indexHeaders = {
  'User stories index',
  'US ↔ FR rollup',
  'Sub-features index',
};

const _fixedTitles = <LegacyKind, String>{
  LegacyKind.project: 'Project context',
  LegacyKind.features: 'System map',
  LegacyKind.gnfr: 'Project-wide non-functional requirements',
};

const Set<LegacyKind> _specKinds = {
  LegacyKind.architecture,
  LegacyKind.api,
  LegacyKind.domain,
  LegacyKind.integration,
  LegacyKind.error,
  LegacyKind.auth,
  LegacyKind.topic,
};

const _visionLabels = <String, String>{
  '**เพื่ออะไร (why):**': '**Why:**',
  '**แก้ปัญหาอะไร (problem):**': '**Problem:**',
  '**แก้ให้ใคร (audience):**': '**Audience:**',
};

const _headerRenames = <LegacyKind, (String, String)>{
  LegacyKind.architecture: ('Tier-2 decisions', 'Concerns'),
  LegacyKind.api: ('FR ↔ endpoint trace', 'FR trace'),
};

/// A doc file as LF text with the line style and byte order mark it came with.
typedef DocText = ({String lf, LineEnding ending, bool bom});

/// Reads UTF-8 [bytes] into LF text, the byte order mark dropped from it.
DocText readDocText(List<int> bytes) {
  final text = utf8.decode(bytes);
  return (
    lf: toLf(text),
    ending: LineEnding.of(text),
    bom: startsWithUtf8Bom(bytes),
  );
}

/// Returns [lf] in the line style of [original], the byte order mark first
/// when [original] had one.
String writtenText(DocText original, String lf) =>
    '${original.bom ? '﻿' : ''}${original.ending.apply(lf)}';

/// The result of [rewriteLegacyDoc].
final class DocRewrite {
  const new({
    required this.lf,
    required this.changes,
    this.gnfrSections = const [],
  });

  /// The rewritten LF text.
  final String lf;

  /// The labels of the changes made, in the order the rewrite applies them.
  final List<String> changes;

  /// The GNFR headers no GNFR section has, in doc order.
  final List<String> gnfrSections;
}

/// Rewrites the title, keys, and sections of one legacy doc of [kind].
///
/// A doc line the legacy mapping does not name stays byte-equal. [gnfrHeaders]
/// are the section headers of the `gnfr` doc type.
DocRewrite rewriteLegacyDoc(
  String lf,
  LegacyKind kind, {
  Set<String> gnfrHeaders = const {},
}) {
  final changes = <String>[];
  var text = lf;

  final folded = kind == LegacyKind.feature ? _foldFeatureName(text) : null;
  if (folded != null) {
    text = folded;
    changes.add('title from Feature name');
  } else {
    final titled = _retitled(text, kind);
    if (titled != null) {
      text = titled;
      changes.add('title');
    }
  }

  void apply(String label, String Function(String) change) {
    final changed = change(text);
    if (changed == text) return;
    text = changed;
    changes.add(label);
  }

  apply('name', (t) => withKeyBlock(t, 'name', null));
  if (_specKinds.contains(kind)) {
    apply('feature_id', (t) => withKeyBlock(t, 'feature_id', null));
  }
  if (kind == LegacyKind.project) apply('vision labels', _withVisionLabels);
  if (kind == LegacyKind.feature) {
    apply('index tables removed', _withoutIndexes);
  }
  final rename = _headerRenames[kind];
  if (rename != null) {
    apply(rename.$2, (t) => _withHeaderRenamed(t, rename.$1, rename.$2));
  }
  if (kind == LegacyKind.topic) {
    apply('covers from applies_to', _withCoversKey);
  }

  return DocRewrite(
    lf: text,
    changes: changes,
    gnfrSections: kind == LegacyKind.gnfr
        ? [
            for (final section in Doc.parse(text).sections)
              if (!gnfrHeaders.contains(section.headerText)) section.headerText,
          ]
        : const [],
  );
}

/// Returns [lf] with the Feature name section folded into the title, or null
/// when the section holds no `- **Human:** <name>` line.
String? _foldFeatureName(String lf) {
  final doc = Doc.parse(lf);
  final index = doc.sections.indexWhere(
    (section) => section.headerText == _featureNameHeader,
  );
  if (index < 0) return null;
  final name = _humanLine
      .firstMatch(doc.sections[index].body)
      ?.group(1)
      ?.trim();
  if (name == null || name.isEmpty) return null;
  return withTitle(withoutSection(lf, index), name);
}

/// Returns [lf] with its title retitled for [kind], or null when it stays.
String? _retitled(String lf, LegacyKind kind) {
  final title = Doc.parse(lf).title;
  if (title == null) return null;
  final fixed = _fixedTitles[kind];
  final retitled = fixed ?? title.replaceFirst(_numberedTitle, '');
  return retitled == title ? null : withTitle(lf, retitled);
}

String _withVisionLabels(String lf) => _visionLabels.entries.fold(
  lf,
  (text, label) => text.replaceAll(label.key, label.value),
);

String _withoutIndexes(String lf) {
  var text = lf;
  while (true) {
    final index = Doc.parse(text).sections
        .indexWhere((section) => _indexHeaders.contains(section.headerText));
    if (index < 0) break;
    text = withoutSection(text, index);
  }
  // Only a removed last section leaves a blank tail to trim; any other tail
  // stays byte-equal.
  if (text == lf || lf.endsWith('\n\n') || !text.endsWith('\n\n')) return text;
  return '${withoutTrailingBlankLines(text)}\n';
}

String _withHeaderRenamed(String lf, String from, String to) {
  final doc = Doc.parse(lf);
  final index = doc.sections.indexWhere((s) => s.headerText == from);
  if (index < 0) return lf;
  final lines = doc.afterFrontmatter.split('\n');
  final lineAt = doc.sectionLineIndexes[index];
  lines[lineAt] = lines[lineAt].replaceRange(
    0,
    doc.sections[index].headerLine.length,
    '## $to',
  );
  final frontmatterLength = lf.length - doc.afterFrontmatter.length;
  return lf.substring(0, frontmatterLength) + lines.join('\n');
}

String _withCoversKey(String lf) {
  final blocks = Doc.parse(lf).frontmatter;
  final block = blocks?.where((b) => b.name == 'applies_to').firstOrNull;
  if (block == null) return lf;
  final covers = block.text.replaceFirst(
    RegExp('^${RegExp.escape(block.key)}(?=\\s*:)', multiLine: true),
    'covers',
  );
  return withKeyBlock(lf, 'applies_to', covers);
}
