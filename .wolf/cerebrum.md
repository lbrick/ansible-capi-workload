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
- **Addon selection:** `enable_cinder_csi`, `enable_envoy_gateway`, `enable_velero` booleans in defaults control what gets generated. Overlay dirs and addons-ks.yaml are only generated when at least one addon is enabled.
- **Cinder CSI credentials:** Reuses `cloud-config` secret deployed to kube-system by the CCM ClusterResourceSet — no separate secret needed (`secret.create: false`, `secret.name: cloud-config`).

## Do-Not-Repeat

<!-- Mistakes made and corrected. Each entry prevents the same mistake recurring. -->
<!-- Format: [YYYY-MM-DD] Description of what went wrong and what to do instead. -->

## Decision Log

<!-- Significant technical decisions with rationale. Why X was chosen over Y. -->
