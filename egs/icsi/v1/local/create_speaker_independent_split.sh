#!/bin/bash

# Copyright 2024 Abed Hameed (author: Abed Hameed)
# Licensed under the MIT license.
#
# This script creates a speaker-independent split for the ICSI dataset,
# ensuring that speakers in the evaluation set do not appear in the training set.
# The evaluation set size is targeted to be a given percentage of the TOTAL
# SEGMENT DURATION (not speaker count), selecting whole speakers greedily to
# avoid exceeding the target when possible.

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
utt2dur="${work_dir}/utt2dur"
spk2dur="${work_dir}/spk2dur"

# --- Compute utterance durations ---
# Prefer computing from segments to avoid dependence on audio access.
if [ -f "${src_dir}/segments" ]; then
  awk '{ printf "%s %.6f\n", $1, ($4 - $3) }' "${src_dir}/segments" > "${utt2dur}" || {
    echo "Error: failed to compute utt2dur from segments in ${src_dir}" >&2; exit 1; }
elif [ -f "${src_dir}/utt2dur" ]; then
  cp "${src_dir}/utt2dur" "${utt2dur}" || { echo "Error: cannot copy utt2dur" >&2; exit 1; }
else
  echo "Error: neither segments nor utt2dur exists in ${src_dir}" >&2
  exit 1
fi

# --- Aggregate to per-speaker duration ---
if [ ! -f "${src_dir}/utt2spk" ]; then
  echo "Error: missing ${src_dir}/utt2spk" >&2; exit 1
fi
awk 'FNR==NR { u2s[$1] = $2; next } {
       spk = u2s[$1]; if (spk != "") dur[spk] += $2
     } END { for (s in dur) printf "%s %.6f\n", s, dur[s] }' \
    "${src_dir}/utt2spk" "${utt2dur}" | sort > "${spk2dur}" || {
  echo "Error: failed to build spk2dur" >&2; exit 1; }

# --- Total and target durations ---
if [ ! -s "${spk2dur}" ]; then
  echo "Error: no speakers with duration found in ${src_dir}" >&2; exit 1
fi

total_duration=$(awk '{ sum += $2 } END { printf "%.6f\n", sum }' "${spk2dur}")
if [ "${total_duration}" = "0.000000" ]; then
  echo "Error: total duration is zero in ${src_dir}" >&2; exit 1
fi

target_duration=$(perl -e 'print sprintf("%.6f", $ARGV[0] * $ARGV[1] / 100.0)' \
  "${eval_percent}" "${total_duration}")

# --- Candidate speakers (shuffle for reproducibility) ---
cut -d' ' -f1 "${spk2dur}" | utils/shuffle_list.pl --srand "${seed}" > "${all_speakers}" || {
  echo "Error: failed to build shuffled speaker list" >&2; exit 1; }

# --- Greedy selection: add speakers until adding the next would exceed target ---
awk -v target="${target_duration}" 'FNR==NR { d[$1] = $2; next }
     {
       sp = $1; dur = d[sp] + 0.0; if (dur <= 0) next;
       if (sum + dur <= target) { print sp; sum += dur }
       else if (sum == 0) { print sp; sum += dur; exit }  # ensure non-empty eval if first speaker exceeds
       else { exit }
     }' "${spk2dur}" "${all_speakers}" > "${eval_speakers}" || {
  echo "Error: failed to select eval speakers" >&2; exit 1; }

# If greedy selection yielded empty (unlikely), fallback to the single longest speaker
if [ ! -s "${eval_speakers}" ]; then
  sort -k2,2nr "${spk2dur}" | head -n 1 | cut -d' ' -f1 > "${eval_speakers}"
fi

# Build train speakers as the complement set
if [ -s "${eval_speakers}" ]; then
  grep -vxF -f "${eval_speakers}" "${all_speakers}" > "${train_speakers}" || {
    echo "Error: failed to build train speakers" >&2; exit 1; }
else
  cp "${all_speakers}" "${train_speakers}" || { echo "Error: cannot copy speakers" >&2; exit 1; }
fi

# Report split statistics
num_train=$(wc -l < "${train_speakers}")
num_eval=$(wc -l < "${eval_speakers}")

eval_duration=$(awk 'FNR==NR { keep[$1] = 1; next } (keep[$1]) { s += $2 } END { printf "%.6f\n", s }' \
  "${eval_speakers}" "${spk2dur}")
actual_eval_percent=$(perl -e 'printf("%.2f", 100.0 * $ARGV[0] / $ARGV[1])' \
  "${eval_duration}" "${total_duration}")

echo "Target eval duration: ${target_duration}s (${eval_percent}%), actual: ${eval_duration}s (~${actual_eval_percent}%)."
echo "Splitting speakers: ${num_train} for training, ${num_eval} for evaluation."

# Create the data directories using the reliable subset_data_dir.sh
utils/subset_data_dir.sh --spk-list "${train_speakers}" "${src_dir}" "${train_dir}" || exit 1
utils/subset_data_dir.sh --spk-list "${eval_speakers}" "${src_dir}" "${eval_dir}" || exit 1

# Post-split processing
utils/data/get_reco2dur.sh "${train_dir}"
utils/data/get_reco2dur.sh "${eval_dir}"

# Fix data dirs to be safe
utils/fix_data_dir.sh "${train_dir}" || true
utils/fix_data_dir.sh "${eval_dir}" || true

echo "Speaker-independent split complete (duration-targeted)." 