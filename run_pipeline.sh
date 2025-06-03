
#!/bin/bash

# This is currently called from top-level of topmed_imputation_update,
# and inside of the limactl amd64.
# Set paths and options in config.yml file. Paths are automatically 
# relative to snakefile location (unless --directory is set)
apptainer exec \
    --writable-tmpfs \
    --bind /Users/slacksa/repos/imputation_snakemake:/repo \
    --bind /Users/slacksa/tm_test_data:/data \
    envs/topmed_imputation.sif \
    snakemake --snakefile /repo/Snakefile --configfile /repo/config.yml \
        --cores 8 --until fix_strands


# Current process
# 1. run create_initial_input
# 2. manually upload VCFs
# 3. manually download VCFs to pre_qc folder
# 4. run fix_strands


# For testing container without snakefile
# apptainer shell \
#     --writable-tmpfs \
#     --bind /Users/slacksa/repos/imputation_snakemake:/repo \
#     --bind /Users/slacksa/tm_test_data:/data \
#     topmed_imputation.sif

# Test outside of container & without snakefile
# bash scripts/create_initial_input.sh \
#     -p /Users/slacksa/tm_test_data/input/daisyexome \
#     -o /Users/slacksa/tm_test_data/pre_qc \
#     -c "6 21 22" \
#     -b "hg38" \
#     -t "hg19"