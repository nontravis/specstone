import 'dart:io';

import 'package:specstone_core/specstone_core.dart';

import '../../../specstone_core/test/helpers/shipped_pins.dart';
import 'temp_tree.dart';

/// The brick_dartfrog commit the baseline sizes were measured at (F1-D35).
const baselineCommit = '66f7c31273';

/// The size deciles of brick_dartfrog's 1,826 `.md` docs, smallest first.
///
/// Each bucket holds its file count and its summed bytes.
const baselineBuckets = <({int files, int bytes})>[
  (files: 182, bytes: 328870),
  (files: 183, bytes: 474484),
  (files: 182, bytes: 566023),
  (files: 183, bytes: 654216),
  (files: 183, bytes: 748097),
  (files: 182, bytes: 871243),
  (files: 183, bytes: 1037411),
  (files: 182, bytes: 1272180),
  (files: 183, bytes: 1978827),
  (files: 183, bytes: 11124893),
];

const _featureCount = 52;
const _storiesPerFeature = 5;
const _frsPerStory = 4;
const _topicCount = 2;
const _stride = 7;
const _recordType = 'implementation';

const _padWords = [
  'amber', 'birch', 'cedar', 'delta', 'ember', 'fjord', 'grove', 'haven', //
  'iris', 'jade', 'kelp', 'lumen', 'maple', 'nova', 'opal', 'quartz',
];

/// Writes a new-format docs project the size of the baseline and returns its
/// root.
///
/// The project pins the shipped `prd-core` and `software-tech` and holds
/// [baselineBuckets]' 1,826 docs in a fixed order. Each feature's record, the
/// 52 `implementation` docs, takes one size of the middle of the ascending size
/// list, so it fits its entries; each other doc takes the rest in generation
/// order, stepping 7 sizes at a time through the 1,774 left. Each of the 1,040
/// FRs has an `implemented` entry in its feature's record that names one class
/// in its own `src/` file, and each of the two topics holds one `src/` file, so
/// 1,042 code files sit under the tech stack's `code:` root and every one is
/// reached by a `covers:` prefix. The folder is deleted by `addTearDown`.
Future<Directory> writeBaselineTree() async {
  final root = await writeTree({'.specstone/config.yaml': shippedPinsConfig()});
  final templates = TemplateResolver().resolve(
    workingDirectory: root,
    homeDirectory: null,
  );
  final specs = _docSpecs();
  final all = _ascendingSizes();
  assert(specs.length == all.length, 'one size for each doc');
  final padding = _padding(all.last);
  final middle = all.length ~/ 2;
  final recordSizes = all.sublist(middle, middle + _featureCount).iterator;
  final sizes = [...all.take(middle), ...all.skip(middle + _featureCount)];
  var other = 0;
  for (final spec in specs) {
    final isRecord = spec.type == _recordType;
    if (isRecord) recordSizes.moveNext();
    final size = isRecord
        ? recordSizes.current
        : sizes[(other++ * _stride) % sizes.length];
    final file = File.fromUri(root.uri.resolve('docs/${spec.path}'));
    await file.parent.create(recursive: true);
    final text = isRecord
        ? _renderRecord(spec, size, padding)
        : _render(templates, spec, size, padding);
    await file.writeAsString(text);
  }
  await _writeCode(root);
  return root;
}

String _codePath(int f, int s, int r) => 'src/feature_$f/story_$s/req_$r.dart';

/// Writes the code files the FRs implement and the topics cover.
Future<void> _writeCode(Directory root) async {
  Future<void> write(String path, String content) async {
    final file = File.fromUri(root.uri.resolve(path));
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  for (var f = 1; f <= _featureCount; f++) {
    for (var s = 1; s <= _storiesPerFeature; s++) {
      for (var r = 1; r <= _frsPerStory; r++) {
        await write(_codePath(f, s, r), 'class Req$r {}\n');
      }
    }
  }
  for (var t = 1; t <= _topicCount; t++) {
    await write('src/topic_$t/topic.dart', '// topic $t\n');
  }
}

/// One doc to write: its type, path under `docs/`, title, and frontmatter.
typedef _DocSpec = ({
  String type,
  String path,
  String title,
  String frontmatter,
});

_DocSpec _spec(
  String type,
  String path,
  String title, [
  String frontmatter = '',
]) => (type: type, path: path, title: title, frontmatter: frontmatter);

/// Lists every doc of the tree in generation order.
List<_DocSpec> _docSpecs() => [
  _spec('project', 'prds/PROJECT.md', 'Baseline project', 'owner: baseline\n'),
  _spec('features', 'prds/FEATURES.md', 'Baseline features'),
  _spec('gnfr', 'prds/GNFR.md', 'Baseline requirements'),
  _spec(
    'tech_stack',
    'specs/TECH_STACK.md',
    'Baseline stack',
    'code:\n  - src/\n',
  ),
  for (var f = 1; f <= _featureCount; f++) ..._featureSpecs(f),
  for (var t = 1; t <= _topicCount; t++)
    _spec(
      'topic',
      'specs/topics/topic_$t.md',
      'Topic $t',
      'covers:\n  - src/topic_$t/\n',
    ),
];

List<_DocSpec> _featureSpecs(int f) {
  final key = 'f${_two(f)}_feature_$f';
  return [
    _spec('feature', 'prds/features/$key/FEATURE.md', 'Feature $f'),
    _spec(
      'architecture',
      'specs/$key/ARCHITECTURE.md',
      'Architecture $f',
      'covers:\n  - src/feature_$f/\n',
    ),
    _spec('domain', 'specs/$key/DOMAIN.md', 'Domain $f'),
    _spec('api', 'specs/$key/API.md', 'Api $f'),
    _spec(
      _recordType,
      'specs/$key/IMPLEMENTATION.md',
      'Feature $f implementation',
      _recordFrontmatter(f),
    ),
    for (var s = 1; s <= _storiesPerFeature; s++) ...[
      _spec(
        'user_story',
        'prds/features/$key/us${_two(s)}_story_$s/USER_STORY.md',
        'Story $s',
      ),
      for (var r = 1; r <= _frsPerStory; r++)
        _spec(
          'fr',
          'prds/features/$key/us${_two(s)}_story_$s/fr${_two(r)}_req_$r.md',
          'Requirement $r',
          'traced_from:\n  - S1\nverify_method: test\n',
        ),
      _spec(
        'nf',
        'prds/features/$key/us${_two(s)}_story_$s/nf01_nfr_1.md',
        'Quality requirement 1',
        'kind: add\nverify_method: test\n',
      ),
    ],
  ];
}

/// Returns the frontmatter of feature [f]'s record: each FR `implemented`, with
/// the one class its `src/` file holds.
String _recordFrontmatter(int f) {
  final items = [
    for (var s = 1; s <= _storiesPerFeature; s++)
      for (var r = 1; r <= _frsPerStory; r++) (s, r),
  ];
  String lines(String key, String Function(int s, int r) line) =>
      '$key:\n${[for (final (s, r) in items) "  - '${line(s, r)}'\n"].join()}';
  String item(int s, int r) => 'story_$s/req_$r';
  return lines('statuses', (s, r) => '${item(s, r)}:implemented') +
      lines(
        'implements',
        (s, r) => '${item(s, r)}:${_codePath(f, s, r)}:Req$r',
      );
}

/// Expands [baselineBuckets] to one size per file, smallest first.
///
/// Each bucket's bytes divide evenly over its files; the remainder adds one
/// byte to as many files as it leaves over.
List<int> _ascendingSizes() {
  final sizes = <int>[];
  for (final (:files, :bytes) in baselineBuckets) {
    final each = bytes ~/ files;
    final extra = bytes % files;
    for (var i = 0; i < files; i++) {
      sizes.add(i < extra ? each + 1 : each);
    }
  }
  return sizes..sort();
}

/// Returns a doc of exactly [size] bytes: frontmatter, a title, the type's
/// required sections, and padding words closing the last section.
String _render(MergedSet templates, _DocSpec spec, int size, String padding) {
  final headers = [
    for (final section in templates.lookup(spec.type)!.sections)
      if (section.required) section.header,
  ];
  final head = StringBuffer()
    ..write(spec.frontmatter.isEmpty ? '' : '---\n${spec.frontmatter}---\n\n')
    ..write('# ${spec.title}\n\n');
  for (final header in headers.take(headers.length - 1)) {
    head.write('## $header\nBaseline text.\n\n');
  }
  head.write('## ${headers.last}\nBaseline text. ');
  return _fill(spec, '$head', size, padding);
}

/// Returns a record of exactly [size] bytes: frontmatter, a title, and padding
/// words.
String _renderRecord(_DocSpec spec, int size, String padding) {
  final head = '---\n${spec.frontmatter}---\n\n# ${spec.title}\n\n';
  return _fill(spec, head, size, padding);
}

/// Returns [head] closed with padding words so the doc is exactly [size]
/// bytes.
String _fill(_DocSpec spec, String head, int size, String padding) {
  final padLength = size - head.length - 1;
  if (padLength < 0) {
    throw StateError('${spec.path} needs ${head.length + 1} bytes, not $size');
  }
  var pad = padding.substring(0, padLength);
  if (pad.endsWith(' ')) pad = '${pad.substring(0, padLength - 1)}a';
  return '$head$pad\n';
}

/// Returns padding words at least [length] characters long.
String _padding(int length) {
  final unit = '${_padWords.join(' ')} ';
  return unit * (length ~/ unit.length + 1);
}

String _two(int n) => n.toString().padLeft(2, '0');
