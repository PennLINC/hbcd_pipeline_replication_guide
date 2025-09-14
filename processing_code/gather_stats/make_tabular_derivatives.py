#!/usr/bin/env python
from pathlib import Path
import pandas as pd

der_root = Path("/cbica/projects/hbcd_dev/tier2_local/midb-hbcd-prerelease-bids")
recons = ["DIPYDKI", "DSIStudio", "TORTOISE_model-MAPMRI", 
          "TORTOISE_model-tensor"]


def create_group_tsv(recon_name, tsv_suffix="scalarstats", tsv_extension="tsv"):
    recon_dir = der_root / f"qsirecon-{recon_name}"
    sep = "\t" if tsv_extension=="tsv" else ","
    scalar_dfs = [pd.read_csv(fname, sep=sep) for fname in recon_dir.rglob(f"*{tsv_suffix}.{tsv_extension}")]
    group_df = pd.concat(scalar_dfs, axis=0, ignore_index=True)
    group_df.to_parquet(f"group_{recon_name}_{tsv_suffix}.parquet")


for  recon_name in recons:
    print(recon_name)
    create_group_tsv(recon_name)

create_group_tsv("DSIStudio", "tdistats")
create_group_tsv("DSIStudio", "bundlestats", "csv")

