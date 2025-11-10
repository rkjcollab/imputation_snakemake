#!/usr/bin/env Rscript

library(argparse)
suppressPackageStartupMessages(library(tidyverse))

parser <- ArgumentParser(
  description = "Rscript sex_check.R run by create_initial_input.sh.")

parser$add_argument(
  "-s", "--sexcheck", help="PLINK2 .sexcheck file path (required)", required=TRUE)
parser$add_argument(
  "-m", "--min-male-xf", help="Threshold for minimum male XF (required)", required=TRUE)
parser$add_argument(
  "-f", "--max-female-xf", help="Threshold for maximum female XF (required)", required=TRUE)
parser$add_argument(
  "-l", "--log", help="Create initial input log file (required)", required=TRUE)

args <- parser$parse_args()

# Sex check --------------------------------------------------------------------

#TODO: temp for testing!
# sexcheck <- read.delim(
#   "/Users/slacksa/temp_data/daisy/new_tm_imp_test/pre_qc/tmp_sexcheck.sexcheck")
# min_male_xf <- 0.8
# max_female_xf <- 0.2
sexcheck <- read.delim(args$sexcheck)
min_male_xf <- as.numeric(args$min_male_xf)
max_female_xf <- as.numeric(args$max_female_xf)

sexcheck$sex <- ifelse(
  sexcheck$F > min_male_xf, "Male",ifelse(sexcheck$F < max_female_xf, "Female",NA))

plot_sexcheck <- ggplot(sexcheck, aes(x = F, fill = sex)) +
  geom_histogram(bins = 50, color = "black") +
  scale_fill_manual(values = c("Female" = "tomato", "Male" = "steelblue")) +
  labs(fill = "Sex") + 
  theme_minimal() + 
  geom_vline(xintercept = max_female_xf, linetype = "dashed", color = "tomato") + 
  geom_vline(xintercept = min_male_xf, linetype = "dashed", color = "steelblue")

sexcheck_err <- sexcheck %>%
  dplyr::filter(STATUS != "OK") %>%
  dplyr::mutate(case = case_when(
    PEDSEX == 1 & SNPSEX == 2 ~ "mislab_male",
    PEDSEX == 2 & SNPSEX == 1 ~ "mislab_female",
    is.na(SNPSEX) ~ "outside_f_thresh"
  ))

sexcheck_err_1 <- sexcheck_err %>%
  dplyr::filter(case == "mislab_male")
log_entry_1 <- data.frame(
  Category = "Sex-Specific",
  Description = "Remove samples mislabeled as male",
  Samples = paste0("(", nrow(sexcheck_err_1), ")"),
  SNPs = "()",
  stringsAsFactors = FALSE)

sexcheck_err_2 <- sexcheck_err %>%
  dplyr::filter(case == "mislab_female")
log_entry_2 <- data.frame(
  Category = "Sex-Specific",
  Description = "Remove samples mislabeled as female",
  Samples = paste0("(", nrow(sexcheck_err_2), ")"),
  SNPs = "()",
  stringsAsFactors = FALSE)

sexcheck_err_3 <- sexcheck_err %>%
  dplyr::filter(case == "outside_f_thresh")
log_entry_3 <- data.frame(
  Category = "Sex-Specific",
  Description = "Remove samples outside X-chr F thresholds",
  Samples = paste0("(", nrow(sexcheck_err_3), ")"),
  SNPs = "()",
  stringsAsFactors = FALSE)

# Write out --------------------------------------------------------------------

path <- dirname(args$sexcheck)
ggsave(
  paste0(path, "/sexcheck_plot.png"),
  plot_sexcheck,
  units = "in", width = 7, height = 5)

out_path <- paste0(gsub("\\.sexcheck", "", args$sexcheck), "_rm.txt")
write.table(
  sexcheck_err %>% dplyr::select(`X.FID`, IID),
  file = out_path,
  sep="\t",
  quote=F,
  row.names=F,
  col.names=F)

write.table(
  rbind(log_entry_1, log_entry_2, log_entry_3),
  file = args$log,
  sep = "\t",
  quote = F,
  row.names = F,
  col.names = F,
  append = T)
