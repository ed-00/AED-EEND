import sys

def get_speakers(spk2utt_file):
    """Reads a spk2utt file and returns a set of speaker IDs."""
    speakers = set()
    try:
        with open(spk2utt_file) as f:
            for line in f:
                parts = line.strip().split()
                if parts:
                    speakers.add(parts[0])
    except FileNotFoundError:
        print(f"Error: File not found at {spk2utt_file}", file=sys.stderr)
        return None
    return speakers

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"Usage: python {sys.argv[0]} <train_spk2utt> <eval_spk2utt>")
        sys.exit(1)

    train_spk_file = sys.argv[1]
    eval_spk_file = sys.argv[2]

    train_speakers = get_speakers(train_spk_file)
    eval_speakers = get_speakers(eval_spk_file)

    if train_speakers is not None and eval_speakers is not None:
        overlap = train_speakers.intersection(eval_speakers)
        
        if not overlap:
            print("SUCCESS: No speaker overlap found between training and evaluation sets.")
            print(f"  - Training speakers: {len(train_speakers)}")
            print(f"  - Evaluation speakers: {len(eval_speakers)}")
        else:
            print(f"FAILURE: Found {len(overlap)} overlapping speakers.")
            for speaker in sorted(list(overlap)):
                print(f"  - {speaker}")
        sys.exit(0)
    
    # Exit with an error if files were not found
    sys.exit(1) 