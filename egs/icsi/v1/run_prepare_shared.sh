#!/bin/bash

# Copyright 2019 Hitachi, Ltd. (author: Yusuke Fujita)
#           2025 Abed Hameed (author: Abed Hameed)

# Licensed under the MIT license.
#
# This script prepares kaldi-style data sets for ICSI diarization.
#   - data/icsi_train
#   - data/icsi_eval (for evaluation)

stage=0 # Controls which part of the script to run. Set to 0 to run all.

# --- Modify corpus directories ---
# Path to the ICSI corpus root directory
# This directory should contain 'NIST_Trans' (for XML annotations) and 'audio' (for .sph files)
ICSI_CORPUS_DIR=$PWD/data/local/ICSI_Corpus_Root # <<<--- IMPORTANT: SET THIS PATH

# --- Source Kaldi environment and parse options ---
. path.sh
. cmd.sh
. utils/parse_options.sh || exit 1

if [ $stage -le 0 ]; then
    echo "Stage 0: Prepare all ICSI kaldi-style datasets"
    # Download and untar the ICSI corpus if not already present.
    if [ ! -d "${ICSI_CORPUS_DIR}" ] || [ -z "$(ls -A "${ICSI_CORPUS_DIR}")" ]; then
        local/download_and_untar.sh data/local || exit 1
    else
        echo "ICSI corpus found in ${ICSI_CORPUS_DIR}. Skipping download."
    fi

    # Prepare ICSI dataset. This will contain all meetings.
    if ! utils/validate_data_dir.sh --no-text --no-feats data/icsi_all; then
        echo "Running local/make_icsi.sh to prepare all ICSI data..."
        local/make_icsi.sh "${ICSI_CORPUS_DIR}" data/icsi_all || exit 1
    else
        echo "Data directory 'data/icsi_all' already exists and is valid. Skipping data preparation."
    fi
fi

if [ $stage -le 1 ]; then
    echo "Stage 1: Composing training and evaluation sets with a speaker-independent split"

    train_set=data/icsi_train
    eval_set=data/icsi_eval

    # We create a speaker-independent split where the evaluation set targets
    # 10% of the TOTAL SEGMENT DURATION, and no speaker in the eval set
    # appears in the train set.
    if ! utils/validate_data_dir.sh --no-text --no-feats "$train_set" || ! utils/validate_data_dir.sh --no-text --no-feats "$eval_set"; then
        echo "Creating duration-targeted speaker-independent training (90%) and evaluation (10%) sets..."
        # The new script handles the splitting logic by duration.
        local/create_speaker_independent_split.sh data/icsi_all "$train_set" "$eval_set"
        if [ $? -ne 0 ]; then
            echo "Error during speaker-independent split. Exiting." >&2
            exit 1
        fi
    else
        echo "Training and evaluation sets '$train_set' and '$eval_set' already exist and are valid. Skipping."
    fi
fi

echo "All shared data preparation stages complete for ICSI diarization."
