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

const _padWords = [
  'amber', 'birch', 'cedar', 'delta', 'ember', 'fjord', 'grove', 'haven', //
  'iris', 'jade', 'kelp', 'lumen', 'maple', 'nova', 'opal', 'quartz',
];

/// Writes a new-format docs project the size of the baseline and returns its
/// root.
///
/// The project pins the shipped `prd-core` and `software-tech` and holds
/// [baselineBuckets]' 1,826 docs in a fixed order; the doc at position `k`
/// gets the size at index `(k * 7) % 1826` of the ascending size list. The
/// folder is deleted by `addTearDown`.
Future<Directory> writeBaselineTree() async {
  final root = await writeTree({'.specstone/config.yaml': shippedPinsConfig()});
  final templates = TemplateResolver().resolve(
    workingDirectory: root,
    homeDirectory: null,
  );
  final specs = _docSpecs();
  final sizes = _ascendingSizes();
  assert(specs.length == sizes.length, 'one size for each doc');
  final padding = _padding(sizes.last);
  for (final (k, spec) in specs.indexed) {
    final size = sizes[(k * _stride) % sizes.length];
    final file = File.fromUri(root.uri.resolve('docs/${spec.path}'));
    await file.parent.create(recursive: true);
    await file.writeAsString(_render(templates, spec, size, padding));
  }
  return root;
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
  _spec('tech_stack', 'specs/TECH_STACK.md', 'Baseline stack'),
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
    _spec('error', 'specs/$key/ERROR.md', 'Error $f'),
    for (var s = 1; s <= _storiesPerFeature; s++) ...[
      _spec(
        'user_story',
        'prds/features/$key/us${_two(s)}_story_$s/USER_STORY.md',
        'Story $s',
        'status: planned\n',
      ),
      for (var r = 1; r <= _frsPerStory; r++)
        _spec(
          'fr',
          'prds/features/$key/us${_two(s)}_story_$s/fr${_two(r)}_req_$r.md',
          'Requirement $r',
          'status: planned\ntraced_from:\n  - S1\nverify_method: test\n',
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
