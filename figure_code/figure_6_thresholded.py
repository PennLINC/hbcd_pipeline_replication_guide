#!/usr/bin/env python
import os
from nilearn.plotting import plot_img
import nilearn.image as nim
import numpy as np
from pathlib import Path
import imageio.v2 as imageio
from scipy.ndimage import binary_erosion
import matplotlib.pyplot as plt

# Set DPI for high-resolution output
plt.rcParams['figure.dpi'] = 800  # Set to desired DPI (e.g., 300 for high-quality)



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


cmap = 'plasma'
vmax = 0.15
vmin = 0.02

# Replace with the path where you downloaded the error mean images
image_dir = Path.cwd() / "means"
mask_image = nim.load_img("../templates/nlin6_1.7mm_mask.nii.gz")
bg_image = nim.load_img("../templates/nlin6_crop.nii.gz")

# Erode mask_image by 1 voxel
mask_data = mask_image.get_fdata()
eroded_mask_data = binary_erosion(mask_data, iterations=1)
eroded_mask_image = nim.new_img_like(mask_image, eroded_mask_data.astype(np.float32))


slices = [
    {"title": "Cerebellar Peduncles", 
     "slice": {"y": -36.9}
    },
    {"title": "Internal Capsule and Genu",
     "slice": {"z": 6.7}
    },
]



def plot_image_row(images, slice_dict, title):
    """Use nilearn to plot a row of slices from each image.
    
    The images are in MNI NLin6 space and should be transparent at values less than 0.02
    The maximum value in the colormap should be 0.2
    The background image is the MNI Nlin6 T1w image and the foreground image is the FA image
    
    Each image in `images` gets one panel in the row.
    Once created, the row should be saved to an svg file with the name `title`.svg

    """
    # Determine slice orientation and coordinates from slice_dict
    if 'x' in slice_dict:
        cut_coords = [slice_dict['x']]
        display_mode = 'x'
    elif 'y' in slice_dict:
        cut_coords = [slice_dict['y']]
        display_mode = 'y'
    elif 'z' in slice_dict:
        cut_coords = [slice_dict['z']]
        display_mode = 'z'
    
    # Plot each image
    pngs = []
    for i, img in enumerate(images):

        # First plot the background (MNI template)
        temp_file = f"{title}_{i}.png"
        plot_img(
            img,
            bg_img=eroded_mask_image,
            display_mode=display_mode,
            cut_coords=cut_coords,
            colorbar=False,
            title=None,
            vmin=vmin,
            vmax=vmax,
            threshold=vmin,
            draw_cross=False,
            black_bg=False,
            resampling_interpolation="nearest",
            annotate=False,
            cmap=cmap,
            output_file=temp_file,
        )
        pngs.append(imageio.imread(temp_file))
        os.remove(temp_file)
    
    combined_sesv02 = np.vstack([pngs[0], pngs[2]])
    combined_sesv03 = np.vstack([pngs[1], pngs[3]])
    combined_image = np.hstack([combined_sesv03, combined_sesv02])
    imageio.imwrite(f"{title}.png", limit_contiguous_white_columns(combined_image, max_white_run=10))

    plot_img(
        img,
        bg_img=eroded_mask_image,
        display_mode="z",
        cut_coords=1,
        colorbar=True,
        title=None,
        draw_cross=False,
        black_bg=False,
        resampling_interpolation="nearest",
        output_file="drbuddi_colorbar.svg",
        vmin=vmin,
        vmax=vmax,
        cmap=cmap,
    )

dice_max = 1.0

image_files = [
    nim.math_img("img * mask_img", img=image_dir / f"drbuddi_ses-V02_masked_FA_dice-max{dice_max}.nii", mask_img=eroded_mask_image),
    nim.math_img("img * mask_img", img=image_dir / f"nodrbuddi_ses-V02_masked_FA_dice-max{dice_max}.nii", mask_img=eroded_mask_image),
    nim.math_img("img * mask_img", img=image_dir / f"drbuddi_ses-V03_masked_FA_dice-max{dice_max}.nii", mask_img=eroded_mask_image),
    nim.math_img("img * mask_img", img=image_dir / f"nodrbuddi_ses-V03_masked_FA_dice-max{dice_max}.nii", mask_img=eroded_mask_image),
]

# Create plots for each slice configuration
for slice_config in slices:
    plot_image_row(image_files, slice_config["slice"], slice_config["title"] + f"_dice-max{dice_max}")







