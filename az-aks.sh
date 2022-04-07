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

kubernetes_cluster="${resource_suffix}cluster"

resource_group=$(create_resource_group $resource_suffix)

# Create an Azure Kubernetes Service within above resource group.
az aks create --resource-group $resource_group --name $kubernetes_cluster --node-count 2 --generate-ssh-keys
# Get credentials, so kubectl will interact with this cluster.
az aks get-credentials --resource-group $resource_group --name $kubernetes_cluster --overwrite-existing

create_container_registry $resource_suffix

echo -e "Everything should be OK!\nOnce terminated, please delete your resources with: az group delete --no-wait --name ${resource_group}"
