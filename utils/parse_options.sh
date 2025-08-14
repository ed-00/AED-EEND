#!/bin/bash
# Simple parse_options.sh for AMI data preparation

# This is a simplified version of Kaldi's parse_options.sh
# It handles basic option parsing for our scripts

# Function to print usage
print_usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --stage N        Start from stage N (default: 0)"
    echo "  --eval-percent N Evaluation percentage (default: 10)"
    echo "  --seed N         Random seed (default: 3)"
    echo "  --help           Show this help message"
}

# Default values
stage=0
eval_percent=10
seed=3

# Parse command line arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --stage)
            stage="$2"
            shift 2
            ;;
        --eval-percent)
            eval_percent="$2"
            shift 2
            ;;
        --seed)
            seed="$2"
            shift 2
            ;;
        --help)
            print_usage
            exit 0
            ;;
        *)
            # If it doesn't start with --, it's not an option
            break
            ;;
    esac
done

# Export variables
export stage
export eval_percent
export seed 