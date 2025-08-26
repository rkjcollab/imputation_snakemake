"""Submits pre_qc files to imputation server

        * submit_initial_input - TODO!
        * main - TODO!

"""

import os
import argparse
import sys
import subprocess
import requests
import json
from pathlib import Path
key_path= Path(Path(__file__).resolve().parent.parent, 'config')
sys.path.insert(0, str(key_path))
import key  # file in .gitignore to store API keys

def main():
    """Runs get_args, TODO.

    """
    args = get_args()
    if args.imp == "topmed":
        if args.imp_job_id != "":
            download_topmed(args)
        else:
            submit_topmed(args)
    elif "mich" in args.imp:
        submit_mich(args)

def get_args():
    """Get command line arguments.

    Returns
    -------
    args : argparse.Namespace
        Arguments from command line

    """
    parser = argparse.ArgumentParser(
        description=('TODO!')
    )
    parser.add_argument('--dir',
                        type=str,
                        required=True,
                        help='Path to directory with pre_qc VCF files.')
    parser.add_argument('--chr',
                        type=str,
                        required=True,
                        help='Space-separated list of chromosomes "21 22".')
    parser.add_argument('--imp',
                        choices = ['topmed', 'mich_hla_v1', 'mich_hla_v2', 'mich_1kg_p3_v5', 'mich_hrc'],
                        required=True,
                        help='Imputation server to be used.')
    parser.add_argument('--build',
                        choices = ['hg19', 'hg38'],
                        required=True,
                        help="Build of data input to imputation, should match reference.")
    parser.add_argument('--mode',
                        choices = ['qconly', 'imputation'],
                        required=True,
                        help="Choose between running QC only or full imputation.")
    parser.add_argument('--rsq-filt',
                        choices = ['0', '0.001', '0.1', '0.2', '0.3'],
                        default = '0',
                        help="Set Rsq imputation quality, default is 0.")
    parser.add_argument('--imp-name',
                        type=str,
                        required=True,
                        help="Job name for imputation server.")
    parser.add_argument('--imp-job-id',
                        type=str,
                        default= '',
                        help="Job ID after imputation (job-#####-##-###).")

    args = parser.parse_args()
    return args

def submit_topmed(args):
    # imputation server url
    base = 'https://imputation.biodatacatalyst.nhlbi.nih.gov/api/v2'
    token = key.TOPMED_API

    # add token to header (see documentation for Authentication)
    headers = {'X-Auth-Token' : token }
    data = {
    'job-name': args.imp_name,
    'refpanel': 'apps@topmed-r3',
    'mode': args.mode,
    'population': 'all',  # compares to TOPMed reference panel
    'build': args.build,
    'phasing': 'eagle',
    'r2Filter': args.rsq_filt
    }

    # select pre or post qc files
    if args.mode == "qconly":
        version = "pre"
    elif args.mode == "imputation":
        version = "post"

    # Submit new job
    # https://topmedimpute.readthedocs.io/en/latest/api/
    vcf_files = []
    chr_list = [c for c in args.chr.split(" ")]
    for c in chr_list:
        vcf_path = os.path.join(args.dir, f"chr{c}_{version}_qc.vcf.gz")
        vcf_files.append(('files', open(vcf_path, 'rb')))

    endpoint = "/jobs/submit/imputationserver"
    resp = requests.post(base + endpoint, files=vcf_files, data=data, headers=headers)

    output = resp.json()

    if resp.status_code != 200:
        print(output['message'])
        raise Exception('POST {} {}'.format(endpoint, resp.status_code))
    else:
        # print message
        print(output['message'])
        print(output['id'])

def submit_mich(args):
    # imputation server url
    base = 'https://imputationserver.sph.umich.edu/api/v2'
    token = key.MICH_API

    # get which refpanel
    if args.imp == 'mich_1kg_p3_v5':
        refpanel = '1000g-phase-3-v5'
    elif args.imp == 'mich_hla_v1':
        refpanel = 'multiethnic-hla-panel-4digit'
    elif args.imp == 'mich_hla_v2':
        refpanel = 'multiethnic-hla-panel-4digit-v2'
    elif args.imp == "mich_hrc":
        refpanel = 'hrc-r1.1'

    # add token to header (see Authentication)
    headers = {'X-Auth-Token' : token }
    data = {
    'job-name': args.imp_name,
    'refpanel': refpanel,
    'mode': args.mode,
    'population': 'off',  # no AF QC check done
    'build': args.build,
    'phasing': 'eagle',
    'r2Filter': args.rsq_filt
    }

    # select pre or post qc files
    if args.mode == "qconly":
        version = "pre"
    elif args.mode == "imputation":
        version = "post"

    # submit new job
    # https://genepi.github.io/michigan-imputationserver/tutorials/api/?h=api
    vcf_files = []
    chr_list = [c for c in args.chr.split(" ")]
    for c in chr_list:
        vcf_path = os.path.join(args.dir, f"chr{c}_{version}_qc.vcf.gz")
        vcf_files.append(('files', open(vcf_path, 'rb')))

    endpoint = "/jobs/submit/imputationserver2"
    resp = requests.post(base + endpoint, files=vcf_files, data=data, headers=headers)

    output = resp.json()

    if resp.status_code != 200:
        print(output['message'])
        raise Exception('POST {} {}'.format(endpoint, resp.status_code))
    else:
        # print message
        print(output['message'])
        print(output['id'])

if __name__ == '__main__':
    main()
