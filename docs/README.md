# Documentation for Snakemake workflow NAME HERE

**Note to developers**: Describe the purpose of the workflow (the big picture)

## General documentation

### Core functionality of the template

All standard workflows of the CUBI implement the same user
interface (or at least aim for a highly similar interface).
Hence, before [executing the workflow](template/running.md),
we strongly recommend reading the through the documentation
that explains how we help you to keep track of your analysis
results; we refer to this concept as
[**"file accounting"**](template/accounting.md). This feature
of standard CUBI workflows enables the pipeline to auto-
matically create a so-called [**"manifest"** file](template/accounting.md)
for your analysis run.

### Core parameters of the template

All relevant parameters are documented in [the auto-doc file](template/autodoc.md).
Users can limit their reading to all command line parameters (labeled
as `USERCONFIG` in the parameter file).

Developers should read the entire [documentation](template/autodoc.md)
and must use all parameters labeled as `GLOBALVAR` when implementing a CUBI
workflow to enforce a coherent layout and structure. Additionally, convenience
functions implemented in the template are labeled as `GLOBALFUN` and globally
accessible 'objects' such as classes are labeled as `GLOBALOBJ`. One such example
is the `DOC_RECORDER` (alias: `DOCREC`) object that must be used
to document workflow parameters, functions and so on.

Parameters labeled as `DEVONLY` have a very specific purpose within the
workflow template and should thus only be used with proper insight into
the inner workings of the workflow template.

In case of questions, please open a GitHub issue in the repository
of the workflow you are trying to execute.

**Note to developers**: the above is the templated user documentation;
make sure to update or link to additional documentation, e.g.
describing workflow-specific parameters etc. (see next)

### Workflow-specific configuration and functionality

**Note to developers**: add workflow-specific documentation
to this section or link to Markdown documents
*organized under `docs/workflow`* in case of a more
extensive documentation.

For example, when documenting the parameters of your workflow,
make use of the `DocRecorder` object with the context `WORKFLOW`
to create the documentation file `docs/workflow/autodoc.md`.

In order to trigger building the documentation, execute the workflow
with the rule `run_build_docs` as the target. For an example how to
document module members (variables/parameters, functions etc.), see
the documentation of the `DocRecorder` instance itself in
`rules::commons::05_docgen.smk`.

## Developer documentation

Besides reading the user documentation, CUBI developers find more
information regarding standadized workflow development in the
[developer notes](template/developing.md). Please keep in mind
to always cross-link that information with the guidelines
published in the
[CUBI knowledge base](https://github.com/core-unit-bioinformatics/knowledge-base/wiki/).

Please raise any issues with these guidelines "close to the code",
i.e., either open an issue in the
[knowledge base repo](https://github.com/core-unit-bioinformatics/knowledge-base)
or in the affected repo for more specific cases.
