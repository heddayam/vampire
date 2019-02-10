local CUDA_DEVICE =
  if std.parseInt(std.extVar("NUM_GPU")) == 0 then
    -1
  else if std.parseInt(std.extVar("NUM_GPU")) > 1 then
    std.range(0, std.extVar("NUM_GPU") - 1)
  else if std.parseInt(std.extVar("NUM_GPU")) == 1 then
    0;

local ELMO_FIELDS = {
  "elmo_indexer": {
    "elmo": {
      "type": "elmo_characters",
    }
  },
  "elmo_embedder": {
    "elmo": {
      "type": "elmo_token_embedder",
      "options_file": "https://s3-us-west-2.amazonaws.com/allennlp/models/elmo/2x4096_512_2048cnn_2xhighway/elmo_2x4096_512_2048cnn_2xhighway_options.json",
      "weight_file": "https://s3-us-west-2.amazonaws.com/allennlp/models/elmo/2x4096_512_2048cnn_2xhighway/elmo_2x4096_512_2048cnn_2xhighway_weights.hdf5",
      "do_layer_norm": false,
      "dropout": 0.2
    }
  }
};

local VAE_FIELDS = {
    "vae_indexer": {
        "vae_tokens": {
            "type": "single_id",
            "namespace": "vae",
            "lowercase_tokens": true
        }
    },  
    "vae_embedder": {
        "vae_tokens": {
                "type": "vae_token_embedder",
                "representation": "encoder_output",
                "expand_dim": true,
                "model_archive": "s3://suching-dev/model.tar.gz",
                "background_frequency": "s3://suching-dev/vae.bgfreq.json",
                "dropout": 0.2
        }
    }
};

local VOCABULARY_WITH_VAE = {
  "vocabulary":{
              "type": "vocabulary_with_vae",
              "vae_vocab_file": "s3://suching-dev/vae.txt",
          }
};

local BASE_READER(ADD_ELMO, ADD_VAE, THROTTLE, USE_SPACY_TOKENIZER) = {
  "lazy": false,
  "type": "semisupervised_text_classification_json",
  "tokenizer": {
    "word_splitter": if USE_SPACY_TOKENIZER == 1 then "spacy" else "just_spaces",
  },
  "token_indexers": {
    "tokens": {
      "type": "single_id",
      "lowercase_tokens": true,
      "namespace": "classifier"
    }
  } + if ADD_VAE == 1 then VAE_FIELDS['vae_indexer'] else {}
    + if ADD_ELMO == 1 then ELMO_FIELDS['elmo_indexer'] else {},
  "sequence_length": 400,
  "sample": THROTTLE,
};


local BOE_CLF(EMBEDDING_DIM, ADD_ELMO, ADD_VAE) = {
         "encoder": {
            "type": "seq2vec",
             "architecture": {
                "embedding_dim": EMBEDDING_DIM,
                "type": "boe"
             }
         },
         "dropout": std.parseInt(std.extVar("DROPOUT")) / 10,
         "input_embedder": {
            "token_embedders": {
               "tokens": {
                  "embedding_dim": EMBEDDING_DIM,
                  "trainable": true,
                  "type": "embedding",
                  "vocab_namespace": "classifier"
               }
            } + if ADD_VAE == 1 then VAE_FIELDS['vae_embedder'] else {}
              + if ADD_ELMO == 1 then ELMO_FIELDS['elmo_embedder'] else {}
         },
         
      
};


local CNN_CLF(EMBEDDING_DIM, NUM_FILTERS,  CLF_HIDDEN_DIM, ADD_ELMO, ADD_VAE) = {
         "encoder": {
             "type": "seq2vec",
             "architecture": {
                 "type": "cnn",
                 "ngram_filter_sizes": std.range(1, std.parseInt(std.extVar("MAX_FILTER_SIZE"))),
                 "num_filters": NUM_FILTERS,
                 "embedding_dim": EMBEDDING_DIM,
                 "output_dim": CLF_HIDDEN_DIM, 
             },
         },
         "dropout": std.parseInt(std.extVar("DROPOUT")) / 10,
         "input_embedder": {
            "token_embedders": {
               "tokens": {
                  "embedding_dim": EMBEDDING_DIM,
                  "trainable": true,
                  "type": "embedding",
                  "vocab_namespace": "classifier"
               }
            }
         } + if ADD_VAE == 1 then VAE_FIELDS['vae_embedder'] else {}
          + if ADD_ELMO == 1 then ELMO_FIELDS['elmo_embedder'] else {},

      
};

local LSTM_CLF(EMBEDDING_DIM, NUM_ENCODER_LAYERS, CLF_HIDDEN_DIM, AGGREGATIONS, ADD_ELMO, ADD_VAE) = {
        "input_embedder": {
            "token_embedders": {
               "tokens": {
                  "embedding_dim": EMBEDDING_DIM,
                  "trainable": true,
                  "type": "embedding",
                  "vocab_namespace": "classifier"
               }
            } + if ADD_VAE == 1 then VAE_FIELDS['vae_embedder'] else {}
              + if ADD_ELMO == 1 then ELMO_FIELDS['elmo_embedder'] else {}
         },
        "encoder": {
          "type" : "seq2seq",
          "architecture": {
            "type": "lstm",
            "num_layers": NUM_ENCODER_LAYERS,
            "bidirectional": true,
            "input_size": EMBEDDING_DIM,
            "hidden_size": CLF_HIDDEN_DIM
          },
         "aggregations": AGGREGATIONS,
        },
        "dropout": std.parseInt(std.extVar("DROPOUT")) / 10
};

local LR_CLF(ADD_VAE) = {
        "input_embedder": {
            "token_embedders": {
               "tokens": {
                  "type": "bag_of_word_counts",
                  "ignore_oov": "true",
                  "vocab_namespace": "classifier"
               }
            } + if ADD_VAE == 1 then VAE_FIELDS['vae_embedder'] else {}
         },
         "dropout": std.parseInt(std.extVar("DROPOUT")) / 10
};

local CLASSIFIER = 
    if std.extVar("CLASSIFIER") == "lstm" then
        LSTM_CLF(std.parseInt(std.extVar("EMBEDDING_DIM")),
                 std.parseInt(std.extVar("NUM_ENCODER_LAYERS")),
                 std.parseInt(std.extVar("CLF_HIDDEN_DIM")),
                 std.extVar("AGGREGATIONS"),
                 std.parseInt(std.extVar("ADD_ELMO")),
                 std.parseInt(std.extVar("ADD_VAE")))
    else if std.extVar("CLASSIFIER") == "cnn" then
        CNN_CLF(std.parseInt(std.extVar("EMBEDDING_DIM")),
                std.parseInt(std.extVar("NUM_FILTERS")),
                std.parseInt(std.extVar("CLF_HIDDEN_DIM")),
                std.parseInt(std.extVar("ADD_ELMO")),
                std.parseInt(std.extVar("ADD_VAE")))
    else if std.extVar("CLASSIFIER") == "boe" then
        BOE_CLF(std.parseInt(std.extVar("EMBEDDING_DIM")),
                std.parseInt(std.extVar("ADD_ELMO")),
                std.parseInt(std.extVar("ADD_VAE")))
    else if std.extVar("CLASSIFIER") == 'lr' then
        LR_CLF(std.parseInt(std.extVar("ADD_VAE")));

{
   "numpy_seed": std.extVar("SEED"),
   "pytorch_seed": std.extVar("SEED"),
   "random_seed": std.extVar("SEED"),
   "dataset_reader": BASE_READER(std.parseInt(std.extVar("ADD_ELMO")), std.parseInt(std.extVar("ADD_VAE")), std.extVar("THROTTLE"), std.parseInt(std.extVar("USE_SPACY_TOKENIZER"))),
    "validation_dataset_reader": BASE_READER(std.parseInt(std.extVar("ADD_ELMO")), std.parseInt(std.extVar("ADD_VAE")), null, std.parseInt(std.extVar("USE_SPACY_TOKENIZER"))),
   "datasets_for_vocab_creation": ["train"],
   "train_data_path": std.extVar("TRAIN_PATH"),
   "validation_data_path": std.extVar("DEV_PATH"),
   "model": {"type": "classifier"} + CLASSIFIER,
    "iterator": {
      "batch_size": 128,
      "type": "basic"
   },
   "trainer": {
      "cuda_device": CUDA_DEVICE,
      "num_epochs": 200,
      "optimizer": {
         "lr": std.parseInt(std.extVar("LEARNING_RATE")) / 10000.0,
         "type": "adam"
      },
      "patience": 20,
      "validation_metric": "+accuracy"
   }
} + if std.parseInt(std.extVar("ADD_VAE")) == 1 then VOCABULARY_WITH_VAE else {}
