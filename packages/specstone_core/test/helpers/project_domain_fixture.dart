/// The project template that adds a project-wide `project_domain` doc type.
///
/// It builds on the shipped `domain` type, moves it to the spec folder root,
/// and clears its parent, so it sits beside the feature-level `domain` docs.
const projectDomainTemplate = <String, String>{
  '.specstone/templates/project_domain.yaml':
      'id: project_domain\n'
      'extends: domain\n'
      'description: The domain rules every feature of the project uses.\n'
      'path: specs/DOMAIN.md\n'
      'parent:\n'
      'bundle: [implement, design]\n',
};
