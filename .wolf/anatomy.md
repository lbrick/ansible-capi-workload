# anatomy.md

> Auto-maintained by OpenWolf. Last scanned: 2026-05-04T23:06:19.805Z
> Files: 50 tracked | Anatomy hits: 0 | Misses: 0

## ./

- `.gitignore` — Git ignore rules (~6 tok)
- `CLAUDE.md` — OpenWolf (~57 tok)
- `README.md` — Project documentation (~2033 tok)

## .claude/

- `settings.json` (~441 tok)

## .claude/rules/

- `openwolf.md` (~313 tok)

## defaults/

- `main.yml` (~996 tok)

## files/

- `create_base64_ca_cert.sh` — you may not use this file except in compliance with the License. (~812 tok)
- `create_base64_yaml.sh` — you may not use this file except in compliance with the License. (~1609 tok)
- `create_cloud_conf.sh` — you may not use this file except in compliance with the License. (~1932 tok)
- `env.rc` — you may not use this file except in compliance with the License. (~2183 tok)

## meta/

- `main.yml` (~131 tok)

## tasks/

- `check-vars.yml` (~124 tok)
- `cni-calico-install.yml` (~140 tok)
- `cni-calico-operator-install.yml` (~269 tok)
- `cni-cilium-install.yml` (~162 tok)
- `configure-install-clusterctl.yml` (~587 tok)
- `gpu-hami-operator.yml` (~230 tok)
- `gpu-node-deploy.yml` (~134 tok)
- `gpu-nvidia-operator.yml` — Declares merge (~412 tok)
- `gpu-prerequisites.yml` (~205 tok)
- `install-autoscaler.yml` — Declares template (~500 tok)
- `install-cloud-manager.yml` (~636 tok)
- `install-cni.yml` (~114 tok)
- `install-gpu.yml` (~111 tok)
- `install-healthchecks.yml` (~174 tok)
- `install-metrics-server.yml` (~94 tok)
- `main.yml` (~922 tok)
- `prerequisites.yml` (~281 tok)
- `secgroups-control-plane.yml` (~714 tok)
- `secgroups-worker.yml` (~796 tok)

## templates/

- `autoscaler-deployment.yml.j2` (~985 tok)
- `calico-custom-resources.yaml.j2` — This section includes base Calico installation configuration. (~208 tok)
- `cluster-template-gpu-node.yml.j2` (~533 tok)
- `cluster-template.yml.j2` (~1924 tok)
- `dummy-pod.yml.j2` (~147 tok)
- `healthcheck-control-plane.yml.j2` (~114 tok)
- `healthcheck-worker.yml.j2` (~356 tok)
- `high-priority-class.yml.j2` — Declares for (~59 tok)
- `low-priority-class.yml.j2` — Declares should (~53 tok)
- `metrics-server.yml.j2` (~1106 tok)
- `nvidia-gpu-mps-config-all.yml.j2` (~61 tok)
- `openstack-cluster-config.yml.j2` — Values for environment variable substitution (~249 tok)

## tests/

- `inventory.ini` (~12 tok)
- `README.md` — Project documentation (~1706 tok)
- `requirements.yml` (~23 tok)
- `test_assert.yml` (~249 tok)
- `test_cleanup.yml` (~81 tok)
- `test_create.yml` (~58 tok)
- `test_vars.yml` — kubernetes_version: v1.33.3 (~495 tok)
- `test_vars.yml.example` (~268 tok)
