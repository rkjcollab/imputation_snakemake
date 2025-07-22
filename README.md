
## TODOs

* update below!
* add instructions for making apptainer
    *TODO: need to update apptainer to include yq, currently interactively installed:
    * sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
    *   -O /usr/local/bin/yq &&\
    *   sudo chmod +x /usr/local/bin/yq
    *TODO: update container to include software needed to view DAG
* add instructions for getting TOPMed API key and/or manual submit?
* add note that need to lift input data over to match reference panel
    build otherwise won't be able to use fix strands code.
* instead of step 2, could I make a script where user gives download link and 
    then auto-downloads to right spot in files?
* add checks that config values are only the allowable ones?
* add QA/tests from CSCI6118?
* revisit auto download before fix strands step
* add more documentation to python functions
* think could remove a config arg so that to_build is auto set based on chosen
    imputation
* not sure how to better handle relative paths within the pipeline directory?


## **imputation_snakemake**

Pipeline for imputing autosomal genetic array data with hg19 or hg38 coordinates
to the TOPMed r3 reference panel, the Michigian 1000 genomes phase 3 version 5
reference panel, or the Michigan HLA four-digit multi-ethnic v1 or v2 panels.

Adapted from Michelle Daya's topmed_imputation pipeline.

## Setup

### Apptainer

TODO: add directions to build from .def

### Conda Environment

TODO: make recipe file!

## Input Files

* Genetic array data in PLINK1.9 file format.

## How to Run

The bash script "run_pipeline.sh" includes an example of running all steps of the
pipeline. Each step is also described below. The only files that need to be edited
before running is "config.yml" and "run_pipeline.sh", if using.

### Step 0

Update "config.yml" with paths and settings specific to the data:

```
plink_prefix: "path/to/plink_prefix"
out_dir: "path/to/data"  # top-level directory for all output in container
code_dir: "path/to/imputation_snakemake"  # top-level of topmed_imputation repo in container
chr: [6,10,22]  # list of chromosome numbers with format [6,10,22]
orig_build: "hg19"  #  either "hg19" or "hg38"
to_build: "hg38"  # either "hg19" or "hg38"
imp:  "mich_hla_v2"  # should be 'topmed', 'mich_hla_v1', 'mich_hla_v2', 'mich_1kg_p3_v5'
```

Note that for TOPMed imputation, the 'population' option is set to 'all', which means allele
frequencies will be compared between the input data and the TOPMed panel to generate a QC
report. For Michigan imputation, the 'population' option is set to 'off', since (at least
for 1000G whole genome imputation) there is no good option for allele frequency comparison
for mixed populations. Either way, imputation results should not be affected.

### Step 1

Use the snakefile to run the pipeline through the "submit_initial_input" step:

```
apptainer exec \
    --writable-tmpfs \
    --bind /Users/slacksa/repos/imputation_snakemake:/repo \
    --bind /Users/slacksa/tm_test_data:/data \
    envs/topmed_imputation.sif \
    snakemake --snakefile /repo/Snakefile --configfile /repo/config.yml \
        --cores 8 --until submit_initial_input

```

This will create and upload the initial input files to the imputation server and panel
selected in the config file.

The pre-imputation QC includes liftover (if necessary), removal of strand ambiguous SNPs,
updating all variant IDs to chr:pos:ref:alt, filtering by PLINK2 --maf (1e-6), --geno (0.05),
and --hwe (1e-20 for chr6 MHC region, 1e-6 for all other regions/chromosomes). A summary of
each step is included in the log file.

## Step 2

Once the QC automatically submitted has run, you will receive an email. Log into the
imputation server, and download the snps-excluded.txt file to the same directory as the
pre-QC input files (this will be in directory called "pre_qc" in the "out_dir" provided in
the config file). It is a good idea to also download the typed-only.txt files and
chunks-excluded.txt files as well, in case you ever need to refer back to this.

## Step 3

Use the snakefile to run the pipeline through the "submit_fixed_strands" step:

```
apptainer exec \
    --writable-tmpfs \
    --bind /Users/slacksa/repos/imputation_snakemake:/repo \
    --bind /Users/slacksa/tm_test_data:/data \
    envs/topmed_imputation.sif \
    snakemake --snakefile /repo/Snakefile --configfile /repo/config.yml \
        --cores 8 --until submit_fixed_strands

```

This step flips strands of variants identified as such in the snps-exlcuded.txt file - this
will produce the final post QC VCF files for imputation.

## Step 4

Upload the output post QC VCF files from Step 3 to the Michigan imputation server for
imputation against the TOPMed reference panel

* Select Array Build GRCh38/hg38 
* Skip the QC frequency check 
* Select Quality Control and imputation

## Step 5

The imputation server will send an email with a download link once the
imputations are done. Use the wget commands to download the imputed files to the
desired folder. After the download completed, use the unzip\_results.sh script to unzip the files with the
provided password.
