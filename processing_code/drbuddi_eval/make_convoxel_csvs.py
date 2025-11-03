#!/usr/bin/env python
from pathlib import Path
import pandas as pd
import re
import os


SUB_RE = re.compile(r"(sub-[A-Za-z0-9]+)")
SES_RE = re.compile(r"(ses-[A-Za-z0-9]+)")


def parse_ids_from_filename(filename: str):
    base = os.path.basename(filename)
    sub_match = SUB_RE.search(base)
    ses_match = SES_RE.search(base)
    if not sub_match or not ses_match:
        return None, None
    return sub_match.group(1), ses_match.group(1)


def main() -> None:
    home = Path.home()

    # Base repro directory and outputs
    repro_dir = home / "rep1"
    appa_diffs_dir = repro_dir / "separate_fa" / "appa_diffs_mni"
    modelarray_dir = repro_dir / "volumetric" / "modelarray"
    modelarray_dir.mkdir(parents=True, exist_ok=True)

    # Group mask in MNI space
    group_mask = home / "pipeline_paper" / "volumetric" / "templates" / "nlin6_1.7mm_mask.nii.gz"

    # Metadata table
    metadata_csv_path = home / "tier2_local" / "code" / "hbcd_1.0.0RC0_scanner_qc.csv"
    metadata_df = pd.read_csv(metadata_csv_path)
    metadata_columns = [
        "DeviceSerialNumber",
        "ManufacturersModelName",
        "SoftwareVersions",
        "Manufacturer",
        "CNR0_mean",
        "CNR1_mean",
        "CNR2_mean",
        "CNR3_mean",
        "CNR4_mean",
        "mean_fd",
        "max_fd",
        "max_rotation",
        "max_translation",
        "max_rel_rotation",
        "max_rel_translation",
        "t1_neighbor_corr",
        "t1_masked_neighbor_corr",
        "t1_dwi_contrast",
        "t1_num_bad_slices",
        "raw_neighbor_corr",
        "raw_masked_neighbor_corr",
        "raw_dwi_contrast",
        "raw_num_bad_slices",
    ]
    metadata_df = metadata_df[[
        "subject_id",
        "session_id",
        "site",
        "age",
        "gestational_age",
        "head_size",
    ] + metadata_columns]

    # Discover warped APPA diffs for both methods and only keep sessions with both
    nodrbuddi_files = sorted(appa_diffs_dir.glob("nodrbuddi_*desc-preproc_dir-APPA*.nii"))
    drbuddi_files = sorted(appa_diffs_dir.glob("drbuddi_*desc-preproc_dir-APPA*.nii"))

    # Map (sub, ses) -> { method: path }
    paired = {}
    for fpath in nodrbuddi_files:
        sub_id, ses_id = parse_ids_from_filename(fpath.name)
        if not sub_id:
            continue
        key = (sub_id, ses_id)
        rec = paired.get(key, {})
        rec["nodrbuddi"] = fpath
        paired[key] = rec
    for fpath in drbuddi_files:
        sub_id, ses_id = parse_ids_from_filename(fpath.name)
        if not sub_id:
            continue
        key = (sub_id, ses_id)
        rec = paired.get(key, {})
        rec["drbuddi"] = fpath
        paired[key] = rec

    # Keep only keys that have both methods
    rows = []
    for (sub_id, ses_id), methods in paired.items():
        if "nodrbuddi" not in methods or "drbuddi" not in methods:
            continue
        for method in ("nodrbuddi", "drbuddi"):
            fpath = methods[method]
            rows.append({
                "subject_id": sub_id,
                "session_id": ses_id,
                "method": method,
                "scalar_name": "appa_fa_diff",
                "source_mask_file": str(group_mask),
                "source_file": str(fpath),
            })

    if not rows:
        raise RuntimeError(f"No APPA diff files found in {appa_diffs_dir}")

    rows_df = pd.DataFrame(rows)

    # Split into ses-V02 and ses-V03 and save
    ses_v02_df = rows_df[rows_df["session_id"] == "ses-V02"]
    ses_v03_df = rows_df[rows_df["session_id"] == "ses-V03"]
    ses_v02_df.to_csv(modelarray_dir / "appa_fa_diff_drbuddi_eval_ses-V02.csv", index=False)
    ses_v03_df.to_csv(modelarray_dir / "appa_fa_diff_drbuddi_eval_ses-V03.csv", index=False)



if __name__ == "__main__":
    main()


