#!/bin/bash -l

# CHANGE THIS!!
REPRO_DIR="${HOME}/rep1"

cd ${REPRO_DIR}/separate_fa/appa_diffs_mni

for method in drbuddi nodrbuddi
do
for metric in FA AD
do
    for sesid in ses-V02 ses-V03
    do
        3dmerge -gmean \
            -1fmask means/nlin6_1.7mm_mask.nii.gz \
            -prefix means/${method}_${sesid}_masked_${metric}.nii \
            ${method}_sub-*_${sesid}*APPAdiff*${metric}.nii
    done
done
done