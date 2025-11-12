

# To get a nicer legend:
my_key <- function(data, params, size) {
  if (all(is.na(data$fill))) {
    draw_key_path(data, params, size)
  } else {
    draw_key_polygon(data, params, size)
  }
}

dice_max <- 1.0
# Load shared configuration (libraries, themes, colors, utility functions)
source("shared_config.R")


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
# Create ridgeline plot comparing Raw vs Processed NDC by manufacturer
ndc_plot <- demos_ndc %>%
  # Create a custom ordering: group by Manufacturer first, then by ManufacturersModelName
  arrange(Manufacturer, ManufacturersModelName) %>%
  mutate(ManufacturersModelName = factor(ManufacturersModelName, 
                                        levels = unique(ManufacturersModelName))) %>%
  ggplot(aes(
    x = NDC, y = ManufacturersModelName,
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
    y = "Model Name",
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
    ManufacturersModelName,
    raw_neighbor_corr,
    t1_neighbor_corr,
    mean_fd,
    raw_dwi_contrast,
    t1_dwi_contrast,
    raw_dwi_contrast,
    t1_dwi_contrast,
    raw_num_bad_slices
  ) %>%
  arrange(Manufacturer, ManufacturersModelName) %>%
  mutate(ManufacturersModelName = factor(ManufacturersModelName, 
                                        levels = unique(ManufacturersModelName))) %>%
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
save_svg_double_col("Figure4.svg", width = 8.0, height = 4.0)

# Create a table of mean, median, std and MAD of cnr for each manufacturersmodelname
CNR_df %>%
  group_by(Manufacturer, ManufacturersModelName, CNR) %>%
  summarize(
    mean_cnr = mean(value, na.rm = TRUE), 
    median_cnr = median(value, na.rm = TRUE), 
    std_cnr = sd(value, na.rm = TRUE), 
    .groups = "drop"
  ) %>%
  # Sort by CNR first, then by ManufacturersModelName
  arrange(CNR, Manufacturer, ManufacturersModelName) %>%
  flextable() %>%
  set_header_labels(
    ManufacturersModelName = "Manufacturer Model Name", 
    CNR = "b-value",
    mean_cnr = "Mean CNR", 
    median_cnr = "Median CNR", 
    std_cnr = "Std CNR"
  ) %>%
  theme_vanilla() %>%
  fontsize(size = 10, part = "all") %>%
  # Format numeric columns to 3 decimal places
  colformat_double(j = c("mean_cnr", "median_cnr", "std_cnr"), digits = 3) %>%
  # Set column widths - wider for model name, consistent for numeric columns
  autofit() %>%
  width(j = "Manufacturer", width = 1.0) %>%
  width(j = "ManufacturersModelName", width = 2.5) %>%  # Wider for model names
  width(j = "CNR", width = 1.0) %>%
  width(j = c("mean_cnr", "median_cnr", "std_cnr"), width = 1.0) %>%
  # Add some styling
  bold(part = "header") %>%
  align(j = c("mean_cnr", "median_cnr", "std_cnr"), align = "right") %>%
  # Color rows by manufacturer using SCANNER_COLORS (with light alpha)
  bg(i = ~ Manufacturer == "GE", bg = paste0(SCANNER_COLORS["GE"], "20")) %>%  # 20 = light alpha
  bg(i = ~ Manufacturer == "Philips", bg = paste0(SCANNER_COLORS["Philips"], "20")) %>%
  bg(i = ~ Manufacturer == "Siemens", bg = paste0(SCANNER_COLORS["Siemens"], "20")) %>%
  # Add thick lines between CNR levels - need to calculate where CNR changes
  {
    # Get the data to find where CNR changes
    table_data <- CNR_df %>%
      group_by(Manufacturer, ManufacturersModelName, CNR) %>%
      summarize(
        mean_cnr = mean(value, na.rm = TRUE), 
        median_cnr = median(value, na.rm = TRUE), 
        std_cnr = sd(value, na.rm = TRUE),
        .groups = "drop"
      ) %>%
      arrange(CNR, Manufacturer, ManufacturersModelName)
    
    # Find rows where CNR changes (end of each CNR group)
    cnr_change_rows <- which(diff(as.numeric(factor(table_data$CNR))) != 0)
    
    # Add thick horizontal lines after each CNR group
    if(length(cnr_change_rows) > 0) {
      hline(., i = cnr_change_rows, border = fp_border(color = "black", width = 2))
    } else {
      .
    }
  } %>%
  set_caption("CNR Statistics by Scanner Model and b-value") %>%
  save_as_docx(path = paste0("SupplementaryTable3.docx"))
