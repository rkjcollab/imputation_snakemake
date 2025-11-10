#!/usr/bin/env Rscript

library(argparse)
suppressPackageStartupMessages(library(tidyverse))

parser <- ArgumentParser(
  description = "Rscript filt_chrX_het.R run by create_initial_input.sh.")

# parser$add_argument(
#   "-h", "--hetx", help="PLINK .hardy.x file path (required)", required=TRUE)
parser$add_argument(
  "-i", "--hh", help="PLINK1.9 .hh file path (required)", required=TRUE)
parser$add_argument(
  "-m", "--n-male", help="Number males in dataset (required)", required=TRUE)
parser$add_argument(
  "-p", "--perc-het", help="Percent (0-100) heterozygosity threshold (required)", required=TRUE)
parser$add_argument(
  "-l", "--log", help="Create initial input log file (required)", required=TRUE)

args <- parser$parse_args()

# chrX Heterozygosity ----------------------------------------------------------

#TODO: previous method - delete?
#TODO: temp for testing!
# hetx <- read.delim(
#   "/Users/slacksa/temp_data/daisy/new_tm_imp_test/pre_qc/tmp_chrX_het.hardy.x")
# hetx <- read.delim(args$hetx)
# 
# # het = male non-A1 alelle count / (male non-A1 allele count + male A1 allele count)
# hetx$het <- hetx$MALE_AX_CT/(hetx$MALE_AX_CT + hetx$MALE_A1_CT) * 100

# Use PLINK1.9's .hh file:
  # Produced automatically when the input data contains heterozygous calls where
  # they shouldn't be possible (haploid chromosomes, male X/Y), or there are
  # nonmissing calls for nonmales on the Y chromosome. A text file with one line
  # per error (sorted primarily by variant ID, secondarily by sample ID) with
  # the following three fields: FID, IID, variant ID
#TODO: temp for testing!
# hh <- read.delim(
#   "/Users/slacksa/temp_data/daisy/new_tm_imp_test/pre_qc/tmp_chrX_het_male_2.hh",
#   col.names = c("FID", "IID", "ID"))
# n_male <- 376
hh <- read.delim(args$hh, col.names = c("FID", "IID", "ID"))
n_male <- as.numeric(args$n_male)
perc_het <- as.numeric(args$perc_het)

hh_summ <- hh %>%
  dplyr::group_by(ID) %>%
  dplyr::summarize(ID_count = n()) %>%
  dplyr::mutate(het_perc = ID_count / n_male)

hh_summ_rm <- hh_summ %>%
  dplyr::filter(het_perc > (perc_het / 100))
hh_summ_rm_ct = length(unique(hh_summ_rm$ID))

log_entry <- data.frame(
  Category = "Sex-Specific",
  Description = paste0("Remove X-chr SNPs with heterozygosity >", perc_het, "% in males"),
  Samples = "()",
  SNPs = paste0("(", hh_summ_rm_ct, ")"),
  stringsAsFactors = FALSE)

# Write out --------------------------------------------------------------------

out_path <- paste0(gsub("\\.hh", "", args$hh), ".txt")
write.table(
  hh_summ_rm$ID,
  file = out_path,
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
