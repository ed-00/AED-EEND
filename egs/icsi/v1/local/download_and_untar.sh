#!/bin/bash
#
# Copyright 2019 Hitachi, Ltd. (author: Yusuke Fujita)
#           2025 Abed Hameed (author: Abed Hameed)
# Licensed under the MIT license.
#
# This script downloads the ICSI corpus from the University of Edinburgh AMI corpus mirror.
# It downloads individual .sph files and annotations rather than tarballs.
set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <data-base-path>"
    exit 1
fi

data_base=$1

# Check if the corpus has already been downloaded and prepared
if [ -f "${data_base}/ICSI_Corpus_Root/.done" ]; then
    echo "ICSI corpus already found in ${data_base}/ICSI_Corpus_Root. Skipping download."
    exit 0
fi

echo "Downloading ICSI corpus from University of Edinburgh AMI mirror..."

# Create directory structure
mkdir -p "${data_base}/ICSI_Corpus_Root/audio"
mkdir -p "${data_base}/ICSI_Corpus_Root/NIST_Trans"

# Base URLs
BASE_AUDIO_URL="https://groups.inf.ed.ac.uk/ami//ICSIsignals/SPH"
BASE_MIXED_URL="https://groups.inf.ed.ac.uk/ami//ICSIsignals/NXT"
BASE_ANNOTATION_URL="https://groups.inf.ed.ac.uk/ami//download/temp"

# List of meeting IDs (extracted from your wget script)
meetings=(
    "Bdb001" "Bed002" "Bed003" "Bed004" "Bed005" "Bed006" "Bed008" "Bed009" "Bed010" "Bed011" "Bed012" "Bed013" "Bed014" "Bed015" "Bed016" "Bed017"
    "Bmr001" "Bmr002" "Bmr003" "Bmr005" "Bmr006" "Bmr007" "Bmr008" "Bmr009" "Bmr010" "Bmr011" "Bmr012" "Bmr013" "Bmr014" "Bmr015" "Bmr016" "Bmr018" "Bmr019" "Bmr020" "Bmr021" "Bmr022" "Bmr023" "Bmr024" "Bmr025" "Bmr026" "Bmr027" "Bmr028" "Bmr029" "Bmr030" "Bmr031"
    "Bns001" "Bns002" "Bns003"
    "Bro003" "Bro004" "Bro005" "Bro007" "Bro008" "Bro010" "Bro011" "Bro012" "Bro013" "Bro014" "Bro015" "Bro016" "Bro017" "Bro018" "Bro019" "Bro021" "Bro022" "Bro023" "Bro024" "Bro025" "Bro026" "Bro027" "Bro028"
    "Bsr001" "Btr001" "Btr002" "Buw001"
)

meetings_to_download=("${meetings[@]}")

echo "Downloading ${#meetings_to_download[@]} meetings..."

for meeting in "${meetings_to_download[@]}"; do
    echo "Processing meeting: $meeting"
    
    # For diarization, we prefer the mixed/interaction wav file first
    mixed_url="${BASE_MIXED_URL}/${meeting}.interaction.wav"
    mixed_file="${data_base}/ICSI_Corpus_Root/audio/${meeting}.wav"
    
    echo "  Trying to download mixed interaction file..."
    if wget --spider "$mixed_url" 2>/dev/null; then
        wget -q -O "$mixed_file" "$mixed_url" && {
            echo "    Successfully downloaded ${meeting}.interaction.wav"
            continue
        }
    fi
    
    # If mixed file not available, download one representative channel
    echo "  Mixed file not available, trying individual channels..."
    downloaded=false
    for chan in chan1 chan0 chanC chanD chanE chanF chan2 chan3; do
        audio_url="${BASE_AUDIO_URL}/${meeting}/${chan}.sph"
        audio_file="${data_base}/ICSI_Corpus_Root/audio/${meeting}.sph"
        
        echo "    Trying to download $chan.sph..."
        if wget --spider "$audio_url" 2>/dev/null; then
            wget -q -O "$audio_file" "$audio_url" && {
                echo "    Successfully downloaded $chan.sph for ${meeting}"
                downloaded=true
                break
            }
        fi
    done
    
    if [ "$downloaded" = false ]; then
        echo "    Warning: No audio file found for ${meeting}"
    fi
done

# Download annotations
echo "Downloading ICSI annotations..."
# Download the ICSI core annotations (these contain the XML transcripts)
annotation_url="https://groups.inf.ed.ac.uk/ami/ICSICorpusAnnotations/ICSI_plus_NXT.zip"
annotation_file="${data_base}/ICSI_plus_NXT.zip"

if [ ! -f "$annotation_file" ]; then
    echo "Downloading ICSI annotations..."
    wget -O "$annotation_file" "$annotation_url" || { echo "Error: Failed to download annotations." >&2; exit 1; }
fi

# Extract annotations
echo "Extracting annotations..."
unzip -o "$annotation_file" -d "${data_base}/" || {
    echo "Warning: Failed to extract annotations."
}

# Move XML files to the expected location
# The zip file contains directories, and we need to find the XML files within them.
found_xml=false
echo "Searching for transcript files..."
# The meeting name is the directory name, and the .segs.xml files are inside.
# e.g. ICSIplus/Segments/Bdb001.A.segs.xml
echo "Combining per-channel annotations..."
# The NXT annotations have one file per channel, e.g., Bdb001.A.segs.xml, Bdb001.B.segs.xml
# We need to combine these into a single file per meeting for the next stage.
# Get a unique list of meeting IDs from the filenames
meeting_ids=$(find "${data_base}" -path "*/Segments/*.segs.xml" -exec basename {} \; | cut -d'.' -f1 | sort -u)

if [ -z "$meeting_ids" ]; then
    echo "Warning: No XML transcript files were found after unzipping."
else
    for meeting_id in $meeting_ids; do
        combined_xml_path="${data_base}/ICSI_Corpus_Root/NIST_Trans/${meeting_id}.xml"
        echo "  Creating combined annotation for ${meeting_id}"

        # Create the header of the combined XML file
        echo '<?xml version="1.0" encoding="ISO-8859-1" standalone="yes"?>' > "${combined_xml_path}"
        echo "<nite:root nite:id=\"${meeting_id}.segs\" xmlns:nite=\"http://nite.sourceforge.net/\">" >> "${combined_xml_path}"

        # Find all segment files for this meeting, extract segment blocks, and append to the combined file
        find "${data_base}" -path "*/Segments/${meeting_id}.*.segs.xml" | sort | while read -r seg_file_path; do
            # Extract all content between the root <nite:root> tags, but not the tags themselves.
            sed -n '/<nite:root/,/<\/nite:root>/p' "$seg_file_path" | sed '1d;$d' >> "${combined_xml_path}"
        done

        # Add the closing root tag
        echo "</nite:root>" >> "${combined_xml_path}"
    done
fi


# Create a .done file to indicate successful preparation.
touch "${data_base}/ICSI_Corpus_Root/.done"

echo "Successfully downloaded ICSI corpus subset (${#meetings_to_download[@]} meetings)."
echo "Audio files are in: ${data_base}/ICSI_Corpus_Root/audio/"
echo "Transcripts are in: ${data_base}/ICSI_Corpus_Root/NIST_Trans/" 