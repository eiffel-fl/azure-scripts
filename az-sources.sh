#! /usr/bin/env bash
# Copyright (c) 2021 Francis Laniel <flaniel@linux.microsoft.com>
# SPDX-License-Identifier: MPL-2.0


# Create a resource group by first trying if name is already taken.
# If this is the case, $RANDOM will be concat to name and group will be tried to
# be created.
function create_resource_group {
	local resource_suffix
	local resource_group

	if [ $# -lt 1 ]; then
		echo "${FUNCNAME[0]} needs one arguments: the resource_suffix" 1>&2

		exit 1
	fi

	resource_suffix=$1
	resource_group="${resource_suffix}rg"

	does_group_exist=$(az group exists -o tsv -n $resource_group)
	if [ $does_group_exist = "true" ]; then
		resource_group="${resource_group}${RANDOM}"
	fi

	az group create --name $resource_group --location westeurope -o none

	# "Returns" resource_group in case we needed to craft one.
	echo $resource_group
}

# Create a vm with given size (like Standard_D32a_v4) and OS disk size (in GB).
function create_vm {
	local resource_suffix
	local resource_group
	local vm_size
	local disk_size

	local vm

	if [ $# -lt 4 ]; then
		echo "${FUNCNAME[0]} needs 4 arguments: the resource_suffix, the resource_group, the vm_size and the disk_size" 1>&2

		exit 1
	fi

	resource_suffix=$1
	resource_group=$2
	vm_size=$3
	disk_size=$4

	vm="${resource_suffix}vm"

	az vm create --resource-group $resource_group --name $vm --public-ip-sku Standard --image UbuntuLTS --admin-username ${resource_suffix} --generate-ssh-keys --size $vm_size --os-disk-size-gb $disk_size

	# To extend OS disk space of an already existing VM, you can do the following:
# 	disk_name=$(az disk list --resource-group $resource_group --query '[*].{Name:name,Gb:diskSizeGb,Tier:accountType}' -o tsv | grep $vm | cut -f1)
# 	az vm deallocate -g $resource_group -n $vm
# 	az disk update --resource-group $resource_group --name $disk_name --size-gb $disk_size --sku StandardSSD_LRS
# 	az vm start -g $resource_group -n $vm

	echo -e "VM was created.\nYou should be able to connect using: ssh ${resource_suffix}@$(az vm show --resource-group $resource_group --name $vm -d --query [publicIps] --output tsv)"
}