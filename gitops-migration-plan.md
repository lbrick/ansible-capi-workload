# Plan: ansible-capi-workload → Fleet GitOps Migration

**Status:** Draft for review  
**Date:** 2026-05-05  
**Companion:** `nesi-capi-seed/flux-gitops-plan.md` — management cluster + Flux bootstrap side  
**Scope:** What changes in this repo as workload cluster lifecycle moves to Flux + tf-controller.

---

## 1. Role of This Repo After Migration

Today this repo is the **sole provisioning tool** for workload clusters — run it, cluster appears. After migration it becomes a **fleet entry generator**: a one-time tool that produces the static files the fleet repo needs for a new cluster. Day-to-day operations (scaling, upgrades, deletion) happen through fleet repo PRs, not Ansible.

```
Before: Operator → ansible-capi-workload → cluster exists
After:  Operator → ansible-capi-workload generate → fleet repo MR → Flux → cluster exists
```

The role is NOT deleted. It stays as:
- Generator for new cluster fleet entries
- Emergency override path (manual apply if Flux is suspended)
- Reference implementation for what each component should look like

---

## 2. Component Disposition

Every task in this role maps to one of three outcomes:

| Component | Current task(s) | Fleet outcome | Applied by |
|-----------|----------------|---------------|-----------|
| **Security groups** | `secgroups-control-plane.yml`, `secgroups-worker.yml` | Terraform HCL in `clusters/<name>/secgroups/` | tf-controller on mgmt cluster |
| **CAPI core manifests** | `configure-install-clusterctl.yml` | Static YAML in `clusters/<name>/` (SOPS encrypted `cloud-config.yaml` + split CAPI objects) | Flux Kustomization on mgmt cluster |
| **CNI (Calico/Cilium)** | `install-cni.yml`, `cni-calico-install.yml`, etc. | ConfigMap in `infrastructure/workload-components/` | ClusterResourceSet → workload cluster |
| **Cloud Controller Manager** | `install-cloud-manager.yml` | ConfigMap in `infrastructure/workload-components/` | ClusterResourceSet → workload cluster |
| **Cluster Autoscaler** | `install-autoscaler.yml` | Static YAML in `clusters/<name>/autoscaler/` | Flux Kustomization on mgmt cluster |
| **MachineHealthChecks** | `install-healthchecks.yml` | Static YAML in `clusters/<name>/healthchecks.yaml` | Flux Kustomization on mgmt cluster |
| **Metrics Server** | `install-metrics-server.yml` | ConfigMap in `infrastructure/workload-components/` | ClusterResourceSet → workload cluster |
| **OIDC RBAC** | `configure-oidc-roles.yml` | ConfigMap in `infrastructure/workload-components/` | ClusterResourceSet → workload cluster |
| **GPU node pool** | `install-gpu.yml`, `gpu-*.yml` | `clusters/<name>/gpu-workers.yaml` + Flux on workload cluster | Flux Kustomization (pool) + Flux on workload cluster (operators) |
| **Prerequisites / var checks** | `check-vars.yml`, `prerequisites.yml` | Absorbed into generator playbook validation | N/A |

---

## 3. Artifacts the Fleet Repo Needs per Cluster

Running the generator playbook for cluster `rdc-workload-1` produces:

```
clusters/rdc-workload-1/
├── secgroups/
│   ├── main.tf          # full secgroup HCL (see §4)
│   ├── variables.tf
│   └── versions.tf
├── kustomization.yaml   # Kustomize base (not a Flux resource)
├── cluster.yaml         # Cluster + OpenStackCluster
├── control-plane.yaml   # KubeadmControlPlane + OpenStackMachineTemplate (CP)
├── workers.yaml         # MachineDeployment + KubeadmConfigTemplate + OpenStackMachineTemplate
├── healthchecks.yaml    # MachineHealthCheck (CP + worker)
├── cluster-resource-set.yaml  # ClusterResourceSet refs to CNI/CCM/metrics ConfigMaps
├── cloud-config.yaml    # SOPS-encrypted Secret (clouds.yaml + CA cert)
└── autoscaler/
    ├── kustomization.yaml
    └── autoscaler.yaml  # Autoscaler Deployment + ServiceAccount on mgmt cluster

clusters/management/ additions:
├── rdc-workload-1-secgroups-tf.yaml   # Flux Terraform CR
├── rdc-workload-1-ks.yaml             # Flux Kustomization (dependsOn secgroups-tf)
└── rdc-workload-1-autoscaler-ks.yaml  # Flux Kustomization (dependsOn rdc-workload-1)
```

One-time shared artifacts (committed once, not per-cluster):
```
infrastructure/
├── autoscaler-rbac/
│   └── rbac.yaml                      # ClusterRole + ClusterRoleBinding (cluster-scoped)
└── workload-components/
    ├── cni-calico-configmap.yaml
    ├── cni-cilium-configmap.yaml
    ├── ccm-openstack-configmap.yaml
    ├── metrics-server-configmap.yaml
    └── oidc-rbac-configmap.yaml       # ClusterRole + ClusterRoleBinding for OIDC
```

---

## 4. Secgroup Terraform HCL

Direct translation of `secgroups-control-plane.yml` and `secgroups-worker.yml`. The `remote_group_id` field solves the problem that ORC cannot express today.

### `secgroups/versions.tf`

```hcl
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.54.0"
    }
  }
  backend "kubernetes" {
    secret_suffix     = "placeholder"   # tf-controller overrides this per Terraform CR
    namespace         = "flux-system"
    in_cluster_config = true
  }
}

provider "openstack" {
  cloud = "openstack"
}
```

### `secgroups/variables.tf`

```hcl
variable "cluster_name" {
  type = string
}

variable "cluster_namespace" {
  type = string
}

variable "source_ips" {
  type    = list(string)
  default = ["163.7.144.0/21"]
}
```

### `secgroups/main.tf`

```hcl
locals {
  cp_name     = "k8s-cluster-${var.cluster_namespace}-${var.cluster_name}-secgroup-controlplane"
  worker_name = "k8s-cluster-${var.cluster_namespace}-${var.cluster_name}-secgroup-worker"
}

resource "openstack_networking_secgroup_v2" "controlplane" {
  name        = local.cp_name
  description = "Ansible Cluster API managed group"
}

resource "openstack_networking_secgroup_v2" "worker" {
  name        = local.worker_name
  description = "Ansible Cluster API managed group"
}

# ── Control plane rules ──────────────────────────────────────────────────────

resource "openstack_networking_secgroup_rule_v2" "cp_ingress_from_cp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  security_group_id = openstack_networking_secgroup_v2.controlplane.id
  remote_group_id   = openstack_networking_secgroup_v2.controlplane.id
  description       = "In-cluster Ingress"
}

resource "openstack_networking_secgroup_rule_v2" "cp_ingress_from_worker" {
  direction         = "ingress"
  ethertype         = "IPv4"
  security_group_id = openstack_networking_secgroup_v2.controlplane.id
  remote_group_id   = openstack_networking_secgroup_v2.worker.id
  description       = "In-cluster Ingress"
}

resource "openstack_networking_secgroup_rule_v2" "cp_ipip_from_cp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "4"
  security_group_id = openstack_networking_secgroup_v2.controlplane.id
  remote_group_id   = openstack_networking_secgroup_v2.controlplane.id
  description       = "IP-in-IP (calico)"
}

resource "openstack_networking_secgroup_rule_v2" "cp_ipip_from_worker" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "4"
  security_group_id = openstack_networking_secgroup_v2.controlplane.id
  remote_group_id   = openstack_networking_secgroup_v2.worker.id
  description       = "IP-in-IP (calico)"
}

resource "openstack_networking_secgroup_rule_v2" "cp_bgp_from_cp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 179
  port_range_max    = 179
  security_group_id = openstack_networking_secgroup_v2.controlplane.id
  remote_group_id   = openstack_networking_secgroup_v2.controlplane.id
  description       = "BGP (calico)"
}

resource "openstack_networking_secgroup_rule_v2" "cp_bgp_from_worker" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 179
  port_range_max    = 179
  security_group_id = openstack_networking_secgroup_v2.controlplane.id
  remote_group_id   = openstack_networking_secgroup_v2.worker.id
  description       = "BGP (calico)"
}

# 6443 restricted to source_ips — one rule per IP range
resource "openstack_networking_secgroup_rule_v2" "cp_kube_api" {
  for_each          = toset(var.source_ips)
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6443
  port_range_max    = 6443
  remote_ip_prefix  = each.key
  security_group_id = openstack_networking_secgroup_v2.controlplane.id
  description       = "Kubernetes API"
}

# ── Worker rules ─────────────────────────────────────────────────────────────

resource "openstack_networking_secgroup_rule_v2" "worker_ingress_from_cp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  security_group_id = openstack_networking_secgroup_v2.worker.id
  remote_group_id   = openstack_networking_secgroup_v2.controlplane.id
  description       = "In-cluster Ingress"
}

resource "openstack_networking_secgroup_rule_v2" "worker_ingress_from_worker" {
  direction         = "ingress"
  ethertype         = "IPv4"
  security_group_id = openstack_networking_secgroup_v2.worker.id
  remote_group_id   = openstack_networking_secgroup_v2.worker.id
  description       = "In-cluster Ingress"
}

resource "openstack_networking_secgroup_rule_v2" "worker_ipip_from_cp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "4"
  security_group_id = openstack_networking_secgroup_v2.worker.id
  remote_group_id   = openstack_networking_secgroup_v2.controlplane.id
  description       = "IP-in-IP (calico)"
}

resource "openstack_networking_secgroup_rule_v2" "worker_ipip_from_worker" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "4"
  security_group_id = openstack_networking_secgroup_v2.worker.id
  remote_group_id   = openstack_networking_secgroup_v2.worker.id
  description       = "IP-in-IP (calico)"
}

resource "openstack_networking_secgroup_rule_v2" "worker_bgp_from_cp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 179
  port_range_max    = 179
  security_group_id = openstack_networking_secgroup_v2.worker.id
  remote_group_id   = openstack_networking_secgroup_v2.controlplane.id
  description       = "BGP (calico)"
}

resource "openstack_networking_secgroup_rule_v2" "worker_bgp_from_worker" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 179
  port_range_max    = 179
  security_group_id = openstack_networking_secgroup_v2.worker.id
  remote_group_id   = openstack_networking_secgroup_v2.worker.id
  description       = "BGP (calico)"
}

resource "openstack_networking_secgroup_rule_v2" "worker_nodeport_tcp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 30000
  port_range_max    = 32767
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.worker.id
  description       = "Node Port Services"
}

resource "openstack_networking_secgroup_rule_v2" "worker_nodeport_udp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 30000
  port_range_max    = 32767
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.worker.id
  description       = "Node Port Services"
}

# ── Outputs (referenced by Terraform CR outputs, not required by CAPI) ───────

output "controlplane_secgroup_id" {
  value = openstack_networking_secgroup_v2.controlplane.id
}

output "worker_secgroup_id" {
  value = openstack_networking_secgroup_v2.worker.id
}
```

### Importing existing secgroups

For clusters where Ansible already created the secgroups, import them before applying the Terraform CR:

```bash
# Look up existing IDs
openstack security group list --project <project-name>

# Import — run locally with the same provider config before committing the TF CR
terraform -chdir=clusters/rdc-workload-1/secgroups init
terraform -chdir=clusters/rdc-workload-1/secgroups import \
  -var="cluster_name=rdc-workload-1" \
  -var="cluster_namespace=nesi-project" \
  openstack_networking_secgroup_v2.controlplane <cp-secgroup-uuid>

terraform -chdir=clusters/rdc-workload-1/secgroups import \
  openstack_networking_secgroup_v2.worker <worker-secgroup-uuid>

# Import each rule — list rules first
openstack security group rule list <cp-secgroup-uuid> -f json

# Then import each rule (tedious but one-time)
terraform import openstack_networking_secgroup_rule_v2.cp_ingress_from_cp <rule-uuid>
# ... repeat for all rules

# Verify no changes planned — if this is non-empty, rules differ from Ansible
terraform plan -var="cluster_name=rdc-workload-1" -var="cluster_namespace=nesi-project"
```

> **Note:** Importing individual security group rules is tedious. An alternative: let Terraform destroy and recreate rules only (not the groups themselves — CAPO references groups by name, not rule content). Since rules are stateless from the cluster's perspective, recreating them causes no disruption. Only the groups themselves must be imported (to preserve their IDs referenced by OpenStackMachineTemplate).

---

## 5. CAPI Static YAML (from cluster-template.yml.j2)

The Jinja2 template + `clusterctl generate cluster` produces one large YAML. Split it per-resource for the fleet repo. The generator playbook runs the template render and splits the output.

**`cluster.yaml`** — contains:
- `Secret` (`<name>-cloud-config`) — SOPS encrypt this alone as `cloud-config.yaml`, remove from `cluster.yaml`
- `Cluster`
- `OpenStackCluster` — update to reference Ansible-named secgroups via `additionalSecurityGroups`:

```yaml
# In OpenStackMachineTemplate spec.template.spec
additionalSecurityGroups:
  - filter:
      name: k8s-cluster-{{ cluster_namespace }}-{{ cluster_name }}-secgroup-controlplane
```

This references the secgroup by name — CAPO resolves the ID. The secgroup is created by tf-controller before the CAPI Kustomization runs (enforced by `dependsOn`).

**`control-plane.yaml`** — `KubeadmControlPlane` + `OpenStackMachineTemplate` (control-plane)

**`workers.yaml`** — `MachineDeployment` + `KubeadmConfigTemplate` + `OpenStackMachineTemplate` (workers)

**`cloud-config.yaml`** — the `<name>-cloud-config` Secret, SOPS encrypted:
```bash
# Generate and encrypt
sops -e cloud-config.plain.yaml > clusters/rdc-workload-1/cloud-config.yaml
rm cloud-config.plain.yaml
```

**Autoscaler `ownerReferences` stripped** — the current template embeds the Cluster UID at deploy time. Drop `ownerReferences` entirely; Flux `prune: true` handles lifecycle cleanup instead.

---

## 6. ClusterResourceSet ConfigMaps

These are shared across all clusters of the same type. Render once from templates and commit to `infrastructure/workload-components/`.

### CNI — Calico

Render `templates/calico-custom-resources.yaml.j2` with the default pod CIDR (`192.168.0.0/16`) to produce the Calico operator install + custom resources manifest. Wrap in a ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cni-calico
  namespace: flux-system    # or the cluster namespace
data:
  calico.yaml: |
    # full Calico operator install manifest here
    # from: tasks/cni-calico-operator-install.yml helm template output
```

> If CNI version varies per cluster (unlikely), produce per-cluster ConfigMaps instead of shared.

### Cloud Controller Manager

Render the CCM Helm chart output (from `install-cloud-manager.yml`) with the OpenStack cloud config. The CCM needs a `clouds.yaml` — it reads from the same `<name>-cloud-config` Secret that CAPI uses. The CCM ConfigMap contains the Helm-rendered manifests with the Secret reference already wired in.

### Metrics Server

Render `templates/metrics-server.yml.j2` → static YAML → ConfigMap.

### OIDC RBAC

Render `templates/cluster-role-oidc.yml.j2` + `templates/cluster-role-binding-oidc.yml.j2` → static YAML → ConfigMap. Non-sensitive, no SOPS needed.

### ClusterResourceSet per cluster

```yaml
apiVersion: addons.cluster.x-k8s.io/v1beta1
kind: ClusterResourceSet
metadata:
  name: rdc-workload-1-addons
  namespace: nesi-project
spec:
  strategy: ApplyOnce
  clusterSelector:
    matchLabels:
      cluster.x-k8s.io/cluster-name: rdc-workload-1
  resources:
    - name: cni-calico
      kind: ConfigMap
    - name: ccm-openstack
      kind: ConfigMap
    - name: metrics-server
      kind: ConfigMap
    - name: oidc-rbac          # only if kube_oidc_auth: true
      kind: ConfigMap
```

---

## 7. Autoscaler Static YAML

The current `autoscaler-deployment.yml.j2` template embeds `cluster_uid` in `ownerReferences`. Drop this — Flux `prune: true` handles cleanup.

The autoscaler RBAC (`ClusterRole`, `ClusterRoleBinding`, `ServiceAccount`) is cluster-scoped and shared across all autoscalers. Commit once to `infrastructure/autoscaler-rbac/rbac.yaml`, applied as a separate Flux Kustomization before any per-cluster autoscaler starts.

Per-cluster `autoscaler/autoscaler.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cluster-autoscaler-rdc-workload-1
  namespace: kube-system
  # ownerReferences removed — Flux prune: true handles deletion
spec:
  # ... same as current template, with cluster_name substituted
  template:
    spec:
      containers:
      - name: cluster-autoscaler
        image: registry.k8s.io/autoscaling/cluster-autoscaler:v1.32.2
        args:
        - --cloud-provider=clusterapi
        - --kubeconfig=/mnt/value
        - --clusterapi-cloud-config-authoritative
        - --node-group-auto-discovery=clusterapi:clusterName=rdc-workload-1
        volumeMounts:
        - name: workload-kubeconfig
          mountPath: /mnt
          readOnly: true
      volumes:
      - name: workload-kubeconfig
        secret:
          secretName: rdc-workload-1-kubeconfig
```

---

## 8. GPU Clusters

GPU clusters require a separate MachineDeployment with `gpu_worker_flavour` and `capi_gpu_image_name`. The fleet repo file `gpu-workers.yaml` is a second `MachineDeployment` + `OpenStackMachineTemplate` in the same cluster namespace.

The GPU node pool uses a different Kubernetes version image (`rocky-9-containerd-hpc-nvidia-v1.33.3`). This version is independent of the control plane version — CAPI supports mixed versions between node pools.

NVIDIA Operator and HaMi are deployed via Flux on the workload cluster (not ClusterResourceSet — too complex for ConfigMap approach). After the GPU workload cluster is provisioned by CAPI:

1. Install Flux on workload cluster (one-time, via bootstrap Job or ClusterResourceSet with a Flux install manifest)
2. Fleet repo path `clusters/rdc-gpu-1/workload-addons/` contains:
   - `HelmRelease` for NVIDIA GPU Operator
   - MPS `ConfigMap` (rendered from `templates/nvidia-gpu-mps-config-all.yml.j2`)
   - `HelmRepository` source for NVIDIA charts

---

## 9. Generator Playbook

New Ansible playbook: `generate-fleet-entry.yml`. Takes the same variables as the current provisioning role but instead of applying anything, it writes files to a specified output directory.

```yaml
# generate-fleet-entry.yml
- hosts: localhost
  gather_facts: false
  vars:
    fleet_output_dir: "{{ playbook_dir }}/../fleet-output/clusters/{{ cluster_name }}"
  tasks:
    - name: Create output directories
      file:
        path: "{{ fleet_output_dir }}/{{ item }}"
        state: directory
      loop: ["secgroups", "autoscaler"]

    - name: Render secgroup Terraform HCL
      template:
        src: templates/secgroups-main.tf.j2
        dest: "{{ fleet_output_dir }}/secgroups/main.tf"

    - name: Render secgroup variables.tf
      template:
        src: templates/secgroups-variables.tf.j2
        dest: "{{ fleet_output_dir }}/secgroups/variables.tf"

    - name: Copy secgroup versions.tf
      copy:
        src: files/secgroups-versions.tf
        dest: "{{ fleet_output_dir }}/secgroups/versions.tf"

    - name: Render CAPI cluster template
      template:
        src: templates/cluster-template.yml.j2
        dest: "{{ fleet_output_dir }}/cluster-template-rendered.yml"

    - name: Split rendered CAPI YAML into per-resource files
      # Uses a script to split on --- boundaries and write named files
      script: files/split-capi-yaml.py {{ fleet_output_dir }}/cluster-template-rendered.yml {{ fleet_output_dir }}

    - name: Render autoscaler deployment
      template:
        src: templates/autoscaler-deployment.yml.j2
        dest: "{{ fleet_output_dir }}/autoscaler/autoscaler.yaml"

    - name: Render healthchecks
      template:
        src: templates/healthcheck-control-plane.yml.j2
        dest: "{{ fleet_output_dir }}/healthcheck-controlplane.yaml"

    - name: Render ClusterResourceSet
      template:
        src: templates/cluster-resource-set.yml.j2
        dest: "{{ fleet_output_dir }}/cluster-resource-set.yaml"

    - name: Render management/ Flux CRs
      template:
        src: "{{ item.src }}"
        dest: "{{ fleet_output_dir }}/../management/{{ cluster_name }}-{{ item.name }}.yaml"
      loop:
        - { src: templates/flux-terraform-cr.yml.j2, name: "secgroups-tf" }
        - { src: templates/flux-kustomization.yml.j2, name: "ks" }
        - { src: templates/flux-autoscaler-ks.yml.j2, name: "autoscaler-ks" }

    - name: Print next steps
      debug:
        msg:
          - "Fleet entry generated in {{ fleet_output_dir }}"
          - "1. Review generated files"
          - "2. Encrypt cloud-config: sops -e {{ fleet_output_dir }}/cloud-config.plain.yaml > {{ fleet_output_dir }}/cloud-config.yaml"
          - "3. Import existing secgroups if migrating: see gitops-migration-plan.md §4"
          - "4. Open MR to fleet repo adding these files"
```

---

## 10. Post-Migration Task Map

| Task file | Status after migration | Reason |
|-----------|----------------------|--------|
| `check-vars.yml` | Keep in generator | Validates vars before generating files |
| `prerequisites.yml` | Keep in generator | Sets up tmp dir, copies clouds.yaml |
| `secgroups-control-plane.yml` | Superseded by Terraform HCL | tf-controller owns secgroups |
| `secgroups-worker.yml` | Superseded by Terraform HCL | tf-controller owns secgroups |
| `configure-install-clusterctl.yml` | Superseded by fleet YAML | CAPI objects in Git |
| `install-cni.yml` + variants | Superseded by ClusterResourceSet | Runs on workload cluster boot |
| `install-cloud-manager.yml` | Superseded by ClusterResourceSet | Runs on workload cluster boot |
| `install-autoscaler.yml` | Superseded by fleet YAML | Flux Kustomization on mgmt cluster |
| `install-healthchecks.yml` | Superseded by fleet YAML | MachineHealthCheck in Git |
| `install-metrics-server.yml` | Superseded by ClusterResourceSet | Runs on workload cluster boot |
| `install-gpu.yml` + variants | Superseded by Flux on workload | NVIDIA Operator via HelmRelease |
| `configure-oidc-roles.yml` | Superseded by ClusterResourceSet | OIDC RBAC ConfigMap |
| `main.yml` | Keep as emergency override path | Manual apply if Flux suspended |

---

## 11. Per-Cluster Migration Sequence

For each existing cluster (do one at a time, non-production first):

```
1. Get secgroup IDs
   openstack security group list --project <project>

2. Write Terraform HCL for cluster into fleet repo
   (copy template from this plan §4, fill in cluster_name + cluster_namespace)

3. Init + import secgroups (locally)
   terraform -chdir=clusters/<name>/secgroups init
   terraform import openstack_networking_secgroup_v2.controlplane <cp-id>
   terraform import openstack_networking_secgroup_v2.worker <worker-id>
   # Import rules or let Terraform recreate them (rules are non-disruptive to recreate)

4. Verify terraform plan shows no changes (or only harmless rule differences)

5. Commit secgroup TF + Terraform CR to fleet repo → MR → merge
   (tf-controller applies — verify secgroups still exist, no new/deleted rules)

6. Export CAPI objects from mgmt cluster
   kubectl get cluster,openstackcluster,kubeadmcontrolplane,openstackmachinetemplate,\
   machinedeployment,kubeadmconfigtemplate,machinehealthcheck \
   -n <namespace> -l cluster.x-k8s.io/cluster-name=<name> -o yaml > raw.yaml
   
   Strip status + managedFields. Split into cluster.yaml / control-plane.yaml / workers.yaml.

7. Encrypt cloud-config Secret
   sops -e cloud-config.plain.yaml > clusters/<name>/cloud-config.yaml

8. Commit CAPI YAML + autoscaler YAML to fleet repo → MR → merge
   Add Kustomization CR (with dependsOn secgroups-tf) + autoscaler Kustomization CR

9. Flux adopts — CAPI sees existing objects, reconciles (no reprovision)
   Monitor: flux get kustomizations -A && kubectl get cluster -A

10. Verify autoscaler functioning
    kubectl get deployment -n kube-system cluster-autoscaler-<name>
```

---

## 12. Open Questions

| # | Question | Options | Recommendation |
|---|----------|---------|----------------|
| 1 | Import secgroup rules individually or let TF recreate? | Import all / import groups only + recreate rules | Import groups only + recreate rules — rules are stateless, recreation is non-disruptive |
| 2 | GPU clusters: how to install Flux on workload cluster? | ClusterResourceSet bootstrap Job / manual | ClusterResourceSet with Flux install manifest as initial bootstrap |
| 3 | CNI version pinned or floating? | Pin version in ConfigMap / update ConfigMap for upgrades | Pin — update ConfigMap = new MR = reviewed change |
| 4 | CCM clouds.yaml: from CAPI cloud-config Secret or separate? | Same Secret / separate CCM Secret | Same Secret — CCM and CAPI both need cloud creds; reuse reduces duplication |
| 5 | Additional secgroups per cluster (`additional_cluster_secgroups`)? | Add to TF as `openstack_networking_secgroup_v2` imports | Import or reference by name in `additionalSecurityGroups` in OpenStackMachineTemplate |
| 6 | `capi_managed_secgroups: true` path (non-default)? | Omit additionalSecurityGroups in CAPI YAML / add a variable | Add variable in cluster.yaml; if CAPO-managed, no TF HCL needed for that cluster |

---

## 13. Disaster Recovery

### 13.1 Two Sources of Truth

After migration, a workload cluster's full state spans two sources:

| Source | What it holds | How to restore |
|--------|--------------|----------------|
| **Fleet repo** (`gitlab.com/nesi1/nesi-capi-fleet`) | CAPI spec, secgroup TF, autoscaler config, CNI manifests | `git clone` — always available |
| **Velero backup** (Swift external storage) | Runtime state: `Machine.spec.providerID`, Kubeconfig Secrets, tf-controller Terraform state Secrets | `velero restore` |

**Critical:** Fleet repo alone is not enough. Without `Machine.spec.providerID` (stored only in mgmt cluster etcd), Flux reconciling the fleet repo against a fresh management cluster will create **new VMs** for existing clusters, duplicating them in OpenStack.

Recovery order is always: **restore Velero runtime state first, then let Flux reconcile.**

---

### 13.2 What This Repo Can and Cannot Recover

| Recoverable from this repo | Not recoverable — needs Velero or manual inspection |
|---------------------------|-----------------------------------------------------|
| Security group HCL (re-generate or from fleet repo) | `Machine.spec.providerID` (OpenStack VM UUIDs) |
| CAPI spec YAML (from fleet repo) | `<cluster-name>-kubeconfig` Secret |
| Autoscaler Deployment spec | Terraform state Secrets (`tfstate-default-*`) |
| CNI / CCM / Metrics ConfigMaps | CAPI internal Secrets (`<cluster-name>-ca`, `-etcd`, `-proxy`) |
| ClusterResourceSet definitions | Active MachineSet and Machine objects linked to real VMs |

---

### 13.3 Primary DR Path (Velero Available)

This is the standard path. See `nesi-capi-seed/flux-gitops-plan.md §16` for the full procedure. This repo's role in it:

1. **Do not run ansible-capi-workload against restored clusters.** Fleet repo + Velero restore is sufficient.
2. After Velero restore completes and Flux reconciles, verify via:
   ```bash
   # Secgroups owned by tf-controller — should show no drift
   kubectl get terraform -n flux-system
   # CAPI cluster adopted — no new VMs
   kubectl get cluster,machine -A
   # Autoscaler running
   kubectl get deployment -n kube-system -l app=cluster-autoscaler
   ```
3. If CNI fails to apply on workload cluster after restore, re-trigger ClusterResourceSet:
   ```bash
   # Delete the ClusterResourceSetBinding to force re-apply
   kubectl delete clusterresourcesetbinding <cluster-name> -n <namespace>
   ```

---

### 13.4 Emergency Override Path (Velero Unavailable)

Use this only when:
- Velero backups are lost or unrestorable
- Management cluster is gone and cannot be rebuilt from Velero
- Workload cluster VMs still exist in OpenStack (not deleted)

**This path uses this repo directly as an emergency tool, not a provisioning tool.**

#### Step 1 — Identify surviving OpenStack VMs

```bash
# List VMs belonging to existing clusters
openstack server list --project <project> --format json | \
  jq '.[] | select(.Name | startswith("k8s-cluster-"))'

# Get their IDs — these are the providerIDs needed by CAPI
# Format: openstack:////<vm-uuid>
openstack server show <vm-name> -f value -c id
```

#### Step 2 — Recover security groups

Security groups likely still exist in OpenStack (they're not deleted when the mgmt cluster dies). Re-import them into tf-controller by running the import steps from §11 steps 1–5 on a fresh mgmt cluster with Flux already installed.

If tf-controller is not yet running:

```bash
# Apply TF state manually — run Terraform locally then push state
cd clusters/<name>/secgroups
terraform init
terraform import openstack_networking_secgroup_v2.controlplane <cp-secgroup-id>
terraform import openstack_networking_secgroup_v2.worker <worker-secgroup-id>
# Verify no destructive changes
terraform plan
```

#### Step 3 — Re-create CAPI objects pointing at existing VMs

CAPI objects can be applied from the fleet repo, but `Machine` objects need `providerID` patched in immediately after creation to prevent CAPI from trying to provision new VMs.

```bash
# Apply cluster objects from fleet repo (without Flux — direct apply)
kubectl apply -k clusters/<name>/

# For each control plane VM — patch providerID before CAPI acts
kubectl patch machine <machine-name> -n <namespace> \
  --type=merge \
  -p '{"spec":{"providerID":"openstack:////<vm-uuid>"}}'

# For each worker VM
kubectl patch machine <worker-machine-name> -n <namespace> \
  --type=merge \
  -p '{"spec":{"providerID":"openstack:////<vm-uuid>"}}'
```

Map VM names to Machine names via `openstack server show <vm> -f value -c metadata` — CAPI stamps cluster/machine labels as server metadata.

#### Step 4 — Recover kubeconfig

If the workload cluster's API server is still running (VMs exist, kubelet running), extract the kubeconfig directly from a control plane node:

```bash
# SSH to control plane VM
ssh rocky@<cp-vm-ip>
sudo cat /etc/kubernetes/admin.conf

# Or use kubeadm
sudo kubeadm kubeconfig user --client-name=admin
```

Create the kubeconfig Secret manually:

```bash
kubectl create secret generic <cluster-name>-kubeconfig \
  -n <namespace> \
  --from-file=value=<recovered-admin.conf>
```

#### Step 5 — Re-deploy autoscaler

Once kubeconfig Secret exists, apply the autoscaler Deployment from the fleet repo:

```bash
kubectl apply -f clusters/<name>/autoscaler/autoscaler.yaml
```

#### Step 6 — Verify CNI on workload cluster

ClusterResourceSet will attempt to re-apply CNI when the cluster reaches Ready. If CNI was already running on workload VMs (calico/cilium processes still up), this is a no-op. If CNI is missing:

```bash
# Force ClusterResourceSet re-apply
kubectl delete clusterresourcesetbinding <cluster-name> -n <namespace>
```

---

### 13.5 ansible-capi-workload as Last Resort

If both Velero and the fleet repo are unavailable, this repo plus the original Ansible variable files are the last source of truth for cluster configuration. The `main.yml` playbook can be run against an existing cluster (not a new one) with care:

- `configure-install-clusterctl.yml` checks `cluster_initialized` before running clusterctl — it will skip if the management cluster already has the cluster object. Safe to run.
- `secgroups-control-plane.yml` and `secgroups-worker.yml` are idempotent — OpenStack module with `state: present` will adopt existing secgroups by name.
- `install-autoscaler.yml` is idempotent — re-applies the same Deployment.
- `install-cni.yml` is **not safe** to re-run against a running workload cluster with existing CNI — it may conflict. Skip via `--skip-tags cni` or check the workload cluster CNI state first.

```bash
# Emergency re-apply — skip CNI if already running on workload cluster
ansible-playbook main.yml \
  -e @vars/rdc-workload-1.yml \
  -e @secrets/clouds.yml \
  --skip-tags cni,metrics-server
```

---

### 13.6 DR Decision Tree

```
Management cluster lost?
├─ YES: Velero backup available and recent?
│   ├─ YES → Use nesi-capi-seed §16 procedure (standard DR)
│   │         This repo: verify only (§13.3)
│   └─ NO  → Workload VMs still running in OpenStack?
│             ├─ YES → Emergency override path (§13.4)
│             └─ NO  → Full reprovision — run ansible-capi-workload
│                       normally, accept cluster recreation
└─ NO (mgmt cluster healthy, single component broken):
    ├─ Flux suspended/broken → Apply fleet YAML directly (kubectl apply -k)
    ├─ tf-controller broken  → Run Terraform locally (§13.4 Step 2)
    ├─ Autoscaler broken     → kubectl apply -f clusters/<name>/autoscaler/
    └─ CNI broken on workload → Delete ClusterResourceSetBinding to re-trigger
```

---

### 13.7 RTO / RPO for This Repo's Components

| Component | RPO | RTO | Recovery method |
|-----------|-----|-----|----------------|
| Security groups | 0 (in Git) | 15 min (tf import + plan) | Terraform import from OpenStack |
| CAPI spec | 0 (in Git) | 30 min (apply + providerID patch) | kubectl apply + manual patch |
| Autoscaler | 0 (in Git) | 5 min | kubectl apply |
| CNI on workload cluster | 0 (in ConfigMap) | 10 min | ClusterResourceSetBinding delete |
| Machine providerID linkage | Velero RPO (24h) | 1–2 h | Velero restore or manual OpenStack inspection |
