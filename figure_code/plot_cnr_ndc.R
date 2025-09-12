library(tidyverse)
library(broom)
library(patchwork)
library(cowplot)
library(ggridges)
library(kableExtra)
library(flextable)
library(officer)

POINT_ALPHA <- 0.05

# Colorblind-friendly colors for scanner manufacturers
SCANNER_COLORS <- c(
  "Siemens" = "#0077BB", # Blue
  "GE" = "#EE7733", # Orange
  "Philips" = "#009988" # Teal
)

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


# Save a plot as an svg with a single column
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

demos <- read.csv("brain_mask_info.csv")

# Merge in the dwi brain mask info, prefix the non-id columns with "dwi_"
dwi_brain_mask_info <- read.csv("dwi_brain_mask_info.csv") %>%
  rename_with(~ paste0("dwimask_", .x), -c(subject_id, session_id))
demos <- merge(demos, dwi_brain_mask_info, by = c("subject_id", "session_id"))


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

# Create longer dataframe for neighbor distance correlations (NDC)
demos_ndc <- demos %>%
  pivot_longer(
    cols = c(t1_neighbor_corr, raw_neighbor_corr),
    names_to = "temp",
    values_to = "NDC"
  ) %>%
  mutate(
    NDC_type = case_when(
      temp == "t1_neighbor_corr" ~ "Processed",
      temp == "raw_neighbor_corr" ~ "Raw"
    )
  ) %>%
  select(-temp) # Remove the temporary column

# To get a nicer legend:
my_key <- function(data, params, size) {
  if (all(is.na(data$fill))) {
    draw_key_path(data, params, size)
  } else {
    draw_key_polygon(data, params, size)
  }
}

## Create tables
# Create a table of the number of subjects that have a given number of sessions
demos %>%
  group_by(subject_id) %>%
  summarize(n_sessions = n()) %>%
  group_by(n_sessions) %>%
  summarize(n_subjects = n())

# Show how many sessions are scanned per site_id, Manufacturer, and SoftwareVersions
scanner_groups <- demos %>%
  group_by(site, Manufacturer, SoftwareVersions) %>%
  summarize(n_sessions = n(), .groups = "drop") %>%
  arrange(Manufacturer, desc(n_sessions)) # First by Manufacturer, then by descending n_sessions

# Create Word-friendly table
scanner_groups %>%
  flextable() %>%
  set_header_labels(
    site = "Site",
    Manufacturer = "Manufacturer",
    SoftwareVersions = "Software Version",
    n_sessions = "N Sessions"
  ) %>%
  theme_vanilla() %>%
  fontsize(size = 10, part = "all") %>% # Set font size to 10
  align(j = "n_sessions", align = "right") %>%
  bold(part = "header") %>%
  set_caption("Scanner Distribution Across Sites") %>%
  hline(
    i = which(diff(as.numeric(factor(scanner_groups$Manufacturer))) != 0),
    border = fp_border(color = "gray", width = 1)
  ) %>%
  autofit() %>% # First autofit to get proportions right
  width(width = c(2, 1.5, 2.5, 1)) %>% # Set specific column widths in inches
  set_table_properties(layout = "autofit") %>% # Ensure table uses full width
  save_as_docx(path = "scanner_distribution_table.docx")

# Keep the HTML version for the Rmd document
scanner_groups %>%
  kbl(
    col.names = c("Site", "Manufacturer", "Software Version", "N Sessions"),
    caption = "Scanner Distribution Across Sites",
    format = "html",
    align = c("l", "l", "l", "r")
  ) %>%
  kable_styling(
    bootstrap_options = c("striped", "hover", "condensed"),
    full_width = FALSE,
    position = "left",
    font_size = 12
  ) %>%
  row_spec(0, bold = TRUE) %>%
  column_spec(1:3, width = "12em") %>%
  column_spec(4, width = "8em") %>%
  add_header_above(c(" " = 3, "Sessions" = 1))


# Create descriptive summaries by session
demos %>%
  group_by(session_id) %>%
  summarise(
    n_subjects = n(),
    age_mean = sprintf("%.1f (%.1f)", mean(age), sd(age)),
    age_min = round(min(age), 2),
    age_max = round(max(age), 2),
    head_mean = sprintf("%.1f (%.1f)", mean(head_size), sd(head_size))
  ) %>%
  flextable() %>%
  set_header_labels(
    session_id = "Session",
    n_subjects = "N",
    age_mean = "Mean Age (SD)",
    age_min = "Min Age",
    age_max = "Max Age",
    head_mean = "Mean Head Size (SD)"
  ) %>%
  theme_vanilla() %>%
  fontsize(size = 10, part = "all") %>%
  align(j = 2:6, align = "right") %>%
  bold(part = "header") %>%
  set_caption("Summary Statistics by Session") %>%
  autofit() %>%
  width(j = 1, width = 0.7) %>% # Reduce Session column width
  width(j = 2, width = 0.7) %>% # Adjust N column width
  width(j = 3:6, width = 1.2) %>% # Set consistent width for numeric columns
  save_as_docx(path = "session_summary_statistics.docx")

# Keep the HTML version for the Rmd document
demos %>%
  group_by(session_id) %>%
  summarise(
    n_subjects = n(),
    age_mean = sprintf("%.1f (%.1f)", mean(age), sd(age)),
    age_min = round(min(age), 2),
    age_max = round(max(age), 2),
    head_mean = sprintf("%.1f (%.1f)", mean(head_size), sd(head_size))
  ) %>%
  knitr::kable(caption = "Summary Statistics by Session") %>%
  kable_styling(
    bootstrap_options = c("striped", "hover", "condensed"),
    full_width = FALSE,
    position = "left",
    font_size = 12
  )








# Create ridgeline plot comparing Raw vs Processed NDC by manufacturer
ndc_plot <- demos_ndc %>%
  ggplot(aes(
    x = NDC, y = Manufacturer,
    fill = Manufacturer,
    linetype = NDC_type
  )) +
  geom_density_ridges(
    alpha = 0.7,
    scale = 0.9,
    key_glyph = my_key
  ) +
  guides(linetype = guide_legend(override.aes = list(fill = NA))) +
  scale_fill_manual(values = SCANNER_COLORS) +
  scale_linetype_manual(values = c("Raw" = 3, "Processed" = 1)) + # dashed for Raw, solid for Processed
  plot_theme_single_col +
  labs(
    x = "Neighboring DWI Correlation",
    y = "Manufacturer",
    fill = "Manufacturer",
    linetype = "Processing"
  ) +
  theme(
    legend.position = "top",
    legend.direction = "horizontal",
    legend.box = "vertical", # Stack the two legend keys
    legend.box.margin = margin(t = 10),
    plot.margin = margin(b = 40, l = 5, r = 5, t = 5),
    legend.spacing.x = unit(0.1, "cm"),
    legend.spacing.y = unit(0.1, "cm"),
    legend.margin = margin(0, 0, 0, 0),
    legend.box.spacing = unit(0, "pt")
  )

CNR_df <- demos %>%
  select(
    starts_with("CNR"),
    subject_id,
    Manufacturer,
    raw_neighbor_corr,
    t1_neighbor_corr,
    mean_fd,
    raw_dwi_contrast,
    t1_dwi_contrast,
    raw_dwi_contrast,
    t1_dwi_contrast,
    raw_num_bad_slices
  ) %>%
  pivot_longer(starts_with("CNR")) %>%
  separate_wider_delim(name, "_", names = c("CNR", "measure"), too_many = "merge") %>%
  filter(measure == "median") %>%
  filter(CNR %in% c("CNR1", "CNR2", "CNR3", "CNR4")) %>%
  mutate(CNR = case_when(
    CNR == "CNR1" ~ "b=500",
    CNR == "CNR2" ~ "b=1000",
    CNR == "CNR3" ~ "b=2000",
    CNR == "CNR4" ~ "b=3000"
  )) %>%
  mutate(CNR = factor(CNR, levels = c("b=3000", "b=2000", "b=1000", "b=500")))

cnr_plot <- CNR_df %>%
  ggplot(aes(x = value, y = CNR, fill = Manufacturer)) +
  geom_density_ridges(alpha = 0.7, scale = 0.9, show.legend = FALSE) + # Remove legend from this plot
  scale_fill_manual(values = SCANNER_COLORS) +
  plot_theme_single_col +
  labs(x = "CNR Value", y = "b-value") +
  xlim(0, 3.5)

# Combine plots horizontally with shared legend
combined_plot <- cnr_plot + ndc_plot +
  plot_layout(widths = c(1, 1), guides = "collect") &
  theme(legend.position = "bottom")

## This is Figure 4: CNR and NDC comparison
save_svg_double_col("ndc_cnr_comparison.svg", width = 8.0, height = 4.0)


