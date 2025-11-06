#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=10
#SBATCH --mem=18G
#SBATCH --time=4:00:00
#SBATCH --output=hbcd-ma-lm-%A_%a.log
#SBATCH --array=0-5

# CHANGE THIS!!
REPRO_DIR="${HOME}/rep2"
dicemax=0.06
if [ ${SLURM_ARRAY_TASK_ID} -ge 3 ]; then
    dicemax=1.0
fi

SIMG="${HOME}"/images/confixel-0.1.5.sif
MA_INPUT_DIR="${REPRO_DIR}/volumetric/modelarray"
EXE_SCRIPT="${PWD}"/model_scalar.R
GROUP_MASK="${HOME}"/pipeline_paper/volumetric/templates/nlin6_1.7mm_mask.nii.gz

# fail whenever something is fishy, use -x to get verbose logfiles
set -e -u -x

# There are 31 scalars: only do 3 for the paper
# The scalar index is the array id mod 3
SCALAR_INDEX=$((SLURM_ARRAY_TASK_ID % 3))
SCALARS=(dsistudiotensor_fa dsistudiotensor_md mapmri_rtop)
SCALAR_NAME="${SCALARS[$SCALAR_INDEX]}"
h5_origin=${MA_INPUT_DIR}/${SCALAR_NAME}_dice-max${dicemax}.h5
csv_origin=${MA_INPUT_DIR}/${SCALAR_NAME}_dice-max${dicemax}.csv

# Use $TMP as the workdir
WORKDIR=${TMP}/"job-${SLURM_JOB_ID}_${SCALAR_NAME}_dice-max${dicemax}"
mkdir -p "${WORKDIR}"
cd ${WORKDIR}

# Copy to the local disk so we're not memmapping over a network
cp ${h5_origin} ./data.h5

# Run modelarray - the results go right back into data.h5
singularity exec -B ${HOME} -B ${PWD} \
    ${SIMG} \
    Rscript \
        ${EXE_SCRIPT} \
	${SCALAR_NAME} \
	${PWD}/data.h5 \
	${csv_origin} \
	${SLURM_JOB_CPUS_PER_NODE}

# Convert the stats back to nifti
output_dir=${PWD}/${SCALAR_NAME}_dice-max${dicemax}_lm0
singularity exec -B ${HOME} -B ${PWD}  \
    ${SIMG} \
    volumestats_write \
        --group-mask-file ${GROUP_MASK} \
	--cohort-file ${csv_origin} \
	--relative-root / \
	--analysis-name results_lm \
	--input-hdf5 ${PWD}/data.h5 \
	--output-dir ${output_dir} \
	--output-ext .nii.gz 

# Copy the nifti results back home
cp -rv ${output_dir} ${MA_INPUT_DIR}/


echo SUCCESS

