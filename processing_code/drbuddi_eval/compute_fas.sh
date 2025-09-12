#!/bin/bash -l 
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=2-00:00:00
#SBATCH --output=calc_fas.log

REPRO_DIR="${HOME}/rep1"
base=${REPRO_DIR}/separate_fa
APT_EXEC="apptainer exec -B $base $HOME/images/qsirecon-1.0.0.sif"
cd $base

ncomps=0

for fname in $(find ${base}/*drbuddi/ -name '*desc-preproc_dir-*_dwi.nii')
do
    echo "Running image #${ncomps}"
    ${APT_EXEC} EstimateTensor --i ${fname} -b 1250
    dt_fname=${fname/.nii/_L1_DT.nii}
    ${APT_EXEC} ComputeFAMap ${dt_fname} 1
    let ncomps++
done

ncomps=0
for pa_fa_file in $(find ${base}/*drbuddi/ -name '*desc-preproc_dir-PA_dwi_L1_DT_FA.nii')
do
    echo "Running image #${ncomps}"
    ap_fa_file=${pa_fa_file/dir-PA/dir-AP}
    appa_fa_diff_file=${pa_fa_file/dir-PA/dir-APPAdiff}
    
    3dcalc -a ${ap_fa_file} -b ${pa_fa_file} -expr 'abs(a-b)' -prefix ${appa_fa_diff_file}

    let ncomps++
done

