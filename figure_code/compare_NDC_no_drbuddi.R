#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(tidyr)
  library(readr)
  library(stringr)
  library(tools)
})

setwd("figure_code")


check_drbuddi_effect <- function(dice_max) {
  # Load shared plotting config (provides SCANNER_COLORS)
  source(file.path("shared_config.R"))

  base_csv <- file.path("hbcd_complete_qc_demographics.csv")
  alt_csv <- file.path("no_drbuddi_qc_1.0.0.csv")
  out_dir <- file.path(".")
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  message(paste("Checking DRBUDDI effect for dice max:", dice_max))

  filter_outliers <- function(df_path) {
    df <- read_csv(df_path, show_col_types = FALSE)

    message(paste("Filtering outliers for dice max:", dice_max))
    df <- df %>%
      filter(t1_dice_distance <= dice_max)
    message(paste("Number of rows after filtering outliers for dice max:", dice_max, ":", nrow(df)))
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

  ## Helper: manufacturer column extraction
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

  # Build plotting data for ONLY t1_neighbor_corr
  base_col <- "t1_neighbor_corr_base"
  alt_col  <- "t1_neighbor_corr_alt"
  if (!(base_col %in% colnames(merged) && alt_col %in% colnames(merged))) {
    stop("Required columns for t1_neighbor_corr not found after merge.")
  }
  df_plot <- merged %>%
    transmute(
      base = .data[[base_col]],
      alt = .data[[alt_col]],
      Manufacturer = get_manufacturer(merged)
    )



  if (nrow(df_plot) > 0) {
    p_ndc <- ggplot(df_plot, aes(x = alt, y = base, color = Manufacturer)) +
      geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "gray50") +
      geom_point(alpha = 0.6, size = 0.8) +
      scale_color_manual(values = SCANNER_COLORS, drop = FALSE) +
      labs(x = "TOPUP Only", y = "TOPUP+DRBUDDI", color = "Manufacturer") +
      plot_theme_double_col +
      theme(legend.position = "bottom")

    ggsave(file.path(out_dir, paste0("drbuddi_ndc_scatter_dice-max", dice_max, ".svg")), p_ndc, width = 7, height = 5, units = "in")
  } else {
    message("No metrics available for faceted scatter plot.")
  }

  # Build summary statistics/tests for NDC only
  tests_df <- test_metric("t1_neighbor_corr")
  if (!is.null(tests_df)) tests_df <- dplyr::bind_rows(tests_df) else tests_df <- dplyr::bind_rows()
  if (nrow(tests_df) > 0) {
    out_csv_tests <- file.path(out_dir, paste0("drbuddi_ndc_metric_tests_summary_dice-max", dice_max, ".csv"))
    readr::write_csv(tests_df, out_csv_tests)
    print(tests_df)
    message("Wrote ", out_csv_tests)
  } else {
    message("No metrics available for statistical testing.")
  }

  message("Done. Plots written to ", out_dir)
}
check_drbuddi_effect(0.06)
check_drbuddi_effect(1.0)
