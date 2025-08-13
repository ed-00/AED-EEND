#!/usr/bin/env bash

# Deterministically combine multiple Kaldi data directories using Zipf-law
# allocation (largest remainder / Hamilton method) and print a duration
# summary at the end.
#
# Edit the configuration below to match your data layout.

set -euo pipefail

# Ensure a valid locale for Perl and tools to avoid warnings
export LC_ALL=C.UTF-8

# Ensure Kaldi paths
. path.sh

# --- Configuration -----------------------------------------------------------

# Destination combined data dir
combine_dest_dir=/workspace/EENDv1/egs/mini_librispeech/v1/data/simu/data/train_clean_5_ns1to7_zipf_s1p75_100000

# Selection unit per source: reco | utt | spk
combine_unit=reco

# Deterministic seed for shuffling
combine_seed=777

# Prefix mode to avoid ID collisions among sources: index | name | none
combine_prefix_mode=index

# Zipf exponent s (>0). Typical values: 0.8..1.4
zipf_exponent=1.75

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

# Target total number of items across all sources for the selected unit
# (required for Zipf scaling). For combine_unit=reco this is total mixtures.
combine_total_reco=100000

# If a requested count exceeds what's available in the source, cap it (true/false)
combine_cap_to_available=true

# --- Dev Configuration (optional) -------------------------------------------
# Destination combined data dir for dev
combine_dest_dir_dev=/workspace/EENDv1/egs/mini_librispeech/v1/data/simu/data/dev_clean_2_ns1to7_zipf_s1p75_3500
# List of dev source data dirs
combine_src_dirs_dev=(
  /workspace/EENDv1/egs/mini_librispeech/v1/data/simu/data/dev_clean_2_ns1_beta2_100000
  /workspace/EENDv1/egs/mini_librispeech/v1/data/simu/data/dev_clean_2_ns2_beta2_100000
  /workspace/EENDv1/egs/mini_librispeech/v1/data/simu/data/dev_clean_2_ns3_beta2_100000
  /workspace/EENDv1/egs/mini_librispeech/v1/data/simu/data/dev_clean_2_ns4_beta2_100000
  /workspace/EENDv1/egs/mini_librispeech/v1/data/simu/data/dev_clean_2_ns5_beta2_100000
  /workspace/EENDv1/egs/mini_librispeech/v1/data/simu/data/dev_clean_2_ns6_beta2_100000
  /workspace/EENDv1/egs/mini_librispeech/v1/data/simu/data/dev_clean_2_ns7_beta2_100000
)
# Target total number of items across all dev sources
combine_total_reco_dev=3500
# If a requested count exceeds what's available in the dev source, cap it
combine_cap_to_available_dev=true

# ----------------------------------------------------------------------------

# --- Helpers ----------------------------------------------------------------

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

# Compute integer percentages q[1..n] that sum to 100 following Zipf's law
# with exponent s, using Largest Remainder (Hamilton) method.
zipf_integer_percentages() {
  local n=$1
  local s=$2
  awk -v n="$n" -v s="$s" '
    BEGIN {
      if (n <= 0) { print ""; exit 0 }
      W = 0
      for (i=1; i<=n; i++) {
        w[i] = 1.0/exp(s*log(i))
        W += w[i]
      }
      sumq = 0
      for (i=1; i<=n; i++) {
        x[i] = 100.0 * w[i] / W
        q[i] = int(x[i] + 1e-12)
        R[i] = x[i] - q[i]
        sumq += q[i]
        idx[i] = i
      }
      leftover = 100 - sumq
      # sort indices by remainder desc (simple O(n^2), fine for small n)
      for (i=1; i<=n; i++) {
        for (j=i+1; j<=n; j++) {
          if (R[idx[j]] > R[idx[i]]) { tmp=idx[i]; idx[i]=idx[j]; idx[j]=tmp }
        }
      }
      for (t=1; t<=leftover; t++) { if (t<=n) q[idx[t]] += 1 }
      for (i=1; i<=n; i++) { printf "%d", q[i]; if (i<n) printf " " }
      printf "\n"
    }'
}

# Scale integer percentages p[1..n] to integer counts that sum to total,
# using Largest Remainder on fractional parts of total*p/100.
scale_percentages_to_counts() {
  local pcts_str=$1
  local total=$2
  local n
  n=$(awk -v s="$pcts_str" 'BEGIN{print split(s, a, " ")}')
  awk -v s="$pcts_str" -v total="$total" -v n="$n" '
    BEGIN {
      if (n <= 0) { print ""; exit 0 }
      split(s, pct, " ")
      sumc = 0
      for (i=1; i<=n; i++) {
        y[i] = total * pct[i] / 100.0
        c[i] = int(y[i] + 1e-12)
        R[i] = y[i] - c[i]
        sumc += c[i]
        idx[i] = i
      }
      leftover = total - sumc
      for (i=1; i<=n; i++) {
        for (j=i+1; j<=n; j++) {
          if (R[idx[j]] > R[idx[i]]) { tmp=idx[i]; idx[i]=idx[j]; idx[j]=tmp }
        }
      }
      for (t=1; t<=leftover; t++) { if (t<=n) c[idx[t]] += 1 }
      for (i=1; i<=n; i++) { printf "%d", c[i]; if (i<n) printf " " }
      printf "\n"
    }'
}

# Sum mixture wall-clock duration (seconds): prefer reco2dur; else derive
# per-reco length from segments as max(end) - min(start). No utt2dur fallback.
compute_data_dir_duration_seconds() {
  local d=$1
  # Prefer mixture wall-clock duration to avoid double-counting overlaps
  if [ -f "$d/reco2dur" ]; then
    awk '{s+=$2} END{printf("%.6f\n", s+0)}' "$d/reco2dur"
    return
  elif [ -f "$d/segments" ]; then
    # Approximate mixture length per reco as max(end) - min(start)
    awk '{ r=$2; st=$3; en=$4; if (!(r in min) || st<min[r]) min[r]=st; if (en>max[r]) max[r]=en } END { for (r in max) s+=(max[r] - (r in min ? min[r] : 0)); printf("%.6f\n", s+0) }' "$d/segments"
    return
  fi
  printf "0.000000\n"
}

fmt_hms() {
  local total=$1
  # Round to nearest integer second for display
  local sec
  sec=$(awk -v x="$total" 'BEGIN{printf("%d\n", (x<0?0:int(x+0.5)))}')
  local h=$(( sec / 3600 ))
  local m=$(( (sec % 3600) / 60 ))
  local s=$(( sec % 60 ))
  printf "%d:%02d:%02d" "$h" "$m" "$s"
}

# --- Validation --------------------------------------------------------------

if [ ${#combine_src_dirs[@]} -eq 0 ]; then
  echo "Error: combine_src_dirs is empty. Edit this script's configuration section." >&2
  exit 1
fi

if [ "$combine_unit" = reco ] && [ ! "${combine_total_reco:-}" -gt 0 ]; then
  echo "Error: combine_total_reco must be > 0 for Zipf scaling (unit=reco)." >&2
  exit 1
fi

# --- Zipf allocation ---------------------------------------------------------

nsrc=${#combine_src_dirs[@]}
zipf_pcts_str=$(zipf_integer_percentages "$nsrc" "$zipf_exponent")
read -r -a zipf_pcts <<< "$zipf_pcts_str"

# Scale to target total count (reco/utt/spk depending on combine_unit)
case "$combine_unit" in
  reco)
    per_src_want_str=$(scale_percentages_to_counts "$zipf_pcts_str" "$combine_total_reco")
    ;;
  utt|spk)
    echo "Error: This script currently supports unit=reco. Set combine_unit=reco." >&2
    exit 1
    ;;
  *)
    echo "Error: Unknown combine_unit '$combine_unit' (expected: reco)." >&2
    exit 1
    ;;
esac
read -r -a per_src_want <<< "$per_src_want_str"

# --- Workdir ----------------------------------------------------------------

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
subset_dirs=()

declare -a per_src_duration

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

  total=$(num_available_items "$src_dir")
  want=${per_src_want[$((index-1))]}
  if ${combine_cap_to_available}; then
    if [ "$want" -gt "$total" ]; then
      echo "Warning: source #$index ($src_dir): requested $want > available $total; capping to $total" >&2
      want=$total
    fi
  fi
  if [ "$want" -le 0 ]; then
    echo "Warning: source #$index ($src_dir): requested 0 items; skipping." >&2
    continue
  fi

  # Determine prefix
  prefix=""
  case "$combine_prefix_mode" in
    index) prefix="p${index}_" ;;
    name)  base=$(basename "$src_dir"); prefix="${base}_" ;;
    none)  prefix="" ;;
    *) echo "Error: Unknown combine_prefix_mode '$combine_prefix_mode'" >&2; exit 1 ;;
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
  esac

  utils/fix_data_dir.sh "$sd/raw" >/dev/null

  # Apply prefixing if requested
  if [ -n "$prefix" ]; then
    utils/copy_data_dir.sh --utt-prefix "$prefix" --spk-prefix "$prefix" "$sd/raw" "$sd/pref"
    utils/fix_data_dir.sh "$sd/pref" >/dev/null
    subset_dirs+=("$sd/pref")
    dur=$(compute_data_dir_duration_seconds "$sd/pref")
  else
    subset_dirs+=("$sd/raw")
    dur=$(compute_data_dir_duration_seconds "$sd/raw")
  fi

  per_src_duration[$((index-1))]="$dur"

done

# Combine all subsets into destination
mkdir -p "$(dirname "$combine_dest_dir")"
if [ ${#subset_dirs[@]} -eq 0 ]; then
  echo "Error: No subsets were created (check your quotas)." >&2
  exit 1
fi
utils/combine_data.sh "$combine_dest_dir" ${subset_dirs[@]}
utils/fix_data_dir.sh "$combine_dest_dir" >/dev/null
utils/validate_data_dir.sh --no-text "$combine_dest_dir" || true

echo "Combined data dir created at: $combine_dest_dir"

# --- Report ------------------------------------------------------------------

# Print Zipf percentages and per-source wants
{
  echo "Zipf exponent s=$zipf_exponent"
  echo "Sources: $nsrc"
  echo -n "Zipf integer percentages: "
  echo "$zipf_pcts_str"
  echo -n "Per-source target counts (unit=$combine_unit): "
  echo "$per_src_want_str"
} >&2

# Duration summary per source and total
# Compute total duration
sum_dur=$(printf "%s\n" "${per_src_duration[@]}" | awk '{s+=$1} END{printf("%.6f\n", s+0)}')

if awk -v x="$sum_dur" 'BEGIN{exit (x>0?0:1)}'; then
  echo "Duration summary (seconds and percent of total):"
  for ((i=0; i<nsrc; i++)); do
    dur_i=${per_src_duration[$i]:-0}
    pct_i=$(awk -v d="$dur_i" -v tot="$sum_dur" 'BEGIN{if (tot>0) printf("%.2f", 100.0*d/tot); else printf("0.00") }')
    src_base=$(basename "${combine_src_dirs[$i]}")
    echo "  - [$((i+1))] $src_base: ${dur_i}s (${pct_i}%)"
  done
  hms=$(fmt_hms "$sum_dur")
  echo "Total duration: ${sum_dur}s (${hms})"
else
  echo "Duration summary: no duration information found (segments/reco2dur missing)."
fi 

# --- DEV COMBINE PASS --------------------------------------------------------

if [ ${#combine_src_dirs_dev[@]} -gt 0 ]; then
  if [ "$combine_unit" = reco ] && [ ! "${combine_total_reco_dev:-}" -gt 0 ]; then
    echo "Error (dev): combine_total_reco_dev must be > 0 for Zipf scaling (unit=reco)." >&2
    exit 1
  fi

  nsrc_dev=${#combine_src_dirs_dev[@]}
  zipf_pcts_str_dev=$(zipf_integer_percentages "$nsrc_dev" "$zipf_exponent")
  read -r -a zipf_pcts_dev <<< "$zipf_pcts_str_dev"

  case "$combine_unit" in
    reco)
      per_src_want_str_dev=$(scale_percentages_to_counts "$zipf_pcts_str_dev" "$combine_total_reco_dev")
      ;;
    *)
      echo "Error (dev): This script currently supports unit=reco. Set combine_unit=reco." >&2
      exit 1
      ;;
  esac
  read -r -a per_src_want_dev <<< "$per_src_want_str_dev"

  workdir_dev=$(mktemp -d)
  trap 'rm -rf "$workdir" "$workdir_dev"' EXIT
  subset_dirs_dev=()

  declare -a per_src_duration_dev

  index=0
  for src_dir in "${combine_src_dirs_dev[@]}"; do
    index=$(( index + 1 ))

    if [ ! -f "$src_dir/utt2spk" ]; then
      echo "Error (dev): Missing $src_dir/utt2spk" >&2
      exit 1
    fi
    if [ "$combine_unit" = reco ] && [ ! -f "$src_dir/wav.scp" ]; then
      echo "Error (dev): Missing $src_dir/wav.scp for reco-level selection" >&2
      exit 1
    fi

    total=$(num_available_items "$src_dir")
    want=${per_src_want_dev[$((index-1))]}
    if ${combine_cap_to_available_dev}; then
      if [ "$want" -gt "$total" ]; then
        echo "Warning (dev): source #$index ($src_dir): requested $want > available $total; capping to $total" >&2
        want=$total
      fi
    fi
    if [ "$want" -le 0 ]; then
      echo "Warning (dev): source #$index ($src_dir): requested 0 items; skipping." >&2
      continue
    fi

    prefix=""
    case "$combine_prefix_mode" in
      index) prefix="p${index}_" ;;
      name)  base=$(basename "$src_dir"); prefix="${base}_" ;;
      none)  prefix="" ;;
      *) echo "Error (dev): Unknown combine_prefix_mode '$combine_prefix_mode'" >&2; exit 1 ;;
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
    esac

    utils/fix_data_dir.sh "$sd/raw" >/dev/null

    if [ -n "$prefix" ]; then
      utils/copy_data_dir.sh --utt-prefix "$prefix" --spk-prefix "$prefix" "$sd/raw" "$sd/pref"
      utils/fix_data_dir.sh "$sd/pref" >/dev/null
      subset_dirs_dev+=("$sd/pref")
      dur=$(compute_data_dir_duration_seconds "$sd/pref")
    else
      subset_dirs_dev+=("$sd/raw")
      dur=$(compute_data_dir_duration_seconds "$sd/raw")
    fi

    per_src_duration_dev[$((index-1))]="$dur"
  done

  mkdir -p "$(dirname "$combine_dest_dir_dev")"
  if [ ${#subset_dirs_dev[@]} -eq 0 ]; then
    echo "Error (dev): No subsets were created (check your quotas)." >&2
    exit 1
  fi
  utils/combine_data.sh "$combine_dest_dir_dev" ${subset_dirs_dev[@]}
  utils/fix_data_dir.sh "$combine_dest_dir_dev" >/dev/null
  utils/validate_data_dir.sh --no-text "$combine_dest_dir_dev" || true

  echo "Combined DEV data dir created at: $combine_dest_dir_dev"

  {
    echo "Zipf exponent s=$zipf_exponent"
    echo "Sources (dev): $nsrc_dev"
    echo -n "Zipf integer percentages (dev): "
    echo "$zipf_pcts_str_dev"
    echo -n "Per-source target counts (dev, unit=$combine_unit): "
    echo "$per_src_want_str_dev"
  } >&2

  sum_dur_dev=$(printf "%s\n" "${per_src_duration_dev[@]}" | awk '{s+=$1} END{printf("%.6f\n", s+0)}')

  if awk -v x="$sum_dur_dev" 'BEGIN{exit (x>0?0:1)}'; then
    echo "DEV duration summary (seconds and percent of total):"
    for ((i=0; i<nsrc_dev; i++)); do
      dur_i=${per_src_duration_dev[$i]:-0}
      pct_i=$(awk -v d="$dur_i" -v tot="$sum_dur_dev" 'BEGIN{if (tot>0) printf("%.2f", 100.0*d/tot); else printf("0.00") }')
      src_base=$(basename "${combine_src_dirs_dev[$i]}")
      echo "  - [D$((i+1))] $src_base: ${dur_i}s (${pct_i}%)"
    done
    hms=$(fmt_hms "$sum_dur_dev")
    echo "DEV total duration: ${sum_dur_dev}s (${hms})"
  else
    echo "DEV duration summary: no duration information found (segments/reco2dur missing)."
  fi
fi 