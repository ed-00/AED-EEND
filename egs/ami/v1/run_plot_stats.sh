#!/bin/bash

set -euo pipefail

# Defaults to the speaker-independent split created by run_prepare_ami.sh
TRAIN_DIR=${1:-data/ami_train}
EVAL_DIR=${2:-data/ami_eval}
OUT_PLOT=${3:-data/dataset_durations.png}

python3 local/plot_dataset_stats.py \
  --train-dir "$TRAIN_DIR" \
  --eval-dir "$EVAL_DIR" \
  --out-plot "$OUT_PLOT" 