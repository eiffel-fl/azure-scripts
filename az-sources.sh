#! /usr/bin/env bash
# Copyright (c) 2021 Francis Laniel <flaniel@linux.microsoft.com>
# SPDX-License-Identifier: MPL-2.0


# Create a resource group by first trying if name is already taken.
# If this is the case, $RANDOM will be concatened to name and group will be
# tried to be created.
function create_resource_group {
	local resource_prefix
	local resource_group
	local location

	if [ $# -lt 2 ]; then
		echo "${FUNCNAME[0]} needs two arguments: the resource_prefix and the location" 1>&2

		exit 1
	fi

	resource_prefix=$1
	resource_group="${resource_prefix}rg"
	location=$2

	does_group_exist=$(az group exists -o tsv -n $resource_group)
	if [ $does_group_exist = "true" ]; then
		resource_group="${resource_group}${RANDOM}"
	fi

	az group create --name $resource_group --location $location -o none

	# "Returns" resource_group in case we needed to craft one.
	echo $resource_group
}

# Get subnet id to be able to ssh.
function get_kv1_id {
	# Taken from https://github.com/kinvolk/msft-azure-vpn/issues/13#issuecomment-1114802695
	echo $(az network vnet subnet list -g kv1 --vnet-name kv1 --query "[?name!='GatewaySubnet'].id" --output tsv | head -n1)
}

function start_vm {
	local resource_group
	local vm_name

	if [ $# -lt 2 ]; then
		echo "${FUNCNAME[0]} needs 2 arguments: the resource_group and the vm_name" 1>&2

		exit 1
	fi

	resource_group=$1
	vm_name=$2

	az vm start --resource-group $resource_group --name $vm_name
}

function get_vm_username {
	local resource_group
	local vm_name

	if [ $# -lt 2 ]; then
		echo "${FUNCNAME[0]} needs 2 arguments: the resource_group and the vm_name" 1>&2

		exit 1
	fi

	resource_group=$1
	vm_name=$2

	az vm show --resource-group $resource_group --name $vm_name -d --query '[osProfile.adminUsername]' --output tsv
}

function get_vm_private_ip {
	local resource_group
	local vm_name

	if [ $# -lt 2 ]; then
		echo "${FUNCNAME[0]} needs 2 arguments: the resource_group and the vm_name" 1>&2

		exit 1
	fi

	resource_group=$1
	vm_name=$2

	az vm show --resource-group $resource_group --name $vm_name -d --query '[privateIps]' --output tsv
}

# Create a vm with given size (like Standard_D32a_v4) and OS disk size (in GB).
function create_vm {
	local resource_prefix
	local resource_group
	local vm_size
	local disk_size
	local image
	local use_bastion

	local vm

	if [ $# -lt 6 ]; then
		echo "${FUNCNAME[0]} needs 5 arguments: the resource_prefix, the resource_group, the vm_size, disk_size, the image and use_bastion" 1>&2

		exit 1
	fi

	resource_prefix=$1
	resource_group=$2
	vm_size=$3
	disk_size=$4
	image=$5
	use_bastion=$6

	vm="${resource_prefix}vm"

	subnet_args=''
	if [ "${use_bastion}" = 'false' ]; then
		subnet_args="--subnet $(get_kv1_id)"
	fi

	az vm create --resource-group $resource_group --name $vm $subnet_args --image $image --admin-username ${resource_prefix} --generate-ssh-keys --size $vm_size --os-disk-size-gb $disk_size --security-type Standard -o none

	# To extend OS disk space of an already existing VM, you can do the following:
# 	disk_name=$(az disk list --resource-group $resource_group --query '[*].{Name:name,Gb:diskSizeGb,Tier:accountType}' -o tsv | grep $vm | cut -f1)
# 	az vm deallocate -g $resource_group -n $vm
# 	az disk update --resource-group $resource_group --name $disk_name --size-gb $disk_size --sku StandardSSD_LRS
# 	az vm start -g $resource_group -n $vm

	# "Returns" the VM name to connect it with bastion.
	echo $vm
}

# Create a virtual network.
function create_vnet {
	local resource_prefix
	local resource_group

	local vn

	if [ $# -lt 2 ]; then
		echo "${FUNCNAME[0]} needs 2 arguments: the resource_prefix and the resource_group" 1>&2

		exit 1
	fi

	resource_prefix=$1
	resource_group=$2

	vn="${resource_prefix}vn"

	az network vnet create --resource-group $resource_group --name $vn --address-prefix 10.1.0.0/16 --subnet-name default --subnet-prefix 10.1.0.0/24 -o none

	# Returns the vnet
	echo $vn
}

# Create a bastion.
function create_bastion {
	local resource_prefix
	local resource_group
	local vnet_name
	local location

	local public_ip
	local bastion

	if [ $# -lt 4 ]; then
		echo "${FUNCNAME[0]} needs 4 arguments: the resource_prefix, the resource_group, the vnet_name and the location" 1>&2

		exit 1
	fi

	resource_prefix=$1
	resource_group=$2
	vnet_name=$3
	location=$4

	public_ip="${resource_prefix}publicip"
	bastion="${resource_prefix}bastion"

	# WARNING The name MUST be AzureBastionSubnet:
	# https://learn.microsoft.com/en-us/azure/bastion/create-host-cli#createhost
	az network vnet subnet create --name AzureBastionSubnet --resource-group $resource_group --vnet-name $vnet_name --address-prefix 10.1.1.0/26 -o none

	az network public-ip create --resource-group $resource_group --name $public_ip --sku Standard --location $location -o none

	# Use Standard as sku and --enable-tunneling to avoid the following error:
	# Bastion Host SKU must be Standard or Premium and Native Client must be enabled.
	# Moreover, --enable-ip-connect permits using --target-ip-address for
	# az network bastion tunnel.
	az network bastion create --name $bastion --public-ip-address $public_ip --resource-group $resource_group --vnet-name $vnet_name --location $location --sku Standard --enable-ip-connect --enable-tunneling -o none

	# "Returns" the created bastion
	echo $bastion
}

function craft_windows_password {
	password=$(echo $RANDOM | md5sum | head -c 10)

	echo -n "${password}&U"
}

# Create a Windows vm.
function create_windows_vm {
	local resource_prefix
	local resource_group

	local vm
	local password

	if [ $# -lt 2 ]; then
		echo "${FUNCNAME[0]} needs 2 arguments: the resource_prefix and the resource_group" 1>&2

		exit 1
	fi

	resource_prefix=$1
	resource_group=$2

	vm="${resource_prefix}vm"
	password=$(craft_windows_password)

	az vm create --resource-group $resource_group --name $vm --public-ip-sku Standard --image 'MicrosoftWindowsDesktop:windows11preview:win11-21h2-pro:22000.194.2109250206' --admin-username ${resource_prefix} --admin-password $password

	echo -e "VM was created.\nYou should be able to connect using: xfreerdp -u:${resource_prefix} -v:$(az vm show --resource-group $resource_group --name $vm -d --query [publicIps] --output tsv) with the following password: ${password}"
}

# Create a registry by first trying if name is already taken.
# If this is the case, $RANDOM will be concatenated to name and group will be
# tried to be created.
function create_container_registry {
	local resource_prefix
	local resource_group
	local registry

	if [ $# -lt 2 ]; then
		echo "${FUNCNAME[0]} needs two arguments: the resource_group and the resource_prefix" 1>&2

		exit 1
	fi

	resource_group=$1
	resource_prefix=$2
	registry="${resource_prefix}registry"

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
