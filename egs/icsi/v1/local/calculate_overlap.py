import os
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict

def get_speakers_from_file(spk2utt_file):
    """Reads a spk2utt file and returns a set of speaker IDs."""
    speakers = set()
    try:
        with open(spk2utt_file) as f:
            for line in f:
                parts = line.strip().split()
                if parts:
                    speakers.add(parts[0])
    except FileNotFoundError:
        print(f"Error: Target speaker file not found at {spk2utt_file}", file=sys.stderr)
        return None
    return speakers

def map_all_speakers_to_meetings(corpus_dir):
    """Parses all ICSI XML files to map each speaker to their meetings."""
    speaker_to_meetings = defaultdict(list)
    if not os.path.isdir(corpus_dir):
        print(f"Error: Corpus directory not found at {corpus_dir}", file=sys.stderr)
        return None
    for filename in os.listdir(corpus_dir):
        if not filename.endswith(".xml"):
            continue
        meeting_id = os.path.splitext(filename)[0]
        xml_file_path = os.path.join(corpus_dir, filename)
        try:
            tree = ET.parse(xml_file_path)
            root = tree.getroot()
            participants = {seg.get('participant') for seg in root.findall('.//segment[@participant]')}
            for speaker_id in participants:
                speaker_to_meetings[speaker_id].append(meeting_id)
        except ET.ParseError as e:
            print(f"Warning: Could not parse {filename}: {e}", file=sys.stderr)
            continue
    return speaker_to_meetings

def analyze_overlap(target_speakers, full_speaker_map):
    """
    Calculates the percentage of target speakers who appear in more than one meeting.
    """
    if not target_speakers or not full_speaker_map:
        return 0, 0
    
    speakers_with_overlap = 0
    for speaker in target_speakers:
        if speaker in full_speaker_map and len(full_speaker_map[speaker]) > 1:
            speakers_with_overlap += 1
            
    total_target_speakers = len(target_speakers)
    if total_target_speakers == 0:
        return 0, 0
        
    overlap_percentage = (speakers_with_overlap / total_target_speakers) * 100
    return speakers_with_overlap, overlap_percentage

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"Usage: python {sys.argv[0]} <target_spk2utt_file> <nist_trans_dir>")
        sys.exit(1)

    target_spk_file = sys.argv[1]
    nist_trans_dir = sys.argv[2]

    # 1. Get the list of speakers to analyze (e.g., from the training set)
    target_speakers = get_speakers_from_file(target_spk_file)
    if target_speakers is None:
        sys.exit(1)

    # 2. Build the global map of all speakers to all their meetings
    full_speaker_map = map_all_speakers_to_meetings(nist_trans_dir)
    if full_speaker_map is None:
        sys.exit(1)

    # 3. Perform the analysis
    num_overlap, percent_overlap = analyze_overlap(target_speakers, full_speaker_map)

    print("--- Speaker Overlap Analysis ---")
    print(f"Total unique speakers in the target set: {len(target_speakers)}")
    print(f"Number of these speakers appearing in >1 meeting: {num_overlap}")
    print(f"Percentage of speakers with meeting overlap: {percent_overlap:.2f}%") 