from glob import glob
import pandas as pd
from pathlib import Path

home = Path.home()

# CHANGE THIS!!
repro_dir = home / "rep2"

metadata_csv_path = home / "tier2_local" / "code" / "hbcd_complete_qc_demographics.csv"
metadata_df = pd.read_csv(metadata_csv_path)
metadata_columns = [
    "DeviceSerialNumber", "ManufacturersModelName", "SoftwareVersions", "Manufacturer",
    "CNR0_mean", "CNR1_mean", "CNR2_mean", "CNR3_mean", "CNR4_mean", "mean_fd", "max_fd",
    "max_rotation", "max_translation", "max_rel_rotation", "max_rel_translation",
    "t1_neighbor_corr", "t1_masked_neighbor_corr", "t1_dwi_contrast", "t1_num_bad_slices",
    "raw_neighbor_corr", "raw_masked_neighbor_corr", "raw_dwi_contrast", "raw_num_bad_slices",
    "t1_dice_distance",
]
metadata_df = metadata_df[
    ["subject_id", "session_id", "site", "scans_gestational_age", "scans_age",
    "age", "gestational_age", "head_size",
] + metadata_columns]

# The path to where the resampled scalars are
mni_scalars_dir = repro_dir / "volumetric" / "data"
mask_pattern = "{subid}/{sesid}/{subid}_{sesid}_space-MNI152NLin6Asym_desc-brain_mask.nii.gz"
dwimap_pattern = "{subid}/{sesid}/qsirecon-{recon_suffix}/{subid}_{sesid}_space-MNI152NLin6Asym_model-{model}_param-{param}_dwimap.nii.gz"
modelarray_dir = repro_dir / "volumetric" / "modelarray"
modelarray_dir.mkdir(parents=True, exist_ok=True)


def create_modelarray_data(scalar_name, recon_suffix, model, param, dice_max=1.0):
    has_data = []
    print(f"finding data for {scalar_name}")
    for _, row in metadata_df.iterrows():
        
        # check the mask file
        mask_file = mni_scalars_dir / mask_pattern.format(subid=row.subject_id, sesid=row.session_id)
        if not mask_file.exists():
            print(f"missing {mask_file}")
            continue

        # Check the scalar file
        scalar_file = mni_scalars_dir / dwimap_pattern.format(
	    subid=row.subject_id, 
	    sesid=row.session_id,
	    recon_suffix=recon_suffix,
	    model=model,
	    param=param)
        if not scalar_file.exists():
            print(f"missing {scalar_file}")
            continue

        # Check the dice score
        dice_score = float(row["t1_dice_distance"])
        if dice_score > dice_max:
            print(f"dice score {dice_score} is greater than {dice_max}")
            continue

        row["scalar_name"] = scalar_name
        row["source_mask_file"] = str(mask_file)
        row["source_file"] = str(scalar_file)
        has_data.append(row)
    print(f"found {len(has_data)} dwimaps")
    if not has_data:
        raise Exception(f"no data found for {scalar_name}")
    all_scalars = pd.DataFrame(has_data)
    all_scalars.to_csv(str(modelarray_dir / scalar_name) + f"_dice-max{dice_max}.csv", index=False)

for dice_max in [0.06, 1.0]:
    create_modelarray_data("dsistudiotensor_fa", "DSIStudio", "tensor", "fa", dice_max=dice_max)
    create_modelarray_data("dsistudiotensor_md", "DSIStudio", "tensor", "md", dice_max=dice_max)
    create_modelarray_data("mapmri_rtop", "TORTOISE_model-MAPMRI", "mapmri", "rtop", dice_max=dice_max)

