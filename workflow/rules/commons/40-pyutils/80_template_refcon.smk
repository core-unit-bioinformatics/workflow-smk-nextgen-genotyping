"""This module implements the functions to
interact with CUBI-style reference containers.
To non-template (workflow) developers, these
functions are irrelevant because the use of
reference containers is hidden to the workflow
users and only triggered by setting the respective
variables - see:
commons::30-settings::20-environment::30_ref_container.smk
"""

import pathlib

# needed to handle reference container
# manifest cache files
import pandas


_THIS_MODULE = ["commons", "40-pyutils", "80_template_refcon.smk"]
_THIS_CONTEXT = DocContext.TEMPLATE

DOCREC.add_module_doc(_THIS_CONTEXT, _THIS_MODULE)


def trigger_refcon_manifest_caching(wildcards):
    """This function merely triggers the checkpoint
    to merge all reference containers caches into
    one. This checkpoint is needed to get a
    start-to-end run, otherwise "refcon_find_container"
    would produce an error.

    Args:
        wildcards (dict): the Snakemake wildcards object

    Returns:
        pathlib.Path: the path to the reference container manifest cache file
    """
    refcon_manifest_cache = str(
        checkpoints.refcon_cache_manifests.get(**wildcards).output.cache
    )
    expected_path = DIR_REFCON_CACHE.joinpath("refcon_manifests.cache")
    # following assert safeguard against future changes
    assert pathlib.Path(refcon_manifest_cache).resolve() == expected_path.resolve()
    return refcon_manifest_cache


DOCREC.add_function_doc(trigger_refcon_manifest_caching)


def refcon_find_container(manifest_cache, ref_filename):
    """Given the requested ref_filename as input,
    find the matching reference container that can provide
    this file. Throws for ambiguous or no matchings.

    TODO: adapt this function to also work in a lenient
    mode that simply checks if the requested file already
    exists in GLOBAL_REF and then returns False to sidestep
    a forced data loading from a container (accept that the
    user manually copies a reference file into the global
    reference folder).

    Args:
        manifest_cache (pathlib.Path): path to reference container manifest cache file
        ref_filename (str): the name of the reference file we are looking for

    Returns:
        pathlib.Path: the path to the reference container holding the reference file

    """

    if not pathlib.Path(manifest_cache).is_file():
        if DRYRUN:
            return ""
        else:
            if VERBOSE:
                warn_msg = "Warning: reference container manifest cache "
                warn_msg += "does not exist yet. Returning empty reference "
                warn_msg += "container path."
                logerr(warn_msg)
            return ""

    manifests = pandas.read_csv(manifest_cache, sep="\t", header=0)

    refcon_names = sorted(manifests["refcon_name"].unique())

    matched_names = set(manifests.loc[manifests["name"] == ref_filename, "refcon_name"])
    matched_alias1 = set(
        manifests.loc[manifests["alias1"] == ref_filename, "refcon_name"]
    )
    matched_alias2 = set(
        manifests.loc[manifests["alias2"] == ref_filename, "refcon_name"]
    )

    select_container = sorted(matched_names.union(matched_alias1, matched_alias2))
    if len(select_container) > 1:
        raise ValueError(
            f'The requested reference file name "{ref_filename}" exists in multiple containers: {select_container}'
        )
    elif len(select_container) == 0:
        raise ValueError(
            f'The requested reference file name "{ref_filename}" exists in none of these containers: {refcon_names}'
        )
    else:
        pass
    container_path = DIR_REFCON.joinpath(select_container[0] + ".sif")
    return container_path


DOCREC.add_function_doc(refcon_find_container)


def load_reference_container_names():
    """Load the names (pathlib.Path.stem) of all reference containers
    (filter by the file extension *.sif) from the DIR_REFCON path.
    Compares that list with the container names required for the current
    workflow run as defined in the workflow config.

    Args:
        None

    Returns:
        List[pathlib.Path]: sorted list of reference container names

    Raises:
        ValueError: requested container is missing from DIR_REFCON location

    """

    existing_container = [sif_file.stem for sif_file in DIR_REFCON.glob("*.sif")]
    requested_container = config.get("reference_container_names", [])
    if not requested_container:
        raise ValueError(
            "The config option 'use_reference_container' is set to True. "
            "Consequently, you need to specify a list of container names "
            "in the config with the option 'reference_container_names'."
        )
    missing_container = ""
    for req_con in requested_container:
        if req_con not in existing_container:
            missing_container += f"\nMissing reference container: {req_con}"
            missing_container += f"\nExpected container image location: {DIR_REFCON.joinpath(req_con)}.sif\n"

    if missing_container:
        logerr(missing_container)
        raise ValueError(
            "At least one of the specified reference containers "
            "(option 'reference_container_names' in the config) "
            "does not exist in the reference container store."
        )
    return sorted(requested_container)


DOCREC.add_function_doc(refcon_find_container)
