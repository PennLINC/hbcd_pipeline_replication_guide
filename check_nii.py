#!/usr/bin/env python3
import argparse
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path
import sys

import nibabel as nib


def iter_nii_gz_files(root_dir: Path):
    yield from root_dir.rglob("*.nii.gz")


def check_file(path_str: str):
    try:
        img = nib.load(path_str)
        # Trigger data access to catch additional I/O/decompression issues
        _ = img.get_fdata()
        return None  # success
    except Exception as exc:
        return (path_str, str(exc))


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Recursively check .nii.gz files in parallel and print names of those that fail to load with nibabel (including get_fdata())."
        )
    )
    parser.add_argument(
        "root",
        nargs="?",
        default=".",
        help="Root directory to search (default: current directory)",
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=10,
        help="Number of parallel workers (default: 10)",
    )
    parser.add_argument(
        "--show-error",
        action="store_true",
        help="Also print the error message for each failing file",
    )
    args = parser.parse_args()

    root_dir = Path(args.root).resolve()
    files = [str(p) for p in iter_nii_gz_files(root_dir)]

    if not files:
        return

    with ProcessPoolExecutor(max_workers=args.workers) as executor:
        futures = {executor.submit(check_file, p): p for p in files}
        for fut in as_completed(futures):
            result = fut.result()
            if result is not None:
                path_str, err = result
                if args.show_error:
                    print(f"{path_str}\t{err}", file=sys.stdout)
                else:
                    print(path_str, file=sys.stdout)


if __name__ == "__main__":
    main()


