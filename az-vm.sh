#! /usr/bin/env bash
# Copyright (c) 2021 Francis Laniel <flaniel@linux.microsoft.com>
# SPDX-License-Identifier: MPL-2.0


source az-sources.sh

resource_prefix=$(whoami)

# The size we will use will be:
# * D: General purpose compute
# * %d: The VM size, often the number of cores.
# * %c: The VM architecture, 'a' for AMD, 'p' for Ampere Altra (i.e. arm64) and
# nothing for Intel.
# * s: Premium Storage capable.
# * v5: Version 5.
# For example: https://azureprice.net/vm/Standard_D2ps_v5
SIZE_FORMAT='Standard_D%d%cs_v5'
architecture='a'
core_count=64
disk_size=128
os='Ubuntu'

image='MicrosoftCBLMariner:cbl-mariner:cbl-mariner-2-gen2:2.20221026.01'

while getopts "ac:o:n:h" option; do
	case $option in
	a)
		architecture='p'
		;;
	c)
		core_count=${OPTARG}
		;;
	o)
		os=${OPTARG}
		;;
	n)
		resource_prefix=${OPTARG}
		;;
	h|\?)
		echo "Usage: $0 [-n resource_prefix] [-a] [-c core_count]" 1>&2
		echo -e "\t-n: The given string will be used as resource prefix, $(whoami) by default." 1>&2
		echo -e "\t-a: Use Ampere Altra (i.e. arm64) node, AMD by default." 1>&2
		echo -e "\t-c: The given number will be used as node size, 64 cores by default." 1>&2
		echo -e "\t-o: The given string will be used as os-sku, Ubuntu by default." 1>&2
		exit 1
	esac
done

case $os in
Debian)
	image='Debian'
	;;
Ubuntu)
	image='Canonical:0001-com-ubuntu-server-jammy:22_04-lts:22.04.202211160'

	# If the vm_size corresponds to Ampere Altra one, we need to use this
	# particular image instead.
	if [ $architecture = 'p' ]; then
		image='Canonical:0001-com-ubuntu-server-jammy:22_04-lts-arm64:22.04.202211160'
	fi
	;;
Mariner)
	image='MicrosoftCBLMariner:cbl-mariner:cbl-mariner-2-gen2:2.20221110.01'

	# If the vm_size corresponds to Ampere Altra one, we need to use this
	# particular image instead.
	if [ $architecture = 'p' ]; then
		image='MicrosoftCBLMariner:cbl-mariner:cbl-mariner-2-arm64:2.20221110.01'
	fi
	;;
esac

az login --scope https://management.core.windows.net//.default

current_subscription=$(az account show -o tsv --query name)
az account set -s 'volk-arc'

resource_group=$(create_resource_group $resource_prefix)

# If the vm_size corresponds to Ampere Altra one, we need to use this
# particular image instead.
# if [ $architecture = 'p' ]; then
# 	image='canonical:0001-com-ubuntu-server-arm-preview-focal:20_04-lts:latest'
# fi
echo "image: ${image}"

# Craft the size string
vm_size=$(printf $SIZE_FORMAT $core_count $architecture)

create_vm $resource_prefix $resource_group $vm_size $disk_size $image

az account set -s "${current_subscription}"

echo -e "Everything should be OK!\nOnce terminated, please delete your resources with: az group delete --no-wait --name ${resource_group}"
