# NeSI RDC CAPI Workload Cluster Role

## Overview

This repository provides an Ansible role for deploying Cluster API (CAPI) workload clusters on NeSI RDC (Research and Development Cloud) infrastructure. It leverages an existing CAPI management cluster to provision and configure workload clusters using the Kubernetes Cluster API Provider OpenStack.

### Key Features
- Automated CAPI workload cluster provisioning with OpenStack integration
- Support for GPU-enabled nodes and workloads
- Built-in autoscaling with Cluster Autoscaler
- Multiple Container Network Interface (CNI) options (Calico, Cilium)
- Integrated monitoring and metrics collection
- Health checks and security group management
- Support for Rocky Linux-based Kubernetes node images
- Compatible with NeSI RDC environment

### Architecture Summary
This Ansible role generates cluster templates using Jinja2 templates, applies them to the management cluster, and provisions the workload cluster on OpenStack infrastructure. It supports optional components like GPU operators, CNIs, autoscaler, metrics server, health checks, and cloud manager.

### Management Support Matrix

The Management version matrix represents the versions of this Workload repo which are recommended with the Management repo versions

| Management Version   | Workload Version |
| -------------------- | ---------------- |
| v0.2.X               | v0.3.X           |
| v0.4.X               | v0.4.X           |

Related repository: [NeSI RDC CAPI Management Cluster](https://github.com/nesi/nesi.rdc.kind-bootstrap-capi)

The CAPI images are generated from the following image builder repo: [CAPI Images](https://github.com/lbrick/image-builder/tree/2023-nesi_images)

## Table of Contents
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Detailed Setup](#detailed-setup)
- [Configuration](#configuration)
- [Deployment](#deployment)
- [Extending Features](#extending-features)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [Notes](#notes)

## Prerequisites

### Required Access
- Active NeSI RDC project with OpenStack API access
- SSH key pair registered in NeSI RDC
- CAPI management cluster deployed and accessible (see related repository above)
- Sufficient compute and network quotas for workload cluster deployment

### Required Tools
- Ansible 2.15+ and ansible-core
- Python 3.8+
- OpenStack SDK (`pip install openstacksdk>=1.0.0`)
- kubectl configured for the management cluster

### Environment Setup
It is recommended to use a Python virtual environment to isolate dependencies:

```bash
# Create virtual environment
python3 -m venv ~/capi-workload-venv

# Activate
source ~/capi-workload-venv/bin/activate

# Install dependencies
pip install ansible ansible-core openstacksdk
```

### OpenStack Credentials
- Download `clouds.yaml` from NeSI RDC dashboard
- Place at `~/.config/openstack/clouds.yaml`
- Use Application Credentials rather than personal credentials for security

## Quick Start

For experienced users:

1. **Setup Environment:**
   ```bash
   # Activate virtual environment
   source ~/capi-workload-venv/bin/activate
   ```

2. **Configure Variables:**
   Copy `defaults/main.yml` to your playbook vars and customize:

   ```bash
   cp defaults/main.yml playbook_vars.yml
   # Edit with your values
   ```

3. **Deploy:**
   ```bash
   ansible-playbook -e @playbook_vars.yml main.yml
   ```

The deployment will create the workload cluster with configured components.

## Detailed Setup

### Variables Configuration

The role uses variables defined in `defaults/main.yml`. Key variables include:

- `kubernetes_version`: Target Kubernetes version (e.g., `v1.31.1`)
- `capi_image_name`: Pre-built CAPI image name
- `cluster_name`: Name of the workload cluster
- `cluster_namespace`: Namespace for the cluster
- `cluster_control_plane_count`: Number of control plane nodes
- `control_plane_flavor`: VM flavor for control plane
- `cluster_worker_count`: Number of worker nodes
- `worker_flavor`: VM flavor for workers
- `cluster_node_cidr`: Node network CIDR
- `cluster_pod_cidr`: Pod network CIDR
- `enable_gpu_nodes`: Enable GPU support
- `cluster_max_worker_count`: Enable autoscaling if > cluster_worker_count

### Supported Kubernetes Versions and Images

Available CAPI images (Rocky 9 base):

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

## Configuration

### CNI Options
- Calico (default)
- Cilium
- Configure via `cni_type` variable

### GPU Configuration
If `enable_gpu_nodes` is true:
- Deploys GPU node with NVIDIA operator and drivers
- Includes MPS configuration for multi-process service
- Uses flavor `gpu1.44cpu240ram.a40.1g.48gb`

### Autoscaling
Set `cluster_max_worker_count > cluster_worker_count` to enable Cluster Autoscaler.

### Security Groups
- Managed via Ansible by default (`capi_managed_secgroups: true`)
- Creates rules for cluster communication and external access from specified source IPs

## Deployment

### Using the Role

Include this role in your Ansible playbook:

```yaml
- hosts: localhost
  roles:
    - role: ansible-capi-workload
      vars:
        kubernetes_version: v1.31.1
        cluster_name: my-workload-cluster
        # ... other variables
```

### Manual Execution

Run directly:

```bash
ansible-playbook main.yml -e "kubernetes_version=v1.31.1 cluster_name=my-cluster"
```

### Verification

After deployment:

```bash
kubectl get clusters -A
kubectl get secrets -n <cluster-namespace> <cluster-name>-kubeconfig -o jsonpath='{.data.value}' | base64 -d > kubeconfig
kubectl --kubeconfig=kubeconfig get nodes
```

## Extending Features

### GPU Support
Set `enable_gpu_nodes: true` to add GPU nodes with:
- NVIDIA GPU Operator
- Multi-Process Service configuration
- Automated driver installation

### Cluster Autoscaler
Configured when `cluster_max_worker_count > cluster_worker_count`

### Metrics Server
Deployed by default to enable `kubectl top` commands

### Health Checks
Adds HTTP health checks for control plane and worker nodes via OpenStack load balancers

### Cloud Manager
Integrates OpenStack Cloud Controller Manager for load balancers, network services, and storage integration

### Multiple CNIs
- **Calico**: Robust networking with network policies and optional operator installation
- **Cilium**: High-performance networking with eBPF-based observability

## Troubleshooting

### Common Issues

**Management Cluster Inaccessible:**
- Verify kubectl context points to management cluster
- Check network connectivity to management cluster

**OpenStack Quota Exceeded:**
- Confirm sufficient compute, network, and security group quotas
- Check flavor availability in your project

**CAPI Image Mismatch:**
- Ensure `capi_image_name` matches `kubernetes_version`
- Verify image availability in NeSI RDC

**GPU Node Provisioning:**
- Confirm GPU flavors are available in your project
- Check NVIDIA operator installation logs

**Security Group Creation:**
- Verify OpenStack permissions for security group management
- Confirm no name conflicts

### Logs and Debugging
- Ansible playbook output for deployment steps
- Kubernetes cluster creation logs: `kubectl logs -n capi-system deployment/cluster-api-controller-manager`
- Workload cluster logs after provisioning: `kubectl --kubeconfig=kubeconfig logs`

### Getting Help
- Review NeSI RDC documentation for infrastructure-specific issues
- Check upstream CAPI OpenStack provider documentation
- Ensure compatible Kubernetes and CAPI versions

## Contributing

1. Fork the repository
2. Create a feature branch
3. Submit pull requests for review
4. Follow existing code structure and naming conventions

## Notes

This setup is specifically designed for NeSI RDC OpenStack environment. For other cloud providers, adjust variables and configuration accordingly while maintaining the CAPI-based provisioning approach.

Support for GPU workloads requires access to GPU flavor's within your NeSI RDC project space.