
#!/bin/bash
# run_pipeline.sh

# apptainer exec \
#     --bind $(pwd):/project \
#     topmed_imputation.sif \
#     snakemake --directory /project --cores 4 "$@"

# This is currently called from top-level of topmed_imputation_update,
# and inside of the limactl amd64
apptainer exec \
    --writable-tmpfs \
    --bind /Users/slacksa/repos/topmed_imputation_update:/repo \
    --bind /Users/slacksa/tm_test_data:/data \
    topmed_imputation.sif \
    snakemake --snakefile /repo/Snakefile --configfile /repo/config.yml \
        --cores 8 --directory /data --until create_initial_input

# For testing container without snakefile
# apptainer shell \
#     --writable-tmpfs \
#     --bind /Users/slacksa/repos/topmed_imputation_update:/repo \
#     --bind /Users/slacksa/tm_test_data:/data \
#     topmed_imputation.sif

# Test outside of container & without snakefile
# bash create_initial_input.sh \
#     -p /Users/slacksa/tm_test_data/input/daisyexome \
#     -o /Users/slacksa/tm_test_data \
#     -c "21" \
#     -b "hg38" \
#     -h "hwe"