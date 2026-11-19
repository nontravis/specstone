import 'package:specstone_core/src/templates/feature_pattern.dart';
import 'package:specstone_core/src/templates/feature_pattern_layer.dart';
import 'package:specstone_core/src/templates/layer.dart';
import 'package:specstone_core/src/templates/merged_set_checks.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:test/test.dart';

final class _NoFiles implements LayerFiles {
  const new();

  @override
  bool exists(String layerRelativePath) => false;
}

const _shipped = 'packs/software/patterns';
const _project = '.specstone/templates/patterns';

WrittenPatternLayer layerOf(
  String id,
  String yaml, {
  String dir = _shipped,
  String? pack = 'software',
  LayerKind kind = LayerKind.shipped,
}) => WrittenPatternLayer(
  pack: pack,
  layer: FeaturePatternLayer.parse(
    yaml,
    file: '$dir/$id.yaml',
    patternId: id,
    kind: kind,
    files: const _NoFiles(),
  ),
);

WrittenPatternLayer projectOf(String id, String yaml) =>
    layerOf(id, yaml, dir: _project, pack: null, kind: LayerKind.project);

/// Merges [layers], loading shipped files, then personal, then project ones,
/// in map order within a kind, unless [loadIndex] says otherwise.
List<FeaturePattern> merge(
  Map<String, List<WrittenPatternLayer>> layers, {
  LoadIndex? loadIndex,
}) {
  final written = [for (final list in layers.values) ...list]
    ..sort((a, b) => a.layer.kind.index.compareTo(b.layer.kind.index));
  return mergeFeaturePatterns(
    layers,
    loadIndex:
        loadIndex ?? {for (final (i, w) in written.indexed) w.layer.file: i},
  );
}

FeaturePattern mergeOne(
  String id,
  Map<String, List<WrittenPatternLayer>> layers,
) => merge(layers).singleWhere((p) => p.id == id);

String authYaml({String? extra}) => '''
id: auth
description: Sign-in checklist.
items:
  - id: lockout
    text: Name the lockout rule.
  - id: reset
    text: Name the reset path.
${extra ?? ''}''';

List<String> textsOf(FeaturePattern pattern) => [
  for (final item in pattern.items) '${item.id}=${item.text}',
];

TypeMatcher<TemplateFault> fault(
  FaultCode code, {
  String? file,
  String? key,
  List<String>? related,
}) {
  var matcher = isA<TemplateFault>()
      .having((f) => f.code, 'code', code)
      .having((f) => f.exitStatus, 'exit status', 78);
  if (file != null) matcher = matcher.having((f) => f.file, 'file', file);
  if (key != null) matcher = matcher.having((f) => f.key, 'key', key);
  if (related != null) {
    matcher = matcher.having((f) => f.relatedFiles, 'relatedFiles', related);
  }
  return matcher;
}

void main() {
  group('mergeFeaturePatterns', () {
    test('a lone defining layer yields its description and items in order', () {
      final pattern = mergeOne('auth', {
        'auth': [layerOf('auth', authYaml())],
      });

      expect(pattern.id, 'auth');
      expect(pattern.pack, 'software');
      expect(pattern.extendsId, isNull);
      expect(pattern.description, 'Sign-in checklist.');
      expect(textsOf(pattern), [
        'lockout=Name the lockout rule.',
        'reset=Name the reset path.',
      ]);
      expect(pattern.reference, isEmpty);
    });

    test('a project layer rewrites one item and disables another', () {
      final pattern = mergeOne('auth', {
        'auth': [
          layerOf('auth', authYaml()),
          projectOf('auth', '''
id: auth
items:
  - id: lockout
    text: Project lockout text.
  - id: reset
    disabled: true
'''),
        ],
      });

      expect(textsOf(pattern), ['lockout=Project lockout text.']);
    });

    test('items of other ids read as shipped after an override', () {
      final pattern = mergeOne('auth', {
        'auth': [
          layerOf('auth', authYaml()),
          projectOf('auth', '''
id: auth
items:
  - id: lockout
    text: Project lockout text.
'''),
        ],
      });

      expect(textsOf(pattern), [
        'lockout=Project lockout text.',
        'reset=Name the reset path.',
      ]);
    });

    test('new item ids land after the base items in the layer order', () {
      final pattern = mergeOne('auth', {
        'auth': [
          layerOf('auth', authYaml()),
          projectOf('auth', '''
id: auth
items:
  - id: passkey
    text: Name the passkey rule.
  - id: magic_link
    text: Name the magic link rule.
'''),
        ],
      });

      expect(pattern.items.map((i) => i.id), [
        'lockout',
        'reset',
        'passkey',
        'magic_link',
      ]);
    });

    test('disabled on an id the base lacks is override_id_not_found', () {
      expect(
        () => merge({
          'auth': [
            layerOf('auth', authYaml()),
            projectOf('auth', '''
id: auth
items:
  - id: ghost
    disabled: true
'''),
          ],
        }),
        throwsA(
          fault(
            FaultCode.overrideIdNotFound,
            file: '$_project/auth.yaml',
            key: 'items',
          ),
        ),
      );
    });

    test('the override_id_not_found message names the item id the base '
        'lacks', () {
      expect(
        () => merge({
          'auth': [
            layerOf('auth', authYaml()),
            projectOf('auth', '''
id: auth
items:
  - id: ghost
    disabled: true
'''),
          ],
        }),
        throwsA(
          isA<TemplateFault>().having(
            (f) => f.message,
            'message',
            contains('"ghost"'),
          ),
        ),
      );
    });

    test('a pattern no lower layer defines is new, its file the defining '
        'layer', () {
      final pattern = mergeOne('onboarding', {
        'onboarding': [
          projectOf('onboarding', '''
id: onboarding
description: Onboarding checklist.
items:
  - id: welcome
    text: Name the welcome step.
'''),
        ],
      });

      expect(pattern.pack, isNull);
      expect(pattern.description, 'Onboarding checklist.');
      expect(pattern.items.single.id, 'welcome');
    });

    test('a defining layer with no description is missing_key', () {
      expect(
        () => merge({
          'auth': [
            projectOf('auth', '''
id: auth
items:
  - id: lockout
    text: Name the lockout rule.
'''),
          ],
        }),
        throwsA(
          fault(
            FaultCode.missingKey,
            file: '$_project/auth.yaml',
            key: 'description',
          ),
        ),
      );
    });

    test('a defining layer with no items is missing_key', () {
      expect(
        () => merge({
          'auth': [
            projectOf('auth', '''
id: auth
description: Sign-in checklist.
'''),
          ],
        }),
        throwsA(
          fault(
            FaultCode.missingKey,
            file: '$_project/auth.yaml',
            key: 'items',
          ),
        ),
      );
    });

    test('an override layer needs neither description nor other items', () {
      final pattern = mergeOne('auth', {
        'auth': [
          layerOf('auth', authYaml()),
          projectOf('auth', '''
id: auth
items:
  - id: reset
    text: Project reset text.
'''),
        ],
      });

      expect(pattern.description, 'Sign-in checklist.');
      expect(pattern.items, hasLength(2));
    });

    test('the pack is the lowest layer that names one', () {
      final pattern = mergeOne('auth', {
        'auth': [
          layerOf('auth', authYaml(), pack: 'software'),
          layerOf(
            'auth',
            'id: auth\nitems:\n  - id: reset\n    text: Personal reset.\n',
            dir: 'personal/patterns',
            pack: 'mine',
            kind: LayerKind.personal,
          ),
        ],
      });

      expect(pattern.pack, 'software');
    });
  });

  group('mergeFeaturePatterns extends', () {
    final signup = layerOf('signup', '''
id: signup
description: Sign-up checklist.
extends: auth
items:
  - id: verify_email
    text: Name the email check.
''');

    test('the target items come first, then the extending items', () {
      final pattern = mergeOne('signup', {
        'auth': [layerOf('auth', authYaml())],
        'signup': [signup],
      });

      expect(pattern.extendsId, 'auth');
      expect(pattern.description, 'Sign-up checklist.');
      expect(pattern.items.map((i) => i.id), [
        'lockout',
        'reset',
        'verify_email',
      ]);
    });

    test('the target merges its own upper layers before it is extended', () {
      final pattern = mergeOne('signup', {
        'auth': [
          layerOf('auth', authYaml()),
          projectOf('auth', '''
id: auth
items:
  - id: reset
    disabled: true
'''),
        ],
        'signup': [signup],
      });

      expect(pattern.items.map((i) => i.id), ['lockout', 'verify_email']);
    });

    test('an item of the target that the extender names is changed, never '
        'repeated', () {
      final pattern = mergeOne('signup', {
        'auth': [layerOf('auth', authYaml())],
        'signup': [
          layerOf('signup', '''
id: signup
description: Sign-up checklist.
extends: auth
items:
  - id: lockout
    text: Signup lockout text.
'''),
        ],
      });

      expect(textsOf(pattern), [
        'lockout=Signup lockout text.',
        'reset=Name the reset path.',
      ]);
    });

    test('the order of the map does not decide which pattern merges first', () {
      final patterns = merge({
        'signup': [signup],
        'auth': [layerOf('auth', authYaml())],
      });

      expect(patterns.map((p) => p.id), ['auth', 'signup']);
      expect(patterns.last.items.map((i) => i.id), [
        'lockout',
        'reset',
        'verify_email',
      ]);
    });

    test('the extending pattern keeps its own pack', () {
      final pattern = mergeOne('signup', {
        'auth': [layerOf('auth', authYaml(), pack: 'base-pack')],
        'signup': [signup],
      });

      expect(pattern.pack, 'software');
    });

    test('the topmost layer that writes extends decides the target', () {
      final pattern = mergeOne('signup', {
        'auth': [layerOf('auth', authYaml())],
        'crud': [
          layerOf('crud', '''
id: crud
description: Crud checklist.
items:
  - id: create
    text: Name the create rule.
'''),
        ],
        'signup': [signup, projectOf('signup', 'id: signup\nextends: crud\n')],
      });

      expect(pattern.extendsId, 'crud');
      expect(pattern.items.map((i) => i.id), ['create', 'verify_email']);
    });

    test('a cycle is extends_cycle naming the files', () {
      expect(
        () => merge({
          'a': [
            layerOf('a', '''
id: a
description: A.
extends: b
items:
  - id: one
    text: One.
'''),
          ],
          'b': [
            layerOf('b', '''
id: b
description: B.
extends: a
items:
  - id: two
    text: Two.
'''),
          ],
        }),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.extendsCycle)
              .having((f) => f.exitStatus, 'exit status', 78)
              .having((f) => f.file, 'file', '$_shipped/b.yaml')
              .having((f) => f.relatedFiles, 'related', ['$_shipped/a.yaml'])
              .having(
                (f) => f.message,
                'message',
                'extends chain returns to its start: a, b, a',
              ),
        ),
      );
    });

    test('a cycle closed by a project layer names that layer as file', () {
      expect(
        () => merge({
          'a': [
            layerOf('a', '''
id: a
description: A.
items:
  - id: one
    text: One.
'''),
            projectOf('a', 'id: a\nextends: b\n'),
          ],
          'b': [
            layerOf('b', '''
id: b
description: B.
extends: a
items:
  - id: two
    text: Two.
'''),
          ],
        }),
        throwsA(
          fault(
            FaultCode.extendsCycle,
            file: '$_project/a.yaml',
            related: ['$_shipped/b.yaml'],
          ),
        ),
      );
    });

    test('a cycle names the later-loaded file, not the later pack name', () {
      final software = layerOf('a', '''
id: a
description: A.
extends: b
items:
  - id: one
    text: One.
''', dir: 'packs/software/patterns');
      final app = layerOf(
        'b',
        '''
id: b
description: B.
extends: a
items:
  - id: two
    text: Two.
''',
        dir: 'packs/app/patterns',
        pack: 'app',
      );

      expect(
        () => merge(
          {
            'a': [software],
            'b': [app],
          },
          loadIndex: {software.layer.file: 0, app.layer.file: 1},
        ),
        throwsA(
          fault(
            FaultCode.extendsCycle,
            file: 'packs/app/patterns/b.yaml',
            related: ['packs/software/patterns/a.yaml'],
          ),
        ),
      );
    });

    test('a pattern that extends itself is extends_cycle', () {
      expect(
        () => merge({
          'a': [
            layerOf('a', '''
id: a
description: A.
extends: a
items:
  - id: one
    text: One.
'''),
          ],
        }),
        throwsA(fault(FaultCode.extendsCycle, file: '$_shipped/a.yaml')),
      );
    });

    test('an extends target no layer defines is extends_target_unknown', () {
      expect(
        () => merge({
          'signup': [signup],
        }),
        throwsA(
          fault(
            FaultCode.extendsTargetUnknown,
            file: '$_shipped/signup.yaml',
            key: 'extends',
          ),
        ),
      );
    });
  });

  group('mergeFeaturePatterns reference', () {
    const defining = '''
id: auth
description: Sign-in checklist.
items:
  - id: lockout
    text: Name the lockout rule.
reference:
  - title: Handbook
    url: https://example.com/handbook
  - title: Standard
''';

    test('the defining layer writes the whole list', () {
      final pattern = mergeOne('auth', {
        'auth': [layerOf('auth', defining)],
      });

      expect(pattern.reference.map((r) => r.title), ['Handbook', 'Standard']);
    });

    test('an upper layer changes the list through add and remove', () {
      final pattern = mergeOne('auth', {
        'auth': [
          layerOf('auth', defining),
          projectOf('auth', '''
id: auth
reference:
  add:
    - title: Project guide
  remove:
    - Standard
'''),
        ],
      });

      expect(pattern.reference.map((r) => r.title), [
        'Handbook',
        'Project guide',
      ]);
    });

    test('removing a title the base lacks is reference_title_not_found', () {
      expect(
        () => merge({
          'auth': [
            layerOf('auth', defining),
            projectOf('auth', '''
id: auth
reference:
  remove:
    - Ghost
'''),
          ],
        }),
        throwsA(
          fault(
            FaultCode.referenceTitleNotFound,
            file: '$_project/auth.yaml',
            key: 'reference',
          ),
        ),
      );
    });

    test(
      'a plain list over a lower list is list_override_needs_add_remove',
      () {
        expect(
          () => merge({
            'auth': [
              layerOf('auth', defining),
              projectOf('auth', '''
id: auth
reference:
  - title: Replacement
'''),
            ],
          }),
          throwsA(
            fault(
              FaultCode.listOverrideNeedsAddRemove,
              file: '$_project/auth.yaml',
              key: 'reference',
            ),
          ),
        );
      },
    );

    test('an extending pattern starts from the target list', () {
      final pattern = mergeOne('signup', {
        'auth': [layerOf('auth', defining)],
        'signup': [
          layerOf('signup', '''
id: signup
description: Sign-up checklist.
extends: auth
items:
  - id: verify_email
    text: Name the email check.
reference:
  add:
    - title: Signup guide
'''),
        ],
      });

      expect(pattern.reference.map((r) => r.title), [
        'Handbook',
        'Standard',
        'Signup guide',
      ]);
    });
  });

  group('ChecklistItem origin', () {
    test('an own item takes the id of its pattern', () {
      final pattern = mergeOne('auth', {
        'auth': [layerOf('auth', authYaml())],
      });

      expect(pattern.items.map((i) => i.origin), ['auth', 'auth']);
    });

    test('an inherited item keeps the id of the pattern that added it', () {
      final pattern = mergeOne('signup', {
        'auth': [layerOf('auth', authYaml())],
        'signup': [
          layerOf('signup', '''
id: signup
description: Sign-up checklist.
extends: auth
items:
  - id: verify_email
    text: Name the email check.
'''),
        ],
      });

      expect(pattern.items.map((i) => (i.id, i.origin)), [
        ('lockout', 'auth'),
        ('reset', 'auth'),
        ('verify_email', 'signup'),
      ]);
    });

    test('an item an extender rewrites takes the id of the extender', () {
      final pattern = mergeOne('signup', {
        'auth': [layerOf('auth', authYaml())],
        'signup': [
          layerOf('signup', '''
id: signup
description: Sign-up checklist.
extends: auth
items:
  - id: lockout
    text: Signup lockout text.
'''),
        ],
      });

      expect(pattern.items.map((i) => (i.id, i.origin)), [
        ('lockout', 'signup'),
        ('reset', 'auth'),
      ]);
    });

    test('an override that leaves the text unchanged keeps its origin', () {
      final pattern = mergeOne('signup', {
        'auth': [layerOf('auth', authYaml())],
        'signup': [
          layerOf('signup', '''
id: signup
description: Sign-up checklist.
extends: auth
items:
  - id: lockout
    text: Name the lockout rule.
'''),
        ],
      });

      expect(pattern.items.first.origin, 'auth');
    });

    test('a project rewrite of an own item takes the pattern id', () {
      final pattern = mergeOne('auth', {
        'auth': [
          layerOf('auth', authYaml()),
          projectOf('auth', '''
id: auth
items:
  - id: lockout
    text: Project lockout text.
'''),
        ],
      });

      expect(pattern.items.first.origin, 'auth');
    });
  });

  group('FeaturePattern.toJson', () {
    test('prints the six keys with items as id and text', () {
      final pattern = mergeOne('signup', {
        'auth': [layerOf('auth', authYaml())],
        'signup': [
          layerOf('signup', '''
id: signup
description: Sign-up checklist.
extends: auth
items:
  - id: verify_email
    text: Name the email check.
reference:
  - title: Handbook
'''),
        ],
      });

      expect(pattern.toJson(), {
        'id': 'signup',
        'pack': 'software',
        'extends': 'auth',
        'description': 'Sign-up checklist.',
        'items': [
          {'id': 'lockout', 'text': 'Name the lockout rule.'},
          {'id': 'reset', 'text': 'Name the reset path.'},
          {'id': 'verify_email', 'text': 'Name the email check.'},
        ],
        'reference': [
          {'title': 'Handbook'},
        ],
      });
    });

    test('leaves out pack and extends when a pattern has neither', () {
      final pattern = mergeOne('onboarding', {
        'onboarding': [
          projectOf('onboarding', '''
id: onboarding
description: Onboarding checklist.
items:
  - id: welcome
    text: Name the welcome step.
'''),
        ],
      });

      expect(pattern.toJson().keys, [
        'id',
        'description',
        'items',
        'reference',
      ]);
    });
  });

  group('FeaturePattern.renderBody', () {
    FeaturePattern signup() => mergeOne('signup', {
      'auth': [layerOf('auth', authYaml())],
      'signup': [
        layerOf('signup', '''
id: signup
description: Sign-up checklist.
extends: auth
items:
  - id: verify_email
    text: Name the email check.
reference:
  - title: Handbook, chapter 2
    url: https://example.test/handbook
  - title: Standard
'''),
      ],
    });

    test('prints the description, every item, then the sources', () {
      expect(
        signup().renderBody(),
        'Sign-up checklist.\n'
        '- **lockout** Name the lockout rule.\n'
        '- **reset** Name the reset path.\n'
        '- **verify_email** Name the email check.\n'
        'Pattern sources:\n'
        '- Handbook, chapter 2: https://example.test/handbook\n'
        '- Standard\n',
      );
    });

    test('prints only the items it is given', () {
      final pattern = signup();

      expect(
        pattern.renderBody([pattern.items.last]),
        'Sign-up checklist.\n'
        '- **verify_email** Name the email check.\n'
        'Pattern sources:\n'
        '- Handbook, chapter 2: https://example.test/handbook\n'
        '- Standard\n',
      );
    });

    test('prints no sources block when the pattern has no reference', () {
      final pattern = mergeOne('auth', {
        'auth': [layerOf('auth', authYaml())],
      });

      expect(
        pattern.renderBody(),
        'Sign-in checklist.\n'
        '- **lockout** Name the lockout rule.\n'
        '- **reset** Name the reset path.\n',
      );
    });

    test('an item written as a block scalar prints with no trailing blank '
        'line', () {
      final pattern = mergeOne('auth', {
        'auth': [
          layerOf('auth', '''
id: auth
description: Sign-in checklist.
items:
  - id: lockout
    text: |
      Name the lockout rule.
'''),
        ],
      });

      expect(pattern.items.single.text, 'Name the lockout rule.');
      expect(
        pattern.renderBody(),
        'Sign-in checklist.\n- **lockout** Name the lockout rule.\n',
      );
    });

    test('prints the description alone when no item is given', () {
      final pattern = signup();

      expect(
        pattern.renderBody(const []),
        'Sign-up checklist.\n'
        'Pattern sources:\n'
        '- Handbook, chapter 2: https://example.test/handbook\n'
        '- Standard\n',
      );
    });
  });
}
