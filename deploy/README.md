# Edge Stack Deployment
In order to easily deploy all the components forming the 5GMETA Edge Stack, an unique Ansible playbook will be used. The following playbook will install all the dependencies and components and repositories necessary for the 5GMETA platform's MEC server.

Furthermore, every time a change is made in the stack, it will be reflected in the playbook and running it again will let to update the deployment without extra effort.

The only requeriment to deploy the stack is an Ubuntu 20.04 image. I can also be an Ubuntu 18.04 image, but in that case OSM 10 will be installed instead OSM 11.

**The server needs at least 16 GB of RAM, 4 vCPUs and 60 GB of disk.**

The playbook will the deploy the following components:
- Docker Engine
- Single-node Kubernetes cluster (v1.20.11)
	- Composed by Flannel CNI, OpenEBS Storage and MetalLB Load-balancer
- Helm k8s application manager
- Kube-prometheus-stack and Kube-eagle for k8s monitoring
	- Prometheus, Grafana and dashboards
- MySQL cluster
- Open Source MANO (OSM): v11 for Ubuntu 20.04 and v10 for Ubuntu 18.04
- Notary and Connaisseur for managing security in the cluster
- 5GMETA MEC APIs and Base Components

## Installing requirements
To run the Ansible playbook, some packages & Ansible collections must be installed before in the control node:

	sudo apt-add-repository ppa:ansible/ansible
	sudo apt update
	sudo apt-get install curl python3-pip ansible
	ansible-galaxy collection install community.general community.docker kubernetes.core
	
In Ubuntu 18.04:

	sudo apt-get install python3-distutils
	python3 get-pip.py
	python3 -m pip install ansible
	ansible-galaxy collection install community.general community.docker kubernetes.core

**For RP1, the public IP of the server should be whitelisted, please contact Vicomtech to add it to the list.**

## Deploying the Edge Stack
After installing the previous requirements, the Ansible playbook should be downloaded:

	curl -s https://<id>@raw.githubusercontent.com/5gmetadmin/orchestrator/main/deploy/EdgeDeployment.yaml -o EdgeDeployment.yaml

Then, before running it, the playbook's hosts field or Ansible's inventory file must be modified to match the Ubuntu machine. Vars section must be also filled with the user provided values. After that it can be runned:

	ansible-playbook EdgeDeployment.yaml

Once deployed you can access the different services in the next ports:
- K8s API in port 6443
- K8s UI in port 8080
- OSM UI in port [80](http://127.0.0.1:80)
- OSM API (Orchestration API) in port 9999
- Grafana UI in port [3000](http://127.0.0.1:3000)
- Grafana/Loki UI in port [7000](http://127.0.0.1:7000)
- Prometheus UI in port [9090](http://127.0.0.1:9090)
- Alert Manager UI in port [9093](http://127.0.0.1:9093)
- 5GMETA Edge Instance API in port 5000
- 5GMETA Registration API in port 12346
- 5GMETA Message-Broker in port 5673 (SB) and 61616 (NB)
- 5GMETA Video-Broker in port 8443

Also you can check the status of OSM ressources managed by Kubernetes in the following way:

	kubectl get all -n osm


## Re-deploying starting from a specific task of the Ansible playbook
If the deployement fails for any reason and you want to play again the playbook starting from a specific task, then you do the following:

	# For running the playbook starting from the "Get IP geolocation data" task
	ansible-playbook EdgeDeployment.yaml --start-at-task="Get IP geolocation data"

### Enable no username/password in a running MEC
```
$ ansible-playbook EdgeDeployment.yaml --tag "deploy_k8s_prometheus_grafana"
$ ansible-playbook EdgeDeployment.yaml --tag "expose_k8s_grafana"
```
### Enable pods log monitoring in a running MEC
```
$ ansible-playbook EdgeDeployment.yaml --tag "deploy_grafana_loki"​
$ ansible-playbook EdgeDeployment.yaml --tag "expose_grafana_loki"
```

## Executing only a pecific task of the Ansible playbook
If instead you want to execute a single task of the playbook, then you can force Ansible to ask for a confirmation before executing the next step, and abort execution when needed:

	# For running only the "Get IP geolocation data" task, abort execution (ctrl+c) when asked to confirm execution of the following step

	ansible-playbook playbook.yml --step --start-at-task="install packages"

## Cleaning deployment
To clean the deployment, use the **cleanDeployment.sh** script.

## Known/Potential issues related to Ansible playbook execution

- ### You are runninng the installer as root
This error can be resolved by running the playbook with the current user and not **the root user**, while having sudo privileges:

	sudo -u $USER ansible-playbook EdgeDeployment.yaml --ask-become-pass

- ### Couldn't resolve module/action 'community.general.ipinfoio_facts'

This error is due to the usage of an old version of ansible, and can be easily resolved through:

	sudo apt purge ansible
	sudo apt-add-repository ppa:ansible/ansible
	sudo apt update
	sudo apt install ansible
	ansible-galaxy collection install community.general community.docker kubernetes.core --force

- ### Cannot uninstall 'PyYAML'

PyYAML is potentially installed and already bundled into some core packages of the distro. To force installation of required PyYAML version:

	sudo pip install --ignore-installed PyYAML

## Known/Potential issues related to Docker

- ### Docker-credential-secretservice failure

If the playbook fails in Docker login task (e.g	**Docker-credential-secretservice fails on Ubuntu 18.04: error getting credentials - err: exit status 1, out:GDBus.Error:org.freedesktop.DBus.Error.ServiceUnknown: The name org.freedesktop.secrets was not provided by any .service files**:), run the following commannd and then the ansible again:
	
	sudo apt install gnupg2 passls -la

## Known/Potential issues related to Kubernetes

- ### Failure of Kubernetes Cluster init due to unvalidated docker version

This error is due to the usage of an unvalidated docker version. To fix it add the following arguments like follows:

	# Not working
	- kubeadm init --config {{ ansible_env.HOME }}/5gmeta/tmp/cluster-config.yaml > {{ ansible_env.HOME }}/5gmeta/logs/cluster_init

	# Working
	- kubeadm init --ignore-preflight-errors=SystemVerification --config {{ ansible_env.HOME }}/5gmeta/tmp/cluster-config.yaml > {{ ansible_env.HOME }}/5gmeta/logs/cluster_init

- ### Failure with validating the existence and emptiness of directory /var/lib/etcd

This error can be easily fixed by removing the directory:

	sudo rm /var/lib/etcd

## Known/Potential issues related to OSM

- ### Failure of OSM install with several deployements still pending
If OSM installation fails due to pending deployements, like below:

	5 of 9 deployments starting:
					lcm	0/1	0
					mon	0/1	0
					nbi	0/1	0
					pol	0/1	0
					ro	0/1	0
	SYSTEM IS BROKEN
	OSM is not healthy, but will probably converge to a healthy state soon.
	Check OSM status with: kubectl -n osm get all
	DONE

Identifying the root cause can be difficult. Still a potential solution is to check the logs related to such deployements like below:
	
	sudo kubectl get all -n osm

	#command output!!!
	NAME                                READY   STATUS     RESTARTS   AGE
	pod/grafana-855d96c47d-w4xfs        2/2     Running    0          66m
	pod/kafka-0                         1/1     Running    3          66m
	pod/keystone-7d9864f8f5-qx4dd       1/1     Running    0          66m
	pod/lcm-556b46f977-c2ljl            0/1     Init:0/1   0          66m
	pod/modeloperator-946f64449-mffbc   1/1     Running    0          66m
	pod/mon-577c8fc975-9kndp            0/1     Init:0/1   0          66m
	pod/mysql-0                         1/1     Running    0          66m
	pod/nbi-7886459c9f-mldhw            0/1     Init:0/1   0          66m
	pod/ng-ui-7d98c6568f-d8862          1/1     Running    0          66m
	pod/pol-7f86867d95-vm762            0/1     Init:0/1   0          66m
	pod/prometheus-0                    1/1     Running    0          66m
	pod/ro-ddbc9f888-6jmlp              0/1     Init:0/1   0          66m
	pod/zookeeper-0                     1/1     Running    0          66m

Then it is possible to get details related to a specific deployment:

	kubectl describe pod/lcm-556b46f977-c2ljl -n osm

	#command output!!!
	Name:         lcm-556b46f977-c2ljl
	Namespace:    osm
	Priority:     0
	....
	....
	Init Containers:
	kafka-ro-mongo-test:
		Container ID:  docker://8c4fb0ce225af5c4419441c21b1493da252441b83fbe963d4ef7125c44389591
		Image:         alpine:latest
		Image ID:      docker-pullable://
		....
		....

And finally to check its logs and identify the root cause

	kubectl logs pod/lcm-556b46f977-c2ljl-n osm -c kafka-ro-mongo-test

	#command output!!!
	nc: bad address 'mongodb-k8s'
	kafka (10.244.0.25:9092) open
	nc: bad address 'mongodb-k8s'
	kafka (10.244.0.25:9092) open

- ### OSM command returning "ModuleNotFoundError: No module named 'prettytable'

This error can be easily fixed by:

	sudo apt install python3-prettytable

- ### OSM command returning TypeError: __init__() got an unexpected keyword argument 'case_sensitive'

This error can be easily fixed by:

	pip3 install -U click
	
## Authors
- Mikel Serón Esnal ([mseron@vicomtech.org](mailto:mseron@vicomtech.org), [GitHub](https://github.com/mikelseron))
