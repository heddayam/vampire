import itertools
import json
import logging
from io import TextIOWrapper
from typing import Dict

import numpy as np
from allennlp.common.checks import ConfigurationError
from allennlp.common.file_utils import cached_path
from allennlp.data.dataset_readers.dataset_reader import DatasetReader
from allennlp.data.fields import (ArrayField, Field, LabelField, ListField,
                                  MetadataField, TextField)
from allennlp.data.instance import Instance
from overrides import overrides

from vampire.common.util import load_sparse

logger = logging.getLogger(__name__)  # pylint: disable=invalid-name


@DatasetReader.register("vampire_reader")
class VampireReader(DatasetReader):
    """
    Reads bag of word vectors from a sparse matrices representing training and validation data.

    Expects a sparse matrix of size N documents x vocab size, which can be created via 
    the scripts/preprocess_data.py file.

    The output of ``read`` is a list of ``Instances`` with the field:
        vec: ``ArrayField``

    Parameters
    ----------
    lazy : ``bool``, optional, (default = ``False``)
        Whether or not instances can be read lazily.
    """
    def __init__(self, lazy: bool = False, covariate_file: str = None) -> None:
        super().__init__(lazy=lazy)
        self._covariate_file = covariate_file

    @overrides
    def _read(self, file_path):
        mat = load_sparse(file_path)        
        mat = mat.tolil()
        if self._covariate_file:
            with open(self._covariate_file, 'r') as file_:
                covariates = [line.strip() for line in file_.readlines()]

        for ix in range(mat.shape[0]):
            if self._covariate_file:
                instance = self.text_to_instance(vec=mat[ix].toarray().squeeze(), covariate=covariates[ix])
            else:
                instance = self.text_to_instance(vec=mat[ix].toarray().squeeze())
            if instance is not None:
                yield instance

    @overrides
    def text_to_instance(self, vec: str, covariate: str=None) -> Instance:  # type: ignore
        """
        Parameters
        ----------
        text : ``str``, required.
            The text to classify
        label ``str``, optional, (default = None).
            The label for this text.

        Returns
        -------
        An ``Instance`` containing the following fields:
            tokens : ``TextField``
                The tokens in the sentence or phrase.
            label : ``LabelField``
                The label label of the sentence or phrase.
        """
        # pylint: disable=arguments-differ
        fields: Dict[str, Field] = {}
        fields['tokens'] = ArrayField(vec)
        if covariate:
            fields['covariate_label'] = LabelField(covariate, skip_indexing=False)
        return Instance(fields)
