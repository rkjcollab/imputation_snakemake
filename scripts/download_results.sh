#!/bin/bash

# Use imputationbot to download results.
# Need version 1 for TOPMed imputation, version 2 for Michigan

# Set up instance automatically, based on
# https://github.com/UW-GAC/primed-imputation/blob/main/register_token.sh

# Parse args
while getopts "i:c:o:j:" opt; do
  case $opt in
    i) imp="$OPTARG" ;;
    c) code_dir="$OPTARG" ;;
    o) out_dir="$OPTARG" ;;
    j) job_id="$OPTARG" ;;
    \?) usage ;;
  esac
done

# Setup instance
cd "$code_dir"
export TOPMED_API=$(python -c "import config.key as k; print(k.TOPMED_API)")
export MICH_API=$(python -c "import config.key as k; print(k.MICH_API)")

# TODO: revisit avoid re-downloading every time
mkdir ~/.imputationbot
if [ "$imp" = "topmed" ]; then
    echo "Downloading imputationbot version for TOPMed."
    curl -sL https://raw.githubusercontent.com/lukfor/imputationbot/c752684bf8edaeb115e929f98206856d6ec27ac7/install/github-downloader-v2.sh | bash
    printf -- "-  hostname: https://imputation.biodatacatalyst.nhlbi.nih.gov\n   token: " > ~/.imputationbot/imputationbot.instances
    echo $TOPMED_API >> ~/.imputationbot/imputationbot.instances
else
    echo "Downloading imputationbot version for Michigan imputation."
    curl -sL https://raw.githubusercontent.com/lukfor/imputationbot/c752684bf8edaeb115e929f98206856d6ec27ac7/install/github-downloader-v2.sh | bash
    printf -- "-  hostname: https://imputationserver.sph.umich.edu\n   token: " > ~/.imputationbot/imputationbot.instances
    echo $MICH_API >> ~/.imputationbot/imputationbot.instances
fi

# Download results
cd "$out_dir"
echo "Starting download."
echo "$job_id"
imputationbot download "$job_id"
