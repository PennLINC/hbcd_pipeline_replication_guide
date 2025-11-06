#!/usr/bin/env python

from pathlib import Path
from tqdm import tqdm
import pandas as pd

qsiprep_dir = Path("/cbica/projects/hbcd_dev/pipeline_paper/penn-run/derivatives/no-denoise-1.0.0/qsiprep")
qc_files = list(qsiprep_dir.rglob("*image_qc.tsv"))

qc_dfs = []
for fname in tqdm(qc_files):
    qc_dfs.append(pd.read_csv(fname, sep="\t"))
all_qc = pd.concat(qc_dfs, axis=0, ignore_index=True)
print(f"found {all_qc.shape[0]} qc files")
all_qc.to_csv("no_mppca_or_gibbs_qc.csv", index=False)

