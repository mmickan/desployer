**This repository has been archived**

I haven't touched this -- or libvirt -- for a long time.

# Desployer

Desployer is a suite of shell scripts for deploying (and later destroying)
virtual machines with libvirt.

The intention is to provide simple setup of a QA environment from within a
CI tool such as [Jenkins](http://jenkins-ci.org), while also being suitable
for deployment of VMs in a production environment.

Currently targeted at Ubuntu and tested only against Ubuntu 14.04 virtual
machine hosts and virtual machines.  Profiles are included for puppet master
and puppet agent VMs, but the framework is in place to easily provide
additional VM profiles.

Please note that these scripts are a work in progress and currently fairly
rough (though they're already working in my environment).  Feedback and
pull requests are both most welcome.

## The Scripts

High level scripts:

* start-domain: deploy configuration for and start a given set of VMs
* remove-domain: destroy and remove configuration for a given set of VMs

Low level scripts:

* deploy-vm: deploy configuration (disks + VM definition) for a given VM
* remove-vm: the opposite of deploy-vm, removes all configuration for a VM
* start-vm: start a VM for which configuration is already deployed
* shutdown-vm: stop a running VM

Helper scripts:

* create-*-domain: prepare data store for deployment of a given set of VMs
* upload-gm: upload a gold master image to a libvirt storage pool

## Quickstart Guide

You'll need the following tools/environment:

* At least one virtual machine host running KVM/libvirt
* A user account capable of starting virtual machines on each virtual machine host, and password-less ssh access between them
* A [Consul](http://consul.io/) cluster running on the virtual machine host(s)
* Optionally, [jq](http://stedolan.github.io/jq/) to view information from Consul
* A golden master image with cloud-init installed - see my ubuntu-14.04 [Packer](http://packer.io) template in [my packer templates repo](https://github.com/mmickan/packer-templates)

Make a copy of the create-qa-domain script, or edit it for your environment.
Run that script to populate Consul with configuration information for your
VMs.

Deploy your gold master image to each virtual machine host, using the
upload-gm helper script.

If any of your virtual machine hosts don't have the appropriate hardware for
KVM acceleration, configure them to use the qemu.xml.erb template in the
deploy-vm script's vm_template array.  Note that the name of the virtual
machine host in that array must match the name used in the create-*-domain
script exactly.

Run the start-domain script and watch as each VM is deployed.

## Misc notes

Useful jq commands for use with Consul:

Comma separated list of CheckIDs for passing checks on current node:
```
curl -s http://localhost:8500/v1/agent/checks | jq -c '[map(select(.Status == "passing"))|.[].CheckID]' | sed 's/[]"[]//g'
```

Comma separated list of Services on a given node ($node):
```
curl -s http://localhost:8500/v1/catalog/node/$node | jq -c '[.Services[].Service]' | sed 's/[]"[]//g'
```
