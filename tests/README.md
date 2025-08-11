## Setup

Make a copy of the file `test_vars.yml.example` and fill in the requried parameters

``` { .sh }
cp -r ./test_vars.yml.example ./test_vars.yml
```

Some of the parameters to change

``` { .sh }
kubernetes_version: v1.27.6
capi_image_name: rocky-89-kube-v1.27.6

cluster_rdc_project: NeSI_RDC_PROJECT_NAME
cluster_name: CAPI_CLUSTER_NAME
cluster_namespace: default

capi_management_cluster: MANGEMENT_CLUSTER_NAME

openstack_ssh_key: NeSI_RDC_KEYPAIR_NAME

cluster_control_plane_count: 1
control_plane_flavor: balanced1.2cpu4ram

cluster_worker_count: 2
worker_flavour: balanced1.2cpu4ram

cluster_node_cidr: 10.10.0.0/24
cluster_pod_cidr: 192.168.0.0/16
cluster_route_id: 3c0cb930-2bbe-4c9c-ac61-6dbc9410c3e9

clouds_yaml_location: ~/.config/openstack/clouds.yaml
clouds_yaml_cloud: openstack

kube_config_local_location: ~/.kube/config
kube_config_location: "~/.kube"

kube_oidc_auth: false

capi_managed_secgroups: true

yaml_openstack_cloud: openstack

source_ips:
  - 163.7.144.0/21
  - "{{ cluster_node_cidr }}"
```

`NeSI_RDC_PROJECT_NAME` needs to be replaced with your NeSI RDC Project name e.g. NeSI-Training-Test

`CAPI_CLUSTER_NAME` the name of your cluster

`MANGEMENT_CLUSTER_NAME` the name of your management cluster that this workload cluster will deploy from

`NeSI_RDC_KEYPAIR_NAME` the name of your keypair that is in the NeSI RDC

There are the following CAPI images available

``` { .sh }
rocky-9-containerd-v1.28.14
rocky-9-containerd-v1.29.7
rocky-9-containerd-v1.30.5
rocky-9-containerd-v1.31.1
rocky-9-containerd-v1.31.6
rocky-9-containerd-v1.32.2
rocky-9-containerd-v1.32.7
rocky-9-containerd-v1.33.3
```

## Install ansible dependencies

``` { .sh }
ansible-galaxy collection install -r requirements.yml
```

## If looking to create ansible managed security groups

It is recommended to use a python virtual environment to contain the required dependencies.

``` { .sh }
# create a virtual environment using the Python3 virtual environment module
python3 -m venv ~/capi-venv

# activate the virtual environment
source ~/capi-venv/bin/activate

# install ansible into the venv
pip install ansible ansible-core

# install the openstacksdk
pip install "openstacksdk>=1.0.0"
```

## Run Tests

From the directory above ansible-capi-workload, run:

```
cd ansible-capi-workload

ansible-playbook -i tests/inventory.ini tests/test_create.yml
ansible-playbook -i tests/inventory.ini tests/test_assert.yml
ansible-playbook -i tests/inventory.ini tests/test_cleanup.yml
```