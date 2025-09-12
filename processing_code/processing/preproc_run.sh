#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=6
#SBATCH --mem=32G
#SBATCH --time=20:00:00
#SBATCH --output=../logs/hbcd-no-drbuddi-%A_%a.log
#SBATCH --array=101-528
#SBATCH --tmp=250G

JOB_ID="${SLURM_JOB_ID}"
NSLOTS="${SLURM_JOB_CPUS_PER_NODE}"

SIMG="${HOME}"/images/qsiprep-1.0.1.sif
CODE_DIR="${HOME}"/pipeline_paper/penn-run/code
SUBJECT_CSV="${HOME}"/tier2_local/code/hbcd1_1.0.0RC01scanner_qc.csv
MIDB_BIDS_DIR="${HOME}"/tier2_local/midb-hbcd-prerelease-bids/assembly_bids
MIDB_DERIVS_DIR="${HOME}"/tier2_local/midb-hbcd-prerelease-bids/derivatives
OUTPUT_DIR="${HOME}/pipeline_paper/penn-run/derivatives/no-drbuddi/qsiprep"
mkdir -p "${OUTPUT_DIR}"

# fail whenever something is fishy, use -x to get verbose logfiles
set -e -u -x
subject_row=$(head -n $((SLURM_ARRAY_TASK_ID + 1)) "${SUBJECT_CSV}" | tail -n 1)
subid=$(echo "$subject_row" | python -c "import sys, re; pattern = r'sub-[a-zA-Z0-9]+(?=,|$)'; matches = re.findall(pattern, sys.stdin.read()); print(matches[0] if len(matches) == 1 else 'ERROR')")
sesid=$(echo "$subject_row" | python -c "import sys, re; pattern = r'ses-[a-zA-Z0-9]+(?=,|$)'; matches = re.findall(pattern, sys.stdin.read()); print(matches[0] if len(matches) == 1 else 'ERROR')")
cbrain_json=${MIDB_DERIVS_DIR}/${sesid}/qsiprep/${subid}/${sesid}/.cbrain/cbrain_params.json

if [ ! -f "${cbrain_json}" ]; then
    echo "No configuration found for ${subid} ${sesid}"
    exit 1
fi

# Use $TMP as the workdir
WORKDIR=${TMP}/"job-${JOB_ID}_${subid}_${sesid}"
mkdir -p "${WORKDIR}"
cd ${WORKDIR}

# Copy only the files used by cbrain
python ${CODE_DIR}/cbrain_mimic.py \
    --dest-dir ${PWD}/BIDS \
    --participant-label ${subid} \
    --session-id ${sesid} \
    --midb-bids-dir ${MIDB_BIDS_DIR} \
    --cbrain-json ${cbrain_json}

# Copy the files we need from the source directory
cp $CODE_DIR/eddy_params.json ./
cp $CODE_DIR/license.txt ./
cp $CODE_DIR/dataset_description.json BIDS/

# Do the run
set +e
singularity run \
    --containall \
    -B ${PWD} \
    -B "${OUTPUT_DIR}" \
    ${SIMG} \
    ${PWD}/BIDS \
    "${OUTPUT_DIR}" \
    participant \
    -w ${PWD}/wkdir \
    --skip-bids-validation \
    --session-id ${sesid} \
    --fs-license-file ${PWD}/fs_license.txt \
    --omp-nthreads ${NSLOTS} \
    --n-cpus ${NSLOTS} \
    --stop-on-first-crash \
    --eddy-config "$PWD"/eddy_params.json \
    --subject-anatomical-reference sessionwise \
    --anat-modality T2w \
    --pepolar-method TOPUP \
    --b1-biascorrect-stage none \
    --infant -v -v \
    --unringing-method rpg \
    --denoise-method dwidenoise \
    --output-resolution 1.7 \
    --notrack

rm -rf ${WORKDIR}

echo SUCCESS

