import sys
from collections import defaultdict

def calculate_speech_overlap(segments_file):
    """
    Calculates the percentage of speech overlap from a Kaldi segments file.

    Overlap is defined as the total duration of speech where two or more
    speakers are talking simultaneously, as a percentage of the total
    duration of all speech.
    """
    reco_to_segments = defaultdict(list)
    try:
        with open(segments_file) as f:
            for line in f:
                parts = line.strip().split()
                if len(parts) != 4:
                    continue
                reco_id = parts[1]
                start_time = float(parts[2])
                end_time = float(parts[3])
                if end_time > start_time:
                    reco_to_segments[reco_id].append((start_time, end_time))
    except FileNotFoundError:
        print(f"Error: Segments file not found at {segments_file}", file=sys.stderr)
        return None, None, None
    except ValueError:
        print(f"Error: Invalid number format in {segments_file}", file=sys.stderr)
        return None, None, None

    total_overlapped_duration = 0.0
    total_speech_duration = 0.0

    for reco_id, segments in reco_to_segments.items():
        if not segments:
            continue

        events = []
        for start, end in segments:
            events.append((start, 1))
            events.append((end, -1))
        
        events.sort()

        active_speakers = 0
        last_time = events[0][0]
        
        for time, type in events:
            dt = time - last_time
            if dt > 1e-9:
                if active_speakers > 0:
                    total_speech_duration += dt
                if active_speakers > 1:
                    total_overlapped_duration += dt
            
            active_speakers += type
            last_time = time
    
    if total_speech_duration == 0:
        return 0.0, 0.0, 0.0

    overlap_percentage = (total_overlapped_duration / total_speech_duration) * 100
    return overlap_percentage, total_overlapped_duration, total_speech_duration

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: python {sys.argv[0]} <path_to_segments_file>")
        sys.exit(1)
        
    segments_file = sys.argv[1]
    percent, overlap_dur, total_dur = calculate_speech_overlap(segments_file)

    if percent is not None:
        print("--- Speech Overlap Analysis ---")
        print(f"Analyzed file: {segments_file}")
        print(f"Total duration of all speech (union of segments): {total_dur/3600:.2f} hours")
        print(f"Total duration of overlapped speech (>1 speaker): {overlap_dur/3600:.2f} hours")
        print(f"Speech Overlap Percentage: {percent:.2f}%")
    else:
        sys.exit(1) 