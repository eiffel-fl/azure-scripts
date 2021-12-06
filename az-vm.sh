#! /usr/bin/env bash
# Copyright (c) 2021 Francis Laniel <flaniel@linux.microsoft.com>
# SPDX-License-Identifier: MPL-2.0


source az-sources.sh

if [ $# -eq 1 ]; then
	resource_suffix=$1
else
	resource_suffix=$(whoami)
fi

az login --scope https://management.core.windows.net//.default

vm_size='Standard_D32a_v4'
disk_size='128'

resource_group=$(create_resource_group $resource_suffix)

create_vm $resource_suffix $resource_group $vm_size $disk_size

echo -e "Everything should be OK!\nOnce terminated, please delete your resources with: az group delete --name ${resource_group}"