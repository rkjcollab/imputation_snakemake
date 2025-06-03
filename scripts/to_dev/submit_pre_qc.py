"""Submits pre_qc files to imputation server

        * submit_initial_input - TODO!
        * main - TODO!

"""

import os
import argparse
import sys
import subprocess
import key  # file in .gitignore to store API keys
import requests

def submit_initial_input(args, log_file):

    # imputation server url
    base = 'https://imputation.biodatacatalyst.nhlbi.nih.gov/api/v2'
    token = key.TOPMED_API

    # add token to header (see documentation for Authentication)
    headers = {'X-Auth-Token' : token }
    data = {
    'job-name': 'auto_test',
    'refpanel': 'apps@topmed-r3',
    'mode': 'qconly',
    'population': 'all',
    'build': 'hg38',
    'phasing': 'eagle',
    'r2Filter': 0
    }

    # Submit new job
    # TODO: define version for chr=all
    # https://topmedimpute.readthedocs.io/en/latest/api/
    vcf1 = f"{args.out_dir}/chr{args.chr}_pre_qc.vcf.gz"

    with open(vcf1, 'rb') as f1:
        files = [
            ('files', f1),
        ]

        endpoint = "/jobs/submit/imputationserver"
        resp = requests.post(base + endpoint, files=files, data=data, headers=headers)

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