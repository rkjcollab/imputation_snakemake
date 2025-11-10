#!/usr/bin/env Rscript

library(argparse)

parser <- ArgumentParser(
  description = "Rscript filt_mono.R run by create_initial_input.sh.")

parser$add_argument(
  "-a", "--afreq", help="PLINK2 .afreq file path (required)", required=TRUE)
parser$add_argument(
  "-l", "--log", help="Create initial input log file (required)", required=TRUE)

args <- parser$parse_args()

# Monomorphic variants ---------------------------------------------------------

#TODO: temp for testing!
# afreq <- read.delim(
#   "/Users/slacksa/temp_data/daisy/new_tm_imp_test/pre_qc/tmp_miss_mono.afreq")
afreq <- read.delim(args$afreq)

afreq_rm <- afreq[afreq$ALT_FREQS == 0, ]
afreq_rm_ct <- nrow(afreq_rm)

log_entry <- data.frame(
  Category = "Pre-Filtering",
  Description = "Remove monomorphic SNPs",
  Samples = "()",
  SNPs = paste0("(", afreq_rm_ct, ")"),
  stringsAsFactors = FALSE)

# Write out --------------------------------------------------------------------

path <- dirname(args$afreq)
write.table(
  afreq_rm$ID,
  file = paste0(path, "/tmp_mono_rm.txt"),
  sep="\t",
  quote=F,
  row.names=F,
  col.names=F)

write.table(
  log_entry,
  file = args$log,
  sep = "\t",
  quote = F,
  row.names = F,
  col.names = F,
  append = T)
