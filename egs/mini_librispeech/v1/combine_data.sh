#!/usr/bin/env bash

# Deterministically combine multiple Kaldi data directories with quotas per source.
# Configure sources and quotas via variables below (similar to other recipe scripts).
#
# How it works:
# - For each source data dir, deterministically select a subset by reco/utt/spk
#   using a fixed seed, then (optionally) prefix IDs to avoid collisions.
# - Combine all subsets into one destination data dir.
#
# Edit these variables to customize.

# --- Configuration -----------------------------------------------------------

# Destination combined data dir
combine_dest_dir=/workspace/EENDv1/egs/mini_librispeech/v1/data/simu/data/train_clean_5_ns1to4_100000_all

# Selection unit per source: reco | utt | spk
combine_unit=reco

# Deterministic seed for shuffling
combine_seed=777

# Prefix mode to avoid ID collisions among sources: index | name | none
#   - index: p1_, p2_, ... (based on source order)
#   - name:  basename(src) + '_'
#   - none:  no prefixing (may cause ID collisions)
combine_prefix_mode=index

# List of source data dirs to draw from
combine_src_dirs=(
  /workspace/EENDv1/egs/mini_librispeech/v1/data/simu/data/train_clean_5_ns1_beta2_100000
  /workspace/EENDv1/egs/mini_librispeech/v1/data/simu/data/train_clean_5_ns2_beta2_100000
  /workspace/EENDv1/egs/mini_librispeech/v1/data/simu/data/train_clean_5_ns3_beta2_100000
  /workspace/EENDv1/egs/mini_librispeech/v1/data/simu/data/train_clean_5_ns4_beta2_100000
  /workspace/EENDv1/egs/mini_librispeech/v1/data/simu/data/train_clean_5_ns5_beta2_100000
  /workspace/EENDv1/egs/mini_librispeech/v1/data/simu/data/train_clean_5_ns6_beta2_100000
  /workspace/EENDv1/egs/mini_librispeech/v1/data/simu/data/train_clean_5_ns7_beta2_100000
)

# Choose one of the following to define quotas per source (same length as combine_src_dirs):
# 1) Percentages per source (0-100, applied to each source independently)
combine_src_percentages=()

# Optional: specify a total number of mixtures (recordings) across all sources.
# If > 0 and both percentages and counts are empty, counts will be evenly split.
combine_total_reco=100000

# 2) Fixed counts per source (number of reco/utt/spk to select per source)
combine_src_counts=()

# If a requested count exceeds what's available in the source, cap it (true/false)
combine_cap_to_available=true

# --- Dev Configuration (built in the same run) -------------------------------
# Destination combined data dir for dev
combine_dest_dir_dev=/workspace/EENDv1/egs/mini_librispeech/v1/data/simu/data/dev_clean_2_ns1to7_500each
# Dev sources
combine_src_dirs_dev=(
  /workspace/EENDv1/egs/mini_librispeech/v1/data/simu/data/dev_clean_2_ns1_beta2_100000
  /workspace/EENDv1/egs/mini_librispeech/v1/data/simu/data/dev_clean_2_ns2_beta2_100000
  /workspace/EENDv1/egs/mini_librispeech/v1/data/simu/data/dev_clean_2_ns3_beta2_100000
  /workspace/EENDv1/egs/mini_librispeech/v1/data/simu/data/dev_clean_2_ns4_beta2_100000
  /workspace/EENDv1/egs/mini_librispeech/v1/data/simu/data/dev_clean_2_ns5_beta2_100000
  /workspace/EENDv1/egs/mini_librispeech/v1/data/simu/data/dev_clean_2_ns6_beta2_100000
  /workspace/EENDv1/egs/mini_librispeech/v1/data/simu/data/dev_clean_2_ns7_beta2_100000
)
# Choose either percentages or counts for dev (counts default to 500 each)
combine_src_percentages_dev=()
# Total mixtures (recordings) for dev (7 sources × 500 each by default)
combine_total_reco_dev=3500
combine_src_counts_dev=()
combine_cap_to_available_dev=true

# ----------------------------------------------------------------------------

set -euo pipefail

# Ensure a valid locale for Perl and tools to avoid warnings
export LC_ALL=C.UTF-8

# Ensure Kaldi paths
. path.sh

# If neither percentages nor counts are provided, derive equal per-source counts
# based on combine_total_reco (when > 0).
if [ ${#combine_src_counts[@]} -eq 0 ] && [ ${#combine_src_percentages[@]} -eq 0 ] && [ "${combine_total_reco:-0}" -gt 0 ]; then
  nsrc=${#combine_src_dirs[@]}
  base=$(( combine_total_reco / nsrc ))
  rem=$(( combine_total_reco % nsrc ))
  combine_src_counts=()
  for ((i=0; i<nsrc; i++)); do
    extra=$(( i < rem ? 1 : 0 ))
    combine_src_counts+=( $(( base + extra )) )
  done
fi

# Disable CLI parsing; values are hard-coded above
# . utils/parse_options.sh || exit 1

# --- Validation --------------------------------------------------------------
if [ ${#combine_src_dirs[@]} -eq 0 ]; then
  echo "Error: combine_src_dirs is empty. Edit this script's configuration section." >&2
  exit 1
fi

have_pct=$([ ${#combine_src_percentages[@]} -gt 0 ] && echo 1 || echo 0)
have_cnt=$([ ${#combine_src_counts[@]} -gt 0 ] && echo 1 || echo 0)
if [ $have_pct -eq 1 ] && [ $have_cnt -eq 1 ]; then
  echo "Error: Define only one of combine_src_percentages or combine_src_counts, not both." >&2
  exit 1
fi
if [ $have_pct -eq 0 ] && [ $have_cnt -eq 0 ]; then
  echo "Error: Define one of combine_src_percentages or combine_src_counts." >&2
  exit 1
fi

if [ $have_pct -eq 1 ] && [ ${#combine_src_percentages[@]} -ne ${#combine_src_dirs[@]} ]; then
  echo "Error: Length mismatch: combine_src_percentages vs combine_src_dirs." >&2
  exit 1
fi
if [ $have_cnt -eq 1 ] && [ ${#combine_src_counts[@]} -ne ${#combine_src_dirs[@]} ]; then
  echo "Error: Length mismatch: combine_src_counts vs combine_src_dirs." >&2
  exit 1
fi

# --- Workdir ----------------------------------------------------------------
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

subset_dirs=()

# --- Helper: compute available items for a source depending on unit ----------
num_available_items() {
  local src_dir=$1
  case "$combine_unit" in
    reco)
      wc -l < "$src_dir/wav.scp"
      ;;
    utt)
      wc -l < "$src_dir/utt2spk"
      ;;
    spk)
      wc -l < "$src_dir/spk2utt"
      ;;
    *)
      echo "Error: Unknown combine_unit '$combine_unit' (expected: reco|utt|spk)" >&2
      return 2
      ;;
  esac
}

# --- Iterate sources ---------------------------------------------------------
index=0
for src_dir in "${combine_src_dirs[@]}"; do
  index=$(( index + 1 ))

  if [ ! -f "$src_dir/utt2spk" ]; then
    echo "Error: Missing $src_dir/utt2spk" >&2
    exit 1
  fi
  if [ "$combine_unit" = reco ] && [ ! -f "$src_dir/wav.scp" ]; then
    echo "Error: Missing $src_dir/wav.scp for reco-level selection" >&2
    exit 1
  fi
  if [ "$combine_unit" = spk ] && [ ! -f "$src_dir/spk2utt" ]; then
    echo "Error: Missing $src_dir/spk2utt for spk-level selection" >&2
    exit 1
  fi

  # Determine quota
  total=$(num_available_items "$src_dir")
  if [ $have_pct -eq 1 ]; then
    pct=${combine_src_percentages[$((index-1))]}
    # floor(percent * total / 100)
    want=$(( (pct * total) / 100 ))
  else
    want=${combine_src_counts[$((index-1))]}
  fi
  if $combine_cap_to_available && [ "$want" -gt "$total" ]; then
    want=$total
  fi
  if [ "$want" -le 0 ]; then
    echo "Warning: source #$index ($src_dir): requested 0 items; skipping."
    continue
  fi

  # Determine prefix
  prefix=""
  case "$combine_prefix_mode" in
    index)
      prefix="p${index}_"
      ;;
    name)
      base=$(basename "$src_dir")
      prefix="${base}_"
      ;;
    none)
      prefix=""
      ;;
    *)
      echo "Error: Unknown combine_prefix_mode '$combine_prefix_mode'" >&2
      exit 1
      ;;
  esac

  sd="$workdir/subset_$index"
  mkdir -p "$sd"

  # Create selection lists and subset
  case "$combine_unit" in
    reco)
      set +o pipefail
      cut -d' ' -f1 "$src_dir/wav.scp" \
        | utils/shuffle_list.pl --srand "$combine_seed" \
        | head -n "$want" > "$sd/rec.list"
      set -o pipefail
      if [ -f "$src_dir/segments" ]; then
        awk 'NR==FNR{r[$1]=1;next} ($2 in r){print $1}' \
          "$sd/rec.list" "$src_dir/segments" > "$sd/utt.list"
      else
        cp "$sd/rec.list" "$sd/utt.list"
      fi
      utils/subset_data_dir.sh --utt-list "$sd/utt.list" "$src_dir" "$sd/raw"
      ;;
    utt)
      set +o pipefail
      cut -d' ' -f1 "$src_dir/utt2spk" \
        | utils/shuffle_list.pl --srand "$combine_seed" \
        | head -n "$want" > "$sd/utt.list"
      set -o pipefail
      utils/subset_data_dir.sh --utt-list "$sd/utt.list" "$src_dir" "$sd/raw"
      ;;
    spk)
      set +o pipefail
      cut -d' ' -f1 "$src_dir/spk2utt" \
        | utils/shuffle_list.pl --srand "$combine_seed" \
        | head -n "$want" > "$sd/spk.list"
      set -o pipefail
      utils/subset_data_dir.sh --spk-list "$sd/spk.list" "$src_dir" "$sd/raw"
      ;;
  esac

  utils/fix_data_dir.sh "$sd/raw" >/dev/null

  # Apply prefixing if requested
  if [ -n "$prefix" ]; then
    utils/copy_data_dir.sh --utt-prefix "$prefix" --spk-prefix "$prefix" "$sd/raw" "$sd/pref"
    utils/fix_data_dir.sh "$sd/pref" >/dev/null
    subset_dirs+=("$sd/pref")
  else
    subset_dirs+=("$sd/raw")
  fi

done

# Combine all subsets into destination
mkdir -p "$(dirname "$combine_dest_dir")"
if [ ${#subset_dirs[@]} -eq 0 ]; then
  echo "Error: No subsets were created (check your quotas)." >&2
  exit 1
fi
utils/combine_data.sh "$combine_dest_dir" ${subset_dirs[@]}
utils/fix_data_dir.sh "$combine_dest_dir"
utils/validate_data_dir.sh --no-text "$combine_dest_dir" || true

echo "Combined data dir created at: $combine_dest_dir"

# --- DEV COMBINE PASS --------------------------------------------------------
# Map dev configuration into the common variable names and repeat the process
combine_dest_dir="$combine_dest_dir_dev"
combine_src_dirs=("${combine_src_dirs_dev[@]}")
combine_src_percentages=("${combine_src_percentages_dev[@]}")
combine_src_counts=("${combine_src_counts_dev[@]}")
combine_cap_to_available="$combine_cap_to_available_dev"

# If neither percentages nor counts are provided for dev, derive equal per-source
# counts based on combine_total_reco_dev (when > 0).
if [ ${#combine_src_counts[@]} -eq 0 ] && [ ${#combine_src_percentages[@]} -eq 0 ] && [ "${combine_total_reco_dev:-0}" -gt 0 ]; then
  nsrc=${#combine_src_dirs[@]}
  base=$(( combine_total_reco_dev / nsrc ))
  rem=$(( combine_total_reco_dev % nsrc ))
  combine_src_counts=()
  for ((i=0; i<nsrc; i++)); do
    extra=$(( i < rem ? 1 : 0 ))
    combine_src_counts+=( $(( base + extra )) )
  done
fi

# Validation for dev
if [ ${#combine_src_dirs[@]} -eq 0 ]; then
  echo "Error: combine_src_dirs_dev is empty. Edit this script's configuration section." >&2
  exit 1
fi
have_pct=$([ ${#combine_src_percentages[@]} -gt 0 ] && echo 1 || echo 0)
have_cnt=$([ ${#combine_src_counts[@]} -gt 0 ] && echo 1 || echo 0)
if [ $have_pct -eq 1 ] && [ $have_cnt -eq 1 ]; then
  echo "Error (dev): Define only one of combine_src_percentages_dev or combine_src_counts_dev, not both." >&2
  exit 1
fi
if [ $have_pct -eq 0 ] && [ $have_cnt -eq 0 ]; then
  echo "Error (dev): Define one of combine_src_percentages_dev or combine_src_counts_dev." >&2
  exit 1
fi
if [ $have_pct -eq 1 ] && [ ${#combine_src_percentages[@]} -ne ${#combine_src_dirs[@]} ]; then
  echo "Error (dev): Length mismatch: combine_src_percentages_dev vs combine_src_dirs_dev." >&2
  exit 1
fi
if [ $have_cnt -eq 1 ] && [ ${#combine_src_counts[@]} -ne ${#combine_src_dirs[@]} ]; then
  echo "Error (dev): Length mismatch: combine_src_counts_dev vs combine_src_dirs_dev." >&2
  exit 1
fi

# Workdir for dev
workdir_dev=$(mktemp -d)
trap 'rm -rf "$workdir" "$workdir_dev"' EXIT
subset_dirs=()

# Iterate sources for dev
index=0
for src_dir in "${combine_src_dirs[@]}"; do
  index=$(( index + 1 ))

  if [ ! -f "$src_dir/utt2spk" ]; then
    echo "Error (dev): Missing $src_dir/utt2spk" >&2
    exit 1
  fi
  if [ "$combine_unit" = reco ] && [ ! -f "$src_dir/wav.scp" ]; then
    echo "Error (dev): Missing $src_dir/wav.scp for reco-level selection" >&2
    exit 1
  fi
  if [ "$combine_unit" = spk ] && [ ! -f "$src_dir/spk2utt" ]; then
    echo "Error (dev): Missing $src_dir/spk2utt for spk-level selection" >&2
    exit 1
  fi

  total=$(num_available_items "$src_dir")
  if [ $have_pct -eq 1 ]; then
    pct=${combine_src_percentages[$((index-1))]}
    want=$(( (pct * total) / 100 ))
  else
    want=${combine_src_counts[$((index-1))]}
  fi
  if $combine_cap_to_available && [ "$want" -gt "$total" ]; then
    want=$total
  fi
  if [ "$want" -le 0 ]; then
    echo "Warning (dev): source #$index ($src_dir): requested 0 items; skipping."
    continue
  fi

  prefix=""
  case "$combine_prefix_mode" in
    index) prefix="p${index}_" ;;
    name)  base=$(basename "$src_dir"); prefix="${base}_" ;;
    none)  prefix="" ;;
  esac

  sd="$workdir_dev/subset_$index"
  mkdir -p "$sd"

  case "$combine_unit" in
    reco)
      set +o pipefail
      cut -d' ' -f1 "$src_dir/wav.scp" \
        | utils/shuffle_list.pl --srand "$combine_seed" \
        | head -n "$want" > "$sd/rec.list"
      set -o pipefail
      if [ -f "$src_dir/segments" ]; then
        awk 'NR==FNR{r[$1]=1;next} ($2 in r){print $1}' \
          "$sd/rec.list" "$src_dir/segments" > "$sd/utt.list"
      else
        cp "$sd/rec.list" "$sd/utt.list"
      fi
      utils/subset_data_dir.sh --utt-list "$sd/utt.list" "$src_dir" "$sd/raw"
      ;;
    utt)
      set +o pipefail
      cut -d' ' -f1 "$src_dir/utt2spk" \
        | utils/shuffle_list.pl --srand "$combine_seed" \
        | head -n "$want" > "$sd/utt.list"
      set -o pipefail
      utils/subset_data_dir.sh --utt-list "$sd/utt.list" "$src_dir" "$sd/raw"
      ;;
    spk)
      set +o pipefail
      cut -d' ' -f1 "$src_dir/spk2utt" \
        | utils/shuffle_list.pl --srand "$combine_seed" \
        | head -n "$want" > "$sd/spk.list"
      set -o pipefail
      utils/subset_data_dir.sh --spk-list "$sd/spk.list" "$src_dir" "$sd/raw"
      ;;
  esac

  utils/fix_data_dir.sh "$sd/raw" >/dev/null

  if [ -n "$prefix" ]; then
    utils/copy_data_dir.sh --utt-prefix "$prefix" --spk-prefix "$prefix" "$sd/raw" "$sd/pref"
    utils/fix_data_dir.sh "$sd/pref" >/dev/null
    subset_dirs+=("$sd/pref")
  else
    subset_dirs+=("$sd/raw")
  fi

done

mkdir -p "$(dirname "$combine_dest_dir")"
if [ ${#subset_dirs[@]} -eq 0 ]; then
  echo "Error (dev): No subsets were created (check your quotas)." >&2
  exit 1
fi
utils/combine_data.sh "$combine_dest_dir" ${subset_dirs[@]}
utils/fix_data_dir.sh "$combine_dest_dir"
utils/validate_data_dir.sh --no-text "$combine_dest_dir" || true

echo "Combined DEV data dir created at: $combine_dest_dir" 
