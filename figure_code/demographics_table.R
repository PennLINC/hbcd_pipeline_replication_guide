source("shared_config.R")

# Create descriptive summaries by session
demos %>%
  group_by(session_id) %>%
  summarise(
    n_subjects = n(),
    age_mean = sprintf("%.1f (%.1f)", mean(age), sd(age)),
    age_min = round(min(age), 2),
    age_max = round(max(age), 2)
  ) %>%
  flextable() %>%
  set_header_labels(
    session_id = "Session",
    n_subjects = "N",
    age_mean = "Mean Age (SD)",
    age_min = "Min Age",
    age_max = "Max Age"
  ) %>%
  theme_vanilla() %>%
  fontsize(size = 10, part = "all") %>%
  align(j = 2:5, align = "right") %>%
  bold(part = "header") %>%
  set_caption("Summary Statistics by Session") %>%
  autofit() %>%
  width(j = 1, width = 0.7) %>% # Reduce Session column width
  width(j = 2, width = 0.7) %>% # Adjust N column width
  width(j = 3:5, width = 1.2) %>% # Set consistent width for numeric columns
  save_as_docx(path = "session_summary_statistics.docx")
