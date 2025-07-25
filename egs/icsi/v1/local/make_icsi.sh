#!/bin/bash
# Copyright 2024 Abed Hameed (author: Abed Hameed)
# Licensed under the MIT license.
#
# This script prepares the ICSI data for Kaldi diarization.
# It parses the ICSI XML annotations and audio files to create:
# - wav.scp
# - segments
# - utt2spk
# - spk2utt
# - rttm (for evaluation)

# Usage: local/make_icsi.sh <ICSI_CORPUS_DIR> <output_data_dir>
# Example: local/make_icsi.sh /path/to/ICSI_Corpus data/train

ICSI_CORPUS_DIR=$1
OUTPUT_DATA_DIR=$2

if [ -z "$ICSI_CORPUS_DIR" ] || [ -z "$OUTPUT_DATA_DIR" ]; then
  echo "Usage: local/make_icsi.sh <ICSI_CORPUS_DIR> <output_data_dir>"
  exit 1
fi

mkdir -p "${OUTPUT_DATA_DIR}" || exit 1;

echo "Processing ICSI data from: ${ICSI_CORPUS_DIR}"
echo "Outputting to: ${OUTPUT_DATA_DIR}"

# --- Initialize files ---
# Ensure these files are empty or created fresh for each run
> "${OUTPUT_DATA_DIR}/wav.scp"
> "${OUTPUT_DATA_DIR}/segments"
> "${OUTPUT_DATA_DIR}/utt2spk"
> "${OUTPUT_DATA_DIR}/spk2utt" # Will be generated from utt2spk later
> "${OUTPUT_DATA_DIR}/rttm"

# Clean up any leftover temporary files from previous runs
rm -f "${OUTPUT_DATA_DIR}/segments_temp" "${OUTPUT_DATA_DIR}/utt2spk_temp" "${OUTPUT_DATA_DIR}/rttm_temp"

# Find all XML annotation files and process them
find "${ICSI_CORPUS_DIR}/NIST_Trans" -name "*.xml" | while IFS= read -r xml_file; do
  # Extract meeting ID from the XML file path (e.g., Bmr001)
  meeting_id=$(basename "${xml_file}" .xml)

  # Check for both .wav and .sph, prioritizing .wav
  audio_file_wav="${ICSI_CORPUS_DIR}/audio/${meeting_id}.wav"
  audio_file_sph="${ICSI_CORPUS_DIR}/audio/${meeting_id}.sph"

  audio_file=""
  audio_cmd=""
  if [ -f "${audio_file_wav}" ]; then
    audio_file=${audio_file_wav}
    # Resample the 16kHz WAV file to 8kHz
    audio_cmd="sox ${audio_file} -t wav -r 8000 - |"
  elif [ -f "${audio_file_sph}" ]; then
    audio_file=${audio_file_sph}
    # sph2pipe converts sphere to wav, then we resample to 8kHz
    audio_cmd="sph2pipe -f wav ${audio_file} | sox -t wav - -t wav -r 8000 - |"
  else
    echo "Warning: No audio file found for ${meeting_id} (checked for .wav and .sph). Skipping."
    continue
  fi

  echo "Processing meeting: ${meeting_id} with audio file ${audio_file}"

  # Add entry to wav.scp
  echo "${meeting_id} ${audio_cmd}" >> "${OUTPUT_DATA_DIR}/wav.scp"

  # Use Python script to parse XML and generate segments, utt2spk, and RTTM
  # The Python script writes to stdout (segments), stderr (utt2spk), and FD 3 (rttm).
  # We redirect these outputs to temporary files.
  python3 local/icsi_to_rttm.py "${xml_file}" "${meeting_id}" "${OUTPUT_DATA_DIR}/rttm_temp_single" \
    >> "${OUTPUT_DATA_DIR}/segments_temp" \
    2>> "${OUTPUT_DATA_DIR}/utt2spk_temp"
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
# fix_data_dir.sh ensures consistency (e.g., all utterances in segments have entries in wav.scp)
# validate_data_dir.sh checks for common issues.
utils/fix_data_dir.sh "${OUTPUT_DATA_DIR}" || exit 1;
utils/validate_data_dir.sh --no-feats --no-text "${OUTPUT_DATA_DIR}" || exit 1; # --no-feats because features are made in run.sh

# Generate reco2dur (recording ID to duration) file, useful for various Kaldi scripts
utils/data/get_reco2dur.sh "${OUTPUT_DATA_DIR}" || exit 1;

echo "ICSI data preparation complete for ${OUTPUT_DATA_DIR}."
