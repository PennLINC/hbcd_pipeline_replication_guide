<br>
<br>

### Abstract
The landmark ongoing HEALthy Brain and Cognitive Development (HBCD) will longitudinally chart brain development in a large sample (projected n=7,200) of infants through age 10 with multi-modal neuroimaging that includes an advanced diffusion MRI (dMRI) sequence. Here we detail advances in dMRI image processing developed for HBCD included in the widely used QSIPrep pipeline. Major changes to preprocessing include improvements in infant brain extraction, distortion correction, and normalization to infant-specific templates. Additionally, we describe a new software package – QSIRecon – that yields rich derived data including diverse maps of tissue microstructure as well as person-specific white matter bundles. Using dMRI data from the HBCD beta release (n=517 sessions across two time points), we observe critical improvements in data quality with preprocessing and see expected developmental patterns. Moving forward, the publicly-available data from HBCD will rapidly grow to become the largest study of brain development in infancy and early childhood using dMRI. QSIPrep and QSIRecon are openly available and can be applied to other infant and pediatric dMRI datasets.

### Project Lead
Matt Cieslak

### Faculty Lead
Theodore D. Satterthwaite

### Analytic Replicator
Steven L. Meisler

### Collaborators 
List to be collected

### Project Start Date
January 2023

### Current Project Status
Manuscript in preparation

### Datasets
HBCD beta release
https://www.nbdc-datahub.org/

### Github Repository
<https://github.com/PennLINC/hbcd_pipeline_replication_guide>
### Slack Channel:
#meisler_abcd_dmri

### Cubic Project Directory Overview
`/cbica/projects/hbcd_dev`

<br>
<br>

# CODE DOCUMENTATION  

All project analyses are described below along with the corresponding code on Github. The following outline describes the order of the analytic workflow:

*0.* Get the data processed by Erik
*1.* Running TOPUP-only QSIPrep on CUBIC
*2.* Computing AP and PA FA subtraction for DRBUDDI evaluation
*3.* Preparing QSIRecon parametric microstructure maps for ModelArray 
*4.* Running ModelArray
*5.* Evaluating SynthSeg performance


In each of the scripts, there is a variable `REPRO_DIR` that needs to be set to the directory where you're running the replication from.

<br>

### 0. Getting Erik's data
Erik ran QSIPrep and QSIRecon on CBRAIN. 
The results from these runs are ultimately uploaded to NBDC,
but we downloaded the files we needed for QC purposes from MSI s3.
These files are on CUBIC in `/cbica/projects/hbcd_dev/tier2_local/midb-hbcd-prerelease-bids`.

The QSIPrep outputs are in `derivaties/ses-V02` and `derivatives/ses-V03`.
They are in separate directories because the initial runs on CBRAIN wrote out to session-specific directories.

The QSIRecon outputs are located directly in the `midb-hbcd-prerelease-bids` directory.
They are named `qsirecon-DIPYDKI`, `qsirecon-DSIStudio`, `qsirecon-TORTOISE_model-tensor`,
`qsirecon-TORTOISE_model-MAPMRI`.

### 1.Running TOPUP-only QSIPrep on CUBIC  
For DRBUDDI benchmarking we needed to rerun QSIPrep on the same data as Erik with just TOPUP instead of TOPUP+DRBUDDI.
The scripts for this are in `processing_code/processing`.

A critical gotcha here is that CBRAIN runs a file selection step based on some hidden files before running a job.
This is beyond what is typically done with BIDS filter files, so we needed to mimic it on CUBIC.
Note that the `preproc_run.sh` script includes

```bash
# Copy only the files used by cbrain
python ${CODE_DIR}/cbrain_mimic.py \
    --dest-dir ${PWD}/BIDS \
    --participant-label ${subid} \
    --session-id ${sesid} \
    --midb-bids-dir ${MIDB_BIDS_DIR} \
    --cbrain-json ${cbrain_json}
```

which uses the hidden `.cbrain` directory to determine which files to include from the original BIDS.
Otherwise, the `preproc_run.sh` script is unremarkable.
The TOPUP-only preprocessed data is in `/cbica/projects/hbcd_dev/pipeline_paper/penn-run/derivatives/no-drbuddi/qsiprep`.

NOTE: This takes a lot of time and disk space and for these reasons it is not going to be re-run.

### 2. Computing AP and PA FA subtraction for DRBUDDI evaluation

Our SDC benchmark consisteted of subtracting the AP-only FA from the PA-only FA after preprocessing.
First, we have to split the AP and PA volumes from the concatenated output into individual scans
This happens in `processing_code/drbuddi_eval/run_split_peds.sh`.

```bash
cd processing_code/drbuddi_eval
sbatch run_split_peds.sh
```

After running this you'll have TORTOISE-compatible unzipped float32 niftis for just the AP and PA scans in `${REPRO_DIR}/separate_fa/nodrbuddi` and `${REPRO_DIR}/separate_fa/drbuddi`.

Next we compute FA on the AP and PA scans again using TORTOISE.
The script for this is `processing_code/drbuddi_eval/compute_fas.sh`.
Continuing from the session above:

```bash
sbatch compute_fas.sh
```

This will take awhile.
The tensor is fit with `EstimateTensor` and the FA is computed with `ComputeFAMap`.
At the end of the script, the subtraction of the AP and PA FA images is calculated with `3dcalc` from AFNI.

With the subtractions calculated, we need to warp them to template space for comparison.
Instead of the MNIInfant templates, we will warp them all to NLin6.
The code for this is in `processing_code/drbuddi_eval/warp_fa_diffs.sh`

```bash
sbatch warp_fa_diffs.sh
```

Finally, with the diffs all warped to NLin6, we get the group averages and plot them.
The averages are created with 

```bash
3dmerge -gmean \
    -1fmask means/nlin6_1.7mm_mask.nii.gz \
    -prefix means/${method}_${sesid}_masked_${metric}.nii \
    ${method}_sub-*_${sesid}*APPAdiff*${metric}.nii
```

The plotting happens in `figure_code/figure_5.py`.


### 3. Preparing QSIRecon parametric microstructure maps for ModelArray 

We need to warp both the masks and the scalar maps into NLin6.
Both the masks and the scalar maps are warped in `processing_code/mass_univariate/warp_scalars.sh`.
Be sure to change `REPRO_DIR`.

```bash
cd processing_code/mass_univariate
sbatch warp_scalars.sh
```
Let this run overnight. 
It also is not optimized.
After warping, you'll need to make some csvs with the warped files.
Edit `make_convoxel_csvs.py` so `repro_dir` points to your replication directory.

```bash
python make_convoxel_csvs.py
```

ModelArray requires "cohort" csvs and h5 files to run.
We created a csv file for each parametric scalar map (RTOP, FA, MD)
We used containerized `confixel` to create ModelArray h5 files in `processing_code/mass_univariate/make_convoxel_h5s.sh`.
This runs quickly, so we can do it interactively:

```bash
bash make_convoxel_h5s.sh
```

When I ran this I found that there was an empty nifti file for some reason.
To fix it I deleted the empty nifti file and resubmitted `warp_scalars.sh`.
Hopefully you won't run into this.


### 4. Running ModelArray

The actual ModelArray run was launched with 

```bash
sbatch run_modelarray.sh
```

Which runs the actual model fitting in R (using `code/mass_univariate/model_scalar.R`),
and also reruns convoxel to get the model results back into nifti format.
These nifti files were visualized with `figure_code/ModelArrayAgeResults.py`


### 5. Evaluating SynthSeg performance

I made a script that gathers the brain masks from all subjects over a certain dice score.
This script is `processing_code/synthstrip_eval/threshold_masks.py`.



Results from sensitivity analyses are visualized using this Rmd file: [/manuscript/results/supp_figures.Rmd](https://github.com/PennLINC/network_replication/blob/main/results/supp_figures.Rmd). The knitted Rmd file displaying supplementary figures can be downloaded at [/manuscript/results/supp_figures.html](https://github.com/PennLINC/network_replication/blob/main/results/supp_figures.html) and viewed on your browswer.
