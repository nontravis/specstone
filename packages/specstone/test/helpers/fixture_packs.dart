import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'temp_tree.dart';

const _configPath = '.specstone/config.yaml';

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

const _context = '''
id: context
description: Project context.
path: prds/d{nn}_{slug}.md
''';

const _feature = r'''
id: feature
description: A feature groups the stories that serve one goal.
path: prds/features/f{nn}_{slug}/FEATURE.md
fields:
  - id: vision
    type: string
    list: true
sections:
  - id: name
    header: Feature name
    required: true
  - id: goal
    header: Feature goal
    required: true
    template: "- **why:**\n"
  - id: flow
    header: Feature flow
''';

const _userStory = '''
id: user_story
description: One story of a feature.
path: prds/features/f{nn}_{slug}/us{nn}_{slug}/USER_STORY.md
sections:
  - id: summary
    header: Summary
    required: true
  - id: criteria
    header: Acceptance Criteria
    required: true
''';

const _functionalRequirement = '''
id: functional_requirement
description: One functional requirement of a story.
path: prds/features/f{nn}_{slug}/us{nn}_{slug}/functional_requirements/fr{nn}_{slug}.md
sections:
  - id: statement
    header: Statement
    required: true
''';

/// Returns the fixture `prd-core` pack files, keyed by shipped path.
///
/// Fixture doc types sit on the docs-root base and never ship (F5-D46).
/// [extra] adds `prd-core/<file>` entries, keyed by file name.
Map<String, Uint8List> fixturePackFiles({
  Map<String, String> extra = const {},
}) => {
  'prd-core/pack.yaml': _bytes('name: prd-core\nversion: 1.1.0\n'),
  'prd-core/context.yaml': _bytes(_context),
  'prd-core/feature.yaml': _bytes(_feature),
  'prd-core/user_story.yaml': _bytes(_userStory),
  'prd-core/functional_requirement.yaml': _bytes(_functionalRequirement),
  for (final MapEntry(:key, :value) in extra.entries)
    'prd-core/$key': _bytes(value),
};

/// Writes a project that lists `prd-core` and returns its folder.
///
/// A [files] entry named `.specstone/config.yaml` replaces the generated
/// config.
Future<Directory> fixtureProject(Map<String, String> files) =>
    writeTree({_configPath: 'packs:\n  prd-core: 1.1.0\n', ...files});
