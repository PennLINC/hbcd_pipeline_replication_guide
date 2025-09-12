library(tidyverse)
library(broom)
library(arrow)
library(patchwork)
library(cowplot)
library(ggridges)
library(kableExtra)
library(flextable)
library(officer)

POINT_ALPHA=0.5

# Colorblind-friendly colors for scanner manufacturers
SCANNER_COLORS <- c(
    "Siemens" = "#0077BB",  # Blue
    "GE" = "#EE7733",       # Orange
    "Philips" = "#009988"   # Teal
)

plot_theme_double_col <- theme_bw(
  base_family="Helvetica",
  base_size=12) +
  theme(axis.text = element_text(size=10),
        axis.title = element_text(size=12),
        legend.text = element_text(size=10),
        legend.title = element_text(size=12),
        plot.title = element_text(size=14),
        plot.margin = margin(t=2, r=2, b=2, l=2, unit="pt"),
        legend.position="bottom")

plot_theme_single_col <- plot_theme_double_col +
  theme(
    axis.text = element_text(size=8),
    axis.title = element_text(size=9),
    legend.text = element_text(size=8),
    legend.title = element_text(size=9))


# Save a plot as an svg with a single column
save_svg_single_col <- function(filename, width=3.5, height=2.5){
  ggsave(filename,
       width=width,
       height=height,
       units="in",
       dpi=300)
}

save_svg_double_col <- function(filename, width=7, height=3.5){
  ggsave(filename,
       width=width,
       height=height,
       units="in",
       dpi=300)
}

demos <- read.csv("hbcd_1.0.0RC0_scanner_qc.csv")
print(paste("Number of rows with NA in gestational_age:",
            sum(is.na(demos$gestational_age))))

# Remove rows with NA in gestational_age
demos <- demos %>%
  filter(!is.na(gestational_age))




read_atk_parquet <- function(atk_parquet, method_name){
  # We need to rename some of the columns because they are hard to
  # access in R
  unnumeralize <- c(
    quarter_1_volume_mm3 = "1st_quarter_volume_mm3",
    quarter_2_and_3_volume_mm3="2nd_and_3rd_quarter_volume_mm3",
    quarter_4_volume_mm3="4th_quarter_volume_mm3"
  )

  return(
    read_parquet(atk_parquet) %>%
    filter(is.finite(number_of_tracts)) %>%
    separate_wider_delim(
      bundle_name,
      delim="_",
      names=c("bundle_type", "bundle"),
      too_many="merge") %>%
    rename(all_of(unnumeralize)) %>%
    mutate(recon_method=method_name)
  )
}

atk_df <- read_atk_parquet("group_DSIStudio_bundlestats.parquet", method_name="GQI")

# Merge the demographics with the bundle stats by subject_id and session_id
atk_df <- merge(atk_df, demos, by=c("subject_id", "session_id"))

# create new columns in atk_df and demos that are the string concenation of subject_id and session_id
atk_df <- atk_df %>%
  mutate(subject_session=paste(subject_id, session_id, sep="_"))
demos <- demos %>%
  mutate(subject_session=paste(subject_id, session_id, sep="_"))

# check that the number of subject_session pairs is the same in atk_df and demos
stopifnot(length(unique(atk_df$subject_session)) == length(unique(demos$subject_session)))

# ensure that the order of the levels of session_id are ses-V02 and ses-V03
atk_df$session_id <- factor(atk_df$session_id, levels=c("ses-V02", "ses-V03"))


# Load group_TORTOISE_model-MAPMRI_scalarstats.parquet
mapmri_df <- read_parquet("group_TORTOISE_model-MAPMRI_scalarstats.parquet") %>%
  mutate(
    bundle_name=bundle,
    session_id=factor(session_id, levels=c("ses-V02", "ses-V03"))) %>%
  select(bundle_name, subject_id, session_id, masked_median, variable_name) %>%
  pivot_wider(names_from=variable_name, values_from=masked_median) %>%
  separate_wider_delim(
      bundle_name,
      delim="_",
      names=c("bundle_type", "bundle"),
      too_many="merge")

# Check to see if the subject_id and session_id, bundle_type, and bundle are unique
check_mapmri <-mapmri_df %>%
  mutate(subject_session_bundle=paste(subject_id, session_id, bundle_type, bundle, sep="_"))

check_atk <- atk_df %>%
  mutate(subject_session_bundle=paste(subject_id, session_id, bundle_type, bundle, sep="_"))

atk_df <- merge(
  check_atk,
  check_mapmri,
  by=c("subject_session_bundle", "bundle_type", "bundle", "session_id", "subject_id")) %>%
  mutate(bundle=str_remove(bundle, "[RL]$"))

atk_df <- atk_df %>%
  mutate(rtop = rtop * 10000)




## Scalar violin plots:
# Plot some metrics side by side
metrics_to_plot <- c("dti_fa", "md", "rtop")

# # Rescale rtop to be eaier to plot
# atk_df <- atk_df %>%
#   mutate(rtop = rtop * 10000)

# Helper function to split labels at capital letters
split_at_capital <- function(x) {
  # Find the first capital letter after the first character
  first_cap <- regexpr("[A-Z]", substring(x, 2))[1]
  if (first_cap == -1) return(x)  # No capital letter found
  # Add 1 because we started searching from position 2
  first_cap <- first_cap + 1
  # Split and join with newline
  paste0(substring(x, 1, first_cap-1), "\n", substring(x, first_cap))
}

plot_bundle_values_grid <- function(metrics) {
  # Create figures directory if it doesn't exist
  if (!dir.exists("figures")) {
    dir.create("figures")
  }

  # Calculate the number of bundles in each type for relative heights
  bundle_counts <- atk_df %>%
    group_by(bundle_type) %>%
    summarize(n_bundles = n_distinct(bundle), .groups = 'drop')

  # Calculate shared breaks and limits for each metric across all data
  shared_axis_info <- list()
  for(metric in metrics) {
    if(metric == "rtop") {
      # Use robust range for RTOP to exclude outliers (5th to 95th percentile)
      data_range <- quantile(atk_df[[metric]], probs = c(0.0001, 0.99), na.rm = TRUE)
      # Create exactly 4 evenly spaced breaks for RTOP
      #breaks <- seq(from = data_range[1], to = data_range[2], length.out = 4)
    } else {
      # Get the full range of data for other metrics
      data_range <- range(atk_df[[metric]], na.rm = TRUE)
      # Use default number of breaks for other metrics
    }
    breaks <- pretty(data_range)
    # Store both breaks and limits
    shared_axis_info[[metric]] <- list(
      breaks = breaks,
      limits = range(breaks)  # Use range of breaks as limits to ensure consistency
    )
  }

  # Create a list to store plots for each bundle type
  bundle_type_plots <- list()

  # Create plots for each bundle type (sorted alphabetically)
  bundle_types <- sort(unique(atk_df$bundle_type))
  for(bt in bundle_types) {
    # Create a list to store plots for each metric
    metric_plots <- list()

    # Create plots for each metric
    for(i in seq_along(metrics)) {
      metric <- metrics[i]
      # Only show y-axis labels and ticks for the first plot
      show_y_axis <- i == 1
      # Only show x-axis ticks for the last bundle type
      show_x_ticks <- bt == bundle_types[length(bundle_types)]

      metric_plots[[metric]] <- atk_df %>%
        filter(bundle_type == bt) %>%
        ggplot(aes(x = .data[[metric]],
                   y = forcats::fct_rev(bundle),  # Reverse bundle order
                   fill = factor(session_id, levels = c("ses-V03", "ses-V02")))) +
        geom_violin(position = position_dodge(width = 0.7), width = 0.7) +
        scale_fill_manual(
          values = c("ses-V02" = "#ff7f0e", "ses-V03" = "#1f77b4"),
          breaks = c("ses-V02", "ses-V03")
        ) +
        plot_theme_single_col +
        labs(
          x = NULL,  # Remove x-axis label
          y = if(show_y_axis) split_at_capital(bt) else NULL,
          title = NULL,
          fill = "Session"
        ) +
        theme(
          axis.text = element_text(size = 10),
          axis.title = element_text(size = 12),
          axis.text.x = if(show_x_ticks) element_text(size = 10, margin = margin(t = 5)) else element_blank(),
          axis.ticks.x = if(show_x_ticks) element_line() else element_blank(),
          axis.text.y = if(show_y_axis) element_text(margin = margin(r = 5)) else element_blank(),
          axis.ticks.y = if(show_y_axis) element_line() else element_blank(),
          plot.margin = margin(t = 5, r = 10, b = 30, l = 10),
          axis.title.y = if(show_y_axis) element_text(
            size = 10,
            angle = 90,
            vjust = 0.5,
            margin = margin(r = 20)
          ) else element_blank(),
          axis.title.x = element_blank()  # Remove x-axis title
        ) +
        scale_x_continuous(
          breaks = shared_axis_info[[metric]]$breaks,
          limits = shared_axis_info[[metric]]$limits
        )
    }

    # Combine metric plots horizontally for this bundle type
    bundle_type_plots[[bt]] <- wrap_plots(metric_plots, ncol = length(metrics)) +
      plot_annotation(
        title = bt,
        theme = theme(
          plot.title = element_text(size = 16, hjust = 0.5),
          legend.position = "none",  # Hide individual legends
          legend.title = element_text(size = 12),
          legend.text = element_text(size = 10)
        )
      ) &
      theme(
        plot.margin = margin(0.2, 0.5, 0.2, 0.5, "cm"),
        panel.spacing = unit(1, "cm")
      )
  }

  # Calculate relative heights
  relative_heights <- 3 * (bundle_counts$n_bundles / max(bundle_counts$n_bundles))

  # Create column titles
  column_titles <- c(
    "dti_fa" = "Fractional Anisotropy",
    "md" = "Mean Diffusivity",
    "rtop" = "RTOP"
  )

  # Create title plots for each column
  title_plots <- lapply(metrics, function(metric) {
    ggplot() +
      annotate("text", x = 0.5, y = 0.5,
               label = column_titles[metric],
               size = 4, hjust = 0.5, vjust = 0.5) +
      coord_cartesian(clip = "off") +
      theme_void()
  })

  # Combine title plots horizontally
  title_row <- wrap_plots(title_plots, ncol = length(metrics))

  # Combine all plots into a single list
  all_plots <- c(list(title_row), bundle_type_plots)

  # Combine all plots vertically
  combined_plot <- wrap_plots(all_plots, ncol = 1, heights = c(0.1, relative_heights)) +
    plot_layout(guides = "collect") +
    plot_annotation(
      theme = theme(
        legend.position = "bottom",  # Move legend to bottom
        legend.title = element_text(size = 12),
        legend.text = element_text(size = 10)
      )
    ) &
    theme(
      plot.margin = margin(0.2, 0.5, 0.2, 0.5, "cm"),
      panel.spacing = unit(1, "cm")
    )

  # Save the combined plot
  ggsave(
    filename = file.path("figures", paste0("bundle_values_grid_", paste(metrics, collapse="_"), ".svg")),
    plot = combined_plot,
    width = 3.2 * length(metrics),  # Reduced from 8 to 4
    height = sum(relative_heights) * 1.4,  # Reduced from 3.5 to 1.75
    units = "in",
    dpi = 300
  )
  # Save the combined plot
  ggsave(
    filename = file.path("figures", paste0("bundle_values_grid_", paste(metrics, collapse="_"), ".png")),
    plot = combined_plot,
    width = 3.2 * length(metrics),  # Reduced from 8 to 4
    height = sum(relative_heights) * 1.4,  # Reduced from 3.5 to 1.75
    units = "in",
    dpi = 300
  )
}

# Create the grid plot with the specified metrics
plot_bundle_values_grid(metrics_to_plot)



### Geometry violin plots
# Plot some metrics side by side
metrics_to_plot <- c("total_volume_mm3", "total_area_of_end_regions_mm2", "irregularity")

plot_bundle_values_grid <- function(metrics) {
  # Create figures directory if it doesn't exist
  if (!dir.exists("figures")) {
    dir.create("figures")
  }

  # Calculate the number of bundles in each type for relative heights
  bundle_counts <- atk_df %>%
    group_by(bundle_type) %>%
    summarize(n_bundles = n_distinct(bundle), .groups = 'drop')

  # Calculate shared breaks and limits for each metric across all data
  shared_axis_info <- list()
  for(metric in metrics) {
    if(metric == "rtop") {
      # Use robust range for RTOP to exclude outliers (5th to 95th percentile)
      data_range <- quantile(atk_df[[metric]], probs = c(0.0001, 0.99), na.rm = TRUE)
      # Create exactly 4 evenly spaced breaks for RTOP
      #breaks <- seq(from = data_range[1], to = data_range[2], length.out = 4)
    } else {
      # Get the full range of data for other metrics
      data_range <- range(atk_df[[metric]], na.rm = TRUE)
      # Use default number of breaks for other metrics
    }
    breaks <- pretty(data_range, n=4)
    # Store both breaks and limits
    shared_axis_info[[metric]] <- list(
      breaks = breaks,
      limits = range(breaks)  # Use range of breaks as limits to ensure consistency
    )
  }

  # Create a list to store plots for each bundle type
  bundle_type_plots <- list()

  # Create plots for each bundle type (sorted alphabetically)
  bundle_types <- sort(unique(atk_df$bundle_type))
  for(bt in bundle_types) {
    # Create a list to store plots for each metric
    metric_plots <- list()

    # Create plots for each metric
    for(i in seq_along(metrics)) {
      metric <- metrics[i]
      # Only show y-axis labels and ticks for the first plot
      show_y_axis <- i == 1
      # Only show x-axis ticks for the last bundle type
      show_x_ticks <- bt == bundle_types[length(bundle_types)]

      metric_plots[[metric]] <- atk_df %>%
        filter(bundle_type == bt) %>%
        ggplot(aes(x = .data[[metric]],
                   y = forcats::fct_rev(bundle),  # Reverse bundle order
                   fill = factor(session_id, levels = c("ses-V03", "ses-V02")))) +
        geom_violin(position = position_dodge(width = 0.7), width = 0.7) +
        scale_fill_manual(
          values = c("ses-V02" = "#ff7f0e", "ses-V03" = "#1f77b4"),
          breaks = c("ses-V02", "ses-V03")
        ) +
        plot_theme_single_col +
        labs(
          x = NULL,  # Remove x-axis label
          y = if(show_y_axis) split_at_capital(bt) else NULL,
          title = NULL,
          fill = "Session"
        ) +
        theme(
          axis.text = element_text(size = 10),
          axis.title = element_text(size = 12),
          axis.text.x = if(show_x_ticks) element_text(size = 10, margin = margin(t = 5)) else element_blank(),
          axis.ticks.x = if(show_x_ticks) element_line() else element_blank(),
          axis.text.y = if(show_y_axis) element_text(margin = margin(r = 5)) else element_blank(),
          axis.ticks.y = if(show_y_axis) element_line() else element_blank(),
          plot.margin = margin(t = 5, r = 10, b = 30, l = 10),
          axis.title.y = if(show_y_axis) element_text(
            size = 10,
            angle = 90,
            vjust = 0.5,
            margin = margin(r = 20)
          ) else element_blank(),
          axis.title.x = element_blank()  # Remove x-axis title
        ) +
        scale_x_continuous(
          breaks = function(x) pretty(x, n = 3),
          limits = shared_axis_info[[metric]]$limits
        )
    }

    # Combine metric plots horizontally for this bundle type
    bundle_type_plots[[bt]] <- wrap_plots(metric_plots, ncol = length(metrics)) +
      plot_annotation(
        title = bt,
        theme = theme(
          plot.title = element_text(size = 16, hjust = 0.5),
          legend.position = "none",  # Hide individual legends
          legend.title = element_text(size = 12),
          legend.text = element_text(size = 10)
        )
      ) &
      theme(
        plot.margin = margin(0.2, 0.5, 0.2, 0.5, "cm"),
        panel.spacing = unit(1, "cm")
      )
  }

  # Calculate relative heights
  relative_heights <- 3 * (bundle_counts$n_bundles / max(bundle_counts$n_bundles))

  # Create column titles
  column_titles <- c(
    "total_volume_mm3" = expression("Total Volume"*" (mm"^3*")"),
    "irregularity" = expression("Irregularity"),
    "total_area_of_end_regions_mm2" = expression("End Region Area"*" (mm"^2*")")
  )

  # Create title plots for each column
  title_plots <- lapply(metrics, function(metric) {
    ggplot() +
      annotate("text", x = 0.5, y = 0.5,
               label = column_titles[metric],
               size = 4, hjust = 0.5, vjust = 0.5) +
      coord_cartesian(clip = "off") +
      theme_void()
  })

  # Combine title plots horizontally
  title_row <- wrap_plots(title_plots, ncol = length(metrics))

  # Combine all plots into a single list
  all_plots <- c(list(title_row), bundle_type_plots)

  # Combine all plots vertically
  combined_plot <- wrap_plots(all_plots, ncol = 1, heights = c(0.25, relative_heights)) +
    plot_layout(guides = "collect") +
    plot_annotation(
      theme = theme(
        legend.position = "bottom",  # Move legend to bottom
        legend.title = element_text(size = 12),
        legend.text = element_text(size = 10)
      )
    ) &
    theme(
      plot.margin = margin(0.2, 0.5, 0.2, 0.5, "cm"),
      panel.spacing = unit(1, "cm")
    )

  # Save the combined plot
  ggsave(
    filename = file.path("figures", paste0("bundle_geometry_grid_", paste(metrics, collapse="_"), ".svg")),
    plot = combined_plot,
    width = 3.2 * length(metrics),  # Reduced from 8 to 4
    height = sum(relative_heights) * 1.4,  # Reduced from 3.5 to 1.75
    units = "in",
    dpi = 300
  )
  ggsave(
    filename = file.path("figures", paste0("bundle_geometry_grid_", paste(metrics, collapse="_"), ".png")),
    plot = combined_plot,
    width = 3.2 * length(metrics),  # Reduced from 8 to 4
    height = sum(relative_heights) * 1.4,  # Reduced from 3.5 to 1.75
    units = "in",
    dpi = 300
  )
}

# Create the grid plot with the specified metrics
plot_bundle_values_grid(metrics_to_plot)