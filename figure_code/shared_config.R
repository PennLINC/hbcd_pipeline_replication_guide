# Shared configuration for HBCD figure generation scripts

# Source this file at the beginning of each figure script with: source("shared_config.R")

# Load required libraries
library(tidyverse)
library(broom)
library(arrow)
library(patchwork)
library(cowplot)
library(ggridges)
library(kableExtra)
library(flextable)
library(officer)

# Constants
POINT_ALPHA <- 0.05  # Can be overridden in individual scripts if needed

# Colorblind-friendly colors for scanner manufacturers
SCANNER_COLORS <- c(
  "Siemens" = "#0077BB",  # Blue
  "GE" = "#EE7733",       # Orange
  "Philips" = "#009988"   # Teal
)

# Plot themes
plot_theme_double_col <- theme_bw(
  base_family = "Helvetica",
  base_size = 12
) +
  theme(
    axis.text = element_text(size = 10),
    axis.title = element_text(size = 12),
    legend.text = element_text(size = 10),
    legend.title = element_text(size = 12),
    plot.title = element_text(size = 14),
    plot.margin = margin(t = 2, r = 2, b = 2, l = 2, unit = "pt"),
    legend.position = "bottom"
  )

plot_theme_single_col <- plot_theme_double_col +
  theme(
    axis.text = element_text(size = 8),
    axis.title = element_text(size = 9),
    legend.text = element_text(size = 8),
    legend.title = element_text(size = 9)
  )

# Utility functions for saving plots
save_svg_single_col <- function(filename, width = 3.5, height = 2.5) {
  ggsave(filename,
    width = width,
    height = height,
    units = "in",
    dpi = 300
  )
}

save_svg_double_col <- function(filename, width = 7, height = 3.5) {
  ggsave(filename,
    width = width,
    height = height,
    units = "in",
    dpi = 300
  )
}

# Additional utility functions can be added here as needed

if (file.exists("hbcd_complete_qc_demographics.csv")) {
  demos <- read.csv("hbcd_complete_qc_demographics.csv")
} else if (file.exists("figure_code/hbcd_complete_qc_demographics.csv")) {
  demos <- read.csv("figure_code/hbcd_complete_qc_demographics.csv")
} else {
  stop("hbcd_complete_qc_demographics.csv not found")
}

print(paste(
  "Number of rows with NA in scans_gestational_age:",
  sum(is.na(demos$scans_gestational_age))
))
table(demos$session_id)

# convert age to weeks
demos <- demos %>%
  mutate(age = scans_age * 52.1429)
