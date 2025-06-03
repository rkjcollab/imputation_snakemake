#!/bin/bash

# set -e
set -u

# Added getopts based on Sam's example: https://github.com/pozdeyevlab/gnomad-query/blob/main/bcftools_query.sh
while getopts p:o:c:n:b:h:t: opt; do
   case "${opt}" in
      p) plink_prefix=${OPTARG};;
      o) out_dir=${OPTARG};;
      c) code_dir=${OPTARG};;
      n) chr=${OPTARG};;
      b) orig_build=${OPTARG};;
      t) to_build=${OPTARG};;
      h) chr6_hwe=${OPTARG};;
      \?) echo "Invalid option -$OPTARG" >&2
      exit 1;;
   esac
done

# Remove SNPs with duplicate positions
plink --bfile $plink_prefix \
   --list-duplicate-vars suppress-first \
   --keep-allele-order \
   --out ${out_dir}/tmp_dupl_check
   
cat ${out_dir}/tmp_dupl_check.dupvar | sed -e '1d' | \
   cut -f4 > ${out_dir}/tmp_dupl_snpids.txt
plink --bfile $plink_prefix \
   --exclude ${out_dir}/tmp_dupl_snpids.txt \
   --keep-allele-order \
   --make-bed --out ${out_dir}/tmp_no_dupl

# Check if liftover needed
orig_build_num=$(echo "$orig_build" | grep -o '[0-9]\+')
to_build_num=$(echo "$to_build" | grep -o '[0-9]\+')

if [ "$orig_build_num" != "$to_build_num" ]; then
   echo "Lifting over"
   #TODO: revisit and add builds to message

   # Create bed file to crossover from hg19 to hg38 
   cat ${out_dir}/tmp_no_dupl.bim | cut -f1 | sed 's/^/chr/' > ${out_dir}/tmp_c1.txt
   cat ${out_dir}/tmp_no_dupl.bim | cut -f4 > ${out_dir}/tmp_c2.txt
   cat ${out_dir}/tmp_no_dupl.bim | cut -f4 > ${out_dir}/tmp_c3.txt
   cat ${out_dir}/tmp_no_dupl.bim | cut -f2 > ${out_dir}/tmp_c4.txt
   paste  ${out_dir}/tmp_c1.txt \
         ${out_dir}/tmp_c2.txt \
         ${out_dir}/tmp_c3.txt \
         ${out_dir}/tmp_c4.txt \
         >  ${out_dir}/tmp_in.bed

   CrossMap bed ${code_dir}/hg${build_num}ToHg${to_build_num}.over.chain \
      ${out_dir}/tmp_in.bed  \
      ${out_dir}/tmp_out.bed

   # Extract only those SNPs that were successfully cross-overed
   cut -f4 ${out_dir}/tmp_out.bed > ${out_dir}/tmp_snp_keep.txt
   plink --bfile ${out_dir}/tmp_no_dupl \
      --extract ${out_dir}/tmp_snp_keep.txt \
      --keep-allele-order \
      --make-bed --out ${out_dir}/tmp_gwas

   # Update bim file positions
   Rscript --vanilla ${code_dir}/update_pos.R \
   ${out_dir}/tmp_out.bed ${out_dir}/tmp_gwas.bim

else 
   echo "Not lifting over"
   cp ${out_dir}/tmp_no_dupl.bim ${out_dir}/tmp_gwas.bim
   cp ${out_dir}/tmp_no_dupl.bed ${out_dir}/tmp_gwas.bed
   cp ${out_dir}/tmp_no_dupl.fam ${out_dir}/tmp_gwas.fam
fi

# Remove strand ambiguous SNPs
Rscript --vanilla ${code_dir}/get_strand_amb_SNPs.R ${out_dir}/tmp_no_dupl.bim
plink --bfile ${out_dir}/tmp_gwas \
   --exclude ${out_dir}/tmp_strand_remove_snps.txt \
   --keep-allele-order \
   --make-bed --out ${out_dir}/tmp_gwas_no_AT_CG

# Set all varids to chr:pos:ref:alt
plink2 --bfile ${out_dir}/tmp_gwas_no_AT_CG \
  --set-all-var-ids @:#:\$r:\$a --new-id-max-allele-len 100 \
  --make-pgen --out ${out_dir}/tmp_gwas_no_AT_CG_chrpos_ids

# Perform pre-imputation QC - remove monomorphic SNPs, SNPs with high
# missingness, SNPs not in HWE, & then reate vcf files for uploading
# to imputation server for QC
# Note that the encoding for chromosome is e.g. chr22, not 22

# If all chromosomes/regions should have same HWE
# if [ "$chr6_hwe" != "yes" ]; then
#    plink2 --pfile ${out_dir}/tmp_gwas_no_AT_CG_chrpos_ids \
#       --maf 0.000001 --geno 0.05 --hwe 0.000001 \
#       --make-bed --out ${out_dir}/pre_qc

#    # If preparing all chromosomes
#    if [ "$chr" == "all" ]
#    then
#       for ((chr_num=1; chr_num<=22; chr_num++)); do
#          plink --bfile ${out_dir}/pre_qc \
#             --chr $chr_num --keep-allele-order \
#             --recode vcf --out ${out_dir}/tmp_chr${chr_num}
#          if [ "$to_build_num" == "38" ]; then
#             vcf-sort ${out_dir}/tmp_chr${chr_num}.vcf | \
#                sed -E 's/^([0-9XYM]+)/chr\1/' | \
#                bgzip -c > ${out_dir}/chr${chr_num}_pre_qc.vcf.gz
#          else
#                vcf-sort ${out_dir}/tmp_chr${chr_num}.vcf | \
#                sed -E 's/^chr([0-9XYM]+)/\1/' | \
#                bgzip -c > ${out_dir}/chr${chr_num}_pre_qc.vcf.gz
#          fi
#       done
#    # If preparing only one chromosome
#    else
#       plink --bfile ${out_dir}/pre_qc \
#             --chr $chr --keep-allele-order \
#             --recode vcf --out ${out_dir}/tmp_chr${chr}
#       if [ "$to_build_num" == "38" ]; then
#          vcf-sort ${out_dir}/tmp_chr${chr}.vcf | \
#             sed -E 's/^([0-9XYM]+)/chr\1/' | \
#             bgzip -c > ${out_dir}/chr${chr}_pre_qc.vcf.gz
#       else
#          vcf-sort ${out_dir}/tmp_chr${chr}.vcf | \
#             sed -E 's/^chr([0-9XYM]+)/\1/' | \
#             bgzip -c > ${out_dir}/chr${chr}_pre_qc.vcf.gz
#       fi
#    fi
# # If chromosome 6 MHC region should have different HWE
# elif [ "$chr6_hwe" == "yes" ]; then
for c in $chr; do

   if [ "$c" == "6" ]; then
      echo "Processing chr6 with HWE 1e-20."
      # Get chr6 MHC region from Paul Norman's coordinates
      start=$(head -n 1 mhc_extended_${build}.bed | awk -F':' '{gsub(/-.*/, "", $2); print $2}')
      stop=$(tail -n 1 mhc_extended_${build}.bed | awk -F':' '{gsub(/-.*/, "", $2); print $2}')

      plink2 --pfile ${out_dir}/tmp_gwas_no_AT_CG_chrpos_ids --chr 6 \
         --from-bp $start --to-bp $stop \
         --make-pgen --out ${out_dir}/tmp_mhc

      # Get all chr6 SNPs not in region
      awk '/^#/ {next} {print $3}' ${out_dir}/tmp_mhc.pvar > \
         ${out_dir}/chr6_mhc_var_id_list.txt

      plink2 --pfile ${out_dir}/tmp_gwas_no_AT_CG_chrpos_ids --chr 6 \
         --exclude ${out_dir}/chr6_mhc_var_id_list.txt \
         --make-pgen --out ${out_dir}/tmp_non_mhc

      # Apply QC
         plink2 --pfile ${out_dir}/tmp_mhc \
         --maf 0.000001 --geno 0.05 --hwe 1e-20 \
         --make-bed --out ${out_dir}/tmp_mhc_pre_qc

      plink2 --pfile ${out_dir}/tmp_non_mhc \
         --maf 0.000001 --geno 0.05 --hwe 1e-6 \
         --make-bed --out ${out_dir}/tmp_non_mhc_pre_qc
   
      # Merge chr6 back together
      plink --bfile ${out_dir}/tmp_mhc_pre_qc \
         --bmerge ${out_dir}/tmp_non_mhc_pre_qc \
         --keep-allele-order \
         --make-bed --out ${out_dir}/chr6_pre_qc
   else
      echo "Processing chr$c with HWE 1e-6."
         plink2 --pfile ${out_dir}/tmp_gwas_no_AT_CG_chrpos_ids \
         --maf 0.000001 --geno 0.05 --hwe 0.000001 \
         --not-chr 6 \
         --make-bed --out ${out_dir}/chr${c}_pre_qc
      
      #TODO: finish here! NEed to add merge of all chr after this!

      # Need to write out pre_qc with all chr for next pipeline step
      plink --bfile ${out_dir}/non_chr6_pre_qc \
         --bmerge ${out_dir}/chr6_pre_qc \
         --keep-allele-order \
         --make-bed --out ${out_dir}/pre_qc

      for ((chr_num=1; chr_num<=22; chr_num++)); do
         plink --bfile ${out_dir}/pre_qc \
            --chr $chr_num --keep-allele-order \
            --recode vcf --out ${out_dir}/tmp_chr${chr_num}
         if [ "$to_build_num" == "38" ]; then
            vcf-sort ${out_dir}/tmp_chr${chr_num}.vcf | \
               sed -E 's/^([0-9XYM]+)/chr\1/' | \
               bgzip -c > ${out_dir}/chr${chr_num}_pre_qc.vcf.gz
         else
            vcf-sort ${out_dir}/tmp_chr${chr_num}.vcf | \
               sed -E 's/^chr([0-9XYM]+)/\1/' | \
               bgzip -c > ${out_dir}/chr${chr_num}_pre_qc.vcf.gz
         fi

      done
   # If preparing only chr6
   else
      # Need to write out pre_qc for next pipeline step
      plink --bfile ${out_dir}/chr6_pre_qc \
         --keep-allele-order \
         --make-bed --out ${out_dir}/pre_qc

      plink --bfile ${out_dir}/pre_qc \
         --chr $chr --keep-allele-order \
         --recode vcf --out ${out_dir}/tmp_chr${chr}

      if [ "$to_build_num" == "38" ]; then
         vcf-sort ${out_dir}/tmp_chr${chr}.vcf | \
            sed -E 's/^([0-9XYM]+)/chr\1/' | \
            bgzip -c > ${out_dir}/chr${chr}_pre_qc.vcf.gz
      else
         vcf-sort ${out_dir}/tmp_chr${chr}.vcf | \
            sed -E 's/^chr([0-9XYM]+)/\1/' | \
            bgzip -c > ${out_dir}/chr${chr}_pre_qc.vcf.gz
      fi
   fi
fi

# Report SNP counts
orig_snp_nr=`wc -l ${plink_prefix}.bim`
crossover_snp_nr=`wc -l ${out_dir}/tmp_gwas.bim`
nonamb_snp_nr=`wc -l ${out_dir}/tmp_gwas_no_AT_CG.bim`
echo "Original SNP nr: $orig_snp_nr"
echo "Crossovered SNP nr: $crossover_snp_nr"
echo "Non-ambiguous SNP nr: $nonamb_snp_nr"
echo "Original SNP nr: $orig_snp_nr" > ${out_dir}/create_initial_input_log.txt
echo "Crossovered SNP nr: $crossover_snp_nr" >> ${out_dir}/create_initial_input_log.txt
echo "Non-ambiguous SNP nr: $nonamb_snp_nr" >> ${out_dir}/create_initial_input_log.txt

if [ "$chr6_hwe" != "yes" ]
then
   qc_snp_nr=`wc -l ${out_dir}/pre_qc.bim`
   echo "Final SNP nr after QC: $qc_snp_nr"
   echo "Final SNP nr after QC: $qc_snp_nr" >> ${out_dir}/create_initial_input_log.txt
   
else
   qc_snp_nr_mhc=`wc -l ${out_dir}/tmp_mhc_pre_qc.bim`
   qc_snp_nr_non_mhc=`wc -l ${out_dir}/tmp_non_mhc_pre_qc.bim` 
   echo "Final chr6 MHC SNP nr after QC: $qc_snp_nr_mhc"
   echo "Final chr6 non-MHC SNP nr after QC: $qc_snp_nr_non_mhc"
   echo "Final chr6 MHC SNP nr after QC: $qc_snp_nr_mhc" >> \
      ${out_dir}/create_initial_input_log.txt
   echo "Final chr6 non-MHC SNP nr after QC: $qc_snp_nr_non_mhc" >> \
      ${out_dir}/create_initial_input_log.txt
   
   if [ "$chr" == "all" ]
   then
      qc_snp_nr_non_chr6=`wc -l ${out_dir}/non_chr6_pre_qc.bim`
      echo "Final all other chr (non-chr6) SNP nr after QC: $qc_snp_nr_non_chr6"
      echo "Final all other chr (non-chr6) SNP nr after QC: $qc_snp_nr_non_chr6" >> \
         ${out_dir}/create_initial_input_log.txt
   fi
fi

# Cleanup
rm ${out_dir}/tmp_*
