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
*6.* Making the rest of the figures


In each of the scripts, there is a variable `REPRO_DIR` or `repro_dir` that needs to be set to the directory where you're running the replication from.

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

The tabular data used for creating figures comes from looping over Erik's results.
To gather the scanner metadata I ran `processing_code/gather_stats/compile_metadata.py`.

```bash
cd processing_code/gather_stats
python compile_metadata.py

```
This will create `hbcd1_1.0.0RC1_scanning_info.csv`,
which contains info for every single scan, including scans that won't be processed due to QC.
Do not be alarmed by the large number in the progress bar - it is for all the individual nifti files.

Next, we get the QC measures from Erik's QSIPrep run and merge them with the metadata.

```bash
python compile_group_qc_csv.py
```

Critically, this one produces the `hbcd1_1.0.0RC01scanner_qc.csv` which is what was used for the first round of coauthor comments.
I later realized that we can get the ages from the `scans.tsv` files.
To create the final demographics/inclusion file, run

```bash
python recheck_ages.py
```

to produce `hbcd_complete_qc_demographics.csv`.
I verified on the HBCD slack that these ages are ok to use.
This is now the definitive inclusion/demographics file to be used throughout.


Finally, gather all the bundle measures with 

```bash
python make_tabular_derivatives.py
```

Which will produce
 * `group_DIPYDKI_scalarstats.parquet`
 * `group_DSIStudio_scalarstats.parquet`
 * `group_TORTOISE_model-MAPMRI_scalarstats.parquet`
 * `group_TORTOISE_model-tensor_scalarstats.parquet`
 * `group_DSIStudio_tdistats.parquet`
 * `group_DSIStudio_bundlestats.parquet`

To make most of the figures, scp these parquet files and `hbcd_complete_qc_demographics.csv` into `figure_code/`.

### 1.Running TOPUP-only QSIPrep on CUBIC  
For DRBUDDI benchmarking we needed to rerun QSIPrep on the same data as Erik with just TOPUP instead of TOPUP+DRBUDDI.
The scripts for this are in `processing_code/processing`.

A critical gotcha here is that CBRAIN runs a file selection step based on some hidden files before running a job.
This is beyond what is typically done with BIDS filter files, so we needed to mimic it on CUBIC.
Note that the `topup_only_1.0.sh` script includes

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
It also critically uses `eddy_params1p0.json`, which does _NOT_ include extra FWHMs like we thought.
Future versions of HBCD will use extra FWHMs.
The TOPUP-only preprocessed data is in `/cbica/projects/hbcd_dev/pipeline_paper/penn-run/derivatives/no-drbuddi1.0.0/qsiprep`.

NOTE: This takes a lot of time and disk space and for these reasons it is not going to be re-run.

### 2. Computing AP and PA FA subtraction for DRBUDDI evaluation

Our SDC benchmark consisteted of subtracting the AP-only FA from the PA-only FA after preprocessing.
First, we have to split the AP and PA volumes from the concatenated output into individual scans
This happens in `processing_code/drbuddi_eval/run_split_peds.sh`.

```bash
cd processing_code/drbuddi_eval
bash run_split_peds.sh
```

This is parallelized and can run in ~40 minutes.
After running this you'll have TORTOISE-compatible unzipped float32 niftis for just the AP and PA scans in `${REPRO_DIR}/separate_fa/nodrbuddi` and `${REPRO_DIR}/separate_fa/drbuddi`.

Next we compute FA on the AP and PA scans again using TORTOISE.
The script for this is `processing_code/drbuddi_eval/compute_fas.sh`.
Continuing from the session above:

```bash 
python compute_fas.py
```

This is also parallelized and will finish pretty quickly.
The tensor is fit with `EstimateTensor` and the FA is computed with `ComputeFAMap`.
At the end of the script, the subtraction of the AP and PA FA images is calculated with `3dcalc` from AFNI.

With the subtractions calculated, we need to warp them to template space for comparison.
Instead of the MNIInfant templates, we will warp them all to NLin6.
The code for this is in `processing_code/drbuddi_eval/warp_fa_diffs.sh`

```bash
bash warp_fa_diffs.sh
```

Finally, with the diffs all warped to NLin6, we get the group averages and plot them.
The averages are created with 

```bash
bash calc_means.sh
```

This will produce a couple nifti files in `$REPRO_DIR/appa_diffs_mni/means` that you need to copy into `figure_code`.
Then you can plot the slices used in Figure 5 with `python figure_5.py`.


### 3. Running QSIPrep without MP-PCA and Gibbs unringing

Just like we ran QSIPrep without DRBUDDI, 
we also ran a version _with_ DRBUDDI but _without_ MP-PCA and Gibbs unringing.
This script is in `processing_code/processing`

```bash
cd processing_code/processing
sbatch nodenoise_1.0.sh
```

This will run the no denoising version.
Note that this will take ~8 hours longer apiece than the topup-only run.
Once the entire batch is finished you can collect the qc values with 

```bash
python processing_code/mppca_eval/compile_nodenoising_qc_csv.py
```

### 4. Preparing QSIRecon parametric microstructure maps for ModelArray 

We need to warp both the masks and the scalar maps into NLin6.
Both the masks and the scalar maps are warped in `processing_code/mass_univariate/warp_scalars.sh`.
Be sure to change `REPRO_DIR`.

```bash
cd processing_code/mass_univariate
bash warp_scalars.sh
```

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


### 5. Running ModelArray

Be sure to change `REPRO_DIR` in `run_modelarray.sh` and `repro_dir` in `model_scalar.R`.
Then you can run the linear models with

```bash
sbatch run_modelarray.sh
```

Which runs the actual model fitting in R (using `code/mass_univariate/model_scalar.R`),
and also reruns convoxel to get the model results back into nifti format.
In `$REPRO_DIR/volumetric/modelarray` you will find directories with niftis of all the results.
You need to download these directories to your computer so you can visualize the results.
The visualization is done with `figure_code/ModelArrayAgeResults.py`.
It has to be run from the `figure_code` directory,
and be sure to change the `results_dir` variable to point to where you downloaded the modelarray results.

```bash
cd ../figure_code
python ModelArrayAgeResults.py
```

I needed to do some work in Inkscape to get the colorbars and text to look good. 
The svg figures are created so I can import the colorbar directly in Inkscape.


### 6. Evaluating SynthSeg performance

I made a script that gathers the brain masks from all subjects over a certain dice score.
Because this uses the MNI152Nlin6Asym-space brain masks it has to be run after ModelArray.
To run this whole thing you can

```bash
cd processing_code/synthstrip_eval
bash group_coverage.sh
```

This will produce 
 * ses-V02_coverage.nii.gz
 * ses-V02_thr0.06_coverage.nii.gz
 * ses-V02_thr0.1_coverage.nii.gz
 * ses-V02_nothresh_coverage.nii.gz
 * ses-V02_thr0.12_coverage.nii.gz
 * ses-V03_coverage.nii.gz

Download these to `figure_code` and run

```bash
python si_figure_2.py
```

This will produce a ton of single pngs that I put together in Inkscape.


### 7. Making the rest of the figures

The rest of the figures need demographics files so we can filter out subjects/sessions that are missing age info.
Since this info is protected by a DUC, we do not include it in this repo.
We will figure out how to share this upon reasonable request when the DUC system is more clear.
Critical note: I downloaded some subjects/sessions after compiling the dataset for this paper :facepalm:.
There are therefore some additional subjects/sessions that we don't have the full work-up for and haven't verified the demographics.
To match the exact info used for the paper, use the `hbcd_complete_qc_demographics.csv` I created when I started working on this paper.


```bash
cd figure_code
Rscript plot_cnr_ndc.R
Rscript si_figure3.R
Rscript bundle_violins.R
```

You'll see all the rest of the figures/tables used in the paper!
