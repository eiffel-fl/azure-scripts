#! /usr/bin/env bash
# Copyright (c) 2021 Francis Laniel <flaniel@linux.microsoft.com>
# SPDX-License-Identifier: MPL-2.0


source az-sources.sh

resource_prefix=$(whoami)

# The size we will use will be:
# * D: General purpose compute
# * %d: The VM size, often the number of cores.
# * %c: The VM architecture, 'a' for AMD, 'p' for Microsoft Cobalt (i.e. arm64)
# and nothing for Intel.
# * s: Premium Storage capable.
# * v6: Version 6. This is important for arm64 to use Microsoft Cobalt, which
# is compatible with Trusted Launch while Ampere Altra is not:
# https://learn.microsoft.com/en-us/azure/virtual-machines/trusted-launch#virtual-machines-sizes
# For example: https://azureprice.net/vm/Standard_D2ps_v5
SIZE_FORMAT='Standard_D%d%cs_v6'
location='westeurope'
architecture='a'
use_bastion='false'
core_count=64
disk_size=128
os='Ubuntu'

while getopts "abc:l:o:n:h" option; do
	case $option in
	a)
		architecture='p'
		;;
	b)
		use_bastion='true'
		;;
	c)
		core_count=${OPTARG}
		;;
	l)
		location=${OPTARG}
		;;
	o)
		os=${OPTARG}
		;;
	n)
		resource_prefix=${OPTARG}
		;;
	h|\?)
		echo "Usage: $0 [-n resource_prefix] [-a] [-b] [-c core_count] [-l location] [-o os_sku]" 1>&2
		echo -e "\t-n: The given string will be used as resource prefix, $(whoami) by default." 1>&2
		echo -e "\t-a: Use Ampere Altra (i.e. arm64) node, AMD by default." 1>&2
		echo -e "\t-b: Use bastion to ssh to VM, does not use use_bastion by default." 1>&2
		echo -e "\t-c: The given number will be used as node size, 64 cores by default." 1>&2
		echo -e "\t-l: The given string will be used as location, westeurope by default." 1>&2
		echo -e "\t-o: The given string will be used as os-sku, Ubuntu by default." 1>&2
		exit 1
	esac
done

case $os in
Debian)
	image='Debian:debian-12:12:latest'

	# If the vm_size corresponds to Microsoft Cobal one, we need to use specific
	# image instead.
	if [ $architecture = 'p' ]; then
		image='Debian:debian-12:12-arm64:latest'
	fi
	;;
Ubuntu)
	image='Canonical:ubuntu-24_04-lts:server:latest'

	if [ $architecture = 'p' ]; then
		image='Canonical:ubuntu-24_04-lts:server-arm64:latest'
	fi
	;;
Mariner)
	image='MicrosoftCBLMariner:azure-linux-3:azure-linux-3:latest'

	if [ $architecture = 'p' ]; then
		image='MicrosoftCBLMariner:azure-linux-3:azure-linux-3-arm64:latest'
	fi
	;;
esac

az login --scope https://management.core.windows.net//.default

if [ "${use_bastion}" = 'false' ]; then
	# kv1 is only available in a given subscription.
	current_subscription=$(az account show -o tsv --query name)
	az account set -s '47635d02-50bb-4f1f-8b44-e9e9518015e6'
fi

resource_group=$(create_resource_group $resource_prefix $location)

# Craft the size string
vm_size=$(printf $SIZE_FORMAT $core_count $architecture)

if [ "${use_bastion}" = 'true' ]; then
	vn=$(create_vnet $resource_prefix $resource_group)
	# Creating a bastion takes aaaaaaages!
	bastion=$(create_bastion $resource_prefix $resource_group $vn $location)
	vm=$(create_vm $resource_prefix $resource_group $vm_size $disk_size $image $use_bastion $vn)

	vm_ip=$(get_vm_private_ip $resource_group $vm)
	vm_username=$(get_vm_username $resource_group $vm)

	cat << EOF
VM was created.
You can now connect to it using:
* Either: az network bastion ssh --name $bastion --resource-group $resource_group --target-ip-address $vm_ip --auth-type "ssh-key" --username $vm_username --ssh-key ~/.ssh/id_rsa
* Or: az network bastion tunnel --name $bastion --resource-group $resource_group --target-ip-address $vm_ip --resource-port 22 --port 1337; ssh $vm_username@127.0.0.1 -p 1337
To use scp or sftp, the tunnel is mandatory.
EOF
else
	if [ "${location}" != 'westeurope' ]; then
		echo -e "Creating VM using kv1 is only available in westeurope, while you want to create it in ${location}, please delete everything (az group delete --no-wait --name ${resource_group}) and run again" 1>&2

		exit 1
	fi

	# Otherwise, create a VM using kv1.
	vm=$(create_vm $resource_prefix $resource_group $vm_size $disk_size $image $use_bastion)

	echo -e "VM was created.\nYou should be able to connect using: ssh $(get_vm_username $resource_group $vm)@$(get_vm_private_ip $resource_group $vm)"

	az account set -s "${current_subscription}"
fi

echo -e "Everything should be OK!\nOnce terminated, please delete your resources with: az group delete --no-wait --name ${resource_group}"
