import enum
import collections
import pathlib


class ReferenceTypes(enum.Enum):
    LINEAR_REFERENCE_GENOME = 0
    GENOME = 0
    PANGENOME_REFERENCE_GRAPH = 1
    PANGENOME = 1
    REFERENCE_CALLSET = 2
    CALLSET = 2


REFERENCE_WILDCARD_LOOKUP = collections.defaultdict(list)
REFERENCE_FILE_LOOKUP = collections.defaultdict(dict)


for member in ReferenceTypes:
    config_key = member.name.lower()
    configured_reference = config[config_key]
    ref_name = configured_reference["label"]
    if not ref_name.isalnum():
        err_msg = (
            f"Invalid reference label: {ref_name} - "
            "Please use only alphanumeric (a-z, 0-9) characters "
            "(case is ignored)."
        )
        logerr(err_msg)
        raise ValueError(err_msg)

    ref_file_path = pathlib.Path(configured_reference["path"])
    if not ref_file_path.is_file():
        err_msg = f"Configured reference file is not accessible: {ref_name} / {ref_file_path}"
        logerr(err_msg)
        raise FileNotFoundError(err_msg)
    REFERENCE_WILDCARD_LOOKUP[member].append(ref_name)
    REFERENCE_FILE_LOOKUP[member][ref_name] = ref_file_path
