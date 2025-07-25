import xml.etree.ElementTree as ET
import sys

def icsi_to_rttm(xml_file, meeting_id, rttm_file_path):
    """
    Parses an ICSI XML file (NXT format) and generates Kaldi-style
    'segments', 'utt2spk', and 'rttm' files.

    Args:
        xml_file (str): Path to the ICSI XML file.
        meeting_id (str): The meeting ID (e.g., 'Bdb001').
        rttm_file_path (str): Path to the RTTM output file.
    """
    try:
        tree = ET.parse(xml_file)
        root = tree.getroot()
    except ET.ParseError as e:
        print(f"Warning: Could not parse XML file {xml_file}: {e}", file=sys.stderr)
        return

    # In NXT format, segments are directly under the root
    for seg in root.findall('.//segment'):
        start_time_str = seg.get('starttime')
        end_time_str = seg.get('endtime')
        
        # Skip segment if start or end time is missing
        if start_time_str is None or end_time_str is None:
            continue

        try:
            start_time = float(start_time_str)
            end_time = float(end_time_str)
        except ValueError:
            continue
        
        # Speaker ID is an attribute of the segment
        speaker_id = seg.get('participant')
        if speaker_id is None:
            continue # Skip segments without a speaker
            
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
    if len(sys.argv) != 4:
        print("Usage: python icsi_to_rttm.py <xml_file> <meeting_id> <rttm_file_path>")
        sys.exit(1)
    
    icsi_to_rttm(sys.argv[1], sys.argv[2], sys.argv[3]) 