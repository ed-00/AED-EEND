import sys
import xml.etree.ElementTree as ET

def icsi_to_rttm(xml_file_path, recording_id):
    """
    Parses an ICSI XML annotation file and outputs data in Kaldi's segments,
    utt2spk, and RTTM formats.

    Outputs:
    - segments: <utterance-id> <recording-id> <start-time> <end-time> (to stdout)
    - utt2spk: <utterance-id> <speaker-id> (to stderr)
    - RTTM: SPEAKER <recording-id> 1 <start-time> <duration> <NA> <NA> <speaker-id> <NA> <NA> (to a custom file descriptor 3)
    """
    try:
        tree = ET.parse(xml_file_path)
        root = tree.getroot()
    except ET.ParseError as e:
        print(f"Error parsing XML file {xml_file_path}: {e}", file=sys.stderr)
        return

    # Find the 'Trans' element which contains the turns
    trans_element = root.find('Trans')
    if trans_element is None:
        print(f"Warning: 'Trans' element not found in {xml_file_path}", file=sys.stderr)
        return

    # Open custom file descriptor 3 for RTTM output
    # This is a common pattern in Kaldi scripts to separate output streams.
    # We will write RTTM lines to this custom file descriptor.
    rttm_fd = None
    try:
        rttm_output_stream = open('/dev/fd/3', 'w')
    except Exception as e:
        print(f"Error opening file descriptor 3 for RTTM output: {e}", file=sys.stderr)
        return


    # Iterate through each 'Turn' element
    for turn in trans_element.findall('Turn'):
        start_time_str = turn.get('startTime')
        endTime_str = turn.get('endTime')
        speaker_id = turn.get('speaker') # This is the speaker ID from the XML (e.g., B001_F01)

        if not all([start_time_str, endTime_str, speaker_id]):
            print(f"Warning: Skipping turn due to missing attributes in {xml_file_path}: {turn.attrib}", file=sys.stderr)
            continue

        try:
            start_time = float(start_time_str)
            end_time = float(endTime_str)
            duration = end_time - start_time
        except ValueError:
            print(f"Warning: Invalid time format in {xml_file_path}: startTime={start_time_str}, endTime={endTime_str}", file=sys.stderr)
            continue

        if duration <= 0:
            print(f"Warning: Skipping turn with non-positive duration in {xml_file_path}: {turn.attrib}", file=sys.stderr)
            continue

        # Generate a unique utterance ID for this segment
        # Format: <recording-id>-<speaker-id>-<start-time-ms>-<end-time-ms>
        utterance_id = f"{recording_id}-{speaker_id}-{int(start_time*1000):09d}-{int(end_time*1000):09d}"

        # Output to segments file (stdout 1)
        sys.stdout.write(f"{utterance_id} {recording_id} {start_time:.3f} {end_time:.3f}\n")

        # Output to utt2spk file (stdout 2)
        # Note: In Kaldi, speaker ID is usually just the person's ID, not meeting-specific.
        # We'll use the speaker ID directly from the XML.
        sys.stderr.write(f"{utterance_id} {speaker_id}\n") # Using stderr as a separate channel for utt2spk

        # Output to RTTM file (stdout 3)
        # RTTM format: SPEAKER <file-id> <channel> <start-time> <duration> <NA> <NA> <speaker-id> <NA> <NA>
        # For channel, we use '1' (mono). <NA> are placeholders.
        rttm_output_stream.write(f"SPEAKER {recording_id} 1 {start_time:.3f} {duration:.3f} <NA> <NA> {speaker_id} <NA> <NA>\n")

    if rttm_output_stream:
        rttm_output_stream.close()

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python3 local/icsi_to_rttm.py <xml_file_path> <recording_id>", file=sys.stderr)
        sys.exit(1)

    xml_file_path = sys.argv[1]
    recording_id = sys.argv[2]
    icsi_to_rttm(xml_file_path, recording_id)

