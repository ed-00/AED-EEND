#!/usr/bin/env python3

import argparse
import sys
import os
from typing import Dict, Tuple, Set, List

# Optional plotting dependency
try:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    HAS_MPL = True
except Exception:
    HAS_MPL = False


def read_kaldi_table_simple(path: str) -> Dict[str, str]:
    """
    Reads a simple Kaldi table with format: KEY VALUE
    Returns a mapping from KEY to VALUE.
    Ignores empty lines and comments.
    """
    mapping: Dict[str, str] = {}
    if not os.path.isfile(path):
        return mapping
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split(maxsplit=1)
            if len(parts) != 2:
                continue
            mapping[parts[0]] = parts[1]
    return mapping


def read_spk2utt(path: str) -> Dict[str, List[str]]:
    """
    Reads Kaldi spk2utt with format: SPEAKER_ID utt1 utt2 ...
    Returns a mapping from SPEAKER_ID to list of utterances.
    """
    spk2utt: Dict[str, List[str]] = {}
    if not os.path.isfile(path):
        return spk2utt
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split()
            if len(parts) < 2:
                # speaker id only, no utts
                spk2utt[parts[0]] = []
                continue
            spk2utt[parts[0]] = parts[1:]
    return spk2utt


def read_segments(path: str) -> List[Tuple[str, str, float, float]]:
    """
    Reads Kaldi segments with format: utt-id reco-id start-time end-time
    Returns list of tuples (utt_id, reco_id, start, end).
    """
    segments: List[Tuple[str, str, float, float]] = []
    if not os.path.isfile(path):
        return segments
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split()
            if len(parts) != 4:
                continue
            utt_id, reco_id, start_str, end_str = parts
            try:
                start = float(start_str)
                end = float(end_str)
            except ValueError:
                continue
            segments.append((utt_id, reco_id, start, end))
    return segments


def compute_reco_durations(
    data_dir: str,
    wav_scp: Dict[str, str],
    segments: List[Tuple[str, str, float, float]],
) -> Dict[str, float]:
    """
    Compute recording durations (in seconds) for each recording id.
    Priority:
      1) Use reco2dur if present.
      2) Else, try reading WAV headers from wav.scp paths via the wave module.
      3) Else, approximate duration as the max end time per recording from segments.
    """
    reco2dur_path = os.path.join(data_dir, "reco2dur")
    reco2dur_map_str = read_kaldi_table_simple(reco2dur_path)
    # Convert to float durations if present
    reco2dur_map: Dict[str, float] = {}
    for reco_id, dur_str in reco2dur_map_str.items():
        try:
            reco2dur_map[reco_id] = float(dur_str)
        except ValueError:
            continue

    # If reco2dur is complete for all recos, return
    if reco2dur_map and set(reco2dur_map.keys()) == set(wav_scp.keys()):
        return reco2dur_map

    # Otherwise, try to fill missing recos by reading audio headers
    filled: Dict[str, float] = dict(reco2dur_map)

    # Use Python's wave module to avoid external dependencies
    import contextlib
    import wave

    for reco_id, wav_path in wav_scp.items():
        if reco_id in filled:
            continue
        # If wav.scp contains a command pipeline, we cannot read headers directly
        # Skip such entries; they will be approximated from segments below
        if "|" in wav_path:
            continue
        # Resolve to absolute path if possible
        abs_path = os.path.abspath(wav_path)
        if not os.path.isfile(abs_path):
            # Try relative to data dir
            rel_path = os.path.abspath(os.path.join(data_dir, wav_path))
            if os.path.isfile(rel_path):
                abs_path = rel_path
        try:
            with contextlib.closing(wave.open(abs_path, "rb")) as wf:
                num_frames = wf.getnframes()
                sample_rate = wf.getframerate()
                if sample_rate > 0:
                    filled[reco_id] = float(num_frames) / float(sample_rate)
        except Exception:
            # Leave missing; may be filled from segments below
            continue

    # As a last resort, approximate duration from segments' max end time per reco
    if segments:
        max_end_by_reco: Dict[str, float] = {}
        for _utt_id, reco_id, start, end in segments:
            prev = max_end_by_reco.get(reco_id, 0.0)
            if end > prev:
                max_end_by_reco[reco_id] = end
        for reco_id, approx_dur in max_end_by_reco.items():
            if reco_id not in filled:
                filled[reco_id] = approx_dur

    return filled


def summarize_dataset(data_dir: str) -> Tuple[Set[str], Set[str], Dict[str, float]]:
    """
    Returns:
      - set of recording ids
      - set of speaker ids
      - mapping of recording id to duration (seconds)
    """
    wav_scp = read_kaldi_table_simple(os.path.join(data_dir, "wav.scp"))
    reco_ids: Set[str] = set(wav_scp.keys())

    spk2utt = read_spk2utt(os.path.join(data_dir, "spk2utt"))
    spk_ids: Set[str] = set(spk2utt.keys())

    segments = read_segments(os.path.join(data_dir, "segments"))
    reco2dur = compute_reco_durations(data_dir, wav_scp, segments)

    # Filter reco_ids to those with known durations (keep mapping complete)
    filtered_reco2dur: Dict[str, float] = {}
    for reco_id in reco_ids:
        if reco_id in reco2dur:
            filtered_reco2dur[reco_id] = reco2dur[reco_id]

    return reco_ids, spk_ids, filtered_reco2dur


def format_hours(seconds: float) -> str:
    hours = seconds / 3600.0
    return f"{hours:.2f} h"


def main() -> int:
    parser = argparse.ArgumentParser(description="Plot and verify AMI dataset stats (durations and overlaps)")
    parser.add_argument("--train-dir", default="data/ami_train", help="Path to training data dir (Kaldi-style)")
    parser.add_argument("--eval-dir", default="data/ami_eval", help="Path to evaluation/validation data dir (Kaldi-style)")
    parser.add_argument("--out-plot", default="data/dataset_durations.png", help="Output path for duration bar chart")
    parser.add_argument("--no-fail-on-overlap", action="store_true", help="Do not exit with non-zero on overlaps; just warn")

    args = parser.parse_args()

    for path in [args.train_dir, args.eval_dir]:
        if not os.path.isdir(path):
            print(f"Error: Data dir not found: {path}", file=sys.stderr)
            return 2

    # Summaries
    train_recos, train_spks, train_reco2dur = summarize_dataset(args.train_dir)
    eval_recos, eval_spks, eval_reco2dur = summarize_dataset(args.eval_dir)

    # Also gather utterance ids to confirm no utterance overlap across splits
    train_spk2utt = read_spk2utt(os.path.join(args.train_dir, "spk2utt"))
    eval_spk2utt = read_spk2utt(os.path.join(args.eval_dir, "spk2utt"))
    train_utts: Set[str] = set(utt for utts in train_spk2utt.values() for utt in utts)
    eval_utts: Set[str] = set(utt for utts in eval_spk2utt.values() for utt in utts)

    # Totals
    total_train_sec = sum(train_reco2dur.values())
    total_eval_sec = sum(eval_reco2dur.values())

    # Overlaps
    overlap_recos = sorted(list(train_recos & eval_recos))
    overlap_spks = sorted(list(train_spks & eval_spks))
    overlap_utts = sorted(list(train_utts & eval_utts))

    # Report
    print("Dataset statistics:")
    print(f"- Train recordings: {len(train_recos)}")
    print(f"- Eval recordings:  {len(eval_recos)}")
    print(f"- Train speakers:   {len(train_spks)}")
    print(f"- Eval speakers:    {len(eval_spks)}")
    print(f"- Train duration:   {format_hours(total_train_sec)}")
    print(f"- Eval duration:    {format_hours(total_eval_sec)}")

    if overlap_recos:
        print(f"NOTE: {len(overlap_recos)} recording ids appear in both train and eval (expected under speaker-independent split).")
        print("  Examples:")
        for rid in overlap_recos[:10]:
            print(f"    {rid}")
    else:
        print("- No overlapping recordings between train and eval.")

    if overlap_spks:
        print(f"WARNING: {len(overlap_spks)} overlapping speaker ids between train and eval.")
        print("  Examples:")
        for sid in overlap_spks[:10]:
            print(f"    {sid}")
    else:
        print("- No overlapping speakers between train and eval.")

    if overlap_utts:
        print(f"WARNING: {len(overlap_utts)} overlapping utterance ids between train and eval.")
        print("  Examples:")
        for uid in overlap_utts[:10]:
            print(f"    {uid}")
    else:
        print("- No overlapping utterance ids between train and eval.")

    # Plot durations
    if HAS_MPL:
        labels = ["Train", "Eval"]
        values_hours = [total_train_sec / 3600.0, total_eval_sec / 3600.0]
        colors = ["#1f77b4", "#ff7f0e"]
        plt.figure(figsize=(6, 4))
        bars = plt.bar(labels, values_hours, color=colors)
        plt.ylabel("Duration (hours)")
        plt.title("Dataset recording durations")
        # Annotate bars
        for bar, val in zip(bars, values_hours):
            plt.text(bar.get_x() + bar.get_width() / 2.0, bar.get_height(), f"{val:.2f}h", ha="center", va="bottom")
        out_dir = os.path.dirname(os.path.abspath(args.out_plot))
        if out_dir and not os.path.isdir(out_dir):
            os.makedirs(out_dir, exist_ok=True)
        plt.tight_layout()
        plt.savefig(args.out_plot)
        print(f"Saved duration plot to: {args.out_plot}")
    else:
        print("matplotlib not available; skipping plot. To enable plotting: pip install matplotlib")

    # Only fail on speaker overlap (dataset leakage), not on shared recordings
    if (overlap_spks) and (not args.no_fail_on_overlap):
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main()) 