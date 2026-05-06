# Memory

> Chronological action log. Hooks and AI append to this file automatically.
> Old sessions are consolidated by the daemon weekly.

| 2026-05-06 | Add addon overlay generation to generate-fleet-entry role | defaults/main.yml, tasks/generate-fleet-entry.yml, templates/gitops/addons-ks.yaml.j2, overlays-*.j2, fleet-kustomization.yaml.j2 | New templates for config/overlays/ (bootstrap, cinder-csi HelmRelease) + fleet entry addons-ks.yaml. Controlled by enable_cinder_csi/enable_envoy_gateway/enable_velero flags. |
