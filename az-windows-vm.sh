#! /usr/bin/env bash
# Copyright (c) 2022 Francis Laniel <flaniel@linux.microsoft.com>
# SPDX-License-Identifier: MPL-2.0


source az-sources.sh

if [ $# -eq 1 ]; then
	resource_prefix=$1
else
	resource_prefix=$(whoami)
fi

az login --scope https://management.core.windows.net//.default

resource_group=$(create_resource_group $resource_prefix)

create_windows_vm $resource_prefix $resource_group

echo -e "Everything should be OK!\nOnce terminated, please delete your resources with: az group delete --no-wait --name ${resource_group}"
