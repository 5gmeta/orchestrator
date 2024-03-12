#!/bin/bash
#
# Date: 28/06/2022
# Author: Arslane HAMZA-CHERIF
# Organization: VEDECOM
# 
# 
# 
# Script for cleaning a faulty deployement

echo "1-Unistalling and cleaning OSM"
# Remove osm deployments and services
kubectl delete ns osm

# Delete osm docker images and volumes
for module in ro lcm keystone nbi mon pol ng-ui osmclient; do
    docker image rm opensourcemano/${module}
done
sudo rm -rf /var/lib/osm/osm
sudo rm -rf /etc/osm/docker

# Remove controller
sg lxd -c "juju kill-controller -t 0 -y osm"
#juju destroy-model controller
#juju destroy-model osm
#juju remove-k8s k8scloud --client
#juju remove-cloud k8scloud
#juju destroy-controller --release-storage --destroy-all-models -y osm

# Remove crontab job
crontab -l | grep -v '/usr/share/osm-devops/installers/update-juju-lxc-images'  | crontab -

# Uninstall osmclient
sudo apt-get remove --purge -y --allow-change-held-packages python3-osmclient

# Purge previous SNAP modules: lxd, juju, jq"
sudo snap remove --purge lxd
sudo snap remove --purge juju
sudo snap remove --purge jq 

sudo rm -rf $HOME/5gmeta/logs/osm*
------------------------------

echo "2-Reseting Kubeadm"
sudo kubeadm reset 

------------------------------

echo "3-Unholding APT modules: kubeadm, kubectl kubelet"
sudo apt-mark unhold kubeadm kubectl kubelet 

------------------------------

echo "4-Purging APT modules: kubeadm, kubectl kubelet kubernetes-cli"
sudo apt-get purge kubeadm kubectl kubelet kubernetes-cni 
sudo apt-get autoremove

------------------------------

echo "5-Deleting previous config files"
sudo rm -rf $HOME/.kube /etc/cni/net.d $HOME/.cache/helm $HOME/.config/helm $HOME/5gmeta /etc/kubernetes/ $HOME/.local/share/juju/

------------------------------

echo "6-Restoring initial iptable config"
sudo iptables-restore $HOME/5gmeta/tmp/iptables_ORIGINAL.txt
sudo rm $HOME/5gmeta/tmp/iptables_ORIGINAL.txt

------------------------------

echo "7-Restoring initial etc/fstab & enabling SWAP"
sudo cp $HOME/5gmeta/tmp/fstab_ORIGINAL /etc/fstab
sudo rm $HOME/5gmeta/tmp/fstab_ORIGINAL
sudo swapon -a 
