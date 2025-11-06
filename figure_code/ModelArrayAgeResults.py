#!/usr/bin/env python
# coding: utf-8


from nilearn.plotting import plot_stat_map
from nilearn.image import load_img, crop_img
import matplotlib.pyplot as plt
import os
import imageio
import numpy as np

plt.rcParams['figure.dpi'] = 800  # Set to desired DPI (e.g., 300 for high-quality)
# CHANGE THIS!!
results_dir = "/Users/mcieslak/projects/hbcd/hbcd_pipeline_replication_guide/rep2/modelarray"
# this directory should contain directories:
#     - dsistudiotensor_fa_lm0 dsistudiotensor_md_lm0 mapmri_rtop_lm0


# Constants that don't depend on the scalar name
model_id = "dice-max0.06_lm0"
map_names = [
    "scans_gestational_age.statistic",
    "raw_neighbor_corr.statistic",
    "ManufacturerGE.statistic",
    "ManufacturerPhilips.statistic",
    "model.adj.r.squared",
]
bg_img = crop_img(load_img("../templates/nlin6_crop.nii.gz"))

# z coordinates for making cut planes
cut_coords = [41, 21, 3, -12, -36][::-1]


def limit_contiguous_white_columns(image, max_white_run):
    """Return a copy of `image` with any contiguous runs of all-white columns
    limited to at most `max_white_run` columns.

    Works for 2D (H, W) and 3D (H, W, C) arrays. White is detected as 255 for
    integer images and 1.0 for float images, across all channels if present.
    """
    if max_white_run is None or max_white_run < 0:
        return image

    # Determine white level depending on dtype
    if np.issubdtype(image.dtype, np.floating):
        white_val = 1.0
        tol = 1e-6
    else:
        white_val = 255
        tol = 0

    # Compute per-pixel white mask
    white_mask = image >= (white_val - tol)
    if image.ndim == 3:
        # Require all channels to be white
        white_mask = white_mask.all(axis=2)

    # Collapse along rows to get per-column white mask
    col_white = white_mask.all(axis=0)

    width = col_white.shape[0]
    keep_indices = []
    i = 0
    while i < width:
        if not col_white[i]:
            keep_indices.append(i)
            i += 1
            continue
        # Find end of the current white run [i, j)
        j = i
        while j < width and col_white[j]:
            j += 1
        run_len = j - i
        keep_len = min(run_len, max_white_run)
        keep_indices.extend(range(i, i + keep_len))
        i = j

    keep_indices = np.asarray(keep_indices, dtype=int)
    if image.ndim == 2:
        return image[:, keep_indices]
    return image[:, keep_indices, :]


def show_map(scalar_name):
    # Create temporary directory for individual maps
    temp_dir = f"temp_{scalar_name}"
    os.makedirs(temp_dir, exist_ok=True)

    # Generate individual maps by saving per-slice PNGs and concatenating rows
    images = []
    for map_name in map_names:
        stat_map_file = f"{results_dir}/{scalar_name}_{model_id}/results_lm_{map_name}.nii.gz"
        kw = {"vmax": 1} if "adj.r" in map_name else {"vmax": 40}
        slice_pngs = []
        # Save one PNG per slice to minimize whitespace, then concatenate horizontally
        for z in cut_coords:
            slice_file = f"{temp_dir}/{map_name}_z{z}.png"
            plot_stat_map(
                stat_map_file,
                bg_img=bg_img,
                display_mode="z",
                cut_coords=[z],
                colorbar=False,
                title=None,
                threshold=3 if map_name.endswith("statistic") else 0.0001,
                draw_cross=False,
                black_bg=False,
                resampling_interpolation="nearest",
                annotate=False,
                symmetric_cbar=True,
                output_file=slice_file,
                **kw
            )
            slice_pngs.append(imageio.imread(slice_file))
            os.remove(slice_file)

        # Remove whitespace around the slices
        row_image = np.hstack(slice_pngs)
        # Limit contiguous all-white columns to at most N columns
        row_image = limit_contiguous_white_columns(row_image, max_white_run=10)
        # Save the row image to a file
        imageio.imwrite(f"{temp_dir}/{map_name}_row.png", row_image)
        images.append(row_image)

    # Do single slice plots for colorbars, save as SVG
    plot_stat_map(
        stat_map_file,
        bg_img=bg_img,
        display_mode="z",
        cut_coords=1,
        colorbar=True,
        title=None,
        threshold=None,
        draw_cross=False,
        black_bg=False,
        resampling_interpolation="nearest",
        output_file="has_adj.r_colorbar.svg",
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
        black_bg=False,
        resampling_interpolation="nearest",
        output_file="has_statistic_colorbar.svg",
        vmax=40,
    )

    # # Stack images vertically
    # combined_image = np.vstack(images)

    # # Save combined image
    # imageio.imwrite(f"{scalar_name}_combined.png", combined_image)

    # Clean up temporary files
    #for file in glob.glob(f"{temp_dir}/*.png"):
    #    os.remove(file)
    #os.rmdir(temp_dir)


show_map("dsistudiotensor_fa")
show_map("dsistudiotensor_md")
show_map("mapmri_rtop")
# show_map("mapmri_rtap")

