#!/bin/bash -l

# CHANGE THIS!!
REPRO_DIR="${HOME}/rep2"

cd ${REPRO_DIR}/separate_fa/appa_diffs_mni
mkdir means

for method in drbuddi nodrbuddi
do
    for sesid in ses-V02 ses-V03
    do
        3dmerge -gmean \
            -1fmask ${REPRO_DIR}/hbcd_pipeline_replication_guide/templates/nlin6_1.7mm_mask.nii.gz \
            -prefix means/${method}_${sesid}_masked_FA.nii \
            ${method}_sub-*_${sesid}*APPAdiff*FA.nii
    done
done
