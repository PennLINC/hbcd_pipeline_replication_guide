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

demos <- read.csv("hbcd_1.0.0RC0_scanner_qc.csv")

print(paste(
  "Number of rows with NA in gestational_age:",
  sum(is.na(demos$gestational_age))
))

# Remove rows with NA in gestational_age
demos <- demos %>%
  filter(!is.na(gestational_age))

# Verify removal
print(paste("Number of rows remaining:", nrow(demos)))

table(demos$session_id)

# convert age to weeks
demos <- demos %>%
  mutate(age = age * 52.1429)

# Remove rows in ses-V01 with gestational age > 60 weeks
demos <- demos %>%
  filter(!(session_id == "ses-V02" & gestational_age > 60))
