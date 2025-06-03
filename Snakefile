# Setup -----------------------------------------------------------------------------------------


# Grab paths and variables from the config file
plink_prefix: str = config["plink_prefix"]
out_dir: str = config["out_dir"]
code_dir: str = config["code_dir"]
chr: str = config["chr_dir"]

chr_list: ["21"]
build: "hg38"
chr6_hwe: = "no"

# Make output dirs
#TODO: is this the correct way to do it?
Path(out_dir, "pre_qc").mkdir(parents=True, exist_ok=True)
Path(out_dir, "post_qc").mkdir(parents=True, exist_ok=True)
Path(out_dir, "imputed").mkdir(parents=True, exist_ok=True)

# Rules -----------------------------------------------------------------------------------------

rule all:
    input:
        # expand("imputed/chr{chr}.dose.vcf.gz", chr=chr)  # final imputed filesxs
        [f"{out_dir}/pre_qc/chr{chr}_pre_qc.vcf.gz" for chr in chr]  # temp after first step

#TODO: need to update bash script to not check if PLINK2 given!
rule create_initial_input:
    input:
        f"{plink_prefix}.bed",
        f"{plink_prefix}.bim",
        f"{plink_prefix}.fam"
    output:
        [f"{out_dir}/pre_qc/chr{chr}_pre_qc.vcf.gz" for chr in chr_list]
    params:
        orig_build="hg38",
        to_build="hg19",
        chr6_hwe="no"
    shell:
        """
        bash {code_dir}/create_initial_input.sh \
            -p {plink_prefix} \
            -o {out_dir}/pre_qc \
            -c {code_dir} \
            -n {chr_list} \
            -b {params.orig_build} \
            -b {params.to_build} \
            -h {params.chr6_hwe}
        """

#TODO: think chr_list here is wrong! 

rule debug_check:
    input:
        f"{plink_prefix}.bed"
    shell:
        "ls -l {input}"
