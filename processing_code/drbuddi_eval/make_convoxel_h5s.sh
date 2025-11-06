#!/bin/bash

REPRO_DIR="${HOME}/rep2"

SIF=${HOME}/images/confixel-0.1.5.sif
GROUP_MASK=${HOME}/pipeline_paper/volumetric/templates/nlin6_1.7mm_mask.nii.gz

cd ${REPRO_DIR}/volumetric/modelarray

set +x
for ses in ses-V02 ses-V03; do
    CSV="appa_fa_diff_drbuddi_eval_${ses}.csv"

  singularity exec \
    --containall \
    -B ${HOME} \
    ${SIF} \
    convoxel \
    --group-mask-file ${GROUP_MASK} \
    --cohort-file $PWD/${CSV} \
    --relative-root / \
    --output-hdf5 $PWD/${CSV/.csv/.h5}
done


