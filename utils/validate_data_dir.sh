#!/bin/bash
# Copyright 2019 Hitachi, Ltd. (author: Yusuke Fujita)
# Licensed under the MIT license.
#
# This script validates a Kaldi data directory.
# Usage: validate_data_dir.sh [options] <data_dir>

# Default options
no_text=false
no_feats=false

# Parse options
while [ $# -gt 0 ]; do
    case "$1" in
        --no-text)
            no_text=true
            shift
            ;;
        --no-feats)
            no_feats=true
            shift
            ;;
        *)
            break
            ;;
    esac
done

if [ $# -ne 1 ]; then
    echo "Usage: $0 [--no-text] [--no-feats] <data_dir>"
    exit 1
fi

data_dir=$1

# Check if data directory exists
if [ ! -d "$data_dir" ]; then
    echo "Error: Data directory '$data_dir' does not exist."
    exit 1
fi

# Check required files
required_files=("wav.scp" "segments" "utt2spk" "spk2utt")

for file in "${required_files[@]}"; do
    if [ ! -f "$data_dir/$file" ]; then
        echo "Error: Required file '$file' is missing in '$data_dir'."
        exit 1
    fi
done

# Check if files are not empty
for file in "${required_files[@]}"; do
    if [ ! -s "$data_dir/$file" ]; then
        echo "Error: File '$file' is empty in '$data_dir'."
        exit 1
    fi
done

echo "Data directory '$data_dir' is valid."
exit 0 