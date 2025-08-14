#!/bin/bash

# Copyright 2019 Hitachi, Ltd. (author: Yusuke Fujita)
#           2024 Maoxuan Sha (author: Maoxuan Sha)

# Licensed under the MIT license.
#
# This script prepares kaldi-style data sets for AMI diarization.
#   - data/ami_train
#   - data/ami_eval (for evaluation)

stage=0 # Controls which part of the script to run. Set to 0 to run all.

# --- Modify corpus directories ---
# Path to the AMI corpus root directory
# This directory should contain 'audio' (for .wav files) and segments files are in ami_public_manual_1.6.2/segments/
AMI_CORPUS_DIR=$PWD/ami_data/AMI_Corpus_Root # <<<--- IMPORTANT: SET THIS PATH

# --- Source Kaldi environment and parse options ---
. path.sh
. cmd.sh
. utils/parse_options.sh || exit 1

if [ $stage -le 0 ]; then
    echo "Stage 0: Prepare all AMI kaldi-style datasets"
    # Download and prepare the AMI corpus if not already present.
    if [ ! -d "${AMI_CORPUS_DIR}" ] || [ -z "$(ls -A "${AMI_CORPUS_DIR}")" ]; then
        local/download_and_untar.sh || exit 1
    else
        echo "AMI corpus found in ${AMI_CORPUS_DIR}. Skipping download."
    fi

    # Prepare AMI dataset. This will contain all meetings.
    if ! utils/validate_data_dir.sh --no-text --no-feats data/ami_all; then
        echo "Running local/make_ami.sh to prepare all AMI data..."
        local/make_ami.sh "${AMI_CORPUS_DIR}" data/ami_all || exit 1
    else
        echo "Data directory 'data/ami_all' already exists and is valid. Skipping data preparation."
    fi
fi

if [ $stage -le 1 ]; then
    echo "Stage 1: Composing training and evaluation sets with a speaker-independent split"

    train_set=data/ami_train
    eval_set=data/ami_eval

    # We create a speaker-independent split where the evaluation set is approximately
    # 10% of the total speakers, and no speaker in the eval set appears in the train set.
    if ! utils/validate_data_dir.sh --no-text --no-feats "$train_set" || ! utils/validate_data_dir.sh --no-text --no-feats "$eval_set"; then
        echo "Creating speaker-independent training and evaluation sets..."
        local/create_ami_speaker_independent_split.sh data/ami_all "$train_set" "$eval_set"
        if [ $? -ne 0 ]; then
            echo "Error during speaker-independent split. Exiting." >&2
            exit 1
        fi
    else
        echo "Training and evaluation sets '$train_set' and '$eval_set' already exist and are valid. Skipping."
    fi
fi

echo "All shared data preparation stages complete for AMI diarization." 