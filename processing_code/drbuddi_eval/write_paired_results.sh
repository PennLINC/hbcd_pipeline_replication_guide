#!/bin/bash
REPRO_DIR="${HOME}/projects/hbcd/hbcd_pipeline_replication_guide/rep2"
GROUP_MASK="${HOME}/projects/hbcd/hbcd_pipeline_replication_guide/templates/nlin6_1.7mm_mask.nii.gz"
SCALAR_NAME="appa_fa_diff"
for session in ses-V02 ses-V03; do
  MA_DIR="${REPRO_DIR}/modelarray"
  H5_PATH="${MA_DIR}/${SCALAR_NAME}_drbuddi_eval_${session}.h5"
  CSV_PATH="${MA_DIR}/${SCALAR_NAME}_drbuddi_eval_${session}.csv"
  OUT_DIR="${MA_DIR}/${SCALAR_NAME}_appa_exploration_${session}"

  mkdir -p "${OUT_DIR}"

  volumestats_write \
    --group-mask-file ${GROUP_MASK} \
    --cohort-file ${CSV_PATH} \
    --relative-root / \
    --analysis-name appa_exploration \
    --input-hdf5 ${H5_PATH} \
    --output-dir ${OUT_DIR} \
    --output-ext .nii.gz


done

echo "SUCCESS: Wrote volumetric results to ${OUT_DIR}"