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

# Get values set in config file
plink_prefix=$(yq '.plink_prefix' "$config")
plink_dir=$(dirname "$plink_prefix")
out_dir=$(yq '.out_dir' "$config")
repo=$(yq '.repo' "$config")
proj_repo=$(yq '.proj_repo' "$config")

plink_dir_cont=$(yq '.plink_dir_cont' "$config")
out_dir_cont=$(yq '.out_dir_cont' "$config")
repo_cont=$(yq '.repo_cont' "$config")
proj_repo_cont=$(yq '.proj_repo_cont' "$config")

# Run snakemake in container
apptainer exec \
    --writable-tmpfs \
    --bind ${repo}:${repo_cont} \
    --bind ${proj_repo}:${proj_repo_cont} \
    --bind ${plink_dir}:${plink_dir_cont} \
    --bind ${out_dir}:${out_dir_cont} \
    ${repo}/envs/topmed_imputation.sif \
    snakemake --rerun-triggers mtime --snakefile ${repo}/Snakefile \
        --configfile "$config" \
        --cores "$n_cores" "$step" $dry_flag
