#!/usr/bin/env python3

from pathlib import Path
import pandas as pd
import argparse
import subprocess

home = Path.home()

# CHANGE THIS!!
repro_dir=home / "rep1"

cwd_dir = Path.cwd()

metadata_csv_path = cwd_dir.parent / "gather_stats" / "hbcd_1.0.0RC0_scanner_qc.csv"
mni_scalars_dir = home / "pipeline_paper" / "volumetric" / "data"
mask_pattern = "{subid}/{sesid}/{subid}_{sesid}_space-MNI152NLin6Asym_desc-brain_mask.nii.gz"



def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output_file", type=Path, help="Path to the output directory")
    parser.add_argument("session_id", type=str, help="Session ID to apply the threshold to")
    parser.add_argument("--dice-threshold", type=float, help="Dice threshold to apply")
    args = parser.parse_args()

    dice_threshold = args.dice_threshold
    session_id = args.session_id
    output_file = args.output_file
    metadata_df = pd.read_csv(metadata_csv_path)
    metadata_df = metadata_df[metadata_df["session_id"] == session_id]
    print("original shape", metadata_df.shape)
    thresh_df = metadata_df[
        (metadata_df["t1_dice_distance"] <= dice_threshold)
        ]
    print("thresholded shape", thresh_df.shape)

    images_to_average = []
    for index, row in thresh_df.iterrows():
        subid = row["subject_id"]
        sesid = row["session_id"]
        mask_path = mni_scalars_dir / mask_pattern.format(subid=subid, sesid=sesid)
        images_to_average.append(mask_path)

    cmd = ["3dmerge", '-gmean', '-prefix', output_file, *[str(mask_path) for mask_path in images_to_average]]
    proc = subprocess.run(cmd, check=True)

if __name__ == "__main__":
    main()
