#!/usr/bin/env python
from pathlib import Path
import nilearn.image as nim
import nibabel as nib
import pandas as pd
import argparse
import numpy as np
import subprocess
import os
import re
from typing import Optional
from tqdm import tqdm
import shutil
from concurrent.futures import ProcessPoolExecutor


home = Path.home()
# Default CSV path, mirroring calc_means.py behavior
DEFAULT_SUB_SES_CSV = home / "tier2_local" / "code" / "hbcd_complete_qc_demographics.csv"


def _extract_run_number(filename: str) -> int:
    match = re.search(r"_run-(\d+)_", filename)
    if match:
        return int(match.group(1))
    return 10**9


def _find_with_optional_run(dwi_dir: Path, sub_id: str, ses_id: str, middle: str, ext: str) -> Path:
    base_path = dwi_dir / f"{sub_id}_{ses_id}_{middle}{ext}"

    candidates = []
    # Prefer files that include run- information, regardless of other entities
    candidates.extend(dwi_dir.glob(f"{sub_id}_{ses_id}_*run-*_*{middle}{ext}"))
    # Then any file with additional entities between ses and middle
    candidates.extend(dwi_dir.glob(f"{sub_id}_{ses_id}_*{middle}{ext}"))
    # Finally, consider the exact base path if it exists
    if base_path.exists():
        candidates.append(base_path)

    # Deduplicate while preserving order
    seen = set()
    unique_candidates = []
    for p in candidates:
        if p not in seen:
            unique_candidates.append(p)
            seen.add(p)

    if unique_candidates:
        candidates_sorted = sorted(unique_candidates, key=lambda p: (_extract_run_number(p.name), p.name))
        return candidates_sorted[0]

    # Return the canonical non-run path for downstream .exists() checks
    return base_path


def files_from_qsiprep(qsiprep_dir, sub_id, ses_id):
    """
    Get the primary qsiprep DWI, gradients, and confounds, allowing flexible run-* patterns.
    """
    dwi_dir = qsiprep_dir / sub_id / ses_id / "dwi"
    files = {}
    files["dwi"] = _find_with_optional_run(dwi_dir, sub_id, ses_id, "space-ACPC_desc-preproc_dwi", ".nii.gz")
    files["bmtxt"] = _find_with_optional_run(dwi_dir, sub_id, ses_id, "space-ACPC_desc-preproc_dwi", ".bmtxt")
    files["bvals"] = _find_with_optional_run(dwi_dir, sub_id, ses_id, "space-ACPC_desc-preproc_dwi", ".bval")
    files["bvecs"] = _find_with_optional_run(dwi_dir, sub_id, ses_id, "space-ACPC_desc-preproc_dwi", ".bvec")
    files["confounds"] = _find_confounds_tsv(dwi_dir, sub_id, ses_id, files["dwi"])
    return files


def _find_confounds_tsv(dwi_dir: Path, sub_id: str, ses_id: str, dwi_path: Path) -> Path:
    desired_run = _extract_run_number(dwi_path.name)

    # Try exact run match first if one was detected from the DWI
    if desired_run != 10**9:
        exact = list(dwi_dir.glob(f"{sub_id}_{ses_id}_*run-{desired_run}_*desc-confounds_timeseries.tsv"))
        if exact:
            return sorted(exact, key=lambda p: p.name)[0]

    # Otherwise, try any confounds file for this subject/session
    candidates = list(dwi_dir.glob(f"{sub_id}_{ses_id}_*desc-confounds_timeseries.tsv"))
    if candidates:
        # Prefer those with a run number, choosing the lowest run index
        candidates_sorted = sorted(candidates, key=lambda p: (_extract_run_number(p.name), p.name))
        return candidates_sorted[0]

    # Fallback: canonical non-run name (may not exist; caller may .exists())
    return dwi_dir / f"{sub_id}_{ses_id}_desc-confounds_timeseries.tsv"


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


def generate_bmtxt_with_apptainer(bvals_path: Path, bvecs_path: Path, output_bmtxt_path: Optional[Path] = None) -> str:
    """
    Generate a TORTOISE .bmtxt by invoking FSLBVecsToTORTOISEBmatrix inside the
    qsirecon Apptainer image located at $HOME/images/qsirecon-1.0.0.sif.

    Parameters
    ----------
    bvals_path : Path
        Path to the input .bvals file.
    bvecs_path : Path
        Path to the input .bvecs file.
    output_bmtxt_path : Path
        Destination path to write the generated .bmtxt (stdout) to.
    """
    home_dir = os.environ.get("HOME", str(Path.home()))
    sif_image = Path(home_dir) / "images" / "qsirecon-1.0.0.sif"

    cmd = [
        "apptainer",
        "exec",
        "-B",
        str(bvals_path.parent),
        "-B",
        str(bvecs_path.parent),
        "-B",
        str(Path.cwd()),
        str(sif_image),
        "FSLBVecsToTORTOISEBmatrix",
        str(bvals_path),
        str(bvecs_path),
    ]

    # Run the command; the tool writes the .bmtxt next to the .bval file
    result = subprocess.run(cmd, check=True, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"Failed to generate .bmtxt with error: {result.stderr}")

    # Determine the produced bmtxt path (same stem, replacing .bval -> .bmtxt)
    bvals_str = str(bvals_path)
    if bvals_str.endswith('.bval'):
        produced_path = Path(bvals_str[:-5] + '.bmtxt')
    else:
        produced_path = bvals_path.with_suffix('.bmtxt')

    if not produced_path.exists():
        raise FileNotFoundError(f"Expected bmtxt not found after generation: {produced_path}")

    # Copy to requested destination if provided
    if output_bmtxt_path is not None:
        output_bmtxt_path.parent.mkdir(parents=True, exist_ok=True)
        if produced_path.resolve() != output_bmtxt_path.resolve():
            shutil.copyfile(produced_path, output_bmtxt_path)
        return output_bmtxt_path.read_text()

    return produced_path.read_text()



def split_peds(input_dir, output_dir, sub_id, ses_id):
    """Takes output from qsiprep where AP and PA have been merged
    and splits them into AP and PA niftis. """
    files = files_from_qsiprep(input_dir, sub_id, ses_id)
    new_ap_nifti_path = output_dir / f"{sub_id}_{ses_id}_space-ACPC_desc-preproc_dir-AP_dwi.nii"
    new_pa_nifti_path = output_dir / f"{sub_id}_{ses_id}_space-ACPC_desc-preproc_dir-PA_dwi.nii"

    if new_ap_nifti_path.exists() and new_pa_nifti_path.exists():
        print(f"Skipping {sub_id}_{ses_id} because it already exists")
        return

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

    # Split the bmtxt file (generate if missing or empty)
    if files["bmtxt"].exists() and files["bmtxt"].stat().st_size > 0:
        bm = np.loadtxt(files["bmtxt"])
    else:
        combined_bmtxt_path = output_dir / f"{sub_id}_{ses_id}_space-ACPC_desc-preproc_dwi.bmtxt"
        _ = generate_bmtxt_with_apptainer(files["bvals"], files["bvecs"], combined_bmtxt_path)
        bm = np.loadtxt(combined_bmtxt_path)

    ap_bm = bm[ap_rows]
    pa_bm = bm[pa_rows]
    np.savetxt(output_dir / f"{sub_id}_{ses_id}_space-ACPC_desc-preproc_dir-AP_dwi.bmtxt", ap_bm, fmt='%.6g', delimiter=' ')
    np.savetxt(output_dir / f"{sub_id}_{ses_id}_space-ACPC_desc-preproc_dir-PA_dwi.bmtxt", pa_bm, fmt='%.6g', delimiter=' ')


def read_subject_sessions_from_csv(csv_path: Path):
    """
    Read subject and session IDs from a CSV file, mirroring calc_means.py behavior.
    Expects columns: 'subject_id', 'session_id'.
    Returns a sorted list of unique (subject_id, session_id) tuples.
    """
    df = pd.read_csv(csv_path)
    pairs = {(row["subject_id"], row["session_id"]) for _, row in df.iterrows()}
    return sorted(pairs)


def _preflight_missing_files(input_dir: Path, subject_sessions):
    """
    For each (sub_id, ses_id), check that required inputs exist:
    - space-ACPC_desc-preproc_dwi.nii.gz
    - corresponding confounds .tsv
    - .bval and .bvec (bmtxt can be generated from these)
    Returns:
      valid_tasks: list of tasks (input_dir, output_dir, sub_id, ses_id) ready to run
      missing_info: list of (sub_id, ses_id, missing_list)
    """
    missing_info = []
    ready = []
    for sub_id, ses_id in subject_sessions:
        files = files_from_qsiprep(input_dir, sub_id, ses_id)
        missing = []
        if not files["dwi"].exists():
            missing.append(f"DWI:{files['dwi'].name}")
        if not files["confounds"].exists():
            missing.append(f"confounds:{files['confounds'].name}")
        if not files["bvals"].exists():
            missing.append(f"bvals:{files['bvals'].name}")
        if not files["bvecs"].exists():
            missing.append(f"bvecs:{files['bvecs'].name}")
        if missing:
            missing_info.append((sub_id, ses_id, missing))
        else:
            ready.append((sub_id, ses_id))
    return ready, missing_info


def _split_wrapper(task):
    input_dir, output_dir, sub_id, ses_id = task
    try:
        split_peds(input_dir, output_dir, sub_id, ses_id)
        return (sub_id, ses_id, None)
    except Exception as e:
        return (sub_id, ses_id, str(e))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input_dir", type=Path, help="Path to the input directory")
    parser.add_argument("output_dir", type=Path, help="Path to the output directory")
    parser.add_argument("--workers", type=int, default=8, help="Number of parallel workers")
    parser.add_argument("--csv", type=Path, default=DEFAULT_SUB_SES_CSV, help="CSV with subject_id and session_id (defaults to the calc_means.py CSV)")
    args = parser.parse_args()

    # Read subjects/sessions from CSV (mirrors calc_means.py source)
    subjects_sessions = read_subject_sessions_from_csv(args.csv)

    # Preflight: report any missing files and only run on valid pairs
    ready_pairs, missing_info = _preflight_missing_files(args.input_dir, subjects_sessions)
    if missing_info:
        print("Preflight check: Missing required inputs for the following subject/session pairs:")
        for sub_id, ses_id, missing in missing_info:
            print(f"  {sub_id}_{ses_id}: missing {', '.join(missing)}")
        print(f"Preflight summary: {len(ready_pairs)} ready, {len(missing_info)} with missing inputs.")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    if not ready_pairs:
        print("No valid subject/session pairs with all required inputs. Exiting.")
        return

    tasks = [(args.input_dir, args.output_dir, sub_id, ses_id) for sub_id, ses_id in ready_pairs]
    with ProcessPoolExecutor(max_workers=args.workers) as executor:
        for sub_id, ses_id, err in tqdm(executor.map(_split_wrapper, tasks), total=len(tasks), desc="Splitting PEDs"):
            if err:
                print(f"Error splitting {sub_id}_{ses_id}: {err}")
if __name__ == "__main__":
    main()

