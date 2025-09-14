#!/bin/bash

python threshold_masks.py ../ses-V02_thr0.06_coverage.nii.gz ses-V02 --dice-threshold 0.06
python threshold_masks.py
python threshold_masks.py ../ses-V02_thr0.1_coverage.nii.gz ses-V02 --dice-threshold 0.1
python threshold_masks.py ../ses-V02_thr0.12_coverage.nii.gz ses-V02 --dice-threshold 0.12