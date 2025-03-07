#!/bin/bash

#Set arguments
if [ "$#" -lt  6 ]
then
    echo "Usage: ${0##*/} <pre_qc_dir> <post_qc_dir> <code_dir> <chr> <imp_server>"
    echo "Script uses output from TOPMed pre-imputation QC to fix strand"
    echo "flips. If "chr" input = "all", then the script will create one"
    echo "VCF file per chr. Otherwise, must be a single chr number '1',"
    echo "'2', etc. This script should follow create_initial_input (with"
    echo "or without crossover)."
    exit
fi

pre_qc_dir=$1
post_qc_dir=$2
code_dir=$3
chr=$4
build=$5  # should be "hg19" or "hg38"
imp_server=$6  # should be "mich" or "tm"
# TODO: should I just maintain separate repo for Michigan pipelines?
# TODO: need to update to make all out dirs

mkdir "$post_qc_dir"

#Get list of SNPs to flip
Rscript --vanilla ${code_dir}/get_strand_flip_snp_names.R $pre_qc_dir $post_qc_dir $imp_server

#Create vcf files for uploading to imputation server for QC
process_chr() {
    chr=$1

    # Flip strands for strand flip & strand flip and allele switch
    plink --bfile ${pre_qc_dir}/pre_qc \
        --flip ${post_qc_dir}/tmp_flip.txt \
        --chr $chr --make-bed --keep-allele-order \
        --out ${post_qc_dir}/tmp_chr${chr}_flip
    # Fix allele switches after flip
    plink --bfile ${post_qc_dir}/tmp_chr${chr}_flip \
        --a2-allele ${post_qc_dir}/tmp_a2-allele.txt \
        --chr $chr --make-bed --keep-allele-order \
        --out ${post_qc_dir}/tmp_chr${chr}_flip_switch
    # Fix allele switches only
    plink --bfile ${post_qc_dir}/tmp_chr${chr}_flip_switch \
        --a2-allele ${post_qc_dir}/tmp_a2-allele_switch_only.txt \
        --chr $chr --recode vcf --keep-allele-order \
        --out ${post_qc_dir}/tmp_chr${chr}_flip_switch_both
    if [ "$build" == "hg38" ]; then
        vcf-sort ${post_qc_dir}/tmp_chr${chr}_flip_switch_both.vcf | \
            sed -E 's/^([0-9XYM]+)/chr\1/' | \
            bgzip -c > ${post_qc_dir}/chr${chr}_post_qc.vcf.gz
    elif [ "$build" == "hg19" ]; then
        vcf-sort ${post_qc_dir}/tmp_chr${chr}_flip_switch_both.vcf | \
            sed -E 's/^chr([0-9XYM]+)/\1/' | \
            bgzip -c > ${post_qc_dir}/chr${chr}_post_qc.vcf.gz
    fi
}

# If chr = "all", then create one VCF file per chr, otherwise
# chr must equal one chr number, so only make that VCF file
if [ "$chr" == "all" ]
then
    for ((chr=1; chr<=22; chr++)); do
        process_chr $chr
    done
else
    process_chr $chr
fi

#Cleanup
rm ${post_qc_dir}/tmp_*
