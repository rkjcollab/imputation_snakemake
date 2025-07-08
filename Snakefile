# Setup -----------------------------------------------------------------------------------------

# Grab paths and variables from the config file
plink_prefix: str = config["plink_prefix"]
out_dir: str = config["out_dir"]
chr: List[str] = config["chr"]
orig_build: str = config["orig_build"]
to_build: str = config["to_build"]
imp: str = config["imp"]
imp_rsq_filt: str = config["imp_rsq_filt"]
imp_name: str = config["imp_name"]
zip_pw: str = config["zip_pw"]
opt: str = config["opt"]

# Set default values currently not controlled by arguments
maf = "0"
rsq = "0.3"

# Modify chr array for bash script
chr_str = " ".join(map(str, chr))

# Get dir of pipeline
code_dir = Path(workflow.snakefile).resolve().parent

# Rules -----------------------------------------------------------------------------------------

rule all:
    input:
        [f"{out_dir}/imputed_clean_maf{maf}_rsq{rsq}/chr{c}_clean.vcf.gz" for c in chr]

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
            --rsq-filt {imp_rsq_filt} \
            --imp-name {imp_name} \
            > {log} 2>&1
        """

# Different from the other rules, this script in this rule runs once for
# each chr
rule unzip_results:
    input:
        f"{out_dir}/imputed/chr_{{chr}}.zip"
        # [f"{out_dir}/imputed/chr_{c}.zip" for c in chr]
    output:
        f"{out_dir}/imputed/chr{{chr}}.dose.vcf.gz"
        # [f"{out_dir}/imputed/chr{c}.dose.vcf.gz" for c in chr]
    log:
        f"{out_dir}/imputed/chr{{chr}}_unzip_results.log"
        # f"{out_dir}/imputed/unzip_results.log"
    params:
        script=Path(code_dir, "scripts/unzip_results.sh")
    shell:
        """
        bash {params.script} \
            -d {out_dir}/imputed \
            -p "{zip_pw}" \
            -c {wildcards.chr} \
            > {log} 2>&1
        """

# Different from the other rules, this script in this rule runs once for
# each chr
# TODO: make ifelse more robust?
rule filter_info_and_vcf_files:
    input:
        f"{out_dir}/imputed/chr{{chr}}.dose.vcf.gz"
    output:
        f"{out_dir}/imputed_clean_maf{maf}_rsq{rsq}/chr{{chr}}_clean.vcf.gz"
    log:
        f"{out_dir}/imputed_clean_maf{maf}_rsq{rsq}/chr{{chr}}_filter_info_and_vcf_files.log"
    params:
        script=f'{code_dir}/scripts/filter_info_and_vcf_files{"_bcftools" if opt == "all" else ""}.sh'
    shell:
        """
        bash {params.script} \
            -n {wildcards.chr} \
            -r {rsq} \
            -m {maf} \
            -d {out_dir} \
            -o {opt} \
           > {log} 2>&1
        """

#TODO: need to add step that merges all VCFs into single PLINK file