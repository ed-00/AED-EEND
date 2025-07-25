#!/bin/bash

# Copyright 2024 Abed Hameed (author: Abed Hameed)
# Licensed under the MIT license.
#
# This script prepares kaldi-style data sets for ICSI diarization.
#   - data/icsi_train
#   - data/icsi_eval (for evaluation)
#   - data/simu_${simu_outputs} (for simulated mixtures, if generated)

stage=0 # Controls which part of the script to run. Set to 0 to run all.

# --- Modify corpus directories ---
# Path to the ICSI corpus root directory
# This directory should contain 'NIST_Trans' (for XML annotations) and 'audio' (for .sph files)
ICSI_CORPUS_DIR=/path/to/ICSI_Corpus_Root # <<<--- IMPORTANT: SET THIS PATH

# These variables are included for stylistic consistency with the Callhome example,
# but are not directly used for ICSI data preparation in this script.
callhome_dir=/export/corpora/NIST/LDC2001S97
swb2_phase1_train=/export/corpora/LDC/LDC98S75
data_root=/export/corpora5/LDC
musan_root=/export/corpora/JHU/musan

# Modify simulated data storage area.
# This script distributes simulated data under these directories
simu_actual_dirs=(
/export/c05/$USER/diarization-data
/export/c08/$USER/diarization-data
/export/c09/$USER/diarization-data
)

# --- Data preparation options ---
max_jobs_run=4 # Included for stylistic consistency
sad_num_jobs=30 # Included for stylistic consistency
sad_opts="--extra-left-context 79 --extra-right-context 21 --frames-per-chunk 150 --extra-left-context-initial 0 --extra-right-context-final 0 --acwt 0.3" # Included for stylistic consistency
sad_graph_opts="--min-silence-duration=0.03 --min-speech-duration=0.3 --max-speech-duration=10.0" # Included for stylistic consistency
sad_priors_opts="--sil-scale=0.1" # Included for stylistic consistency

# --- Feature extraction configuration ---
nj=8 # Number of parallel jobs for feature extraction for MFCCs
mfcc_config=conf/mfcc.conf # MFCC configuration file

# --- Simulation options ---
simu_opts_overlap=yes
simu_opts_num_speaker_array=(1 2 3 4) # Array of speaker counts for simulation
simu_opts_sil_scale_array=(2 2 5 9) # Array of silence scales for simulation
simu_opts_rvb_prob=0.5
simu_opts_num_train=100000
simu_opts_min_utts=10
simu_opts_max_utts=20

# --- Source Kaldi environment and parse options ---
. path.sh
. cmd.sh
. parse_options.sh || exit 1

if [ $stage -le 0 ]; then
    echo "Stage 0: Prepare ICSI kaldi-style datasets and extract features"
    # Prepare ICSI dataset. This will be used for training/evaluation.
    if ! utils/validate_data_dir.sh --no-text --no-feats data/icsi_train; then
        echo "Running local/make_icsi.sh to prepare ICSI data..."
        local/make_icsi.sh "${ICSI_CORPUS_DIR}" data/icsi_train || exit 1
    else
        echo "Data directory 'data/icsi_train' already exists and is valid. Skipping data preparation."
    fi

    # Extract MFCC features and compute CMVN stats for the prepared data.
    # This is done immediately after data preparation for the base dataset.
    for x in icsi_train; do
        if [ ! -f "data/${x}/feats.scp" ]; then
            echo "Running steps/make_mfcc.sh and steps/compute_cmvn_stats.sh for data/${x}..."
            steps/make_mfcc.sh --mfcc-config "${mfcc_config}" --nj "${nj}" --cmd "${train_cmd}" "data/${x}" || exit 1;
            steps/compute_cmvn_stats.sh "data/${x}" || exit 1;
        else
            echo "MFCC features for 'data/${x}' already exist. Skipping feature extraction."
        fi
    done
fi

simudir=data/simu
if [ $stage -le 1 ]; then
    echo "Stage 1: Simulation of mixtures (using ICSI as base data)"
    mkdir -p $simudir/.work

    # Determine which mixture generation scripts to use based on overlap option
    random_mixture_cmd=random_mixture_nooverlap.py
    make_mixture_cmd=make_mixture_nooverlap.py
    if [ "$simu_opts_overlap" == "yes" ]; then
        random_mixture_cmd=random_mixture.py
        make_mixture_cmd=make_mixture.py
    fi

    # Loop through different speaker counts and silence scales for simulation
    for ((i=0; i<${#simu_opts_sil_scale_array[@]}; ++i)); do
        simu_opts_num_speaker=${simu_opts_num_speaker_array[i]}
        simu_opts_sil_scale=${simu_opts_sil_scale_array[i]}
        
        # We will use 'icsi_train' as the base dataset for simulation
        # For demonstration, we'll create a single simulated set.
        # In a real scenario, you might split icsi_train into train/dev/eval for simulation.
        dset_base=icsi_train
        n_mixtures=${simu_opts_num_train} # Use the configured number of training mixtures

        simuid=${dset_base}_ns${simu_opts_num_speaker}_beta${simu_opts_sil_scale}_${n_mixtures}
        
        # Check if the simulation data already exists
        if ! utils/validate_data_dir.sh --no-text --no-feats $simudir/data/$simuid; then
            echo "Generating random mixtures for $simuid..."
            # Random mixture generation (requires random_mixture.py/random_mixture_nooverlap.py)
            # Note: You would need to provide or adapt these Python scripts for ICSI.
            # This is a placeholder structure.
            $train_cmd $simudir/.work/random_mixture_$simuid.log \
                $random_mixture_cmd --n_speakers $simu_opts_num_speaker --n_mixtures $n_mixtures \
                --speech_rvb_probability $simu_opts_rvb_prob \
                --sil_scale $simu_opts_sil_scale \
                data/$dset_base data/musan_noise_bg data/simu_rirs_8k \
                \> $simudir/.work/mixture_$simuid.scp || { echo "Error in random mixture generation"; exit 1; }
            
            nj_simu=100 # Number of jobs for mixture generation, as in Callhome example
            mkdir -p $simudir/wav/$simuid
            
            # Distribute simulated data to actual directories (placeholder)
            split_scps=
            for n in $(seq $nj_simu); do
                split_scps="$split_scps $simudir/.work/mixture_$simuid.$n.scp"
                mkdir -p $simudir/.work/data_$simuid.$n
                actual=${simu_actual_dirs[($n-1)%${#simu_actual_dirs[@]}]}/$simudir/wav/$simuid/$n
                mkdir -p $actual
                ln -nfs $actual $simudir/wav/$simuid/$n
            done
            utils/split_scp.pl $simudir/.work/mixture_$simuid.scp $split_scps || exit 1

            # Make mixtures (requires make_mixture.py/make_mixture_nooverlap.py)
            # This is a placeholder structure.
            $train_cmd --max-jobs-run 32 JOB=1:$nj_simu $simudir/.work/make_mixture_$simuid.JOB.log \
                $make_mixture_cmd --rate=8000 \
                $simudir/.work/mixture_$simuid.JOB.scp \
                $simudir/.work/data_$simuid.JOB $simudir/wav/$simuid/JOB || { echo "Error in make mixture"; exit 1; }
            
            # Combine generated data
            utils/combine_data.sh $simudir/data/$simuid $simudir/.work/data_$simuid.* || exit 1
            
            # Generate RTTM for simulated data
            steps/segmentation/convert_utt2spk_and_segments_to_rttm.py \
                $simudir/data/$simuid/utt2spk $simudir/data/$simuid/segments \
                $simudir/data/$simuid/rttm || exit 1
            
            utils/data/get_reco2dur.sh $simudir/data/$simuid || exit 1
        else
            echo "Simulated data '$simudir/data/$simuid' already exists and is valid. Skipping simulation."
        fi
        
        # Concatenate simulated data (as in the Callhome example)
        # This part is for combining results from different simulation parameters.
        simuid_concat=${dset_base}_ns"$(IFS="n"; echo "${simu_opts_num_speaker_array[*]}")"_beta"$(IFS="n"; echo "${simu_opts_sil_scale_array[*]}")"_${n_mixtures}
        mkdir -p $simudir/data/$simuid_concat
        for f in `ls -F $simudir/data/$simuid | grep -v "/"`; do
            cat $simudir/data/$simuid/$f >> $simudir/data/$simuid_concat/$f
        done
    done
fi

if [ $stage -le 2 ]; then
    echo "Stage 2: Compose evaluation set (icsi_eval)"
    # This stage composes a dedicated evaluation set from the prepared ICSI data.
    eval_set=data/icsi_eval
    if ! utils/validate_data_dir.sh --no-text --no-feats $eval_set; then
        echo "Composing evaluation set '$eval_set'..."
        utils/copy_data_dir.sh data/icsi_train $eval_set
        # Copy the RTTM from the 'icsi_train' set to 'icsi_eval'.
        # If you have specific ICSI evaluation RTTMs, replace this with filtering or direct copying.
        cp data/icsi_train/rttm $eval_set/rttm
        # Ensure reco2dur is present for the evaluation set
        utils/data/get_reco2dur.sh $eval_set || exit 1
        echo "Evaluation set '$eval_set' composed."
    else
        echo "Evaluation set '$eval_set' already exists and is valid. Skipping composition."
    fi
fi

echo "All shared data preparation stages complete for ICSI diarization."