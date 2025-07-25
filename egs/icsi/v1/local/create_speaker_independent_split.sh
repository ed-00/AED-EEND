#!/bin/bash

# Copyright 2024 Abed Hameed (author: Abed Hameed)
# Licensed under the MIT license.
#
# This script creates a speaker-independent split for the ICSI dataset,
# ensuring that speakers in the evaluation set do not appear in the training set.
# This version manually creates speaker lists to avoid issues with buggy
# versions of subset_data_dir_tr_cv.sh.

# --- Options ---
eval_percent=10
seed=3

. utils/parse_options.sh

if [ $# -ne 3 ]; then
  echo "Usage: $0 [options] <src-data-dir> <train-out-dir> <eval-out-dir>"
  exit 1
fi

src_dir=$1
train_dir=$2
eval_dir=$3

# Manually create the speaker lists
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

all_speakers="${work_dir}/all_speakers"
train_speakers="${work_dir}/train_speakers"
eval_speakers="${work_dir}/eval_speakers"

# Get all speakers and shuffle them with the specified seed
cut -d' ' -f1 "$src_dir/spk2utt" | utils/shuffle_list.pl --srand "$seed" > "$all_speakers"
num_speakers=$(wc -l < "$all_speakers")
num_eval=$(perl -e "print int($eval_percent * $num_speakers / 100)")
num_train=$((num_speakers - num_eval))

# Split the speaker list into train and eval
head -n "$num_train" "$all_speakers" > "$train_speakers"
tail -n "$num_eval" "$all_speakers" > "$eval_speakers"

echo "Splitting speakers: $num_train for training, $num_eval for evaluation."

# Create the data directories using the reliable subset_data_dir.sh
utils/subset_data_dir.sh --spk-list "$train_speakers" "$src_dir" "$train_dir"
utils/subset_data_dir.sh --spk-list "$eval_speakers" "$src_dir" "$eval_dir"

# Post-split processing
utils/data/get_reco2dur.sh "$train_dir"
utils/data/get_reco2dur.sh "$eval_dir"

echo "Speaker-independent split complete." 