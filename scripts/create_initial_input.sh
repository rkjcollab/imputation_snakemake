#!/bin/bash

set -e
set -u

# Added getopts based on Sam's example:
# https://github.com/pozdeyevlab/gnomad-query/blob/main/bcftools_query.sh
while getopts p:o:c:b:t: opt; do
   case "${opt}" in
      p) plink_prefix=${OPTARG};;
      o) out_dir=${OPTARG};;
      c) chr=${OPTARG};;
      b) orig_build=${OPTARG};;
      t) to_build=${OPTARG};;
      \?) echo "Invalid option -$OPTARG" >&2
      exit 1;;
   esac
done

# Code paths here are relative, assuming run from location of snakefile.
# Current code ALWAYS applies less strict HWE for chr6.

# Convert to array
chr=($chr)

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

   CrossMap bed refs/hg${orig_build_num}ToHg${to_build_num}.over.chain \
      ${out_dir}/tmp_in.bed  \
      ${out_dir}/tmp_out.bed

   # Extract only those SNPs that were successfully cross-overed
   cut -f4 ${out_dir}/tmp_out.bed > ${out_dir}/tmp_snp_keep.txt
   plink --bfile ${out_dir}/tmp_no_dupl \
      --extract ${out_dir}/tmp_snp_keep.txt \
      --keep-allele-order \
      --make-bed --out ${out_dir}/tmp_gwas

   # Update bim file positions
   Rscript --vanilla scripts/update_pos.R \
   ${out_dir}/tmp_out.bed ${out_dir}/tmp_gwas.bim

else 
   echo "Not lifting over"
   cp ${out_dir}/tmp_no_dupl.bim ${out_dir}/tmp_gwas.bim
   cp ${out_dir}/tmp_no_dupl.bed ${out_dir}/tmp_gwas.bed
   cp ${out_dir}/tmp_no_dupl.fam ${out_dir}/tmp_gwas.fam
fi

# Remove strand ambiguous SNPs
Rscript --vanilla scripts/get_strand_amb_SNPs.R ${out_dir}/tmp_no_dupl.bim
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
# to imputation server for QC.
for c in "${chr[@]}"; do
   if [ "$c" == "6" ]; then
      echo "Processing chr6 with HWE 1e-20."
      # Get chr6 MHC region from Paul Norman's coordinates
      start=$(head -n 1 refs/mhc_extended_hg${to_build_num}.bed | awk -F':' '{gsub(/-.*/, "", $2); print $2}')
      stop=$(tail -n 1 refs/mhc_extended_hg${to_build_num}.bed | awk -F':' '{gsub(/-.*/, "", $2); print $2}')

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
         --make-bed --out ${out_dir}/tmp_chr6_pre_qc
   else
      echo "Processing chr$c with HWE 1e-6."
         plink2 --pfile ${out_dir}/tmp_gwas_no_AT_CG_chrpos_ids \
         --maf 0.000001 --geno 0.05 --hwe 0.000001 \
         --chr "$c" \
         --make-bed --out ${out_dir}/tmp_chr${c}_pre_qc
   fi
done

# If multiple chrs being processed, prep for merge of all chr,
# which is needed to next pipeline step
if [ "${#chr[@]}" -gt 1 ]; then
   echo "Processing more than one chr."
   base_chr=${chr[0]}
   merge_list="${out_dir}/tmp_merge_list.txt"

   for c in "${chr[@]}"; do
      if [ "$c" != "$base_chr" ]; then
         echo "${out_dir}/tmp_chr${c}_pre_qc" >> "$merge_list"
      fi
   done

   # Merge all chr currently preparing
   plink --bfile ${out_dir}/tmp_chr${base_chr}_pre_qc \
      --merge-list "$merge_list" \
      --keep-allele-order \
      --make-bed --out ${out_dir}/pre_qc
else
   echo "Processing only one chr."
   plink --bfile ${out_dir}/tmp_chr${chr[0]}_pre_qc \
      --keep-allele-order \
      --make-bed --out ${out_dir}/pre_qc
fi

# Write out VCF files split by chr for imputation.
for c in "${chr[@]}"; do
   plink --bfile ${out_dir}/pre_qc \
      --chr $c --keep-allele-order \
      --recode vcf --out ${out_dir}/tmp_chr${c}
   if [ "$to_build_num" == "38" ]; then
      vcf-sort ${out_dir}/tmp_chr${c}.vcf | \
         sed -E 's/^([0-9XYM]+)/chr\1/' | \
         bgzip -c > ${out_dir}/chr${c}_pre_qc.vcf.gz
   else
      vcf-sort ${out_dir}/tmp_chr${c}.vcf | \
         sed -E 's/^chr([0-9XYM]+)/\1/' | \
         bgzip -c > ${out_dir}/chr${c}_pre_qc.vcf.gz
   fi
done

# Report SNP counts
orig_snp_nr=`wc -l ${plink_prefix}.bim`
echo "Original SNP nr: $orig_snp_nr"

if [ "$orig_build_num" != "$to_build_num" ]; then
   crossover_snp_nr=`wc -l ${out_dir}/tmp_gwas.bim`
   echo "Crossovered SNP nr: $crossover_snp_nr"
fi

nonamb_snp_nr=`wc -l ${out_dir}/tmp_gwas_no_AT_CG.bim`
echo "Non-ambiguous SNP nr: $nonamb_snp_nr"

# Report all chr prepared
qc_snp_nr=`wc -l ${out_dir}/pre_qc.bim`
echo "Final SNP nr after QC, subset to only processed chrs: $qc_snp_nr"
   
# Report details on just chr6, if prepared
if [[ " ${chr[@]} " =~ " 6 " ]]; then
   qc_snp_nr_mhc=`wc -l ${out_dir}/tmp_mhc_pre_qc.bim`
   qc_snp_nr_non_mhc=`wc -l ${out_dir}/tmp_non_mhc_pre_qc.bim` 
   echo "Final chr6 MHC SNP nr after QC: $qc_snp_nr_mhc"
   echo "Final chr6 non-MHC SNP nr after QC: $qc_snp_nr_non_mhc"

fi

# Cleanup
rm ${out_dir}/tmp_*
