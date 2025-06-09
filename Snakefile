# Setup -----------------------------------------------------------------------------------------

# Grab paths and variables from the config file
plink_prefix: str = config["plink_prefix"]
out_dir: str = config["out_dir"]
chr: List[str] = config["chr"]
orig_build: str = config["orig_build"]
to_build: str = config["to_build"]
imp: str = config["imp"]
imp_name: str = config["imp_name"]

# Make output dirs
Path(out_dir, "pre_qc").mkdir(parents=True, exist_ok=True)
Path(out_dir, "post_qc").mkdir(parents=True, exist_ok=True)
Path(out_dir, "imputed").mkdir(parents=True, exist_ok=True)

# Modify chr array for bash script
chr_str = " ".join(map(str, chr))

# Get dir of pipeline
code_dir = Path(workflow.snakefile).resolve().parent

# Rules -----------------------------------------------------------------------------------------

rule all:
    input:
        # expand("imputed/chr{chr}.dose.vcf.gz", chr=chr)  # final imputed files
        [f"{out_dir}/pre_qc/chr{c}_pre_qc.vcf.gz" for c in chr]  # temp after first step

rule create_initial_input:
    input:
        f"{plink_prefix}.bed",
        f"{plink_prefix}.bim",
        f"{plink_prefix}.fam"
    output:
        [f"{out_dir}/pre_qc/chr{c}_pre_qc.vcf.gz" for c in chr]
    log:
        f"{out_dir}/pre_qc/create_initial_input.log"
    params:
        script=Path(code_dir, "scripts/create_initial_input.sh")
    shell:
        """
        bash {params.script} \
            -p {plink_prefix} \
            -o {out_dir}/pre_qc \
            -c {code_dir} \
            -n "{chr_str}" \
            -b {orig_build} \
            -t {to_build} \
            > {log} 2>&1
        """

rule submit_initial_input:
    input:
        [f"{out_dir}/pre_qc/chr{c}_pre_qc.vcf.gz" for c in chr]
    output:
        f"{out_dir}/pre_qc/submit_initial_input.log"
    log:
        f"{out_dir}/pre_qc/submit_initial_input.log"
    params:
        script=Path(code_dir, "scripts/submit.py")
    shell:
        """
        python {params.script} \
            --dir {out_dir}/pre_qc \
            --chr "{chr_str}" \
            --imp {imp} \
            --build {to_build} \
            --mode "qconly" \
            --imp-name {imp_name} \
            > {log} 2>&1
        """

rule fix_strands:
    input:
        f"{out_dir}/pre_qc/snps-excluded.txt",
        f"{out_dir}/pre_qc/submit_initial_input.log"
    output:
        [f"{out_dir}/post_qc/chr{c}_post_qc.vcf.gz" for c in chr]
    log:
        f"{out_dir}/post_qc/fix_strands.log"
    params:
        script=Path(code_dir, "scripts/fix_strands.sh")
    shell:
        """
        bash {params.script} \
            -o {out_dir} \
            -c {code_dir} \
            -n "{chr_str}" \
            -t {to_build} \
            -i {imp} \
            > {log} 2>&1
        """

rule submit_fix_strands:
    input:
        [f"{out_dir}/post_qc/chr{c}_post_qc.vcf.gz" for c in chr]
    output:
        f"{out_dir}/post_qc/submit_fix_strands.log"
    log:
        f"{out_dir}/post_qc/submit_fix_strands.log"
    params:
        script=Path(code_dir, "scripts/submit.py")
    shell:
        """
        python {params.script} \
            --dir {out_dir}/post_qc \
            --chr "{chr_str}" \
            --imp {imp} \
            --build {to_build} \
            --mode "imputation" \
            --imp-name {imp_name} \
            > {log} 2>&1
        """
