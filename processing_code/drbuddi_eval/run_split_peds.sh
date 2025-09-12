#!/bin/bash -l
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=2-00:00:00
#SBATCH --output=split_peds.log

# Split the drbuddi outputs
conda activate hbcd

for sesid in ses-V02 ses-V03
do

# DRBUDDI
python split_peds.py \
    "$HOME"/tier2_local/midb-hbcd-prerelease-bids/derivatives/${sesid}/qsiprep \
    "$HOME"/pipeline_paper/separate_fa/drbuddi/${sesid} \
    "$HOME"/pipeline_paper/separate_fa/code/drbuddi_${sesid}.txt

# No DRBUDDI
python split_peds.py \
    "$HOME"/pipeline_paper/penn-run/derivatives/no-drbuddi/qsiprep \
    "$HOME"/pipeline_paper/separate_fa/nodrbuddi/${sesid} \
    "$HOME"/pipeline_paper/separate_fa/code/nodrbuddi_${sesid}.txt
done

