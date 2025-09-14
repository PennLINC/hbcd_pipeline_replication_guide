#!/usr/bin/env python
# coding: utf-8


from nilearn.plotting import plot_stat_map
from nilearn.image import load_img
import matplotlib.pyplot as plt
from matplotlib.colorbar import ColorbarBase
import os
import imageio
import numpy as np
import glob

# CHANGE THIS!!
results_dir = "/Users/mcieslak/projects/hbcd/hbcd_pipeline_replication_guide/rep1/modelarray"
# this directory should contain directories:
#     - dsistudiotensor_fa_lm0 dsistudiotensor_md_lm0 mapmri_rtop_lm0


# Constants that don't depend on the scalar name
model_id = "lm0"
map_names = [
    "gestational_age.statistic",
    "raw_neighbor_corr.statistic",
    "ManufacturerGE.statistic",
    "ManufacturerPhilips.statistic",
    "model.adj.r.squared",
]
bg_img = load_img("../templates/nlin6_crop.nii.gz")

# z coordinates for making cut planes
cut_coords = [51, 31, 21, 3, -12, -36][::-1]


def show_map(scalar_name):
    # Create temporary directory for individual maps
    temp_dir = f"temp_{scalar_name}"
    os.makedirs(temp_dir, exist_ok=True)

    # Generate individual maps
    images = []
    for map_name in map_names:
        stat_map_file = f"{results_dir}/{scalar_name}_{model_id}/results_lm_{map_name}.nii.gz"
        kw = {"vmax": 1} if "adj.r" in map_name else {"vmax": 30}
        plot_stat_map(
            stat_map_file,
            bg_img=bg_img,
            display_mode="z",
            cut_coords=cut_coords,
            colorbar=False,
            title=None,
            threshold=3 if map_name.endswith("statistic") else None,
            draw_cross=False,
            black_bg=True,
            resampling_interpolation="nearest",
            annotate=False,
            symmetric_cbar=True,
            output_file=f"{temp_dir}/{map_name}.png",
            **kw
        )
        images.append(imageio.imread(f"{temp_dir}/{map_name}.png"))

    # Do a single slice plot, save as svg
    plot_stat_map(
        stat_map_file,
        bg_img=bg_img,
        display_mode="z",
        cut_coords=1,
        colorbar=True,
        title=None,
        threshold=None,
        draw_cross=False,
        black_bg=True,
        resampling_interpolation="nearest",
        output_file=f"has_adj.r_colorbar.svg",
        vmax=1,
    )
    plot_stat_map(
        stat_map_file,
        bg_img=bg_img,
        display_mode="z",
        cut_coords=1,
        colorbar=True,
        title=None,
        threshold=0.02,
        draw_cross=False,
        black_bg=True,
        resampling_interpolation="nearest",
        output_file=f"has_statistic_colorbar.svg",
        vmax=30,
    )

    # Stack images vertically
    combined_image = np.vstack(images)

    # Save combined image
    imageio.imwrite(f"{scalar_name}_combined.png", combined_image)

    # Clean up temporary files
    for file in glob.glob(f"{temp_dir}/*.png"):
        os.remove(file)
    os.rmdir(temp_dir)


show_map("dsistudiotensor_fa")
show_map("dsistudiotensor_md")
show_map("mapmri_rtop")

