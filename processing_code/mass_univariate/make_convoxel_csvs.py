from glob import glob
import pandas as pd
from pathlib import Path

home = Path.home()
metadata_csv_path = home / "tier2_local" / "code" / "hbcd_1.0.0RC0_scanner_qc.csv"
metadata_df = pd.read_csv(metadata_csv_path)
metadata_columns = [
    "DeviceSerialNumber", "ManufacturersModelName", "SoftwareVersions", "Manufacturer",
    "CNR0_mean", "CNR1_mean", "CNR2_mean", "CNR3_mean", "CNR4_mean", "mean_fd", "max_fd",
    "max_rotation", "max_translation", "max_rel_rotation", "max_rel_translation",
    "t1_neighbor_corr", "t1_masked_neighbor_corr", "t1_dwi_contrast", "t1_num_bad_slices",
    "raw_neighbor_corr", "raw_masked_neighbor_corr", "raw_dwi_contrast", "raw_num_bad_slices"
]
metadata_df = metadata_df[["subject_id", "session_id", "site", "age", "gestational_age", "head_size"] + metadata_columns]

# The path to where the resampled scalars are
mni_scalars_dir = home / "pipeline_paper" / "volumetric" / "data"
mask_pattern = "{subid}/{sesid}/{subid}_{sesid}_space-MNI152NLin6Asym_desc-brain_mask.nii.gz"
dwimap_pattern = "{subid}/{sesid}/qsirecon-{recon_suffix}/{subid}_{sesid}_space-MNI152NLin6Asym_model-{model}_param-{param}_dwimap.nii.gz"
modelarray_dir = home / "pipeline_paper" / "volumetric" / "modelarray"


def create_modelarray_data(scalar_name, recon_suffix, model, param):
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

        row["scalar_name"] = scalar_name
        row["source_mask_file"] = str(mask_file)
        row["source_file"] = str(scalar_file)
        has_data.append(row)
    print(f"found {len(has_data)} dwimaps")
    if not has_data:
        raise Exception(f"no data found for {scalar_name}")
    all_scalars = pd.DataFrame(has_data)
    all_scalars.to_csv(str(modelarray_dir / scalar_name) + ".csv", index=False)

create_modelarray_data("dsistudiotensor_fa", "DSIStudio", "tensor", "fa")
create_modelarray_data("dsistudiotensor_md", "DSIStudio", "tensor", "md")
create_modelarray_data("mapmri_rtop", "TORTOISE_model-MAPMRI", "mapmri", "rtop")
