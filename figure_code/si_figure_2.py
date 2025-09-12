#!/usr/bin/env python
import os
from matplotlib import colors
import matplotlib.pyplot as plt
from nilearn.plotting import plot_stat_map
import nilearn.image as nim
import numpy as np
from pathlib import Path
import imageio.v2 as imageio
from scipy.ndimage import binary_erosion

vmax = 1.0
vmin = 0.0

image_dir = Path("/Users/mcieslak/projects/hbcd/coverage_maps/")
bg_image = nim.load_img(image_dir / "nlin6_crop.nii.gz")

slices = {
    "y": [-36.9],
    "z": [-13],
    "x": [0],
}

sesv02_coverage = nim.load_img(image_dir / "ses-V02_coverage.nii.gz")
sesv02_thr006_coverage = nim.load_img(image_dir / "ses-V02_thr0.06_coverage.nii.gz")
sesv02_thr01_coverage = nim.load_img(image_dir / "ses-V02_thr0.1_coverage.nii.gz")
sesv02_thr012_coverage = nim.load_img(image_dir / "ses-V02_thr0.12_coverage.nii.gz")
sesv03_coverage = nim.load_img(image_dir / "ses-V03_coverage.nii.gz")

# create a custom colormap that is like 'twilight' but with the white ends cut off
twilight_cmap = plt.get_cmap('twilight')

# Create a cropped version by removing bottom and top 10%
# This samples from 0.1 to 0.9 of the original colormap range
cmap = colors.LinearSegmentedColormap.from_list(
    'twilight_cropped', 
    twilight_cmap(np.linspace(0.15, 0.85, 256))
)


def plot_image_row(img, slice_dict, title):
    """Use nilearn to plot a row of slices from each image.
    
    Highlights areas where masking is inconsistent (values between 0.1 and 0.9)
    by setting other values to NaN for transparency.
    """
    # # Create masked image to highlight inconsistent areas
    # img_data = img.get_fdata()
    # masked_img_data = img_data.copy()
    
    # # Only show values between 0.1 and 0.9 (inconsistent masking areas)
    # inconsistent_mask = (img_data >= 0.1) & (img_data <= 0.9)
    # masked_img_data[~inconsistent_mask] = np.nan
    
    # # Create new image with masked data
    # masked_img = nim.new_img_like(img, masked_img_data)
    
    # Plot each image
    pngs = []
    for axis in ["x", "y", "z"]:
        for cut_coord in slice_dict[axis]:
            plot_stat_map(
                img,
                bg_img=bg_image,  # Show brain anatomy in background
                annotate=False,
                display_mode=axis,
                cut_coords=[cut_coord],
                colorbar=False,
                title=None,
                vmin=vmin,
                vmax=vmax,
                draw_cross=False,
                black_bg=False,
                resampling_interpolation="nearest",
                cmap=cmap,  # Cropped twilight colormap
                transparency=0.8,
                output_file=f"{title}_{axis}_{cut_coord}.png",
            )
            pngs.append(imageio.imread(f"{title}_{axis}_{cut_coord}.png"))
            # os.remove(f"{title}_{axis}_{cut_coord}.png")
    
    #combined_image = np.hstack(pngs)
    #imageio.imwrite(f"{title}_coverage.png", combined_image)

    plot_stat_map(
        img,
        bg_img=bg_image,
        display_mode="z",
        cut_coords=1,
        colorbar=True,
        title=None,
        draw_cross=False,
        black_bg=False,
        resampling_interpolation="nearest",
        output_file=f"{title}_colorbar.svg",
        vmin=vmin,
        vmax=vmax,
        cmap=cmap,
        transparency=0.8,
    )


#plot_image_row(sesv02_coverage, slices, "ses-V02")
#plot_image_row(sesv03_coverage, slices, "ses-V03")
#plot_image_row(sesv02_thr006_coverage, slices, "ses-V02_thr0.06")
plot_image_row(sesv02_thr01_coverage, slices, "ses-V02_thr0.1")
plot_image_row(sesv02_thr012_coverage, slices, "ses-V02_thr0.12")
