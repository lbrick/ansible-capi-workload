# Memory

> Chronological action log. Hooks and AI append to this file automatically.
> Old sessions are consolidated by the daemon weekly.

| 2026-05-06 | Add addon overlay generation to generate-fleet-entry role | defaults/main.yml, tasks/generate-fleet-entry.yml, templates/gitops/addons-ks.yaml.j2, overlays-*.j2, fleet-kustomization.yaml.j2 | New templates for config/overlays/ (bootstrap, cinder-csi HelmRelease) + fleet entry addons-ks.yaml. Controlled by enable_cinder_csi/enable_envoy_gateway/enable_velero flags. |
| 2026-05-07 | Add Velero to all clusters (management + rdc-workload-1 + rdc-workload-2 + ansible role) | reannz-capi-fleet: infrastructure/apps/overlays/management/, clusters/management/velero-ks.yaml, clusters/workload/rdc-workload-{1,2}/addons-ks.yaml + overlays; rdc-workload-2: overlays/ + bootstrap/velero/; ansible-capi-workload: overlays-velero-*.j2, addons-ks.yaml.j2, generate-fleet-entry.yml | enable_velero: true, velero_backup_bucket var. Dedicated velero-credentials KS in flux-system for SOPS decryption. Credentials via clouds.yaml key in openstack-credentials secret. |
| 2026-05-07 | Fix velero credentials approach + audit ansible templates | cloud-config.plain.yaml.j2, overlays-velero-*.j2, cerebrum.md | Bake reflector annotations into cloud-config.plain.yaml.j2 (enable_velero). extraVolumes mount approach (not credentialsFile). cerebrum updated with correct velero pattern and 3 do-not-repeat entries. |
| 2026-05-07 | Add GPU worker MachineDeployment to workers.yaml.j2 | templates/gitops/workers.yaml.j2 | enable_gpu_nodes guard; md-gpu-0 MachineDeployment + OpenStackMachineTemplate; uses gpu_kubernetes_version, gpu_worker_flavour, capi_gpu_image_name; no autoscaler annotations; reuses md-0 KubeadmConfigTemplate |
