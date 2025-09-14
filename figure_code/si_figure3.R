# Load shared configuration (libraries, themes, colors, utility functions)
source("shared_config.R")

# Make a grid of scatter plots to show the relationships between the columns
# age, raw_neighbor_corr, max_fd, CNR0_median, CNR1_median, CNR2_median, CNR3_median, CNR4_median
# color the points by Manufacturer

# Select the variables of interest
plot_vars <- c("age", "raw_neighbor_corr", "t1_neighbor_corr", "mean_fd", 
               "CNR1_median", "CNR2_median", "CNR3_median", "CNR4_median")

# Create a mapping for better variable names
var_labels <- c(
  "age" = "Age",
  "raw_neighbor_corr" = "Unprocessed NDC",  # Keep original if no specific label needed
  "t1_neighbor_corr" = "Processed NDC",
  "mean_fd" = "Mean FD",
  "CNR1_median" = "b=500 CNR",
  "CNR2_median" = "b=1000 CNR", 
  "CNR3_median" = "b=2000 CNR",
  "CNR4_median" = "b=3000 CNR"
)



# Create a function to generate scatter plots with consistent axis ranges
create_scatter_plot <- function(data, x_var, y_var, x_range, y_range, show_x_labels = TRUE, show_y_labels = TRUE) {
  ggplot(data, aes(x = .data[[x_var]], y = .data[[y_var]], color = .data[["Manufacturer"]])) +
    geom_point(alpha = 0.6, size = 0.8) +
    scale_color_manual(values = SCANNER_COLORS) +
    scale_x_continuous(limits = c(x_range$x_min, x_range$x_max), 
                       breaks = scales::pretty_breaks(n = 3)) +
    scale_y_continuous(limits = c(y_range$y_min, y_range$y_max),
                       breaks = scales::pretty_breaks(n = 3)) +
    plot_theme_single_col +
    theme(
      legend.position = "none",
      axis.text.x = if (show_x_labels) element_text(size = 8, margin = margin(t = 2)) else element_blank(),
      axis.text.y = if (show_y_labels) element_text(size = 8, margin = margin(r = 2)) else element_blank(),
      axis.title.x = if (show_x_labels) element_text(size = 9, margin = margin(t = 4)) else element_blank(),
      axis.title.y = if (show_y_labels) element_text(size = 9, margin = margin(r = 4)) else element_blank(),
      # Ensure consistent margins for all plots - reserve space for y-axis labels
      plot.margin = margin(t = 2, r = 2, b = 2, l = 20, unit = "pt"),
      # Ensure consistent axis spacing
      axis.ticks.length = unit(2, "pt"),
      axis.ticks.margin = unit(2, "pt")
    ) +
    labs(x = if (show_x_labels) var_labels[[x_var]] else "", y = if (show_y_labels) var_labels[[y_var]] else "")
}

# Create a function to generate blank plots for diagonal elements
create_blank_plot <- function(var_name, show_x_labels = TRUE, show_y_labels = TRUE) {
  ggplot() +
    theme_void() +
    theme(
      plot.background = element_rect(fill = "white", color = NA),
      axis.text.x = if (show_x_labels) element_text(size = 8) else element_blank(),
      axis.text.y = if (show_y_labels) element_text(size = 8) else element_blank(),
      axis.title.x = if (show_x_labels) element_text(size = 9) else element_blank(),
      axis.title.y = if (show_y_labels) element_text(size = 9) else element_blank()
    ) +
    labs(x = if (show_x_labels) var_labels[[var_name]] else "", 
         y = if (show_y_labels) var_labels[[var_name]] else "")
}

# Calculate axis ranges for each variable to ensure consistent scaling
axis_ranges <- map(plot_vars, ~ {
  var_data <- demos[[.x]]
  var_data <- var_data[!is.na(var_data)]  # Remove NAs
  list(
    var = .x,
    x_min = min(var_data),
    x_max = max(var_data),
    y_min = min(var_data),
    y_max = max(var_data)
  )
}) %>% 
  set_names(plot_vars)

# Function to create plots for a specific session using patchwork
create_session_plots <- function(session_data, session_name) {
  # Calculate axis ranges for this specific session
  session_axis_ranges <- map(plot_vars, ~ {
    var_data <- session_data[[.x]]
    var_data <- var_data[!is.na(var_data)]  # Remove NAs
    list(
      var = .x,
      x_min = min(var_data),
      x_max = max(var_data),
      y_min = min(var_data),
      y_max = max(var_data)
    )
  }) %>% 
    set_names(plot_vars)
  
  n_vars <- length(plot_vars)
  
  # Create a matrix to hold all plots (including blanks)
  plot_matrix <- matrix(list(NULL), nrow = n_vars, ncol = n_vars)
  
  # Fill the lower triangle with actual plots
  for (i in 1:n_vars) {
    for (j in 1:n_vars) {
      if (j < i) {
        # Lower triangle - create actual plot
        x_var <- plot_vars[j]
        y_var <- plot_vars[i]
        
        # Determine label visibility
        show_x_labels <- (i == n_vars)  # Bottom row
        show_y_labels <- (j == 1)       # Left column
        
        # Create the plot
        x_range <- session_axis_ranges[[x_var]]
        y_range <- session_axis_ranges[[y_var]]
        plot_matrix[[i, j]] <- create_scatter_plot(session_data, x_var, y_var, x_range, y_range, show_x_labels, show_y_labels)
      } else {
        # Upper triangle or diagonal - blank plot
        plot_matrix[[i, j]] <- ggplot() + theme_void()
      }
    }
  }
  
  
  # Convert matrix to a flat list for patchwork
  plot_list <- vector("list", n_vars * n_vars)
  for (i in 1:n_vars) {
    for (j in 1:n_vars) {
      plot_list[[(i-1) * n_vars + j]] <- plot_matrix[[i, j]]
    }
  }
  
  # Use patchwork with explicit layout
  wrap_plots(plot_list, ncol = n_vars) +
    plot_annotation(
      title = paste("Pairwise Relationships Between QC Metrics"),
      theme = theme(plot.title = element_text(size = 14, hjust = 0.5))
    )
}

# Create plots for ses-V02
demos_v02 <- demos %>% filter(
  CNR1_median < 4,
  CNR2_median < 4,
  CNR3_median < 4,
  CNR4_median < 4
)
plots_v02 <- create_session_plots(demos_v02, "All Sessions")
print(plots_v02)
save_svg_double_col("qc_metrics_relationships_all_sessions.svg", width = 10, height = 8)