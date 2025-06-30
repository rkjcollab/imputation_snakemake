#!/bin/bash

#Set arguments
if [ "$#" -eq  "0" ]
then
   echo "Usage: ${0##*/} <chr> <rsq> <maf> <in_dir> <out_dir>"
   echo "Script filters new TOPMed INFO files formatted as VCFs."
   echo "Keeps TYPED or IMPUTED with Rsq less than given threshold,"
   echo "and filters MAF to given threshold."
   echo "Script expects file formats: chr#.dose.vcf.gz & chr#.info.gz"
   exit
fi

# TO NOTE: this script does not use PLINK, so preserves all dosage information
# in imputed VCF (helpful for keeping HDS after Michigan HLA imputation). This
# also means that it is MUCH slower than the other script, and the other
# script should be run if only GT is needed.

chr=$1
rsq=$2
maf=$3
in_dir=$4
out_dir=$5

# Make all out dirs
mkdir "${out_dir}"

# Set filter
to_filt="((INFO/TYPED = 1 | (INFO/IMPUTED = 1 & INFO/R2 > ${rsq})) & INFO/MAF > ${maf})"

# Filter INFO file, for smaller output with kept variables
    # ((typed OR (imputed & R2)) & MAF)
bcftools filter -i \
    "$to_filt" \
    "${in_dir}/chr${chr}.info.gz" -o "${out_dir}/chr${chr}_clean.info"

# Write out list of RSIDs want to keep
snp_list="${out_dir}/chr${chr}_maf${maf}_rsq${rsq}_snps.txt"
bcftools query -f '%ID\n' \
    "${out_dir}/chr${chr}_clean.info" > "$snp_list"

# Filter VCF to these IDs using bcftools
bcftools view --include ID==@"$snp_list" "${in_dir}/chr${chr}.dose.vcf.gz" \
    -Oz -o "${out_dir}/tmp_chr${chr}_clean.vcf.gz"

# Finally, clean up RSIDs that may have appeared more than once, mainly '.' IDs.
bcftools filter -i \
    "$to_filt" \
    "${out_dir}/tmp_chr${chr}_clean.vcf.gz" -o "${out_dir}/chr${chr}_clean.vcf.gz"
tabix "${out_dir}/chr${chr}_clean.vcf.gz"

# Clean up
rm -f ${out_dir}/tmp_*
