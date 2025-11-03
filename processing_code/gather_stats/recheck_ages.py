from pathlib import Path
import pandas as pd
from tqdm import tqdm


base = Path("/cbica/projects/hbcd_dev/tier2_local/midb-hbcd-prerelease-bids/assembly_bids")
qc_df = pd.read_csv("/cbica/projects/hbcd_dev/tier2_local/code/hbcd_1.0.0RC01scanner_qc.csv")


# Part 3: get the demographics info
new_demo_rows = []
for _, row in qc_df.iterrows():
    subid = row["subject_id"]
    sesid = row["session_id"]
    demo_file = base / subid / sesid / f"{subid}_{sesid}_scans.tsv" 
    demo_df = pd.read_csv(demo_file, sep="\t")
    row["scans_gestational_age"] = float(demo_df["gestational_age"].median())
    row["scans_age"] = float(demo_df["age"].median())
    new_demo_rows.append(row)

new_demo_df = pd.DataFrame(new_demo_rows)
new_demo_df.to_csv("/cbica/projects/hbcd_dev/tier2_local/code/hbcd_complete_qc_demographics.csv", index=False)

