#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(tidyr)
  library(readr)
  library(stringr)
  library(tools)
})



check_mppca_effect <- function(dice_max) {
  # Load shared plotting config (provides SCANNER_COLORS)
  source(file.path("figure_code", "shared_config.R"))

  base_csv <- file.path("processing_code/inclusion", "hbcd_complete_qc_demographics.csv")
  alt_csv <- file.path("figure_code", "no_mppca_or_gibbs_qc.csv")
  out_dir <- file.path("figure_code")
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  message(paste("Checking MP-PCA effect for dice max:", dice_max))

  filter_outliers <- function(df_path) {
    df <- read_csv(df_path, show_col_types = FALSE)

    message(paste("Filtering outliers for dice max:", dice_max))
    df <- df %>%
      filter(t1_dice_distance <= dice_max)
    message(paste("Number of rows after filtering outliers for dice max:", dice_max, ":", nrow(df)))
    table(df$session_id)

    message("Filtering out CNR2 and CNR4 outliers")
    df <- df %>%
      filter(CNR2_median < 3.5) %>%
      filter(CNR4_median < 3.5)
    message(
      paste("Number of rows after filtering out CNR2 and CNR4 outliers:", nrow(df)))
    table(df$session_id)
    return(df)
  }

  base_df <- filter_outliers(base_csv)
  alt_df <- filter_outliers(alt_csv)

  # Merge with suffixes to disambiguate
  merged <- base_df %>%
    inner_join(alt_df, by = c("subject_id", "session_id"), suffix = c("_base", "_alt"))
  table(merged$session_id)
  if (nrow(merged) == 0) {
    stop("No overlapping rows between base and alt after merge on subject_id/session_id")
  }

  ## Faceted scatter plots for T1 NDC and all CNRs
  get_manufacturer <- function(df) {
    if ("Manufacturer_base" %in% names(df)) return(df$Manufacturer_base)
    if ("Manufacturer_alt" %in% names(df)) return(df$Manufacturer_alt)
    if ("Manufacturer" %in% names(df)) return(df$Manufacturer)
    return(rep(NA_character_, nrow(df)))
  }

  # Statistical testing: paired t-test (for reference) and Wilcoxon signed-rank (more appropriate)
  test_metric <- function(metric_name) {
    base_col <- paste0(metric_name, "_base")
    alt_col  <- paste0(metric_name, "_alt")
    if (!(base_col %in% colnames(merged) && alt_col %in% colnames(merged))) {
      return(NULL)
    }
    base_vals <- merged[[base_col]]
    alt_vals  <- merged[[alt_col]]
    ok <- is.finite(base_vals) & is.finite(alt_vals)
    if (!any(ok)) {
      return(NULL)
    }
    base_vals <- base_vals[ok]
    alt_vals  <- alt_vals[ok]
    diffs <- alt_vals - base_vals
    n <- length(diffs)
    if (n < 2) {
      return(NULL)
    }

    # Paired t-test (reference only; may be inappropriate for skewed >0 distributions)
    t_res <- try(stats::t.test(alt_vals, base_vals, paired = TRUE), silent = TRUE)
    t_stat <- if (inherits(t_res, "htest")) unname(as.numeric(t_res$statistic)) else NA_real_
    t_p    <- if (inherits(t_res, "htest")) unname(as.numeric(t_res$p.value))   else NA_real_
    t_ci_l <- if (inherits(t_res, "htest")) as.numeric(t_res$conf.int[1]) else NA_real_
    t_ci_u <- if (inherits(t_res, "htest")) as.numeric(t_res$conf.int[2]) else NA_real_

    # Wilcoxon signed-rank on paired differences (alt - base)
    w_res <- try(stats::wilcox.test(diffs, mu = 0, alternative = "two.sided", exact = FALSE, correct = TRUE, conf.int = TRUE), silent = TRUE)
    w_stat <- if (inherits(w_res, "htest")) unname(as.numeric(w_res$statistic)) else NA_real_
    w_p    <- if (inherits(w_res, "htest")) unname(as.numeric(w_res$p.value))   else NA_real_
    w_est  <- if (inherits(w_res, "htest") && !is.null(w_res$estimate)) as.numeric(w_res$estimate) else stats::median(diffs, na.rm = TRUE)
    w_ci_l <- if (inherits(w_res, "htest") && !is.null(w_res$conf.int)) as.numeric(w_res$conf.int[1]) else NA_real_
    w_ci_u <- if (inherits(w_res, "htest") && !is.null(w_res$conf.int)) as.numeric(w_res$conf.int[2]) else NA_real_

    data.frame(
      metric = metric_name,
      n_pairs = n,
      mean_base = mean(base_vals, na.rm = TRUE),
      mean_alt  = mean(alt_vals,  na.rm = TRUE),
      median_base = stats::median(base_vals, na.rm = TRUE),
      median_alt  = stats::median(alt_vals,  na.rm = TRUE),
      mean_diff = mean(diffs, na.rm = TRUE),
      median_diff = stats::median(diffs, na.rm = TRUE),
      t_statistic = t_stat,
      t_pvalue = t_p,
      t_conf_low = t_ci_l,
      t_conf_high = t_ci_u,
      wilcox_statistic = w_stat,
      wilcox_pvalue = w_p,
      wilcox_estimate = w_est,
      wilcox_conf_low = w_ci_l,
      wilcox_conf_high = w_ci_u,
      stringsAsFactors = FALSE
    )
  }

  # Build list of metrics to facet: T1 NDC and all CNR*_median present
  cnr_candidates <- grep("^CNR[0-9]+_median$", colnames(base_df), value = TRUE)
  if (length(cnr_candidates) == 0) {
    # Fallback: look in alt_df
    cnr_candidates <- grep("^CNR[0-9]+_median$", colnames(alt_df), value = TRUE)
  }
  cnr_names <- unique(cnr_candidates)
  metrics_to_plot <- c("t1_neighbor_corr", cnr_names)

  df_plot_list <- list()
  for (metric in metrics_to_plot) {
    base_col <- paste0(metric, "_base")
    alt_col  <- paste0(metric, "_alt")
    if (!(base_col %in% colnames(merged) && alt_col %in% colnames(merged))) next
    df_plot_list[[metric]] <- merged %>%
      transmute(
        metric = metric,
        base = .data[[base_col]],
        alt = .data[[alt_col]],
        Manufacturer = get_manufacturer(merged)
      )
  }
  df_plot <- bind_rows(df_plot_list)



  if (nrow(df_plot) > 0) {
    df_plot <- df_plot %>%
      mutate(
        metric_label = dplyr::case_when(
          metric == "t1_neighbor_corr" ~ "Preprocessed NDC",
          metric == "CNR0_median" ~ "b=0 TSNR",
          metric == "CNR1_median" ~ "b=500 CNR",
          metric == "CNR2_median" ~ "b=1000 CNR",
          metric == "CNR3_median" ~ "b=2000 CNR",
          metric == "CNR4_median" ~ "b=3000 CNR",
        )
      )

    # Remove TSNR panel and build individual panels so we can use the empty slot for the legend
    df_plot <- df_plot %>% filter(metric_label != "b=0 TSNR")

    # Order of panels (only keep those present)
    desired_order <- c("Preprocessed NDC", "b=500 CNR", "b=1000 CNR", "b=2000 CNR", "b=3000 CNR")
    panel_order <- intersect(desired_order, unique(df_plot$metric_label))

    if (length(panel_order) == 0) {
      message("No metrics available after removing TSNR panel.")
    } else {
      # Build one plot per metric label (leave legends on so patchwork can collect them)
      build_panel <- function(df_sub, label_text) {
        ggplot(df_sub, aes(x = alt, y = base, color = Manufacturer)) +
          geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "gray50") +
          geom_point(alpha = 0.6, size = 0.8) +
          scale_color_manual(values = SCANNER_COLORS, drop = FALSE) +
          labs(x = NULL, y = NULL, color = "Manufacturer") +
          plot_theme_double_col +
          theme(plot.title = element_text(size = 10, hjust = 0.5)) +
          ggtitle(label_text)
      }

      panel_plots <- lapply(panel_order, function(lbl) {
        df_sub <- dplyr::filter(df_plot, metric_label == lbl)
        build_panel(df_sub, lbl)
      })

      # Arrange into a 2x3 grid: the last slot reserved for the legend using guide_area
      # If we have fewer than 5 panels, fill remaining before legend with spacers
      num_needed <- 5
      if (length(panel_plots) < num_needed) {
        panel_plots <- c(panel_plots, rep(list(patchwork::plot_spacer()), num_needed - length(panel_plots)))
      }

      # Add guide area as the 6th slot so collected guides go there
      panel_plots <- c(panel_plots, list(patchwork::guide_area()))

      grid_plot <- patchwork::wrap_plots(
        panel_plots,
        ncol = 3,
        guides = "collect"
      ) &
        theme(legend.position = "bottom", legend.direction = "vertical", axis.title = element_blank()) &
        guides(color = guide_legend(ncol = 1, byrow = TRUE))

      # Inset the grid to create padding and add shared axis labels on the outer boundaries
      grid_with_labels <- cowplot::ggdraw() +
        cowplot::draw_plot(grid_plot, x = 0.08, y = 0.10, width = 0.87, height = 0.87) +
        cowplot::draw_label("No MP-PCA/RPG", x = 0.52, y = 0.05, vjust = 1, size = 12) +
        cowplot::draw_label("Using MP-PCA/RPG", x = 0.03, y = 0.52, angle = 90, vjust = 1, size = 12)

      ggsave(file.path(out_dir, paste0("qc_scatter_facets_dice-max", dice_max, ".svg")), grid_with_labels, width = 7, height = 9, units = "in")
    }
  } else {
    message("No metrics available for faceted scatter plot.")
  }

  # Build summary statistics/tests table
  metrics_to_test <- c("t1_neighbor_corr", cnr_names)
  tests_list <- lapply(metrics_to_test, test_metric)
  tests_df <- dplyr::bind_rows(Filter(Negate(is.null), tests_list))
  if (nrow(tests_df) > 0) {
    out_csv_tests <- file.path(out_dir, paste0("qc_metric_tests_summary_dice-max", dice_max, ".csv"))
    readr::write_csv(tests_df, out_csv_tests)
    print(tests_df)
    message("Wrote ", out_csv_tests)
  } else {
    message("No metrics available for statistical testing.")
  }

  message("Done. Plots written to ", out_dir)
}
# check_mppca_effect(0.06)
check_mppca_effect(1.0)

