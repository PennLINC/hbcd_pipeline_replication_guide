#!/bin/bash -l
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=2-00:00:00
#SBATCH --output=warp_fas.log

SIMG="${HOME}"/images/qsirecon-1.0.1RC0.sif
REFVOL=${HOME}/pipeline_paper/volumetric/templates/nlin6_1.7mm.nii.gz
base=/cbica/projects/hbcd_dev/pipeline_paper/separate_fa
OUTPUT_DIR=${HOME}/pipeline_paper/separate_fas/appa_diffs_mni
mkdir -p ${OUTPUT_DIR}


# First warp the no-drbuddi APPA diffs
nodrbuddi_diffs=$(find ${base}/nodrbuddi/ -name '*desc-preproc_dir-APPA*.nii')

for fname in ${nodrbuddi_diffs}
do

    subid=$(basename ${fname} | sed 's/^\(sub-[A-Za-z0-9]*\).*$/\1/')
    sesid=$(basename ${fname} | sed 's/^.*\(ses-[A-Za-z0-9]*\).*$/\1/')
    QSIPREP_DIR=${HOME}/pipeline_paper/penn-run/derivatives/no-drbuddi/qsiprep/${subid}/${sesid}

    WARP_FILE=$(find "${QSIPREP_DIR}" -name '*from-ACPC_to-MNI*xfm.h5')
    COHORT=$(echo "${WARP_FILE}" | sed 's/.*MNIInfant+\([0-9][0-9]*\)_.*/\1/')
    XFORM2=${HOME}/pipeline_paper/volumetric/templates/from-MNIInfant+${COHORT}_to-MNI152NLin6Asym_xfm.h5

    fname_space=$(basename ${fname} | sed 's/ACPC/MNI152NLin6Asym/')

    singularity exec \
        --containall \
        -B ${HOME} \
        ${SIMG} \
        antsApplyTransforms \
        -d 3 \
        -r ${REFVOL} \
        --interpolation nearestneighbor \
        -i ${fname} \
        -t ${XFORM2} \
        -t ${WARP_FILE} \
        -o ${OUTPUT_DIR}/nodrbuddi_${fname_space} \
        -v 1


done



# Then do the drbuddi APPA diffs
drbuddi_diffs=$(find ${base}/drbuddi/ -name '*desc-preproc_dir-APPA*.nii')
for fname in ${drbuddi_diffs}
do

    subid=$(basename ${fname} | sed 's/^\(sub-[A-Za-z0-9]*\).*$/\1/')
    sesid=$(basename ${fname} | sed 's/^.*\(ses-[A-Za-z0-9]*\).*$/\1/')
    QSIPREP_DIR=/cbica/projects/hbcd_dev/tier2_local/midb-hbcd-prerelease-bids/derivatives/${sesid}/qsiprep/${subid}/${sesid}

    WARP_FILE=$(find "${QSIPREP_DIR}" -name '*from-ACPC_to-MNI*xfm.h5')
    COHORT=$(echo "${WARP_FILE}" | sed 's/.*MNIInfant+\([0-9][0-9]*\)_.*/\1/')
    XFORM2=${HOME}/pipeline_paper/volumetric/templates/from-MNIInfant+${COHORT}_to-MNI152NLin6Asym_xfm.h5

    fname_space=$(basename ${fname} | sed 's/ACPC/MNI152NLin6Asym/')

    if [ ! -f ${WARP_FILE} ]; then
        PROBLEM: No ${WARP_FILE}
    fi

    singularity exec \
        --containall \
        -B ${HOME} \
        ${SIMG} \
        antsApplyTransforms \
        -d 3 \
        -r ${REFVOL} \
        --interpolation nearestneighbor \
        -i ${fname} \
        -t ${XFORM2} \
        -t ${WARP_FILE} \
        -o ${OUTPUT_DIR}/drbuddi_${fname_space} \
        -v 1


done

