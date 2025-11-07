#!/bin/bash -l
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=2-00:00:00
#SBATCH --output=split_peds.log

# Split the drbuddi outputs
conda activate hbcd

OUTDIR="${HOME}/rep2/separate_fa"

for sesid in ses-V02 ses-V03
do

# DRBUDDI
mkdir -p "${OUTDIR}/drbuddi/${sesid}"
python split_peds.py \
    "$HOME"/tier2_local/midb-hbcd-prerelease-bids/derivatives/${sesid}/qsiprep \
    "${OUTDIR}/drbuddi"
done

# No DRBUDDI
mkdir -p "${OUTDIR}/nodrbuddi/${sesid}"
python split_peds.py \
    "$HOME"/pipeline_paper/penn-run/derivatives/no-drbuddi-1.0.0/qsiprep \
    "${OUTDIR}/nodrbuddi"

