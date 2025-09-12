#!/usr/bin/env python
from pathlib import Path
import nilearn.image as nim
import nibabel as nib
import pandas as pd
import argparse
import numpy as np


def files_from_qsiprep(qsiprep_dir, sub_id, ses_id):
    """
    Get the files from qsiprep output.
    """
    files = {}
    files["dwi"] = qsiprep_dir / sub_id / ses_id / "dwi" / f"{sub_id}_{ses_id}_space-ACPC_desc-preproc_dwi.nii.gz"
    if not files["dwi"].exists():
        files["dwi"] = qsiprep_dir / sub_id / ses_id / "dwi" / f"{sub_id}_{ses_id}_run-1_space-ACPC_desc-preproc_dwi.nii.gz"
    files["bmtxt"] = qsiprep_dir / sub_id / ses_id / "dwi" / f"{sub_id}_{ses_id}_space-ACPC_desc-preproc_dwi.bmtxt"
    if not files["bmtxt"].exists():
        files["bmtxt"] = qsiprep_dir / sub_id / ses_id / "dwi" / f"{sub_id}_{ses_id}_run-1_space-ACPC_desc-preproc_dwi.bmtxt"
    files["confounds"] = qsiprep_dir / sub_id / ses_id / "dwi" / f"{sub_id}_{ses_id}_desc-confounds_timeseries.tsv"
    if not files["confounds"].exists():
        files["confounds"] = qsiprep_dir / sub_id / ses_id / "dwi" / f"{sub_id}_{ses_id}_run-1_desc-confounds_timeseries.tsv"

    return files


def force_float32(nifti):
    """
    Force the nifti to be float32.
    """
    if nifti.header.get_data_dtype() == np.float32:
        return nifti
    
    new_data = nifti.get_fdata().astype(np.float32)
    f32_nifti = nib.Nifti1Image(new_data, nifti.affine, nifti.header)
    f32_nifti.set_data_dtype(np.float32)
    return f32_nifti


def split_peds(input_dir, output_dir, sub_id, ses_id):
    """Takes output from qsiprep where AP and PA have been merged
    and splits them into AP and PA niftis. """
    files = files_from_qsiprep(input_dir, sub_id, ses_id)
    confounds_df = pd.read_csv(files["confounds"], sep="\t")
    
    # Get row numbers where original_file has "dir-AP" in its value as a numpy array
    ap_rows = confounds_df[confounds_df["original_file"].str.contains("dir-AP")].index.to_numpy()
    # Get row numbers where original_file has "dir-PA" in its value as a numpy array
    pa_rows = confounds_df[confounds_df["original_file"].str.contains("dir-PA")].index.to_numpy()

    # create new niftis from the subset, make sure they're float32
    new_ap_nifti = force_float32(nim.index_img(files["dwi"], ap_rows))
    new_pa_nifti = force_float32(nim.index_img(files["dwi"], pa_rows))

    # Non-gzipped for TORTOISE
    new_ap_nifti.to_filename(output_dir / f"{sub_id}_{ses_id}_space-ACPC_desc-preproc_dir-AP_dwi.nii")
    new_pa_nifti.to_filename(output_dir / f"{sub_id}_{ses_id}_space-ACPC_desc-preproc_dir-PA_dwi.nii")

    # Split the bmtxt file
    bm = np.loadtxt(files["bmtxt"])
    ap_bm = bm[ap_rows]
    pa_bm = bm[pa_rows]
    np.savetxt(output_dir / f"{sub_id}_{ses_id}_space-ACPC_desc-preproc_dir-AP_dwi.bmtxt", ap_bm, fmt='%.6g', delimiter=' ')
    np.savetxt(output_dir / f"{sub_id}_{ses_id}_space-ACPC_desc-preproc_dir-PA_dwi.bmtxt", pa_bm, fmt='%.6g', delimiter=' ')


def parse_subjects_sessions(subjects_sessions_file):
    """
    Parse the subjects_sessions_file and return a list of tuples of (sub_id, ses_id).
    """
    
    with open(subjects_sessions_file, "r") as f:
        return [line.strip().split("_")[:2] for line in f.readlines()]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input_dir", type=Path, help="Path to the input directory")
    parser.add_argument("output_dir", type=Path, help="Path to the output directory")
    parser.add_argument("subjects_sessions_file", type=Path, help="Path to the subjects_sessions_file")
    args = parser.parse_args()

    subjects_sessions = parse_subjects_sessions(args.subjects_sessions_file)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    for sub_id, ses_id in subjects_sessions:
        split_peds(args.input_dir, args.output_dir, sub_id, ses_id)

if __name__ == "__main__":
    main()

