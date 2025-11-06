#!/usr/bin/env python
from pathlib import Path
import argparse
import os
import re
import subprocess
from concurrent.futures import ProcessPoolExecutor, as_completed
from typing import List, Tuple, Optional

try:
    from tqdm import tqdm
except Exception:  # pragma: no cover
    tqdm = None  # type: ignore


SUB_RE = re.compile(r"^(sub-[A-Za-z0-9]+)")
SES_RE = re.compile(r"(ses-[A-Za-z0-9]+)")
COHORT_RE = re.compile(r"MNIInfant\+(\d+)")


def parse_ids_from_filename(filename: str) -> Tuple[str, str]:
    base = os.path.basename(filename)
    sub_match = SUB_RE.search(base)
    ses_match = SES_RE.search(base)
    if not sub_match or not ses_match:
        raise ValueError(f"Could not parse sub/ses from filename: {filename}")
    return sub_match.group(1), ses_match.group(1)


def find_warp_file(qsiprep_dir: Path) -> Path:
    candidates = list(qsiprep_dir.rglob("*from-ACPC_to-MNI*xfm.h5"))
    if not candidates:
        raise FileNotFoundError(f"No warp file found under {qsiprep_dir}")
    # Pick the first in sorted order for determinism
    return sorted(candidates)[0]


def cohort_from_warp(warp_path: Path) -> str:
    m = COHORT_RE.search(warp_path.name)
    if not m:
        raise ValueError(f"Could not extract MNIInfant cohort from {warp_path}")
    return m.group(1)


def build_output_name(fname: Path, prefix: str) -> str:
    base = fname.name.replace("ACPC", "MNI152NLin6Asym")
    return f"{prefix}_{base}"


def run_warp(
    simg: Path,
    refvol: Path,
    input_fname: Path,
    qsiprep_dir: Path,
    xform2_template_dir: Path,
    output_dir: Path,
    prefix: str,
    bind_home: Optional[Path] = None,
) -> Tuple[Path, Optional[str]]:
    try:
        warp_file = find_warp_file(qsiprep_dir)
        cohort = cohort_from_warp(warp_file)
        xform2 = xform2_template_dir / f"from-MNIInfant+{cohort}_to-MNI152NLin6Asym_xfm.h5"

        output_dir.mkdir(parents=True, exist_ok=True)
        out_name = build_output_name(input_fname, prefix)
        out_path = output_dir / out_name

        cmd: List[str] = [
            "singularity",
            "exec",
            "--containall",
        ]
        if bind_home is not None:
            cmd += ["-B", str(bind_home)]
        cmd += [
            str(simg),
            "antsApplyTransforms",
            "-d", "3",
            "-r", str(refvol),
            "--interpolation", "nearestneighbor",
            "-i", str(input_fname),
            "-t", str(xform2),
            "-t", str(warp_file),
            "-o", str(out_path),
            "-v", "1",
        ]

        subprocess.run(cmd, check=True)
        return out_path, None
    except Exception as e:  # pragma: no cover
        return input_fname, str(e)


def discover_inputs(base_dir: Path) -> Tuple[List[Path], List[Path]]:
    nodrbuddi = list((base_dir / "nodrbuddi").rglob("*desc-preproc_dir-APPA*.nii"))
    drbuddi = list((base_dir / "drbuddi").rglob("*desc-preproc_dir-APPA*.nii"))
    return sorted(nodrbuddi), sorted(drbuddi)


def build_qsiprep_dir_nodrbuddi(root: Path, sub_id: str, ses_id: str) -> Path:
    return root / sub_id / ses_id


def build_qsiprep_dir_drbuddi(root_template: str, sub_id: str, ses_id: str) -> Path:
    # root_template may include {sub} and {ses}
    path_str = root_template.format(sub=sub_id, ses=ses_id)
    return Path(path_str)


def main() -> None:
    home = Path(os.environ.get("HOME", str(Path.home())))

    parser = argparse.ArgumentParser()
    parser.add_argument("--simg", type=Path, default=home / "images" / "qsirecon-1.0.1RC0.sif", help="Path to Singularity image")
    parser.add_argument("--refvol", type=Path, default=home / "pipeline_paper" / "volumetric" / "templates" / "nlin6_1.7mm.nii.gz", help="Reference volume")
    parser.add_argument("--input-base", type=Path, default=home / "rep2" / "separate_fa", help="Base directory containing nodrbuddi/ and drbuddi/")
    parser.add_argument("--output-dir", type=Path, help="Output directory; defaults to <input-base>/appa_diffs_mni")
    parser.add_argument("--qsiprep-nodrbuddi-root", type=Path, default=home / "pipeline_paper" / "penn-run" / "derivatives" / "no-drbuddi-1.0.0" / "qsiprep", help="Root of qsiprep (nodrbuddi)")
    parser.add_argument(
        "--qsiprep-drbuddi-root-template",
        type=str,
        default="/cbica/projects/hbcd_dev/tier2_local/midb-hbcd-prerelease-bids/derivatives/{ses}/qsiprep/{sub}/{ses}",
        help="Template for qsiprep (drbuddi) path with {sub} and {ses}",
    )
    parser.add_argument("--workers", type=int, default=os.cpu_count() or 1, help="Number of parallel workers")
    args = parser.parse_args()

    output_dir = args.output_dir if args.output_dir is not None else (args.input_base / "appa_diffs_mni")
    output_dir.mkdir(parents=True, exist_ok=True)

    nodrbuddi_inputs, drbuddi_inputs = discover_inputs(args.input_base)

    tasks = []
    for fname in nodrbuddi_inputs:
        sub_id, ses_id = parse_ids_from_filename(fname.name)
        qsiprep_dir = build_qsiprep_dir_nodrbuddi(args.qsiprep_nodrbuddi_root, sub_id, ses_id)
        tasks.append((args.simg, args.refvol, fname, qsiprep_dir, args.refvol.parent, output_dir, "nodrbuddi", home))

    for fname in drbuddi_inputs:
        sub_id, ses_id = parse_ids_from_filename(fname.name)
        qsiprep_dir = build_qsiprep_dir_drbuddi(args.qsiprep_drbuddi_root_template, sub_id, ses_id)
        tasks.append((args.simg, args.refvol, fname, qsiprep_dir, args.refvol.parent, output_dir, "drbuddi", home))

    progress = tqdm(total=len(tasks), desc="Warping diffs") if tqdm is not None else None
    errors = 0
    with ProcessPoolExecutor(max_workers=args.workers) as ex:
        futures = [
            ex.submit(
                run_warp,
                simg,
                refvol,
                fname,
                qsiprep_dir,
                xform2_template_dir,
                output_dir,
                prefix,
                home,
            )
            for (simg, refvol, fname, qsiprep_dir, xform2_template_dir, output_dir, prefix, home) in tasks
        ]

        for fut in as_completed(futures):
            _, err = fut.result()
            if err:
                errors += 1
            if progress is not None:
                progress.update(1)

    if progress is not None:
        progress.close()

    if errors:
        print(f"Completed with {errors} errors")


if __name__ == "__main__":
    main()


