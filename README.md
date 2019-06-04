[![codecov](https://codecov.io/gh/allenai/vae/branch/master/graph/badge.svg?token=NOriF2Rm8p)](https://codecov.io/gh/allenai/vae)

# VAMPIRE

VAriational Methods for Pretraining in Resource-limited Environments

To appear in ACL 2019

## Installation

Install necessary dependencies via `requirements.txt`, which will include the latest unreleased install of `allennlp` (from the `master` branch).

```
pip install -r requirements.txt
```

Verify your installation by running: 

```
SEED=42 pytest -v --color=yes vampire
```

All tests should pass.

## Download Data

Download your dataset of interest, and make sure it is made up of json files, where each line of each file corresponds to a separate instance. Each line must contain a `text` field, and optionally a `label` field. 

In this tutorial we use the AG News dataset hosted on AllenNLP. Download it using the following script:

```
sh scripts/download_ag.sh
```

## Preprocess data

To make pretraining fast, we precompute fixed bag-of-words representations of the data. 

```
python -m spacy download en
python -m scripts.preprocess_data \
            --train-path examples/ag/train.jsonl \
            --dev-path examples/ag/dev.jsonl \
            --tokenize \
            --tokenizer-type spacy \
            --vocab-size 30000 \
            --serialization-dir examples/ag
```

This script will tokenize your data, and save the resulting output into the specified `serialization-dir`.

In `examples/ag`, you should see:

* `train.npz` - pre-computed bag of word representations of the training data
* `dev.npz` - pre-computed bag of word representations of the dev data
* `vampire.bgfreq` - background word frequencies
* `vocabulary/` - AllenNLP vocabulary directory

## Create reference corpus

We now have to build a reference corpus to calcuate NPMI (normalized pointwise mutual information), a measure of topical coherence that we use for early stopping.

In this work, we use the validation data as our reference corpus. Run:

```
python -m scripts.make_reference_corpus examples/ag/dev.jsonl examples/ag/reference
```

In `examples/ag/reference`, you should see:

* `ref.npz` - pre-computed bag of word representations of the reference corpus
* `ref.vocab.json` - the reference corpus vocabulary


## Pretrain VAMPIRE

Set your data directory as the environment variable:

```
export DATA_DIR="$(pwd)/examples/ag"
```

Then run VAMPIRE:

```
python -m scripts.train -c training_config/vampire.jsonnet -s model_logs/vampire -e VAMPIRE -d -1
```

This model can be run on a CPU (`-d -1`). To run on a GPU instead, run with `-d 0` (or any other available CUDA device number)

This command will output training logs at `model_logs/vampire`.

For convenience, we include the `-o` (`--override`) flag to remove the previous experiment at the same serialization directory.


## Inspect topics learned

During training, we output the learned topics after each epoch in the serialization directory. 

Check out the `best_epoch` field in `model_logs/vampire/metrics.json`, which corresponds to when NPMI is highest during training. 

Then look at the corresponding epoch's file in `model_logs/vampire/topics/`.

## Use VAMPIRE with a downstream classifier

Using VAMPIRE is essentially the same as using regular ELMo. See [this documentation](https://github.com/allenai/allennlp/blob/master/tutorials/how_to/elmo.md#using-elmo-with-existing-allennlp-models) for details on how to do that.

This module's classifier has some convenience functions for including VAMPIRE with a downstream classifier. 

First, set some environment variables:
* `VAMPIRE_DIR`: path to newly trained VAMPIRE
* `VAMPIRE_DIM`: dimensionality of the newly trained VAMPIRE (the token embedder needs it explicitly)
* `THROTTLE`: the sample size of the data we want to train on.
* `EVALUATE_ON_TEST`: whether or not you would like to evaluate on test


```
export VAMPIRE_DIR="$(pwd)/model_logs/vampire"
export VAMPIRE_DIM=64
export THROTTLE=200
export EVALUATE_ON_TEST=0
```

Then, you can run the classifier:

```
python -m scripts.train -c training_config/classifier.jsonnet -s model_logs/clf -e CLASSIFIER -d -1
```


To run on a GPU, run with `-d 0` (or any other available CUDA device number)

This command will output training logs at `model_logs/clf`.

The dataset sample (specified by `THROTTLE`) is governed by the global seed supplied to the trainer; the same seed will result in the same subsampling of training data. You can set an explicit seed by passing the additional flag `-x` to the `train` module.

With 200 examples, we report a test accuracy of 83.9 +- 0.9 over 5 random seeds on the AG dataset. Note that your results may vary beyond these bounds in the low-resource setting.
