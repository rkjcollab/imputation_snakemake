#!/bin/bash

set -e
set -u

while getopts o:c:t:i: opt; do
   case "${opt}" in
      o) out_dir=${OPTARG};;
      c) chr=${OPTARG};;
      t) to_build=${OPTARG};;
      i) imp=${OPTARG};;
      \?) echo "Invalid option -$OPTARG" >&2
      exit 1;;
   esac
done

# Convert to array
chr=($chr)

#Get list of SNPs to flip
Rscript --vanilla scripts/get_strand_flip_snp_names.R \
    ${out_dir}/pre_qc ${out_dir}/post_qc $imp

#Create vcf files for uploading to imputation server for QC
to_build_num=$(echo "$to_build" | grep -o '[0-9]\+')

process_chr() {
    c=$1

    # Flip strands for strand flip & strand flip and allele switch
    plink --bfile ${out_dir}/pre_qc/pre_qc \
        --flip ${out_dir}/post_qc/tmp_flip.txt \
        --chr $c --make-bed --keep-allele-order \
        --out ${out_dir}/post_qc/tmp_chr${c}_flip
    # Fix allele switches after flip
    plink --bfile ${out_dir}/post_qc/tmp_chr${c}_flip \
        --a2-allele ${out_dir}/post_qc/tmp_a2-allele.txt \
        --chr $c --make-bed --keep-allele-order \
        --out ${out_dir}/post_qc/tmp_chr${c}_flip_switch
    # Fix allele switches only
    plink --bfile ${out_dir}/post_qc/tmp_chr${c}_flip_switch \
        --a2-allele ${out_dir}/post_qc/tmp_a2-allele_switch_only.txt \
        --chr $c --recode vcf --keep-allele-order \
        --out ${out_dir}/post_qc/tmp_chr${c}_flip_switch_both
    if [ "$to_build_num" = "38" ]; then
        vcf-sort ${out_dir}/post_qc/tmp_chr${c}_flip_switch_both.vcf | \
            sed -E 's/^([0-9XYM]+)/chr\1/' | \
            bgzip -c > ${out_dir}/post_qc/chr${c}_post_qc.vcf.gz
    elif [ "$to_build_num" = "19" ]; then
        vcf-sort ${out_dir}/post_qc/tmp_chr${c}_flip_switch_both.vcf | \
            sed -E 's/^chr([0-9XYM]+)/\1/' | \
            bgzip -c > ${out_dir}/post_qc/chr${c}_post_qc.vcf.gz
    fi
}

# If chr = "all", then create one VCF file per chr, otherwise
# chr must equal one chr number, so only make that VCF file
for c in "${chr[@]}"; do
    process_chr $c
done

#Cleanup
rm ${out_dir}/post_qc/tmp_*
