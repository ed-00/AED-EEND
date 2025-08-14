#!/bin/bash
#
# Copyright 2019 Hitachi, Ltd. (author: Yusuke Fujita)
#           2025 Maoxuan Sha (author: Maoxuan Sha)
# Licensed under the MIT license.
#
# This script downloads the AMI corpus from the University of Edinburgh AMI corpus mirror.
# It downloads individual .wav files and annotations rather than tarballs.
set -e

# 自动设置数据目录为脚本所在目录下的 ami_data 文件夹
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
data_base="${script_dir}/ami_data"

echo "Data will be downloaded to: $data_base"

# Check if the corpus has already been downloaded and prepared
if [ -f "${data_base}/AMI_Corpus_Root/.done" ]; then
    echo "AMI corpus already found in ${data_base}/AMI_Corpus_Root. Skipping download."
    exit 0
fi

echo "Downloading AMI corpus from University of Edinburgh AMI mirror..."

# Create directory structure
mkdir -p "${data_base}/AMI_Corpus_Root/audio"
mkdir -p "${data_base}/AMI_Corpus_Root/NIST_Trans"

# 自动从 segments 目录下所有 .segments.xml 文件提取会议ID（去重）
segments_dir="/sbt-fast/dia-df/maoxuan/AED-EEND/egs/ami/ami_public_manual_1.6.2/segments"

# Check if segments directory exists
if [ ! -d "$segments_dir" ]; then
    echo "Error: Segments directory not found: $segments_dir"
    echo "Please check the path and make sure the segments directory exists."
    exit 1
fi

# Extract meeting IDs from segments files - 修正正则表达式
meetings=($(ls $segments_dir/*.segments.xml 2>/dev/null | xargs -n1 basename | sed 's/\([A-Z0-9]*\)\.[A-Z]\.segments\.xml/\1/' | sort -u))

if [ ${#meetings[@]} -eq 0 ]; then
    echo "Error: No segments files found in $segments_dir"
    echo "Please check if the segments directory contains *.segments.xml files."
    exit 1
fi

echo "Found ${#meetings[@]} meetings to download:"
printf '%s\n' "${meetings[@]}" | head -10
if [ ${#meetings[@]} -gt 10 ]; then
    echo "... and $(( ${#meetings[@]} - 10 )) more"
fi
echo ""

# Download audio files
successful_downloads=0
failed_downloads=0

for i in "${!meetings[@]}"; do
    meeting="${meetings[$i]}"
    echo "[$((i+1))/${#meetings[@]}] Processing meeting: $meeting"
    
    audio_url="https://groups.inf.ed.ac.uk/ami/AMICorpusMirror//amicorpus/${meeting}/audio/${meeting}.Mix-Headset.wav"
    audio_dir="${data_base}/AMI_Corpus_Root/audio/${meeting}"
    audio_file="${audio_dir}/${meeting}.Mix-Headset.wav"
    
    # Create directory
    mkdir -p "$audio_dir"
    
    # Check if file already exists
    if [ -f "$audio_file" ]; then
        echo "  ✓ File already exists, skipping: $audio_file"
        ((successful_downloads++))
        continue
    fi
    
    echo "  Downloading $audio_url ..."
    
    # Try to download with wget using -P parameter (like the working examples)
    if wget -q --show-progress -P "$audio_dir" "$audio_url" 2>/dev/null; then
        echo "  ✓ Successfully downloaded: $meeting"
        ((successful_downloads++))
    else
        echo "  ✗ Failed to download: $meeting"
        ((failed_downloads++))
        # Remove partial file if download failed
        rm -f "$audio_file"
    fi
done

echo ""
echo "Download Summary:"
echo "  Successful: $successful_downloads"
echo "  Failed: $failed_downloads"
echo "  Total: ${#meetings[@]}"

# Create a .done file to indicate successful preparation
if [ $failed_downloads -eq 0 ]; then
    touch "${data_base}/AMI_Corpus_Root/.done"
    echo ""
    echo "Successfully downloaded AMI corpus (${#meetings[@]} meetings)."
    echo "Audio files are in: ${data_base}/AMI_Corpus_Root/audio/"
    echo "Transcripts are in: ${data_base}/AMI_Corpus_Root/NIST_Trans/"
else
    echo ""
    echo "Warning: Some downloads failed. Please check the failed meetings and retry if needed."
    echo "You can run this script again to download only the missing files."
fi

# # Download annotations
# echo "Downloading ICSI annotations..."
# # Download the ICSI core annotations (these contain the XML transcripts)
# annotation_url="https://groups.inf.ed.ac.uk/ami/ICSICorpusAnnotations/ICSI_plus_NXT.zip"
# annotation_file="${data_base}/ICSI_plus_NXT.zip"

# if [ ! -f "$annotation_file" ]; then
#     echo "Downloading ICSI annotations..."
#     wget -O "$annotation_file" "$annotation_url" || { echo "Error: Failed to download annotations." >&2; exit 1; }
# fi

# # Extract annotations
# echo "Extracting annotations..."
# unzip -o "$annotation_file" -d "${data_base}/" || {
#     echo "Warning: Failed to extract annotations."
# }

# # Move XML files to the expected location
# # The zip file contains directories, and we need to find the XML files within them.
# found_xml=false
# echo "Searching for transcript files..."
# # The meeting name is the directory name, and the .segs.xml files are inside.
# # e.g. ICSIplus/Segments/Bdb001.A.segs.xml
# echo "Combining per-channel annotations..."
# # The NXT annotations have one file per channel, e.g., Bdb001.A.segs.xml, Bdb001.B.segs.xml
# # We need to combine these into a single file per meeting for the next stage.
# # Get a unique list of meeting IDs from the filenames
# meeting_ids=$(find "${data_base}" -path "*/Segments/*.segs.xml" -exec basename {} \; | cut -d'.' -f1 | sort -u)

# if [ -z "$meeting_ids" ]; then
#     echo "Warning: No XML transcript files were found after unzipping."
# else
#     for meeting_id in $meeting_ids; do
#         combined_xml_path="${data_base}/ICSI_Corpus_Root/NIST_Trans/${meeting_id}.xml"
#         echo "  Creating combined annotation for ${meeting_id}"

#         # Create the header of the combined XML file
#         echo '<?xml version="1.0" encoding="ISO-8859-1" standalone="yes"?>' > "${combined_xml_path}"
#         echo "<nite:root nite:id=\"${meeting_id}.segs\" xmlns:nite=\"http://nite.sourceforge.net/\">" >> "${combined_xml_path}"

#         # Find all segment files for this meeting, extract segment blocks, and append to the combined file
#         find "${data_base}" -path "*/Segments/${meeting_id}.*.segs.xml" | sort | while read -r seg_file_path; do
#             # Extract all content between the root <nite:root> tags, but not the tags themselves.
#             sed -n '/<nite:root/,/<\/nite:root>/p' "$seg_file_path" | sed '1d;$d' >> "${combined_xml_path}"
#         done

#         # Add the closing root tag
#         echo "</nite:root>" >> "${combined_xml_path}"
#     done
# fi


# # Create a .done file to indicate successful preparation.
# touch "${data_base}/ICSI_Corpus_Root/.done"

# echo "Successfully downloaded ICSI corpus subset (${#meetings_to_download[@]} meetings)."
# echo "Audio files are in: ${data_base}/ICSI_Corpus_Root/audio/"
# echo "Transcripts are in: ${data_base}/ICSI_Corpus_Root/NIST_Trans/" 