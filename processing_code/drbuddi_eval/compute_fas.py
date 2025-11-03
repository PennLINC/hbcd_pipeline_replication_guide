#!/usr/bin/env python
from pathlib import Path
import argparse
import os
import subprocess
from concurrent.futures import ProcessPoolExecutor, as_completed
from typing import List, Tuple, Optional

try:
    from tqdm import tqdm
except Exception:  # pragma: no cover
    tqdm = None  # type: ignore


def discover_dwi_inputs(base: Path) -> List[Path]:
    return sorted(base.glob("*drbuddi/**/" + "*desc-preproc_dir-*_dwi.nii"))


def run_tensor_and_fa(
    simg: Path,
    bind_dir: Path,
    dwi_path: Path,
    bval: int,
) -> Tuple[Path, Optional[str]]:
    try:
        cmd_est = [
            "apptainer",
            "exec",
            "-B",
            str(bind_dir),
            str(simg),
            "EstimateTensor",
            "--i",
            str(dwi_path),
            "-b",
            str(bval),
        ]
        subprocess.run(cmd_est, check=True)

        dt_path = Path(str(dwi_path).replace(".nii", "_L1_DT.nii"))
        cmd_fa = [
            "apptainer",
            "exec",
            "-B",
            str(bind_dir),
            str(simg),
            "ComputeFAMap",
            str(dt_path),
            "1",
        ]
        subprocess.run(cmd_fa, check=True)
        return dwi_path, None
    except Exception as e:  # pragma: no cover
        return dwi_path, str(e)


def discover_pa_fa_files(base: Path) -> List[Path]:
    return sorted(base.glob("*drbuddi/**/" + "*desc-preproc_dir-PA_dwi_L1_DT_FA.nii"))


def run_appa_diff(pa_fa_path: Path) -> Tuple[Path, Optional[str]]:
    try:
        ap_fa_path = Path(str(pa_fa_path).replace("dir-PA", "dir-AP"))
        out_path = Path(str(pa_fa_path).replace("dir-PA", "dir-APPAdiff"))
        out_path.parent.mkdir(parents=True, exist_ok=True)

        cmd = [
            "3dcalc",
            "-a",
            str(ap_fa_path),
            "-b",
            str(pa_fa_path),
            "-expr",
            "abs(a-b)",
            "-prefix",
            str(out_path),
        ]
        subprocess.run(cmd, check=True)
        return out_path, None
    except Exception as e:  # pragma: no cover
        return pa_fa_path, str(e)


def main() -> None:
    home = Path(os.environ.get("HOME", str(Path.home())))

    parser = argparse.ArgumentParser()
    parser.add_argument("--base", type=Path, default=home / "rep1" / "separate_fa", help="Base directory containing *drbuddi subdirs")
    parser.add_argument("--simg", type=Path, default=home / "images" / "qsirecon-1.0.0.sif", help="Apptainer image path")
    parser.add_argument("--bval", type=int, default=1250, help="b-value for EstimateTensor")
    parser.add_argument("--workers", type=int, default=os.cpu_count() or 1, help="Number of parallel workers")
    args = parser.parse_args()

    base: Path = args.base
    base.mkdir(parents=True, exist_ok=True)

    # Phase 1: Tensor and FA computation in parallel
    dwi_inputs = discover_dwi_inputs(base)
    if tqdm is not None:
        pbar = tqdm(total=len(dwi_inputs), desc="Compute tensor/FA")
    else:
        pbar = None

    errors = 0
    with ProcessPoolExecutor(max_workers=args.workers) as ex:
        futures = [ex.submit(run_tensor_and_fa, args.simg, base, dwi_path, args.bval) for dwi_path in dwi_inputs]
        for fut in as_completed(futures):
            _, err = fut.result()
            if err:
                errors += 1
            if pbar is not None:
                pbar.update(1)
    if pbar is not None:
        pbar.close()

    # Phase 2: AP-PA FA difference in parallel
    pa_fa_files = discover_pa_fa_files(base)
    if tqdm is not None:
        pbar2 = tqdm(total=len(pa_fa_files), desc="Compute APPAdiff")
    else:
        pbar2 = None

    with ProcessPoolExecutor(max_workers=args.workers) as ex:
        futures = [ex.submit(run_appa_diff, pa_fa) for pa_fa in pa_fa_files]
        for fut in as_completed(futures):
            _, err = fut.result()
            if err:
                errors += 1
            if pbar2 is not None:
                pbar2.update(1)
    if pbar2 is not None:
        pbar2.close()

    if errors:
        print(f"Completed with {errors} errors")


if __name__ == "__main__":
    main()


