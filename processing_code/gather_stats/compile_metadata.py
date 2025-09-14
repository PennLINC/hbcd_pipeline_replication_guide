from pathlib import Path
import pandas as pd
import json
from tqdm import tqdm


# Part 1: concatenate the jsons into tabular format
important_fields = [
    "PhaseEncodingDirection",
    "TotalReadoutTime",
    "EchoTime",
    "DeviceSerialNumber",
    "ManufacturersModelName",
    "SoftwareVersions",
    "Manufacturer",
]

base = Path("/cbica/projects/hbcd_dev/tier2_local/midb-hbcd-prerelease-bids/assembly_bids")
json_files = sorted(list(base.rglob("*dwi.json")))
metadatas = []
for jsonf in tqdm(json_files):
    details = {}
    parts = jsonf.name.split("_")
    details["subject_id"] = parts[0]
    details["session_id"] = parts[1]
    with jsonf.open("r") as jf:
        sidecar = json.load(jf)
    for field in important_fields:
        details[field] = sidecar.get(field)
    metadatas.append(details)

all_metadatas = pd.DataFrame(metadatas)

# Part 2: deal with multiple runs from some of the manufacturers
complete_rows = []
for subses_names, subses_df in all_metadatas.groupby(["subject_id", "session_id"]):
    subses_df["n_scans"] = subses_df.shape[0]
    if subses_df.shape[0] == 1:
        complete_rows.append(subses_df.iloc[0])
        continue

    # Copy the first row
    new_df = subses_df.iloc[0].copy()
    for field in important_fields:
        unique_vals = subses_df[field].unique()
        if len(unique_vals) > 1:
            new_df[field] = None
    complete_rows.append(new_df)
oneperses = pd.DataFrame(complete_rows)


# Part 3: get the demographics info
demographics = []
for sub_id in oneperses["subject_id"].unique():
    demo_file = base / sub_id / f"{sub_id}_sessions.tsv" 
    demo_df = pd.read_csv(demo_file, sep="\t")
    demo_df["subject_id"] = sub_id
    demographics.append(demo_df)
demo_df_all = pd.concat(demographics, axis=0, ignore_index=True)

all_info = oneperses.merge(demo_df_all)
all_info.to_csv("hbcd1_1.0.0RC1_scanning_info.csv", index=False)

