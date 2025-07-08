#!/bin/bash

set -e
set -u

while getopts d:p:c: opt; do
   case "${opt}" in
      d) impute_dir=${OPTARG};;
      p) zip_password=${OPTARG};;
      c) chr=${OPTARG};;
      \?) echo "Invalid option -$OPTARG" >&2
      exit 1;;
   esac
done

cd $impute_dir
7z e chr_${chr}.zip -y -p$zip_password
