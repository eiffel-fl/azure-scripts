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
architecture=''
core_count=2
node_count=1
os=''

while getopts "ac:n:o:s:h" option; do
	case $option in
	a)
		architecture='p'
		;;
	c)
		core_count=${OPTARG}
		;;
	s)
		node_count=${OPTARG}
		;;
	n)
		resource_prefix=${OPTARG}
		;;
	o)
		os=${OPTARG}
		;;
	h|\?)
		echo "Usage: $0 [-n resource_prefix] [-a] [-c core_count]" 1>&2
		echo -e "\t-n: The given string will be used as resource prefix, $(whoami) by default." 1>&2
		echo -e "\t-a: Use Ampere Altra (i.e. arm64) node, Intel by default." 1>&2
		echo -e "\t-c: The given number will be used as node size, 2 cores by default." 1>&2
		echo -e "\t-s: The given number will be used as node count, 1 node by default." 1>&2
		echo -e "\t-o: The given string will be used as os-sku, Ubuntu by default." 1>&2
		exit 1
		;;
	esac
done

az login --scope https://management.core.windows.net//.default

resource_group=$(create_resource_group $resource_prefix)

# Craft the size string.
node_size=$(printf $SIZE_FORMAT $core_count $architecture)
kubernetes_cluster="${resource_prefix}cluster"

if [ -n "$os" ]; then
	os="--os-sku ${os}"
fi

# Create an Azure Kubernetes Service within above resource group.
az aks create --resource-group $resource_group --name $kubernetes_cluster --node-count $node_count -s $node_size $os
# Get credentials, so kubectl will interact with this cluster.
az aks get-credentials --resource-group $resource_group --name $kubernetes_cluster --overwrite-existing

# Parameter 'registry_name' must conform to the following pattern: '^[a-zA-Z0-9]*$'.
# So, let's remove '-'.
create_container_registry ${resource_prefix//-/}

echo -e "Everything should be OK!\nOnce terminated, please delete your resources with: az group delete --no-wait --name ${resource_group}"
