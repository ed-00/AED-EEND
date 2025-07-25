#!/bin/bash

# Copyright 2019 Hitachi, Ltd. (author: Yusuke Fujita)
# Licensed under the MIT license.
#
# This script prepares kaldi-style data sets for ICSI diarization.
#   - data/icsi_train
#   - data/icsi_eval (for evaluation)

stage=0 # Controls which part of the script to run. Set to 0 to run all.

# --- Modify corpus directories ---
# Path to the ICSI corpus root directory
# This directory should contain 'NIST_Trans' (for XML annotations) and 'audio' (for .sph files)
ICSI_CORPUS_DIR=/path/to/ICSI_Corpus_Root # <<<--- IMPORTANT: SET THIS PATH

# These variables are included for stylistic consistency with the Callhome example,
# but are not directly used in this ICSI-specific script.
callhome_dir=/export/corpora/NIST/LDC2001S97
swb2_phase1_train=/export/corpora/LDC/LDC98S75
data_root=/export/corpora5/LDC
musan_root=/export/corpora/JHU/musan

# Modify simulated data storage area.
# This script distributes simulated data under these directories
simu_actual_dirs=(
/export/c05/$USER/diarization-data
/export/c08/$USER/diarization-data
/export/c09/$USER/diarization-data
)

# --- Data preparation options ---
max_jobs_run=4 # Included for stylistic consistency
sad_num_jobs=30 # Included for stylistic consistency
sad_opts="--extra-left-context 79 --extra-right-context 21 --frames-per-chunk 150 --extra-left-context-initial 0 --extra-right-context-final 0 --acwt 0.3" # Included for stylistic consistency
sad_graph_opts="--min-silence-duration=0.03 --min-speech-duration=0.3 --max-speech-duration=10.0" # Included for stylistic consistency
sad_priors_opts="--sil-scale=0.1" # Included for stylistic consistency

# --- Feature extraction configuration ---
nj=8 # Number of parallel jobs for feature extraction for MFCCs
mfcc_config=conf/mfcc.conf # MFCC configuration file

# --- Simulation options ---
# These variables are included for stylistic consistency with the Callhome example,
# but are not directly used in this ICSI-specific script.
simu_opts_overlap=yes
simu_opts_num_speaker=2
simu_opts_sil_scale=2
simu_opts_rvb_prob=0.5
simu_opts_num_train=100000
simu_opts_min_utts=10
simu_opts_max_utts=20

# --- Source Kaldi environment and parse options ---
. path.sh
. cmd.sh
. parse_options.sh || exit 1

if [ $stage -le 0 ]; then
    echo "Stage 0: Prepare ICSI kaldi-style datasets"
    # Prepare ICSI dataset. This will be used for training/evaluation.
    if ! utils/validate_data_dir.sh --no-text --no-feats data/icsi_train; then
        echo "Running local/make_icsi.sh to prepare ICSI data..."
        local/make_icsi.sh "${ICSI_CORPUS_DIR}" data/icsi_train || exit 1
    else
        echo "Data directory 'data/icsi_train' already exists and is valid. Skipping data preparation."
    fi
fi

if [ $stage -le 1 ]; then
    echo "Stage 1: Feature extraction (MFCCs)"
    # Extract MFCC features and compute CMVN stats for the prepared data.
    for x in icsi_train; do
        if [ ! -f "data/${x}/feats.scp" ]; then
            echo "Running steps/make_mfcc.sh and steps/compute_cmvn_stats.sh for data/${x}..."
            steps/make_mfcc.sh --mfcc-config "${mfcc_config}" --nj "${nj}" --cmd "${train_cmd}" "data/${x}" || exit 1;
            steps/compute_cmvn_stats.sh "data/${x}" || exit 1;
        else
            echo "MFCC features for 'data/${x}' already exist. Skipping feature extraction."
        fi
    done
fi

if [ $stage -le 2 ]; then
    echo "Stage 2: Compose evaluation set (e.g., icsi_eval)"
    # This stage demonstrates how to create a dedicated evaluation set if desired.
    # For ICSI, you might want to split a portion of the data for evaluation,
    # or define specific meetings as evaluation sets.
    # For simplicity, let's assume we're just copying the 'icsi_train' data
    # to 'icsi_eval' for demonstration, or you can filter it later.
    eval_set=data/icsi_eval
    if ! utils/validate_data_dir.sh --no-text --no-feats $eval_set; then
        echo "Composing evaluation set '$eval_set'..."
        utils/copy_data_dir.sh data/icsi_train $eval_set
        # If you have a specific RTTM for evaluation (e.g., a subset of meetings),
        # replace the above with filtering or direct copying of that RTTM.
        # For now, we'll just copy the generated RTTM from the train set.
        cp data/icsi_train/rttm $eval_set/rttm
        # Ensure reco2dur is present for the evaluation set
        utils/data/get_reco2dur.sh $eval_set || exit 1
        echo "Evaluation set '$eval_set' composed."
    else
        echo "Evaluation set '$eval_set' already exists and is valid. Skipping composition."
    fi
fi

echo "All shared data preparation stages complete for ICSI diarization."
