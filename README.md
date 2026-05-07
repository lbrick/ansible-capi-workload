# ansible-capi-workload

Generates GitOps fleet entries for CAPI workload clusters on NeSI RDC OpenStack. Produces all files needed to onboard a new cluster into the [reannz-capi-fleet](https://gitlab.com/nesi1/rebase/reannz-capi-fleet) repo.

## How it works

Set `generate_fleet_entry: true` and run the role. Instead of provisioning anything, it writes ready-to-commit files to `fleet-output/`:

```
fleet-output/
├── <cluster_name>/                  # commit as the cluster's own Git repo
│   ├── kustomization.yaml
│   ├── ks.yaml
│   ├── secgroups-tf.yaml
│   └── config/
│       ├── namespace.yaml
│       ├── cloud-config.yaml        # SOPS encrypted (reflector annotations baked in if enable_velero)
│       ├── ccm-cloud-config.yaml    # SOPS encrypted
│       ├── cluster.yaml
│       ├── control-plane.yaml
│       ├── workers.yaml             # includes GPU MachineDeployment if enable_gpu_nodes
│       ├── healthchecks.yaml
│       ├── cluster-resource-set.yaml
│       ├── autoscaler/
│       ├── secgroups/               # Terraform HCL
│       └── overlays/                # generated when any addon is enabled
│           ├── kustomization.yaml
│           ├── bootstrap/
│           │   ├── namespace.yaml
│           │   └── kustomization.yaml
│           ├── velero-helmrelease.yaml        # when enable_velero
│           └── velero/                        # when enable_velero
│               ├── velero-namespace.yaml
│               ├── reflected-credentials.yaml
│               └── kustomization.yaml
└── <cluster_name>-fleet-entry/      # copy to fleet repo at clusters/workload/<cluster_name>/
    ├── kustomization.yaml
    ├── gitrepo.yaml
    ├── ks.yaml
    ├── addons-ks.yaml               # generated when any addon is enabled
    └── gitlab-token-secret.yaml     # SOPS encrypted
```

After generation, the operator:
1. Pushes `<cluster_name>/` as its own GitLab repo (or copies it into the fleet repo directly)
2. Copies `<cluster_name>-fleet-entry/` into the fleet repo at `clusters/workload/<cluster_name>/`
3. Appends `<cluster_name>-workload-ks-entry.yaml` to `clusters/management/workload-ks.yaml`
4. Opens an MR — Flux does the rest

## Prerequisites

- Ansible 2.15+
- `sops` CLI installed and on PATH
- `~/.config/openstack/clouds.yaml` with application credentials for the target project
- An age key at `~/.config/sops/age/keys.txt` (or set `sops_age_key_file`)
- A GitLab deploy token for the new cluster repo

## Quick start

```bash
ansible-playbook your-playbook.yml \
  -e generate_fleet_entry=true \
  -e cluster_name=rdc-workload-3 \
  -e cluster_namespace=nesi-training-prod \
  -e cluster_network=NeSI-Training-Prod \
  -e openstack_ssh_key=kahu-key \
  -e kubernetes_version=v1.35.3 \
  -e capi_image_name=ubuntu-24-containerd-v1.35.3 \
  -e cluster_repo_url=https://gitlab.com/nesi1/rebase/demos/rdc-workload-3 \
  -e cluster_repo_gitlab_token=gldt-xxxxxxxxxxxx
```

## Key variables

| Variable | Default | Description |
|---|---|---|
| `generate_fleet_entry` | `false` | Set `true` to generate files instead of provisioning |
| `fleet_output_dir` | `<playbook_dir>/fleet-output` | Where to write generated files |
| `cluster_name` | — | Cluster name (required) |
| `cluster_namespace` | `{{ cluster_rdc_project \| lower }}` | Kubernetes namespace |
| `kubernetes_version` | `v1.30.5` | Kubernetes version |
| `capi_image_name` | — | OS image name in OpenStack |
| `cluster_control_plane_count` | `1` | Control plane node count |
| `control_plane_flavor` | `balanced1.2cpu4ram` | Control plane VM flavor |
| `cluster_worker_count` | `2` | Initial worker count (autoscaler min) |
| `cluster_max_worker_count` | `3` | Autoscaler max workers |
| `worker_flavour` | `balanced1.2cpu4ram` | Worker VM flavor |
| `cluster_network` | `{{ cluster_rdc_project }}` | OpenStack network name |
| `cluster_external_network_id` | `3f405cc9-...` | External network UUID |
| `openstack_ssh_key` | — | OpenStack keypair name (required) |
| `cluster_pod_cidr` | `192.168.0.0/16` | Pod network CIDR |
| `cni_provider` | `calico` | CNI: `calico` or `cilium` |
| `kube_oidc_auth` | `false` | Enable OIDC on the API server |
| `capi_managed_secgroups` | `false` | Let CAPO manage secgroups (skips Terraform HCL) |
| `source_ips` | `[163.7.144.0/21]` | IPs allowed to reach the Kubernetes API |
| `sops_age_key_file` | `~/.config/sops/age/keys.txt` | Age key used to encrypt generated secrets |
| `clouds_yaml_local_location` | `~/.config/openstack/clouds.yaml` | Source clouds.yaml |
| `clouds_yaml_cloud` | `openstack` | Cloud entry name in clouds.yaml |
| `cluster_repo_url` | `https://gitlab.com/nesi1/rebase/demos/{{ cluster_name }}` | GitLab URL of the cluster repo |
| `cluster_repo_gitlab_username` | `git` | GitLab deploy token username |
| `cluster_repo_gitlab_token` | — | GitLab deploy token (required) |

### Add-on variables

| Variable | Default | Description |
|---|---|---|
| `enable_cinder_csi` | `false` | Generate Cinder CSI HelmRelease overlay |
| `enable_envoy_gateway` | `false` | Generate Envoy Gateway HelmRelease overlay |
| `enable_velero` | `true` | Generate Velero HelmRelease overlay + credentials KS |
| `velero_backup_bucket` | `REPLACE_ME_<cluster_name>` | Swift bucket name for Velero backups |

When `enable_velero: true`, the generated `cloud-config.yaml` (SOPS-encrypted) carries emberstack reflector annotations so the workload cluster's `velero` namespace receives a copy of the OpenStack credentials automatically. No separate credentials file is needed — the plugin reads from `/etc/openstack/clouds.yaml` via `extraVolumes`.

### GPU clusters

| Variable | Default | Description |
|---|---|---|
| `enable_gpu_nodes` | `false` | Add a GPU MachineDeployment (`md-gpu-0`) alongside standard workers |
| `cluster_gpu_worker_count` | `1` | Fixed GPU worker count (no autoscaling) |
| `gpu_worker_flavour` | `gpu1.40cpu200ram.a40.1g.48gb` | GPU worker VM flavor |
| `gpu_worker_volume_size` | `30` | Root volume size GiB (rootVolume block only emitted if > 30) |
| `gpu_kubernetes_version` | `v1.33.3` | K8s version for GPU nodes (may differ from standard workers) |
| `capi_gpu_image_name` | `rocky-9-containerd-hpc-nvidia-v1.33.3` | GPU node OS image (HPC image with pre-installed drivers) |
| `gpu_operator` | `nvidia` | GPU operator type: `nvidia` or `hami` |
| `nvidia_gpu_operator_version` | `25.3.1` | NVIDIA GPU Operator chart version |
| `nvidia_container_toolkit_version` | `1.17.8` | NVIDIA Container Toolkit version (appends `-ubi8` for Rocky) |
| `nvidia_gpu_sharing_type` | `mps` | GPU sharing mode: `mps` or `time-slicing` |

GPU workers do not autoscale — `replicas` is fixed at `cluster_gpu_worker_count`. The NVIDIA GPU Operator base (`infrastructure/apps/base/nvidia-gpu-operator/`) in the fleet repo includes an MPS ConfigMap pre-wired to the HelmRelease. To deploy the operator to a workload cluster, add a `nvidia-gpu-operator-helmrelease.yaml` overlay and reference the base from the cluster's `overlays/kustomization.yaml`.

## Available images

```
ubuntu-24-containerd-v1.35.3
rocky-9-containerd-v1.33.3
rocky-9-containerd-v1.32.7
rocky-9-containerd-v1.32.2
rocky-9-containerd-v1.31.6
rocky-9-containerd-v1.30.5
rocky-9-containerd-hpc-nvidia-v1.33.3   # GPU
```

## Emergency override path

The original direct-provisioning tasks (`tasks/main.yml`) are retained as a break-glass path for when Flux is suspended or the management cluster needs manual recovery. See `gitops-migration-plan.md §13` for guidance. Do not use this path for routine cluster creation.

```bash
# Emergency only — bypasses GitOps
ansible-playbook your-playbook.yml -e @vars/rdc-workload-1.yml --skip-tags cni,metrics-server
```
