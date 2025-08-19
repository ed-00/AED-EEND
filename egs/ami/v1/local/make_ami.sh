#!/bin/bash
# Copyright 2024 Maoxuan Sha (author: Maoxuan Sha)
# Licensed under the MIT license.
#
# This script prepares the AMI data for Kaldi diarization.
# It parses the AMI XML annotations and audio files to create:
# - wav.scp
# - segments
# - utt2spk
# - spk2utt
# - rttm (for evaluation)

# Usage: local/make_ami.sh <AMI_CORPUS_DIR> <output_data_dir>
# Example: local/make_ami.sh /path/to/AMI_Corpus data/train

AMI_CORPUS_DIR=$1
OUTPUT_DATA_DIR=$2

if [ -z "$AMI_CORPUS_DIR" ] || [ -z "$OUTPUT_DATA_DIR" ]; then
  echo "Usage: local/make_ami.sh <AMI_CORPUS_DIR> <output_data_dir>"
  exit 1
fi

# Ensure required tools are available
if ! command -v sox >/dev/null 2>&1; then
  echo "Error: sox is required for resampling but was not found in PATH." >&2
  exit 1
fi

# Target sampling rate and directory to store resampled audio
TARGET_SR=8000
RESAMPLED_DIR="data/ami_wav_${TARGET_SR}"
mkdir -p "${RESAMPLED_DIR}" || exit 1

mkdir -p "${OUTPUT_DATA_DIR}" || exit 1;

echo "Processing AMI data from: ${AMI_CORPUS_DIR}"
echo "Outputting to: ${OUTPUT_DATA_DIR}"

echo "Resampled audio will be stored in: ${RESAMPLED_DIR} at ${TARGET_SR} Hz"

# --- Initialize files ---
# Ensure these files are empty or created fresh for each run
> "${OUTPUT_DATA_DIR}/wav.scp"
> "${OUTPUT_DATA_DIR}/segments"
> "${OUTPUT_DATA_DIR}/utt2spk"
> "${OUTPUT_DATA_DIR}/spk2utt" # Will be generated from utt2spk later
> "${OUTPUT_DATA_DIR}/rttm"

# Clean up any leftover temporary files from previous runs
rm -f "${OUTPUT_DATA_DIR}/segments_temp" "${OUTPUT_DATA_DIR}/utt2spk_temp" "${OUTPUT_DATA_DIR}/rttm_temp"

# Find all XML annotation files in the segments directory
# Use the already downloaded segments files
SEGMENTS_DIR="ami_public_manual_1.6.2/segments"
find "${SEGMENTS_DIR}" -name "*.segments.xml" | while IFS= read -r xml_file; do
  # Extract meeting ID and speaker from the XML file path (e.g., EN2001a.A.segments.xml -> EN2001a)
  filename=$(basename "${xml_file}")
  meeting_id=$(echo "${filename}" | cut -d'.' -f1)
  speaker_id=$(echo "${filename}" | cut -d'.' -f2)

  # Check for audio file
  audio_file="${AMI_CORPUS_DIR}/audio/${meeting_id}/${meeting_id}.Mix-Headset.wav"

  if [ ! -f "${audio_file}" ]; then
    echo "Warning: No audio file found for ${meeting_id}: ${audio_file}. Skipping."
    continue
  fi

  echo "Processing meeting: ${meeting_id}, speaker: ${speaker_id} with audio file ${audio_file}"

  # Prepare resampled audio path and resample if needed
  resampled_file="${RESAMPLED_DIR}/${meeting_id}.wav"
  if [ ! -f "${resampled_file}" ]; then
    echo "Resampling ${audio_file} -> ${resampled_file} at ${TARGET_SR} Hz (mono)"
    # Downmix to mono and resample to target rate; write standard WAV
    sox "${audio_file}" -c 1 -r ${TARGET_SR} "${resampled_file}"
    if [ $? -ne 0 ]; then
      echo "Error: sox failed to resample ${audio_file}" >&2
      exit 1
    fi
  fi

  # Add entry to wav.scp (only once per meeting)
  if ! grep -q "^${meeting_id} " "${OUTPUT_DATA_DIR}/wav.scp"; then
    echo "${meeting_id} ${resampled_file}" >> "${OUTPUT_DATA_DIR}/wav.scp"
  fi

  # Use Python script to parse XML and generate segments, utt2spk, and RTTM
  python3 local/ami_to_rttm.py "${xml_file}" "${meeting_id}" "${speaker_id}" \
    "${OUTPUT_DATA_DIR}/segments_temp" "${OUTPUT_DATA_DIR}/utt2spk_temp" "${OUTPUT_DATA_DIR}/rttm_temp_single"
  cat "${OUTPUT_DATA_DIR}/rttm_temp_single" >> "${OUTPUT_DATA_DIR}/rttm_temp"
  rm -f "${OUTPUT_DATA_DIR}/rttm_temp_single"
done

# If no XML files were found, the temp files will not be created.
# We should touch them to prevent the script from failing.
touch "${OUTPUT_DATA_DIR}/segments_temp" "${OUTPUT_DATA_DIR}/utt2spk_temp" "${OUTPUT_DATA_DIR}/rttm_temp"

# Sort and unique the temporary files, then move them to final locations
# This ensures correct Kaldi format and removes duplicates.
sort -u "${OUTPUT_DATA_DIR}/segments_temp" > "${OUTPUT_DATA_DIR}/segments"
sort -u "${OUTPUT_DATA_DIR}/utt2spk_temp" > "${OUTPUT_DATA_DIR}/utt2spk"
sort -u "${OUTPUT_DATA_DIR}/rttm_temp" > "${OUTPUT_DATA_DIR}/rttm"

# Clean up temporary files
rm "${OUTPUT_DATA_DIR}/segments_temp" "${OUTPUT_DATA_DIR}/utt2spk_temp" "${OUTPUT_DATA_DIR}/rttm_temp"

# Create spk2utt from utt2spk (standard Kaldi utility)
utils/utt2spk_to_spk2utt.pl "${OUTPUT_DATA_DIR}/utt2spk" > "${OUTPUT_DATA_DIR}/spk2utt" || exit 1;

# Fix and validate the data directory (standard Kaldi utilities)
utils/fix_data_dir.sh "${OUTPUT_DATA_DIR}" || exit 1;
utils/validate_data_dir.sh --no-feats --no-text "${OUTPUT_DATA_DIR}" || exit 1;

echo "AMI data preparation complete for ${OUTPUT_DATA_DIR}" 