#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(tidyr)
  library(readr)
  library(stringr)
  library(tools)
  library(ggtext)
})

# Load shared plotting config (provides SCANNER_COLORS)
source(file.path("shared_config.R"))

out_dir <- getwd()

# Plot histogram and a vertical line at 0.06
ggplot(demos, aes(x = t1_dice_distance)) +
  geom_histogram(binwidth = 0.02) +
  labs(x = "T2w / <i>b</i>=0 brain mask Dice Score", y = "Count") +
  geom_vline(xintercept = 0.06, linetype = "dashed", color = "maroon") +
  ggtitle("Coregistration Dice Score Distribution") +
  plot_theme_single_col +
  theme(axis.title.x = ggtext::element_markdown(),
       plot.title = element_text(hjust = 0.5, size = 10))

ggsave(file.path(out_dir, "t1_dice_distance_histogram.svg"), width = 3.5, height = 3.5, units = "in")
