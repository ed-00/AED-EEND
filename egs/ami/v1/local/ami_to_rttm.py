import xml.etree.ElementTree as ET
import sys
import re

def ami_to_rttm(xml_file, meeting_id, speaker_id, rttm_file_path):
    """
    Parses an AMI XML file and generates Kaldi-style
    'segments', 'utt2spk', and 'rttm' files.

    Args:
        xml_file (str): Path to the AMI XML file.
        meeting_id (str): The meeting ID (e.g., 'EN2001a').
        speaker_id (str): The speaker ID (e.g., 'A', 'B', 'C').
        rttm_file_path (str): Path to the RTTM output file.
    """
    try:
        tree = ET.parse(xml_file)
        root = tree.getroot()
    except ET.ParseError as e:
        print(f"Warning: Could not parse XML file {xml_file}: {e}", file=sys.stderr)
        return

    # AMI uses NITE format, segments are under <nite:root>
    # Look for segments in the XML structure
    segments = []
    
    # Try different possible XML structures for AMI
    # Method 1: Look for <segment> elements directly
    segments = root.findall('.//segment')
    
    # Method 2: If no segments found, look for <nite:segment> elements
    if not segments:
        segments = root.findall('.//nite:segment')
    
    # Method 3: Look for <seg> elements (alternative format)
    if not segments:
        segments = root.findall('.//seg')
    
    # Method 4: Look for <turn> elements (another possible format)
    if not segments:
        segments = root.findall('.//turn')

    for seg in segments:
        # Try different attribute names for start and end times
        start_time_str = None
        end_time_str = None
        
        # Check various possible attribute names
        for attr_name in ['starttime', 'start', 'startTime', 'start_time', 'transcriber_start']:
            if seg.get(attr_name):
                start_time_str = seg.get(attr_name)
                break
                
        for attr_name in ['endtime', 'end', 'endTime', 'end_time', 'transcriber_end']:
            if seg.get(attr_name):
                end_time_str = seg.get(attr_name)
                break
        
        # Skip segment if start or end time is missing
        if start_time_str is None or end_time_str is None:
            continue

        try:
            start_time = float(start_time_str)
            end_time = float(end_time_str)
        except ValueError:
            continue
        
        # Use the speaker_id passed as parameter (from filename)
        if speaker_id is None:
            continue # Skip segments without a speaker
            
        # Clean up speaker ID (remove any non-alphanumeric characters except underscore)
        speaker_id = re.sub(r'[^a-zA-Z0-9_]', '', str(speaker_id))
        
        # Generate utterance ID
        utt_id = f"{speaker_id}-{meeting_id}-{int(start_time*100):08d}-{int(end_time*100):08d}"

        # Print to stdout for 'segments'
        print(f"{utt_id} {meeting_id} {start_time:.2f} {end_time:.2f}")
        
        # Print to stderr for 'utt2spk'
        print(f"{utt_id} {speaker_id}", file=sys.stderr)
        
        # Print to file descriptor 3 for 'rttm'
        with open(rttm_file_path, 'a') as f:
            duration = end_time - start_time
            f.write(f"SPEAKER {meeting_id} 1 {start_time:.2f} {duration:.2f} <NA> <NA> {speaker_id} <NA> <NA>\n")

if __name__ == "__main__":
    if len(sys.argv) != 5:
        print("Usage: python ami_to_rttm.py <xml_file> <meeting_id> <speaker_id> <rttm_file_path>")
        sys.exit(1)
    
    ami_to_rttm(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]) 