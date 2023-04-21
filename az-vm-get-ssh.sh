#! /usr/bin/env bash
# Copyright (c) 2023 Francis Laniel <flaniel@linux.microsoft.com>
# SPDX-License-Identifier: MPL-2.0


source az-sources.sh

function usage {
	echo "Usage: $0 [-g resource_group] [-n vm_name] [-s]" 1>&2
	echo -e "\t-g: The resource group to search the VM." 1>&2
	echo -e "\t-n: The VM to get the IP." 1>&2
	echo -e "\t-s: Start the VM unconditionnaly (in case they were deallocated)." 1>&2
	echo -e "\t-h: Print this help message." 1>&2
}

resource_group=''
vm_name=''

while getopts "g:n:sh" option; do
	case $option in
	g)
		resource_group=${OPTARG}
		;;
	n)
		vm_name=${OPTARG}
		;;
	s)
		start_vm='yes'
		;;
	h|\?)
		usage
		exit 1
	esac
done

if [ -z $resource_group ]; then
	usage

	exit 1
fi

# az login --scope https://management.core.windows.net//.default

if [ -n "${vm_name}" ]; then
	if [ -n "${start_vm}" ]; then
		echo "Starting $resource_group:$vm_name!"

		start_vm $resource_group $vm_name
	fi

	echo "Use the following to ssh to ${vm_name}: ssh $(get_vm_username $resource_group $vm_name)@$(get_vm_private_ip $resource_group $vm_name)"

	exit
fi

for vm_name in $(az vm list -g $resource_group --query '[].name' --output tsv); do
	if [ -n "${start_vm}" ]; then
		echo "Starting $resource_group:$vm_name!"

		start_vm $resource_group $vm_name
	fi

	echo "Use the following to ssh to ${vm_name}: ssh $(get_vm_username $resource_group $vm_name)@$(get_vm_private_ip $resource_group $vm_name)"
done
