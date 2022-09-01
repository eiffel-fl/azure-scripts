#! /usr/bin/env bash
# Copyright (c) 2021 Francis Laniel <flaniel@linux.microsoft.com>
# SPDX-License-Identifier: MPL-2.0


source az-sources.sh

if [ $# -eq 1 ]; then
	resource_prefix=$1
else
	resource_prefix=$(whoami)
fi

az login --scope https://management.core.windows.net//.default

# Ampere Altra Neoverse ('p' means Ampere)
vm_size='Standard_E8ps_v5'
# AMD EPYC ('a' means AMD)
vm_size='Standard_D32a_v4'

disk_size='128'

current_subscription=$(az account show -o tsv --query name)
az account set -s 'volk-arc'

resource_group=$(create_resource_group $resource_prefix)

create_vm $resource_prefix $resource_group $vm_size $disk_size

az account set -s "${current_subscription}"

echo -e "Everything should be OK!\nOnce terminated, please delete your resources with: az group delete --no-wait --name ${resource_group}"
