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
location='westeurope'
architecture=''
core_count=2
node_count=1
with_gpu=''
os=''

while getopts "agc:n:o:s:h" option; do
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
	g)
		with_gpu='true'
		;;
	h|\?)
		echo "Usage: $0 [-n resource_prefix] [-ag] [-c core_count]" 1>&2
		echo -e "\t-n: The given string will be used as resource prefix, $(whoami) by default." 1>&2
		echo -e "\t-a: Use Ampere Altra (i.e. arm64) node, Intel by default." 1>&2
		echo -e "\t-c: The given number will be used as node size, 2 cores by default." 1>&2
		echo -e "\t-s: The given number will be used as node count, 1 node by default." 1>&2
		echo -e "\t-o: The given string will be used as os-sku, Ubuntu by default." 1>&2
		echo -e "\t-g: Add GPU capabilities to the cluster." 1>&2
		exit 1
		;;
	esac
done

az login --use-device-code --scope https://management.core.windows.net//.default

if [ -n "$with_gpu" ]; then
	# GPUs seem to be only available there...
	location='centralus'
fi

resource_group=$(create_resource_group $resource_prefix $location)

# Craft the size string.
node_size=$(printf $SIZE_FORMAT $core_count $architecture)
kubernetes_cluster="${resource_prefix}cluster"

if [ -n "$os" ]; then
	os="--os-sku ${os}"
fi

# Create an Azure Kubernetes Service within above resource group.
az aks create --resource-group $resource_group --name $kubernetes_cluster --node-count $node_count --generate-ssh-keys -s 'Standard_NC24ads_A100_v4' $os
# Get credentials, so kubectl will interact with this cluster.
az aks get-credentials --resource-group $resource_group --name $kubernetes_cluster --overwrite-existing

if [ -n "$with_gpu" ]; then
	# Mainly taken from:
	# https://learn.microsoft.com/fr-fr/azure/aks/use-nvidia-gpu?tabs=add-ubuntu-gpu-node-pool
# 	az aks nodepool add --resource-group $resource_group --cluster-name $kubernetes_cluster --name 'gpu' --node-count $node_count --node-vm-size 'Standard_NC24ads_A100_v4' --node-taints sku=gpu:NoSchedule $os

	kubectl create namespace gpu-resources

	kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: nvidia-device-plugin-daemonset
  namespace: gpu-resources
spec:
  selector:
    matchLabels:
      name: nvidia-device-plugin-ds
  updateStrategy:
    type: RollingUpdate
  template:
    metadata:
      labels:
        name: nvidia-device-plugin-ds
    spec:
      tolerations:
      - key: "sku"
        operator: "Equal"
        value: "gpu"
        effect: "NoSchedule"
      # Mark this pod as a critical add-on; when enabled, the critical add-on
      # scheduler reserves resources for critical add-on pods so that they can
      # be rescheduled after a failure.
      # See https://kubernetes.io/docs/tasks/administer-cluster/guaranteed-scheduling-critical-addon-pods/
      priorityClassName: "system-node-critical"
      containers:
      - image: nvcr.io/nvidia/k8s-device-plugin:v0.18.0
        name: nvidia-device-plugin-ctr
        env:
          - name: FAIL_ON_INIT_ERROR
            value: "false"
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
        volumeMounts:
        - name: device-plugin
          mountPath: /var/lib/kubelet/device-plugins
      volumes:
      - name: device-plugin
        hostPath:
          path: /var/lib/kubelet/device-plugins
EOF
fi

# Parameter 'registry_name' must conform to the following pattern: '^[a-zA-Z0-9]*$'.
# So, let's remove '-'.
create_container_registry $resource_group ${resource_prefix//-/}

create_blob_storage $resource_group $resource_prefix $location

echo -e "Everything should be OK!\nOnce terminated, please delete your resources with: az group delete --no-wait --name ${resource_group}"
