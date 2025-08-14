#!/bin/bash
# Copyright 2019 Hitachi, Ltd. (author: Yusuke Fujita)
# Licensed under the MIT license.
#
# This script creates a subset of a Kaldi data directory.
# Usage: subset_data_dir.sh [options] <src-data-dir> <dest-data-dir>

# Parse options
spk_list=""
while [ $# -gt 0 ]; do
    case "$1" in
        --spk-list)
            spk_list="$2"
            shift 2
            ;;
        *)
            break
            ;;
    esac
done

if [ $# -ne 2 ]; then
    echo "Usage: $0 [--spk-list <spk-list-file>] <src-data-dir> <dest-data-dir>"
    exit 1
fi

src_dir=$1
dest_dir=$2

# Check if source directory exists
if [ ! -d "$src_dir" ]; then
    echo "Error: Source directory '$src_dir' does not exist."
    exit 1
fi

# Create destination directory
mkdir -p "$dest_dir"

# Copy required files
for file in wav.scp segments utt2spk spk2utt rttm; do
    if [ -f "$src_dir/$file" ]; then
        cp "$src_dir/$file" "$dest_dir/"
    fi
done

# If speaker list is provided, filter by speakers
if [ -n "$spk_list" ] && [ -f "$spk_list" ]; then
    # Create speaker list for filtering
    awk '{print $1}' "$spk_list" > "${dest_dir}/spk_list"
    
    # Filter utt2spk by speakers
    if [ -f "$dest_dir/utt2spk" ]; then
        awk 'NR==FNR{spk[$1]=1; next} $2 in spk{print}' "${dest_dir}/spk_list" "$dest_dir/utt2spk" > "${dest_dir}/utt2spk.tmp"
        mv "${dest_dir}/utt2spk.tmp" "$dest_dir/utt2spk"
    fi
    
    # Filter segments by utterances in utt2spk
    if [ -f "$dest_dir/segments" ] && [ -f "$dest_dir/utt2spk" ]; then
        awk 'NR==FNR{utt[$1]=1; next} $1 in utt{print}' "$dest_dir/utt2spk" "$dest_dir/segments" > "${dest_dir}/segments.tmp"
        mv "${dest_dir}/segments.tmp" "$dest_dir/segments"
    fi
    
    # Filter rttm by utterances in segments
    if [ -f "$dest_dir/rttm" ] && [ -f "$dest_dir/segments" ]; then
        awk 'NR==FNR{utt[$1]=1; next} $2 in utt{print}' "$dest_dir/segments" "$dest_dir/rttm" > "${dest_dir}/rttm.tmp"
        mv "${dest_dir}/rttm.tmp" "$dest_dir/rttm"
    fi
    
    # Regenerate spk2utt
    if [ -f "$dest_dir/utt2spk" ]; then
        utils/utt2spk_to_spk2utt.pl "$dest_dir/utt2spk" > "$dest_dir/spk2utt"
    fi
    
    # Clean up
    rm -f "${dest_dir}/spk_list"
fi

echo "Subset created in '$dest_dir'" 