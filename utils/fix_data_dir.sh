#!/bin/bash
# Copyright 2019 Hitachi, Ltd. (author: Yusuke Fujita)
# Licensed under the MIT license.
#
# This script fixes a Kaldi data directory.
# Usage: fix_data_dir.sh <data_dir>

if [ $# -ne 1 ]; then
    echo "Usage: $0 <data_dir>"
    exit 1
fi

data_dir=$1

# Check if data directory exists
if [ ! -d "$data_dir" ]; then
    echo "Error: Data directory '$data_dir' does not exist."
    exit 1
fi

# Sort files to ensure consistency
for file in wav.scp segments utt2spk spk2utt; do
    if [ -f "$data_dir/$file" ]; then
        sort -u "$data_dir/$file" > "$data_dir/${file}.tmp"
        mv "$data_dir/${file}.tmp" "$data_dir/$file"
    fi
done

echo "Data directory '$data_dir' has been fixed."
exit 0 