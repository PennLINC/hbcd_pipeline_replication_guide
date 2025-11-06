import pandas as pd
from pathlib import Path
import subprocess

home = Path.home()

# CHANGE THIS!!
REPRO_DIR = home / "rep2"

dice_maxes = [0.06, 1.0]
complete_qc_df = pd.read_csv(home / "tier2_local" / "code" / "hbcd_complete_qc_demographics.csv")
diffs_dir = REPRO_DIR / "separate_fa" / "appa_diffs_mni"
means_dir = diffs_dir / "means"
means_dir.mkdir(parents=True, exist_ok=True)

mask_file = REPRO_DIR / "hbcd_pipeline_replication_guide" / "templates" / "nlin6_1.7mm_mask.nii.gz"

def run_3dmerge(diffs, out_file):
    """Use subprocess.run to run 3dmerge on the diffs files. """
    cmd = ["3dmerge", "-1fmask", str(mask_file), "-gmean", "-prefix", str(out_file), 
           *[str(diff) for diff in diffs]]
    subprocess.run(cmd, check=True)


def get_diff_file(subject_id: str, session_id: str, method: str):
    return diffs_dir / f"{method}_{subject_id}_{session_id}*APPAdiff*FA.nii"


diffs_n_df = []
for dice_max in dice_maxes:
    for method in ["drbuddi", "nodrbuddi"]:
        for sesid in ["ses-V02", "ses-V03"]:
            selected_sessions = complete_qc_df[
                (complete_qc_df["session_id"] == sesid) &
                (complete_qc_df["t1_dice_distance"] <= dice_max)
            ]
            print(f"found {len(selected_sessions)} sessions for {method} {sesid} with dice max {dice_max}")
            diffs_n_df.append({
                "method": method,
                "session_id": sesid,
                "dice_max": dice_max,
                "n_sessions": len(selected_sessions),
            })
            diff_files = [
                get_diff_file(selected_session["subject_id"], selected_session["session_id"], method)
                for _, selected_session in selected_sessions.iterrows()
            ]
            run_3dmerge(diff_files, means_dir / f"{method}_{sesid}_masked_FA_dice-max{dice_max}.nii")

counts_df = pd.DataFrame(diffs_n_df)
counts_df.to_csv(diffs_dir / "means" / "counts_df.csv", index=False)
