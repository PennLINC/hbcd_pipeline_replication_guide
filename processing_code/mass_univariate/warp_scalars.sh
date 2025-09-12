#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=16G
#SBATCH --time=24:00:00
#SBATCH --output=hbcd-scalarwarp-%A.log

# CHANGE THIS!!
REPRO_DIR="${HOME}/rep1"

SIMG="${HOME}"/images/qsirecon-1.0.1RC0.sif
RESULTS_CSV="${HOME}/tier2_local/code/hbcd_1.0.0RC0_scanner_qc.csv"

[ -z "${JOB_ID}" ] && JOB_ID=TEST

if [[ ! -z "${SLURM_JOB_ID}" ]]; then
    echo SLURM detected
    JOB_ID="${SLURM_JOB_ID}"
fi

# fail whenever something is fishy, use -x to get verbose logfiles
set -e -u -x

# Get total number of subjects from CSV (excluding header)
TOTAL_SUBJECTS=$(tail -n +2 ${RESULTS_CSV} | wc -l)
echo "Processing ${TOTAL_SUBJECTS} subjects"

# Loop through all subjects in the CSV file
for i in $(seq 1 ${TOTAL_SUBJECTS}); do
    echo "Processing subject ${i}/${TOTAL_SUBJECTS}"
    
    # Get the subject row (skip header with +2, then get the i-th row)
    subject_row=$(head -n $((${i} + 1)) ${RESULTS_CSV} | tail -n 1)
    subid=$(echo $subject_row | sed 's/^.*,\(sub-[A-Za-z0-9]*\).*$/\1/')
    sesid=$(echo $subject_row | sed 's/^.*,\(ses-[A-Za-z0-9]*\).*$/\1/')
    
    echo "Processing ${subid}/${sesid}"
    
    OUTPUT_DIR=${REPRO_DIR}/volumetric/data/${subid}/${sesid}
    mkdir -p ${OUTPUT_DIR}
    
    # Use $TMP as the workdir
    WORKDIR=${TMP}/"job-${JOB_ID}_${subid}_${sesid}"
    mkdir -p "${WORKDIR}"
    cd ${WORKDIR}
    
    # Get dir holding session qsiprep outputs
    QSIPREP_DIR=/cbica/projects/hbcd_dev/tier2_local/midb-hbcd-prerelease-bids/derivatives/${sesid}/qsiprep/${subid}/${sesid}
    
    # Check if the qsiprep directory exists before proceeding
    if [[ ! -d "${QSIPREP_DIR}" ]]; then
        echo "Warning: QSIPREP_DIR does not exist for ${subid}/${sesid}: ${QSIPREP_DIR}"
        continue
    fi
    
    WARP_FILE=$(find "${QSIPREP_DIR}" -name '*from-ACPC_to-MNI*xfm.h5')
    BRAIN_MASK=$(find "${QSIPREP_DIR}" -name '*_space-ACPC_desc-brain_mask.nii.gz')
    
    # Check if required files exist
    if [[ -z "${WARP_FILE}" ]] || [[ -z "${BRAIN_MASK}" ]]; then
        echo "Warning: Missing required files for ${subid}/${sesid}"
        echo "  WARP_FILE: ${WARP_FILE}"
        echo "  BRAIN_MASK: ${BRAIN_MASK}"
        continue
    fi
    
    COHORT=$(echo "${WARP_FILE}" | sed 's/.*MNIInfant+\([0-9][0-9]*\)_.*/\1/')
    XFORM2=${HOME}/pipeline_paper/volumetric/templates/from-MNIInfant+${COHORT}_to-MNI152NLin6Asym_xfm.h5
    REFVOL=${HOME}/pipeline_paper/volumetric/templates/nlin6_1.7mm.nii.gz
    
    # Check if template files exist
    if [[ ! -f "${XFORM2}" ]] || [[ ! -f "${REFVOL}" ]]; then
        echo "Warning: Missing template files for ${subid}/${sesid}"
        echo "  XFORM2: ${XFORM2}"
        echo "  REFVOL: ${REFVOL}"
        continue
    fi
    
    MASK_OUT=${OUTPUT_DIR}/$(basename ${BRAIN_MASK} | sed 's/ACPC/MNI152NLin6Asym/')
    
    # Check if brain mask output already exists
    if [[ -f "${MASK_OUT}" ]]; then
        echo "Brain mask already exists, skipping: ${MASK_OUT}"
    else
        echo "Processing brain mask: ${MASK_OUT}"
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
    fi
    
    TO_TRANSFORM=$(find ${HOME}/tier2_local/midb-hbcd-prerelease-bids/qsirecon-* -name "${subid}_${sesid}*dwimap.nii.gz")
    
    for dwimap in ${TO_TRANSFORM}
    do
        dwimap_space=$(basename ${dwimap} | sed 's/ACPC/MNI152NLin6Asym/')
        recon_spec=$(echo ${dwimap} | sed 's/.*\(qsirecon-[a-zA-Z][-_a-zA-Z0-9]*\)\/.*/\1/')
        out_dir=${OUTPUT_DIR}/${recon_spec}
        mkdir -p ${out_dir}
        DWIMAP_OUT=${out_dir}/${dwimap_space}
        
        # Check if DWI map output already exists
        if [[ -f "${DWIMAP_OUT}" ]]; then
            echo "DWI map already exists, skipping: ${DWIMAP_OUT}"
        else
            echo "Processing DWI map: ${DWIMAP_OUT}"
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
        fi
    done
    
    echo "Completed processing ${subid}/${sesid}"
    
    # Clean up workdir for this subject
    rm -rf "${WORKDIR}"
    
done

echo "SUCCESS: All subjects processed"

