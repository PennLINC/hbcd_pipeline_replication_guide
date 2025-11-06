# Get command line arguments
args <- commandArgs(trailingOnly = TRUE)

# CHANGE THIS!!
repro_dir <- "/cbica/projects/hbcd_dev/rep2"

# Check if enough arguments are provided
if (length(args) < 4) {
  stop("Usage: Rscript model_scalar.R <h5_file> <cohort_csv> <num_cpus>")
}
library(ModelArray)
ma_root <- paste0(repro_dir, "/volumetric/modelarray")

scalar_name <- args[1]
ma_h5  <- args[2]
ma_cohort <- args[3]
n_cpus <- as.numeric(args[4])

ma <- ModelArray(ma_h5, scalar_types=scalar_name)
phenotypes <- read.csv(ma_cohort, header=TRUE)
phenotypes$Manufacturer <- factor(
    phenotypes$Manufacturer,
    levels=c("Siemens", "GE", "Philips"))
model_str <- " ~ Manufacturer + scans_gestational_age + raw_neighbor_corr"
formula_lm <- as.formula(paste0(scalar_name, model_str))

ma_lm <- ModelArray.lm(formula_lm, ma, phenotypes, scalar_name, n_cores=n_cpus)
writeResults(ma_h5, df.output=ma_lm, analysis_name="results_lm")



