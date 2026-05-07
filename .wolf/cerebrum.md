# Cerebrum

> OpenWolf's learning memory. Updated automatically as the AI learns from interactions.
> Do not edit manually unless correcting an error.
> Last updated: 2026-05-04

## User Preferences

<!-- How the user likes things done. Code style, tools, patterns, communication. -->

## Key Learnings

- **Project:** ansible-capi-workload
- **Description:** This repository provides an Ansible role for deploying Cluster API (CAPI) workload clusters on NeSI RDC (Research and Development Cloud) infrastructure. It leverages an existing CAPI management cluster.
- **External-repo cluster pattern:** Clusters are git-repo-per-cluster (external). `_cluster_dir` = content for cluster's own repo; `_fleet_entry_dir` = content for `clusters/workload/<cluster>/` in reannz-capi-fleet. Addon KSs live in fleet entry, not cluster repo root kustomization.
- **Addon overlay pattern:** `config/overlays/` in the cluster repo holds self-contained HelmReleases (no cross-repo base references). Bootstrap KS applies `config/overlays/bootstrap/` via kubeConfig to workload cluster; addons KS applies `config/overlays/` to mgmt cluster. Both KSs are in fleet entry `addons-ks.yaml`.
- **Addon selection:** `enable_cinder_csi`, `enable_envoy_gateway`, `enable_velero`, `enable_gpu_nodes` booleans in defaults control what gets generated. Overlay dirs and addons-ks.yaml are only generated when at least one addon is enabled.
- **Cinder CSI credentials:** Reuses `cloud-config` secret deployed to kube-system by the CCM ClusterResourceSet — no separate secret needed (`secret.create: false`, `secret.name: cloud-config`).
- **Velero credentials (working approach):** `cloud-config.plain.yaml.j2` bakes reflector annotations in when `enable_velero=true` (annotation added before SOPS encrypt, so no post-hoc `sops --set` needed). `overlays/velero/` holds velero-namespace.yaml + `../../cloud-config.yaml` reference + `reflected-credentials.yaml` stub. Reflector (emberstack) copies cloud-config data into `velero/openstack-credentials`. Velero HelmRelease mounts that secret via `extraVolumes`/`extraVolumeMounts` at `/etc/openstack/clouds.yaml`. `credentials.useSecret: false`. No `credentialsFile` in BSL config.
- **velero-plugin-for-openstack v0.8.0:** Ignores `credentialsFile` BSL config entirely. Only reads from standard OS paths: `/etc/openstack/clouds.yaml` or `~/.config/openstack/clouds.yaml`. Must use `extraVolumes` mount approach.
- **Velero-credentials KS namespace:** Lives in `{{ cluster_namespace }}` (NOT flux-system) because `sops-age` secret is replicated to `cluster_namespace`. The velero-credentials KS uses `kubeConfig` to deploy the decrypted secret to the workload cluster.
- **Kustomize patches on SOPS-encrypted resources:** NEVER WORK. Flux kustomize-controller runs `kustomize build` (including patches) BEFORE SOPS decryption. Patch targets on encrypted resources have `ENC[AES256_GCM,...]` as metadata.name — patch never matches. Fix: embed annotations directly in the plaintext template before encryption.

## Do-Not-Repeat

<!-- Mistakes made and corrected. Each entry prevents the same mistake recurring. -->
<!-- Format: [YYYY-MM-DD] Description of what went wrong and what to do instead. -->

- [2026-05-07] **Do NOT use kustomize patches on SOPS-encrypted resources.** Flux builds kustomize (patches run) BEFORE decrypting — patch targets never match encrypted `ENC[...]` values. Embed annotations/labels directly in `.plain.yaml` templates before encryption instead.
- [2026-05-07] **Do NOT add `credentialsFile` to velero BSL config.** velero-plugin-for-openstack v0.8.0 ignores it entirely. Use `extraVolumes`/`extraVolumeMounts` to mount the secret at `/etc/openstack/clouds.yaml`.
- [2026-05-07] **Do NOT put velero-credentials KS in flux-system.** It belongs in `cluster_namespace` because `sops-age` is replicated there and `kubeconfig` secret lives there too.

## Decision Log

<!-- Significant technical decisions with rationale. Why X was chosen over Y. -->
