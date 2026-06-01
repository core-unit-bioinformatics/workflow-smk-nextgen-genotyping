"""Module for settings related to
the use of reference containers.
Reference containers are the CUBI-specific
way for handling fixed reference data.
The template must always be developed in a
way that makes the use of reference containers
entirely optional.
"""

_THIS_MODULE = ["commons", "30-settings", "20-environment", "30_ref_container.smk"]
_THIS_CONTEXT = DocContext.TEMPLATE

DOCREC.add_module_doc(_THIS_CONTEXT, _THIS_MODULE)


USE_REFERENCE_CONTAINER = config.get(OPTIONS.refcon.name, OPTIONS.refcon.default)
USE_REFCON = USE_REFERENCE_CONTAINER  # shorthand
assert isinstance(USE_REFERENCE_CONTAINER, bool)


DOCREC.add_member_doc(
    DocLevel.USERCONFIG,
    "USE_REFERENCE_CONTAINER",
    USE_REFERENCE_CONTAINER,
    (
        "Using CUBI-style reference containers in this workflow "
        "requires setting the parameter 'use_reference_container: true' "
        "in a loaded config YAML file or on the command line via "
        "--config use_reference_container=true. This user setting is "
        "stored in the global variable USE_REFERENCE_CONTAINER in the "
        "workflow context at runtime. Note to users: setting this option "
        "to 'true' implies that the options 'reference_container_store' "
        "and 'reference_container_names' must be non-empty."
    ),
)


DOCREC.add_member_doc(
    DocLevel.USERCONFIG,
    "USE_REFCON",
    USE_REFCON,
    (
        "Shorthand for 'USE_REFERENCE_CONTAINER' - only available in "
        "the workflow context at runtime. See documentation for "
        "'USE_REFERENCE_CONTAINER' for details."
    ),
)


if USE_REFERENCE_CONTAINER:
    try:
        DIR_REFERENCE_CONTAINER = config[OPTIONS.refstore.name]
    except KeyError:
        raise KeyError(
            "The config option 'use_reference_container' is set to True. "
            "Consequently, the option 'reference_container_store' must be "
            "set to an existing folder on the file system containing the "
            "reference container images (*.sif files)."
        )
    else:
        DIR_REFERENCE_CONTAINER = pathlib.Path(DIR_REFERENCE_CONTAINER).resolve(
            strict=True
        )
        # if the workflow is configured to use reference container,
        # create the necessary caching folder structure.
        DIR_REFCON_CACHE = CONST_DIRS.cache_refcon
        DIR_REFCON_CACHE.mkdir(exist_ok=True, parents=True)
else:
    DIR_REFERENCE_CONTAINER = pathlib.Path("/")
    DIR_REFCON_CACHE = None

# TODO - ?
# this is technically a PATH whose definition is
# put here by contextual grouping because of the access
# to USE_REFERENCE_CONTAINER; logically, it would
# also fit in
# commons::30-settings::20-environment::05_paths.smk
# Same holds for the above DIR_REFCON_CACHE
DIR_REFCON = DIR_REFERENCE_CONTAINER  # shorthand


DOCREC.add_member_doc(
    DocLevel.USERCONFIG,
    "DIR_REFERENCE_CONTAINER",
    DIR_REFERENCE_CONTAINER,
    (
        "The path on the file system (accessible at workflow runtime) "
        "that contains the reference containers (*.sif files). "
        "Setting the option 'reference_container_store' to a non-empty "
        "value is required if 'use_reference_container' is set to 'true'."
    ),
)


DOCREC.add_member_doc(
    DocLevel.USERCONFIG,
    "DIR_REFCON",
    DIR_REFCON,
    (
        "Shorthand for 'DIR_REFERENCE_CONTAINER' - only available in "
        "the workflow context at runtime. See documentation for "
        "'DIR_REFERENCE_CONTAINER' for details."
    ),
)


DOCREC.add_member_doc(
    DocLevel.DEVONLY,
    "DIR_REFCON_CACHE",
    DIR_REFCON_CACHE,
    (
        "The path in the Snakemake working directory hierarchy that "
        "contains the manifest cache for all reference containers."
    ),
)
