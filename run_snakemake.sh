#!/bin/bash

set -e
set -u

# Help message
usage() {
    echo "Usage: $0 -s <step> -f <config> [-d] [-c <cores>] [-h]"
    echo "Options:"
    echo "  -s  Step to run (required): submit_initial_input, submit_fix_strands, unzip_results, or filter_info_and_vcf_files"
    echo "  -f  Path to config file"
    echo "  -d  Run snakemake --dry-run"
    echo "  -c  Number of cores to use (default: 6)"
    echo "  -h  Show this help message"
    exit 1
}

# Run help message if no args given
if [ "$#" -eq 0 ]; then
    usage
fi

# Default args
dry_run=0
local=0
n_cores=6

# Parse args
while getopts "s:f:c:dh" opt; do
  case $opt in
    s) step="$OPTARG" ;;
    f) config="$OPTARG" ;;
    d) dry_run=1 ;;
    c) n_cores="$OPTARG" ;;
    h) usage ;;
    \?) usage ;;
  esac
done

# Set dry-run flag
if [ "$dry_run" -eq 1 ]; then
    dry_flag="--dry-run"
else
    dry_flag=""
fi

# Get info about config file path passed in
config_name=$(basename "$config")
config_path=$(dirname "$config")

# Get values set in config file
plink_prefix=$(yq '.plink_prefix' "$config")
plink_dir=$(dirname "$plink_prefix")
id_list_hwe=$(yq '.id_list_hwe' "$config")
id_list_hwe_dir=$(dirname "$id_list_hwe")
out_dir=$(yq '.out_dir' "$config")
repo=$(yq -r '.repo' "$config")
plink_dir_cont=$(yq '.plink_dir_cont' "$config")
id_list_hwe_dir_cont=$(yq '.id_list_hwe_dir_cont' "$config")
out_dir_cont=$(yq '.out_dir_cont' "$config")
repo_cont=$(yq '.repo_cont' "$config")
use_cont=$(yq '.use_cont' "$config")

if [ "$use_cont" = "false" ]; then
    # Run snakemake on local machine
    # For SDS, first do mamba activate bcftools-vcftools-osx64-crossmap
    #TODO: automate mambe env?
    snakemake --rerun-triggers mtime --snakefile ${repo}/Snakefile \
        --configfile ${config_path}/${config_name} \
        --cores "$n_cores" "$step" $dry_flag
elif [ "$use_cont" = "true" ]; then
    # Run snakemake in container (default)
    #TODO: add this as argument option when need to unlock
    # snakemake --cleanup-metadata /output_data/pre_qc/* \
    # apptainer exec \
    #     --writable-tmpfs \
    #     --bind ${repo}:${repo_cont} \
    #     --bind ${config_path}:/proj_repo \
    #     --bind ${plink_dir}:${plink_dir_cont} \
    #     --bind ${id_list_hwe_dir}:${id_list_hwe_dir_cont} \
    #     --bind ${out_dir}:${out_dir_cont} \
    #     ${repo}/envs/topmed_imputation.sif \
    #     snakemake --unlock create_initial_input \
    #     --configfile /proj_repo/${config_name}
    apptainer exec \
        --writable-tmpfs \
        --bind ${repo}:${repo_cont} \
        --bind ${config_path}:/proj_repo \
        --bind ${plink_dir}:${plink_dir_cont} \
        --bind ${id_list_hwe_dir}:${id_list_hwe_dir_cont} \
        --bind ${out_dir}:${out_dir_cont} \
        ${repo}/envs/topmed_imputation.sif \
        snakemake --rerun-triggers mtime --snakefile ${repo}/Snakefile \
            --configfile /proj_repo/${config_name} \
            --cores "$n_cores" "$step" $dry_flag
else
    echo "Config file use_cont must be either true or false"
    exit
fi
