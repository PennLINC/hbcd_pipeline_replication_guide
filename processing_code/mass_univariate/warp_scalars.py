#!/usr/bin/env python3
import os
import re
import sys
import pandas as pd
import subprocess
from pathlib import Path
from concurrent.futures import ProcessPoolExecutor, as_completed
from typing import List, Tuple, Dict, Optional, Set


MAX_CPUS = 10
try:
    from tqdm.auto import tqdm
except Exception:
    tqdm = None


def getenv_path(name: str, default: str) -> str:
    value = os.environ.get(name, default)
    return os.path.expanduser(value)


HOME = str(Path.home())
REPRO_DIR = getenv_path("REPRO_DIR", f"{HOME}/rep2")
SIMG = getenv_path("SIMG", f"{HOME}/images/qsirecon-1.0.1RC0.sif")
RESULTS_CSV = getenv_path("RESULTS_CSV", f"{HOME}/tier2_local/code/hbcd_complete_qc_demographics.csv")

# Roots for inputs/refs (override with env vars if needed)
QSIPREP_DERIV_BASE = getenv_path(
    "QSIPREP_DERIV_BASE",
    "/cbica/projects/hbcd_dev/tier2_local/midb-hbcd-prerelease-bids/derivatives",
)
QSIRECON_BASE = getenv_path(
    "QSIRECON_BASE",
    f"{HOME}/tier2_local/midb-hbcd-prerelease-bids",
)
TEMPLATE_BASE = getenv_path(
    "TEMPLATE_BASE",
    f"{HOME}/pipeline_paper/volumetric/templates",
)
REFVOL = os.path.join(TEMPLATE_BASE, "nlin6_1.7mm.nii.gz")


class WarpTask:
    def __init__(
        self,
        input_path: str,
        output_path: str,
        xform2: str,
        warp_file: str,
        refvol: str,
        interpolation: str = "nearestneighbor",
    ) -> None:
        self.input_path = input_path
        self.output_path = output_path
        self.xform2 = xform2
        self.warp_file = warp_file
        self.refvol = refvol
        self.interpolation = interpolation

    def __repr__(self) -> str:
        return f"WarpTask({self.input_path} -> {self.output_path})"


def parse_subjects_from_csv(csv_path: str) -> List[Tuple[str, str]]:
    df = pd.read_csv(csv_path, dtype=str, usecols=["subject_id", "session_id"])
    df = df.dropna(subset=["subject_id", "session_id"])  # ensure present
    tuples = list(df[["subject_id", "session_id"]].itertuples(index=False, name=None))
    return [(sub.strip(), ses.strip()) for sub, ses in tuples]


def find_first(pattern: str, root: str) -> Optional[str]:
    base = Path(root)
    for p in base.rglob(pattern):
        return str(p)
    return None


def index_dwimaps(root: str, model_scalar_patterns: List[str]) -> Dict[str, List[str]]:
    index: Dict[str, List[str]] = {}
    root_path = Path(root)
    # Scan once: qsirecon-* trees for *dwimap.nii.gz
    for qsirecon_dir in root_path.glob("qsirecon-*"):
        for pattern in model_scalar_patterns:
            for p in qsirecon_dir.rglob(f"*space-ACPC*{pattern}*dwimap.nii.gz"):
                name = p.name  # e.g., sub-XXX_ses-YYY_...dwimap.nii.gz
                key_match = re.match(r"(sub-[A-Za-z0-9]+)_(ses-[A-Za-z0-9]+)", name)
                if not key_match:
                    continue
                key = f"{key_match.group(1)}_{key_match.group(2)}"
                index.setdefault(key, []).append(str(p))
    return index


def index_existing_outputs(repro_dir: str) -> Set[str]:
    existing: Set[str] = set()
    output_root = os.path.join(repro_dir, "volumetric", "data")
    if not os.path.isdir(output_root):
        return existing
    for dirpath, _dirnames, filenames in os.walk(output_root):
        for fn in filenames:
            # Collect all files; membership test is path-based and cheap
            existing.add(os.path.join(dirpath, fn))
    return existing


def get_recon_spec(path: str) -> str:
    m = re.search(r"(qsirecon-[A-Za-z][-_A-Za-z0-9]*)", path)
    return m.group(1) if m else "qsirecon-unknown"


def build_tasks(model_scalar_patterns: List[str]) -> List[WarpTask]:
    tasks: List[WarpTask] = []
    subjects = parse_subjects_from_csv(RESULTS_CSV)

    # Precompute dwimap index (slow listing happens once, outside multiprocessing)
    dwimap_index = index_dwimaps(QSIRECON_BASE, model_scalar_patterns)
    # Precompute existing outputs once
    existing_outputs = index_existing_outputs(REPRO_DIR)

    for (subid, sesid) in subjects:
        output_dir = os.path.join(REPRO_DIR, "volumetric", "data", subid, sesid)
        os.makedirs(output_dir, exist_ok=True)

        qsiprep_dir = os.path.join(
            QSIPREP_DERIV_BASE, sesid, "qsiprep", subid, sesid
        )
        if not os.path.isdir(qsiprep_dir):
            print(f"Warning: QSIPREP_DIR missing for {subid}/{sesid}: {qsiprep_dir}")
            continue

        warp_file = find_first("*from-ACPC_to-MNI*xfm.h5", qsiprep_dir)
        brain_mask = find_first("*_space-ACPC_desc-brain_mask.nii.gz", qsiprep_dir)

        if not warp_file or not brain_mask:
            print(
                f"Warning: Missing required files for {subid}/{sesid}\n"
                f"  WARP_FILE: {warp_file}\n  BRAIN_MASK: {brain_mask}"
            )
            continue

        cohort_match = re.search(r"MNIInfant\+(\d+)_", os.path.basename(warp_file))
        if not cohort_match:
            print(f"Warning: Could not parse cohort from warp file: {warp_file}")
            continue
        cohort = cohort_match.group(1)

        xform2 = os.path.join(
            TEMPLATE_BASE,
            f"from-MNIInfant+{cohort}_to-MNI152NLin6Asym_xfm.h5",
        )

        if not (os.path.isfile(xform2) and os.path.isfile(REFVOL)):
            print(
                f"Warning: Missing template files for {subid}/{sesid}\n"
                f"  XFORM2: {xform2}\n  REFVOL: {REFVOL}"
            )
            continue

        # Mask task
        mask_out = os.path.join(
            output_dir, os.path.basename(brain_mask).replace("ACPC", "MNI152NLin6Asym")
        )
        if mask_out not in existing_outputs:
            tasks.append(
                WarpTask(
                    input_path=brain_mask,
                    output_path=mask_out,
                    xform2=xform2,
                    warp_file=warp_file,
                    refvol=REFVOL,
                    interpolation="nearestneighbor",
                )
            )

        # DWI map tasks
        key = f"{subid}_{sesid}"
        for dwimap in dwimap_index.get(key, []):
            recon_spec = get_recon_spec(dwimap)
            out_dir = os.path.join(output_dir, recon_spec)
            os.makedirs(out_dir, exist_ok=True)

            dwimap_out = os.path.join(
                out_dir, os.path.basename(dwimap).replace("ACPC", "MNI152NLin6Asym")
            )
            if dwimap_out in existing_outputs:
                continue

            tasks.append(
                WarpTask(
                    input_path=dwimap,
                    output_path=dwimap_out,
                    xform2=xform2,
                    warp_file=warp_file,
                    refvol=REFVOL,
                    interpolation="nearestneighbor",
                )
            )

    return tasks


def run_task(task: WarpTask) -> Tuple[str, bool, Optional[str]]:

    cmd = [
        "singularity",
        "exec",
        "--containall",
        "-B",
        HOME,
        SIMG,
        "antsApplyTransforms",
        "-d",
        "3",
        "-r",
        task.refvol,
        "--interpolation",
        task.interpolation,
        "-i",
        task.input_path,
        "-t",
        task.xform2,
        "-t",
        task.warp_file,
        "-o",
        task.output_path,
        "-v",
        "1",
    ]

    try:
        subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return (task.output_path, True, None)
    except subprocess.CalledProcessError as e:
        return (task.output_path, False, e.stderr.decode(errors="ignore"))


def main() -> int:
    if not os.path.isfile(RESULTS_CSV):
        print(f"ERROR: RESULTS_CSV not found: {RESULTS_CSV}")
        #return 1
    if not os.path.isfile(SIMG):
        print(f"ERROR: Singularity image not found: {SIMG}")
        #return 1

    model_scalar_patterns = [
        "model-tensor_param-md",
        "model-tensor_param-fa",
        "model-mapmri_param-rtop",
    ]
    tasks = build_tasks(model_scalar_patterns)
    if not tasks:
        print("Nothing to do: all outputs already exist or inputs missing.")
        return 0

    max_workers_env = os.environ.get("MAX_WORKERS")
    max_workers = int(max_workers_env) if max_workers_env else MAX_CPUS or 1

    print(f"Executing {len(tasks)} transform tasks with {max_workers} workers")
    completed = 0
    failed = 0

    if tqdm is not None:
        pbar = tqdm(total=len(tasks), desc="Warping", unit="task")
    else:
        pbar = None

    with ProcessPoolExecutor(max_workers=max_workers) as ex:
        futures = [ex.submit(run_task, t) for t in tasks]
        for fut in as_completed(futures):
            out_path, ok, err = fut.result()
            if ok:
                completed += 1
            else:
                failed += 1
                sys.stderr.write(f"ERROR: Failed to write {out_path}\n")
                if err:
                    sys.stderr.write(err + "\n")
            if pbar is not None:
                pbar.update(1)

    if pbar is not None:
        pbar.close()

    print(
        f"Done. Succeeded: {completed}, Failed: {failed}, Total: {len(tasks)}"
    )
    return 0 if failed == 0 else 2


if __name__ == "__main__":
    sys.exit(main())


