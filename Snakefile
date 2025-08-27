# Setup -----------------------------------------------------------------------------------------

### Get variables from config file
# Pipeline settings
chr: List[str] = config["chr"]
orig_build: str = config["orig_build"]
to_build: str = config["to_build"]
imp: str = config["imp"]
imp_rsq_filt: str = config["imp_rsq_filt"]
imp_name: str = config["imp_name"]
imp_job_id: str = config["imp_job_id"]
zip_pw: str = config["zip_pw"]
opt: str = config["opt"]
use_cont: bool = config["use_cont"]

# Host paths outside container
plink_prefix: str = config["plink_prefix"]
plink_prefix_name = Path(plink_prefix).name
id_list_hwe: str = config["id_list_hwe"]
id_list_hwe_name = Path(id_list_hwe).name

if use_cont:
    # Container paths
    plink_dir: str = config["plink_dir_cont"]
    id_list_hwe_dir: str = config["id_list_hwe_dir_cont"]
    out_dir: str = config["out_dir_cont"]
else:
    plink_dir = Path(plink_prefix).parent
    id_list_hwe_dir = Path(id_list_hwe).parent
    out_dir: str = config["out_dir"]

# Modify chr array for bash script
chr_str = " ".join(map(str, chr))

### Other prep
# Set default values currently not controlled by arguments
maf = "0"
rsq = "0.3"

# Get dir of pipeline
code_dir = Path(workflow.snakefile).resolve().parent

# Rules -----------------------------------------------------------------------------------------

rule all:
    input:
        # [f"{out_dir}/imputed_clean_maf{maf}_rsq{rsq}/chr{c}_clean.vcf.gz" for c in chr]
        f"{out_dir}/imputed_clean_maf{maf}_rsq{rsq}/chr_all_concat.pvar",
        f"{out_dir}/imputed_clean_maf{maf}_rsq{rsq}/chr_all_concat.psam",
        f"{out_dir}/imputed_clean_maf{maf}_rsq{rsq}/chr_all_concat.pgen"

rule create_initial_input:
    input:
        f"{plink_dir}/{plink_prefix_name}.bed",
        f"{plink_dir}/{plink_prefix_name}.bim",
        f"{plink_dir}/{plink_prefix_name}.fam"
    output:
        [f"{out_dir}/pre_qc/chr{c}_pre_qc.vcf.gz" for c in chr]
    log:
        f"{out_dir}/pre_qc/create_initial_input.log"
    params:
        script=Path(code_dir, "scripts/create_initial_input.sh")
    shell:
        """
        bash {params.script} \
            -p {plink_dir}/{plink_prefix_name} \
            -o {out_dir}/pre_qc \
            -c {code_dir} \
            -n "{chr_str}" \
            -b {orig_build} \
            -t {to_build} \
            -h {id_list_hwe_dir}/{id_list_hwe_name} \
            > {log} 2>&1
        """

# Need "" around chr_str to keep all as single input
rule submit_initial_input:
    input:
        [f"{out_dir}/pre_qc/chr{c}_pre_qc.vcf.gz" for c in chr]
    output:
        log_final=f"{out_dir}/pre_qc/submit_initial_input.log"
    params:
        script=Path(code_dir, "scripts/submit.py"),
        log_tmp=f"{out_dir}/pre_qc/tmp_submit_initial_input.log"
    shell:
        """
        python {params.script} \
            --dir {out_dir}/pre_qc \
            --chr "{chr_str}" \
            --imp {imp} \
            --build {to_build} \
            --mode "qconly" \
            --imp-name {imp_name} \
            > {params.log_tmp} 2>&1

        mv {params.log_tmp} {output.log_final}
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
        log_final=f"{out_dir}/post_qc/submit_fix_strands.log"
    params:
        script=Path(code_dir, "scripts/submit.py"),
        log_tmp=f"{out_dir}/post_qc/tmp_submit_fix_strands.log"
    shell:
        """
        python {params.script} \
            --dir {out_dir}/post_qc \
            --chr "{chr_str}" \
            --imp {imp} \
            --build {to_build} \
            --mode imputation \
            --rsq-filt {imp_rsq_filt} \
            --imp-name {imp_name} \
            > {params.log_tmp} 2>&1

        mv {params.log_tmp} {output.log_final}
        """

rule download_results:
    output:
        [f"{out_dir}/imputed/chr_{c}.zip" for c in chr]
    log:
        f"{out_dir}/imputed/download_results.log"
    params:
        script=Path(code_dir, "scripts/download_results.sh")
    shell:
        """
        bash {params.script} \
            -i {imp} \
            -c {code_dir} \
            -o {out_dir}/imputed \
            -j {imp_job_id} \
            > {log} 2>&1
        """

# Different from the other rules, this script in this rule runs once for each chr
rule unzip_results:
    input:
        [f"{out_dir}/imputed/chr{c}.dose.vcf.gz" for c in chr]

rule unzip_results_helper:
    input:
        f"{out_dir}/imputed/chr_{{chr}}.zip"
    output:
        f"{out_dir}/imputed/chr{{chr}}.dose.vcf.gz"
    log:
        f"{out_dir}/imputed/chr{{chr}}_unzip_results.log"
    params:
        script=Path(code_dir, "scripts/unzip_results.sh")
    shell:
        """
        bash {params.script} \
            -d {out_dir}/imputed \
            -p {zip_pw} \
            -c {wildcards.chr} \
            > {log} 2>&1
        """

# Different from the other rules, this script in this rule runs once for each chr
rule filter_info_and_vcf_files:
    input:
        [f"{out_dir}/imputed_clean_maf{maf}_rsq{rsq}/chr{c}_clean.vcf.gz" for c in chr]

rule filter_info_and_vcf_files_helper:
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

rule concat_convert_to_plink:
    input:
        [f"{out_dir}/imputed_clean_maf{maf}_rsq{rsq}/chr{c}_clean.vcf.gz" for c in chr]
    output:
        f"{out_dir}/imputed_clean_maf{maf}_rsq{rsq}/chr_all_concat.pvar",
        f"{out_dir}/imputed_clean_maf{maf}_rsq{rsq}/chr_all_concat.psam",
        f"{out_dir}/imputed_clean_maf{maf}_rsq{rsq}/chr_all_concat.pgen"
    log:
        f"{out_dir}/imputed_clean_maf{maf}_rsq{rsq}/concat_convert_to_plink.log"
    params:
        script=Path(code_dir, "scripts/concat_convert_to_plink.sh")
    shell:
        """
        bash {params.script} \
            -d {out_dir}/imputed_clean_maf{maf}_rsq{rsq} \
            > {log} 2>&1
        """
