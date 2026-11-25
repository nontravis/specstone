/// Project layers that stand in for the per-feature rule doc, its project
/// twin, and the shared-rule doc that `software-tech` no longer ships.
///
/// A test of a rule over ID'd items, override lines, or covers needs a doc
/// type holding them; these keep the old paths, `DOMAIN.md` and
/// `topics/{slug}.md`, under ids no shipped step folds or drops.
library;

/// The project layer file of [rulebookLayer].
const rulebookLayerFile = '.specstone/templates/rulebook.yaml';

/// The project layer file of [projectRulebookLayer].
const projectRulebookLayerFile = '.specstone/templates/project_rulebook.yaml';

/// The project layer file of [charterLayer].
const charterLayerFile = '.specstone/templates/charter.yaml';

/// A per-feature doc of entities and `INV-` invariants at
/// `specs/f{nn}_{slug}/DOMAIN.md`, with `overrides` and `tasks`.
const rulebookLayer = r'''
id: rulebook
description: |-
  One feature's rules: its entities and the invariants that hold.
path: specs/f{nn}_{slug}/DOMAIN.md
parent: feature
per_target: true
fields:
  - id: overrides
    type: string
    list: true
    description: |-
      Records one entry per Overrides line link.
  - id: tasks
    type: task_ref
    list: true
    description: |-
      Lists the doc's tasks.
sections:
  - id: entities
    header: Entities
    required: true
    description: |-
      Write a table of Entity, Kind, Identity, Owns.
    lint:
      banned_patterns:
        - id: entity_kind
          pattern: '^\|[^|]*\|(?! *(?:Kind|Aggregate root|Entity|Service|Repository|:?-+:?) *\|)[^|]*\|'
          message: 'Kind is not an allowed value; guide line: Write Kind as Aggregate root, Entity, Service, or Repository'
          in: all
  - id: value_objects
    header: Value objects
    description: |-
      Write a table of VO, Backed by, Validation.
  - id: invariants
    header: Invariants
    required: true
    prefix_id: INV-
    description: |-
      Write each invariant as `- **INV-<N>** <rule>`, never a numbered item.
    lint:
      max_sentences:
        - count: 1
      item_fields:
        - field: Enforcer
          default_from: entities
        - field: Consistency
          values: [eventual]
          optional: true
        - field: Corrective policy
          when:
            field: Consistency
            value: eventual
      banned_patterns:
        - id: numbered_invariant
          pattern: '^\d+[.)] '
          message: 'invariant is a numbered item; guide line: never a numbered item'
          in: all
  - id: known_limits
    header: Known limits
    description: |-
      List the cases the feature leaves unhandled.
  - id: lifecycle
    header: Lifecycle
    description: |-
      Write a Mermaid `stateDiagram-v2` alone, no prose.
    lint:
      banned_patterns:
        - id: lifecycle_prose
          pattern: '^(?!## |\s*(?:- )?Overrides:)\s*\S'
          message: 'Lifecycle holds a line outside the Mermaid fence; guide line: Write a Mermaid `stateDiagram-v2` alone, no prose'
          in: all
  - id: data_touch
    header: Data touch
    description: |-
      Write a table of Table, Operation, Field / Change.
  - id: commands_and_events
    header: Commands and events
    description: |-
      Write a table of the commands and events.
  - id: terms
    header: Terms
    description: |-
      List the terms the feature adds.
lint:
  title_no_number: true
  max_chars: 50000
  max_lines: 300
''';

/// The project twin of [rulebookLayer] at `specs/DOMAIN.md`, with no parent
/// and no `overrides`.
const projectRulebookLayer = '''
id: project_rulebook
extends: rulebook
description: |-
  The project's rules: the entities and invariants every feature uses.
path: specs/DOMAIN.md
parent:
bundle: [implement, design]
fields:
  - id: overrides
    disabled: true
''';

/// A shared doc of `RULE-` rules at `specs/topics/{slug}.md`, with a required
/// prefix `covers` list, `overrides`, and `tasks`.
const charterLayer = '''
id: charter
description: |-
  A rule set two or more features apply, tied to its code.
path: specs/topics/{slug}.md
per_target: true
fields:
  - id: covers
    type: output_ref
    list: true
    required: true
    pointer: prefix
    description: |-
      Lists the code folders or files the charter covers.
  - id: overrides
    type: string
    list: true
    description: |-
      Records one entry per Overrides line link.
  - id: tasks
    type: task_ref
    list: true
    description: |-
      Lists the doc's tasks.
sections:
  - id: purpose
    header: Purpose
    required: true
    description: |-
      Write what the charter is for.
    lint:
      item_count:
        max: 1
  - id: scope
    header: Scope
    required: true
    description: |-
      Write what it covers.
  - id: used_by
    header: Used by
    required: true
    description: |-
      Write a table of Feature, What it uses.
    lint:
      item_count:
        min: 2
  - id: rules
    header: Rules
    prefix_id: RULE-
    description: |-
      Write each rule as `- **RULE-<N>** <rule>`.
    lint:
      max_sentences:
        - count: 1
  - id: interface
    header: Interface
    description: |-
      List the public entry points as `path:Symbol` pointers.
  - id: model
    header: Model
    description: |-
      Name the shared data shapes in words.
  - id: examples
    header: Examples
    description: |-
      Give one example per rule that needs it.
  - id: open_questions
    header: Open questions
    description: |-
      List the unresolved decisions.
lint:
  title_no_number: true
  max_chars: 50000
  max_lines: 300
''';

/// The three layer files, keyed by project path.
const rulebookLayers = <String, String>{
  rulebookLayerFile: rulebookLayer,
  projectRulebookLayerFile: projectRulebookLayer,
  charterLayerFile: charterLayer,
};

/// The project layer file of [concernsLayer].
const concernsLayerFile = '.specstone/templates/architecture.yaml';

/// A project layer that gives `architecture` a `concerns` section, one line
/// per concern ending `see <place>`, which `software-tech` no longer ships.
const concernsLayer = '''
sections:
  - id: concerns
    header: Concerns
    description: |-
      Write one line per concern that applies, ending `see <section or sibling doc>`.
''';
