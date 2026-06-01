import dataclasses
import enum


class SampleColumn(enum.Enum):
    sample = 0
    sample_id = enum.auto()
    sampleid = enum.auto()
    samples = enum.auto()
    sample_name = enum.auto()


class InputPathColumn(enum.Enum):
    input_path = 0
    inputpath = enum.auto()
    inputs = enum.auto()
    input_files = enum.auto()
    input_data = enum.auto()


@dataclasses.dataclass(frozen=True)
class MinimalSampleSheetColumns:
    sample: str = SampleColumn(0).name
    input_path: str = InputPathColumn(0).name
    _column_alias_names: dict[str | str] = dataclasses.field(
        init=False, default_factory=dict
    )

    def __post_init__(self):
        self._update_alias_names(SampleColumn)
        self._update_alias_names(InputPathColumn)
        return

    def _update_alias_names(self, column_aliases):

        norm_name = column_aliases(0).name
        for alias in column_aliases:
            self._column_alias_names[alias.name] = norm_name
        return

    def get_mandatory_column_names(self):
        """Returns a sorted list of mandatory column
        names, i.e. columns that must exist in the
        sample sheet for the workflow. Additional
        columns are always allowed.

        Args:
            self (MinimalSampleSheetColumns): class instance

        Returns:
            column_names (List[str]): sorted list of column names

        """
        not_callable = lambda m: not callable(getattr(self, m))
        not_internal = lambda m: not m.startswith("_")

        is_mandatory_column_name = lambda m: not_callable(m) and not_internal(m)

        column_names = sorted(
            member for member in dir(self) if is_mandatory_column_name(member)
        )
        assert len(column_names) > 1
        return column_names

    def norm_column_name(self, column_name):
        """Perform a simple normalization for the given column
        name (strip underscores, make lowercase) and then
        check that the column name is a valid Python identifier, which
        is equivalent to representing a well-behaved column name for
        a Pandas DataFrame.
        Next, it is checked if the column name is an alias for a
        mandatory column and, if so, the primary name for that column
        is returned instead.
        Example: 'sample_id' would be normalized to 'sample'

        Args:
            self (MinimalSampleSheetColumns): class instance
            column_name (str): column name to normalize

        Returns:
            norm_column_name (str): normalized column name

        Raises:
            ValueError: if column name is not a valid Python identifier
        """
        sanitized_column_name = column_name.strip().strip("_").lower()
        if not sanitized_column_name.isidentifier():
            err_msg = (
                f"Column name is invalid: {column_name} / {sanitized_column_name} --- "
                "Please only use the characters a-z, 0-9 and '_' in the sample sheet header."
            )
            raise ValueError(err_msg)
        norm_column_name = self._column_alias_names.get(sanitized_column_name, None)
        if norm_column_name is None:
            norm_column_name = sanitized_column_name
        return norm_column_name
