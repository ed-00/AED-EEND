import xml.etree.ElementTree as ET
import sys
import re


def ami_to_rttm(xml_file, meeting_id, speaker_id, rttm_file_path,
                 segments_file_path=None, utt2spk_file_path=None):
    """
    Parses an AMI XML file and generates Kaldi-style
    'segments', 'utt2spk', and 'rttm' entries.

    Args:
        xml_file (str): Path to the AMI XML file.
        meeting_id (str): The meeting ID (e.g., 'EN2001a').
        speaker_id (str): The speaker ID (e.g., 'A', 'B', 'C').
        rttm_file_path (str): Path to the RTTM output file.
        segments_file_path (str, optional): Path to append 'segments' lines. If None, write to stdout.
        utt2spk_file_path (str, optional): Path to append 'utt2spk' lines. If None, write to stderr.
    """
    try:
        tree = ET.parse(xml_file)
        root = tree.getroot()
    except ET.ParseError as e:
        print(f"Warning: Could not parse XML file {xml_file}: {e}", file=sys.stderr)
        return

    # Collect segment-like elements while being namespace-agnostic
    def localname(tag):
        return tag.split('}')[-1] if '}' in tag else tag

    candidate_elements = []
    for elem in root.iter():
        tag = localname(elem.tag).lower()
        if tag in {'segment', 'seg', 'turn'}:
            candidate_elements.append(elem)

    # Prepare writers depending on provided paths
    segments_fp = open(segments_file_path, 'a') if segments_file_path else None
    utt2spk_fp = open(utt2spk_file_path, 'a') if utt2spk_file_path else None

    try:
        for seg in candidate_elements:
            # Try different attribute names for start and end times
            start_time_str = None
            end_time_str = None

            for attr_name in ['starttime', 'start', 'startTime', 'start_time', 'transcriber_start']:
                if seg.get(attr_name) is not None:
                    start_time_str = seg.get(attr_name)
                    break

            for attr_name in ['endtime', 'end', 'endTime', 'end_time', 'transcriber_end']:
                if seg.get(attr_name) is not None:
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

            # Skip non-positive durations or reversed times
            if end_time <= start_time:
                continue

            # Use the speaker_id passed as parameter (from filename)
            if speaker_id is None:
                continue  # Skip segments without a speaker

            # Clean up speaker ID (remove any non-alphanumeric characters except underscore)
            speaker_id_clean = re.sub(r'[^a-zA-Z0-9_]', '', str(speaker_id))
            # Make speaker key meeting-specific to avoid global collisions (A/B/C/D reused across meetings)
            speaker_key = f"{meeting_id}_{speaker_id_clean}"

            # Generate utterance ID that starts with speaker_key (Kaldi expects speaker-id as utt-id prefix)
            utt_id = f"{speaker_key}-{int(start_time*100):08d}-{int(end_time*100):08d}"

            # Write 'segments' line
            segments_line = f"{utt_id} {meeting_id} {start_time:.2f} {end_time:.2f}\n"
            if segments_fp:
                segments_fp.write(segments_line)
            else:
                # Backward compatibility: stdout
                sys.stdout.write(segments_line)

            # Write 'utt2spk' line (meeting-specific speaker)
            utt2spk_line = f"{utt_id} {speaker_key}\n"
            if utt2spk_fp:
                utt2spk_fp.write(utt2spk_line)
            else:
                # Backward compatibility: stderr
                sys.stderr.write(utt2spk_line)

            # Append to RTTM (spk id can remain local to the recording)
            with open(rttm_file_path, 'a') as f:
                duration = end_time - start_time
                f.write(f"SPEAKER {meeting_id} 1 {start_time:.2f} {duration:.2f} <NA> <NA> {speaker_id_clean} <NA> <NA>\n")
    finally:
        if segments_fp:
            segments_fp.close()
        if utt2spk_fp:
            utt2spk_fp.close()


if __name__ == "__main__":
    # Backward compatible CLI:
    # - Old: ami_to_rttm.py <xml_file> <meeting_id> <speaker_id> <rttm_file_path>
    # - New: ami_to_rttm.py <xml_file> <meeting_id> <speaker_id> <segments_out> <utt2spk_out> <rttm_out>
    if len(sys.argv) == 5:
        ami_to_rttm(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])
    elif len(sys.argv) == 7:
        ami_to_rttm(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[6],
                    segments_file_path=sys.argv[4], utt2spk_file_path=sys.argv[5])
    else:
        print("Usage (old): python ami_to_rttm.py <xml_file> <meeting_id> <speaker_id> <rttm_file_path>")
        print("Usage (new): python ami_to_rttm.py <xml_file> <meeting_id> <speaker_id> <segments_out> <utt2spk_out> <rttm_out>")
        sys.exit(1) 