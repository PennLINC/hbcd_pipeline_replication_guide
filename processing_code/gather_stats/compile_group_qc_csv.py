#!/usr/bin/env python

from pathlib import Path
from tqdm import tqdm
import pandas as pd

qsiprep_dir = Path("/cbica/projects/hbcd_dev/tier2_local/midb-hbcd-prerelease-bids/derivatives")
ses_dirs = [qsiprep_dir / "ses-V02" / "qsiprep", qsiprep_dir / "ses-V03" / "qsiprep"]
qc_files = []
for ses_dir in ses_dirs:
    qc_files += list(ses_dir.rglob("*image_qc.tsv"))

qc_dfs = []
for fname in tqdm(qc_files):
    qc_dfs.append(pd.read_csv(fname, sep="\t"))
all_qc = pd.concat(qc_dfs, axis=0, ignore_index=True)
print(f"found {all_qc.shape[0]} qc files")
metadata = pd.read_csv("hbcd1_1.0.0RC1_scanning_info.csv")
qc_complete = pd.merge(all_qc, metadata)
print(f"after merging with {metadata.shape[0]} metadata rows, {qc_complete.shape[0]} remain")
qc_complete.to_csv("hbcd1_1.0.0RC01scanner_qc.csv", index=False)

