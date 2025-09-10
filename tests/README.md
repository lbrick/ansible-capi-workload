# Testing NeSI RDC CAPI Workload Clusters

## Overview

This directory provides automated tests for verifying the ansible-capi-workload role, including cluster creation, validation, and cleanup scenarios within the NeSI RDC environment.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Setup](#setup)
- [Configuration](#configuration)
- [Running Tests](#running-tests)
- [Available CAPI Images](#available-capi-images)
- [Test Scenarios](#test-scenarios)
- [Troubleshooting](#troubleshooting)

## Prerequisites

### Required Access
- Active NeSI RDC project with sufficient quotas
- SSH key pair registered in NeSI RDC
- Working CAPI management cluster (see main README)
- Network and security group creation permissions

### Required Tools
- Ansible 2.15+ and ansible-core
- Python 3.8+ with openstacksdk
- kubectl configured for management cluster
- Git for cloning repositories

### Environment Preparation
Ensure kubectl context is set to your management cluster:

```bash
kubectl config current-context
# Should show your CAPI management cluster
```

## Setup

### 1. Prepare Test Directory
Navigate to the tests directory in your ansible-capi-workload checkout.

### 2. Install Ansible Dependencies

```bash
ansible-galaxy collection install -r requirements.yml
```

### 3. Setup Python Virtual Environment (Recommended)

For security group management and dependency isolation:

```bash
# Create virtual environment
python3 -m venv ~/capi-test-venv

# Activate
source ~/capi-test-venv/bin/activate

# Install dependencies
pip install ansible ansible-core openstacksdk
```

## Configuration

### Test Variables Setup

1. **Copy Template:**
   ```bash
   cp test_vars.yml.example test_vars.yml
   ```

2. **Configure Variables:**

   Edit `test_vars.yml` with your NeSI RDC project specifics:

   ```yaml
   kubernetes_version: v1.31.1
   capi_image_name: rocky-9-containerd-v1.31.1

   cluster_rdc_project: NeSI_RDC_PROJECT_NAME
   cluster_name: CAPI_CLUSTER_NAME
   cluster_namespace: default

   capi_management_cluster: MANAGEMENT_CLUSTER_NAME

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

### Variable Explanations

- `NeSI_RDC_PROJECT_NAME`: Your RDC project name (e.g., NeSI-Training-Test)
- `CAPI_CLUSTER_NAME`: Unique test cluster identifier
- `MANAGEMENT_CLUSTER_NAME`: Name of your CAPI management cluster
- `NeSI_RDC_KEYPAIR_NAME`: SSH key pair registered in your RDC project
- Network CIDRs must not conflict with existing NeSI resources
- Source IPs should include your management cluster network ranges

## Running Tests

### Complete Test Cycle

1. **Create Cluster:**
   ```bash
   ansible-playbook -i inventory.ini test_create.yml
   ```

2. **Verify Deployment:**
   ```bash
   ansible-playbook -i inventory.ini test_assert.yml
   ```

3. **Clean Up:**
   ```bash
   ansible-playbook -i inventory.ini test_cleanup.yml
   ```

### Manual Execution from Parent Directory

If running from ansible-capi-workload root:

```bash
cd ansible-capi-workload

ansible-playbook -i tests/inventory.ini tests/test_create.yml
ansible-playbook -i tests/inventory.ini tests/test_assert.yml
ansible-playbook -i tests/inventory.ini tests/test_cleanup.yml
```

## Available CAPI Images

Supported Rocky 9-based Kubernetes images:

```
rocky-9-containerd-v1.28.14
rocky-9-containerd-v1.29.7
rocky-9-containerd-v1.30.5
rocky-9-containerd-v1.31.1
rocky-9-containerd-v1.31.6
rocky-9-containerd-v1.32.2
rocky-9-containerd-v1.32.7
rocky-9-containerd-v1.33.3
```

**Important**: Ensure the `capi_image_name` matches the `kubernetes_version` exactly.

## Test Scenarios

### Validation Content

The `test_assert.yml` playbook validates:

- **Cluster Creation**: Successful deployment of control plane and worker nodes
- **Node Readiness**: All nodes in Ready state
- **Networking**: Pod-to-pod communication and external access
- **Kubernetes API**: Access via generated kubeconfig
- **Optional Components**: GPU operators, CNIs, autoscaler if enabled
- **Security**: Proper security group rules and access controls

### Test Variations

You can modify test scenarios by adjusting variables:

- **GPU Tests**: Set `enable_gpu_nodes: true`
- **CNI Tests**: Change `cni_type` to test Calico vs Cilium
- **Autoscaling Tests**: Set `cluster_max_worker_count > cluster_worker_count`
- **Security Group Tests**: Toggle `capi_managed_secgroups`

### Expected Runtime

- Basic cluster creation: 15-20 minutes
- With GPU nodes: 25-35 minutes
- Full test cycle: 30-45 minutes

## Troubleshooting

### Common Test Issues

**Ansible Connection Failures:**
- Verify SSH key permissions and paths
- Ensure security groups allow SSH from your location
- Confirm VM flavors are available and correctly spelled

**Terraform/OpenStack Errors:**
- Check RDC quotas for instances, floating IPs, security groups
- Verify OpenStack credentials and project permissions
- Ensure network and subnet configurations are valid

**Kubernetes Deployment Failures:**
- Confirm management cluster is accessible and functional
- Verify CAPI provider versions match
- Check node readiness and kubelet logs

**Security Group Creation Errors:**
- Confirm OpenStack permissions for security group management
- Ensure no naming conflicts with existing resources
- Verify role variables for security group configuration

### Debug Steps

1. **Enable Verbose Output:**
   ```bash
   ansible-playbook -i inventory.ini -vv test_create.yml
   ```

2. **Check Cluster Status:**
   ```bash
   kubectl get clusters -A
   kubectl get machines -A
   ```

3. **Review OpenStack Resources:**
   ```bash
   openstack server list --project your-project
   openstack security group list
   ```

4. **Examine Ansible Logs:**
   - Review console output for task failures
   - Check individual task results for OpenStack API errors
   - Verify variable values at runtime

### Getting Help

- Review main README for detailed feature explanations
- Check NeSI RDC documentation for environment-specific issues
- Verify compatibility with management cluster versions
- Ensure all prerequisite access and credentials are correct

This test framework enables confident deployment and validation of ansible-capi-workload changes within NeSI RDC environments.