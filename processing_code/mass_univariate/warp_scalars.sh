#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=0:10:00
#SBATCH --output=hbcd-scalarwarp-%A_%a.log
#SBATCH --array=1-517

# CHANGE THIS!!
REPRO_DIR="${HOME}/rep1"

SIMG="${HOME}"/images/qsirecon-1.0.1RC0.sif
RESULTS_CSV="${HOME}/tier2_local/code/hbcd_1.0.0RC0_scanner_qc.csv"

[ -z "${JOB_ID}" ] && JOB_ID=TEST

if [[ ! -z "${SLURM_JOB_ID}" ]]; then
    echo SLURM detected
    JOB_ID="${SLURM_JOB_ID}"
    NSLOTS="${SLURM_JOB_CPUS_PER_NODE}"
fi

# fail whenever something is fishy, use -x to get verbose logfiles
set -e -u -x

# Set up the remotes and get the subject id from the call
subject_row=$(head -n $((${SLURM_ARRAY_TASK_ID} + 1)) ${RESULTS_CSV} | tail -n 1)
subid=$(echo $subject_row | sed 's/^.*,\(sub-[A-Za-z0-9]*\).*$/\1/')
sesid=$(echo $subject_row | sed 's/^.*,\(ses-[A-Za-z0-9]*\).*$/\1/')

OUTPUT_DIR=${REPRO_DIR}/volumetric/data/${subid}/${sesid}
mkdir -p ${OUTPUT_DIR}


# Use $TMP as the workdir
WORKDIR=${TMP}/"job-${JOB_ID}_${subid}_${sesid}"
mkdir -p "${WORKDIR}"
cd ${WORKDIR}

# Get dir holding session qsiprep outputs
QSIPREP_DIR=/cbica/projects/hbcd_dev/tier2_local/midb-hbcd-prerelease-bids/derivatives/${sesid}/qsiprep/${subid}/${sesid}

WARP_FILE=$(find "${QSIPREP_DIR}" -name '*from-ACPC_to-MNI*xfm.h5')
BRAIN_MASK=$(find "${QSIPREP_DIR}" -name '*_space-ACPC_desc-brain_mask.nii.gz')
COHORT=$(echo "${WARP_FILE}" | sed 's/.*MNIInfant+\([0-9][0-9]*\)_.*/\1/')
XFORM2=${HOME}/pipeline_paper/volumetric/templates/from-MNIInfant+${COHORT}_to-MNI152NLin6Asym_xfm.h5
REFVOL=${HOME}/pipeline_paper/volumetric/templates/nlin6_1.7mm.nii.gz


MASK_OUT=${OUTPUT_DIR}/$(basename ${BRAIN_MASK} | sed 's/ACPC/MNI152NLin6Asym/')
singularity exec \
    --containall \
    -B ${HOME} \
    ${SIMG} \
    antsApplyTransforms \
        -d 3 \
        -r ${REFVOL} \
	--interpolation nearestneighbor \
	-i ${BRAIN_MASK} \
	-t ${XFORM2} \
	-t ${WARP_FILE} \
	-o ${MASK_OUT} \
	-v 1

TO_TRANSFORM=$(find ${HOME}/tier2_local/midb-hbcd-prerelease-bids/qsirecon-* -name "${subid}_${sesid}*dwimap.nii.gz")

for dwimap in ${TO_TRANSFORM}
do
    dwimap_space=$(basename ${dwimap} | sed 's/ACPC/MNI152NLin6Asym/')
    recon_spec=$(echo ${dwimap} | sed 's/.*\(qsirecon-[a-zA-Z][-_a-zA-Z0-9]*\)\/.*/\1/')
    out_dir=${OUTPUT_DIR}/${recon_spec}
    mkdir -p ${out_dir}
    DWIMAP_OUT=${out_dir}/${dwimap_space}
    
    singularity exec \
        --containall \
        -B ${HOME} \
        ${SIMG} \
        antsApplyTransforms \
        -d 3 \
        -r ${REFVOL} \
        --interpolation nearestneighbor \
        -i ${dwimap} \
        -t ${XFORM2} \
        -t ${WARP_FILE} \
        -o ${DWIMAP_OUT} \
        -v 1
done

echo SUCCESS

