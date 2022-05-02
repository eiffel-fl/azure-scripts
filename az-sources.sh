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

# Get subnet id to be able to ssh.
function get_kv1_id {
	# Taken from https://github.com/kinvolk/msft-azure-vpn/issues/13#issuecomment-1114802695
	echo $(az network vnet subnet list -g kv1 --vnet-name kv1 --query "[?name!='GatewaySubnet'].id" --output tsv | head -n1)
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

	# Use Ubuntu 22.04 as default image.
	image='canonical:0001-com-ubuntu-server-jammy:22_04-lts:22.04.202204200'

	# If the vm_size corresponds to Ampere Altra one, we need to use this
	# particular image instead.
	# VM size corresponding to Ampere Altra seems to have the 'p' feature but it
	# is not documented so far.
	if [[ $vm_size =~ [ED][0-9]+p ]]; then
		image='canonical:0001-com-ubuntu-server-arm-preview-focal:20_04-lts:latest'
	fi

	az vm create --resource-group $resource_group --name $vm --subnet $(get_kv1_id) --image $image --admin-username ${resource_suffix} --generate-ssh-keys --size $vm_size --os-disk-size-gb $disk_size

	# To extend OS disk space of an already existing VM, you can do the following:
# 	disk_name=$(az disk list --resource-group $resource_group --query '[*].{Name:name,Gb:diskSizeGb,Tier:accountType}' -o tsv | grep $vm | cut -f1)
# 	az vm deallocate -g $resource_group -n $vm
# 	az disk update --resource-group $resource_group --name $disk_name --size-gb $disk_size --sku StandardSSD_LRS
# 	az vm start -g $resource_group -n $vm

	echo -e "VM was created.\nYou should be able to connect using: ssh ${resource_suffix}@$(az vm show --resource-group $resource_group --name $vm -d --query [privateIps] --output tsv)"
}

function craft_windows_password {
	password=$(echo $RANDOM | md5sum | head -c 10)

	echo -n "${password}&U"
}

# Create a Windows vm.
function create_windows_vm {
	local resource_suffix
	local resource_group

	local vm
	local password

	if [ $# -lt 2 ]; then
		echo "${FUNCNAME[0]} needs 2 arguments: the resource_suffix and the resource_group" 1>&2

		exit 1
	fi

	resource_suffix=$1
	resource_group=$2

	vm="${resource_suffix}vm"
	password=$(craft_windows_password)

	az vm create --resource-group $resource_group --name $vm --public-ip-sku Standard --image 'MicrosoftWindowsDesktop:windows11preview:win11-21h2-pro:22000.194.2109250206' --admin-username ${resource_suffix} --admin-password $password

	echo -e "VM was created.\nYou should be able to connect using: xfreerdp -u:${resource_suffix} -v:$(az vm show --resource-group $resource_group --name $vm -d --query [publicIps] --output tsv) with the following password: ${password}"
}

# Create a registry by first trying if name is already taken.
# If this is the case, $RANDOM will be concatenated to name and group will be
# tried to be created.
function create_container_registry {
	local resource_suffix
	local registry

	if [ $# -lt 1 ]; then
		echo "${FUNCNAME[0]} needs one arguments: the resource_suffix" 1>&2

		exit 1
	fi

	resource_suffix=$1
	registry="${resource_suffix}registry"

	# If registry name is already taken, we add some randomness.
	is_name_available=$(az acr check-name -o yaml -n $registry | grep 'nameAvailable' | cut -d' ' -f2)
	if [ $is_name_available = "false" ]; then
		registry="${registry}${RANDOM}"
	fi

	# We use Standard to be able to enable anonymous pull.
	az acr create --resource-group $resource_group --name $registry --sku Standard
	az acr update --name $registry --anonymous-pull-enabled
	az acr login --name $registry

	echo -e "Container registry is: ${registry}.azurecr.io\nYou can use this as CONTAINER_REPO"
}