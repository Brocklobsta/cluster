<div align="center">

# Kubernetes Home Cluster

A two-node, GitOps-managed home Kubernetes cluster powered by [Talos Linux](https://www.talos.dev/), [Flux CD](https://fluxcd.io/), and [TrueCharts ClusterTool](https://truecharts.org/clustertool/).

[![Talos](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.brocklobsta.net%2Fbadges%2Ftalos_version%3Fformat%3Dshields&style=for-the-badge&logo=talos&logoColor=white&label=%20&color=blue)](https://www.talos.dev/)&nbsp;&nbsp;
[![Kubernetes](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.brocklobsta.net%2Fbadges%2Fkubernetes_version%3Fformat%3Dshields&style=for-the-badge&logo=kubernetes&logoColor=white&label=%20&color=blue)](https://www.kubernetes.io/)&nbsp;&nbsp;
[![Flux](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.brocklobsta.net%2Fbadges%2Fflux_version%3Fformat%3Dshields&style=for-the-badge&logo=flux&logoColor=white&color=blue&label=%20)](https://fluxcd.io/)&nbsp;&nbsp;

[![Home-Internet](https://img.shields.io/endpoint?url=https%3A%2F%2Fstatus.brocklobsta.net%2Fapi%2Fv1%2Fendpoints%2Fbuddy_ping-(buddy)%2Fhealth%2Fbadge.shields&style=for-the-badge&logo=ubiquiti&logoColor=white&label=Home%20Internet)](https://status.brocklobsta.net)&nbsp;&nbsp;
[![Alertmanager](https://img.shields.io/endpoint?url=https%3A%2F%2Fstatus.brocklobsta.net%2Fapi%2Fv1%2Fendpoints%2Fbuddy_heartbeat-(buddy)%2Fhealth%2Fbadge.shields&style=for-the-badge&logo=prometheus&logoColor=white&label=Alertmanager)](https://status.brocklobsta.net)

[![Age-Days](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.brocklobsta.net%2Fbadges%2Fcluster_age_days%3Fformat%3Dshields&style=flat-square&label=Age)](https://github.com/home-operations/kromgo)&nbsp;&nbsp;
[![Uptime-Days](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.brocklobsta.net%2Fbadges%2Fcluster_uptime_days%3Fformat%3Dshields&style=flat-square&label=Uptime)](https://github.com/home-operations/kromgo)&nbsp;&nbsp;
[![Node-Count](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.brocklobsta.net%2Fbadges%2Fcluster_node_count%3Fformat%3Dshields&style=flat-square&label=Nodes)](https://github.com/home-operations/kromgo)&nbsp;&nbsp;
[![Pod-Count](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.brocklobsta.net%2Fbadges%2Fcluster_pod_count%3Fformat%3Dshields&style=flat-square&label=Pods)](https://github.com/home-operations/kromgo)&nbsp;&nbsp;
[![CPU-Usage](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.brocklobsta.net%2Fbadges%2Fcluster_cpu_usage%3Fformat%3Dshields&style=flat-square&label=CPU)](https://github.com/home-operations/kromgo)&nbsp;&nbsp;
[![Memory-Usage](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.brocklobsta.net%2Fbadges%2Fcluster_memory_usage%3Fformat%3Dshields&style=flat-square&label=Memory)](https://github.com/home-operations/kromgo)&nbsp;&nbsp;
[![Alerts](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.brocklobsta.net%2Fbadges%2Fcluster_alert_count%3Fformat%3Dshields&style=flat-square&label=Alerts)](https://github.com/home-operations/kromgo)&nbsp;&nbsp;

</div>

---

## Overview

This repository is the source of truth for the cluster. Flux continuously reconciles Kubernetes resources from Git, while Renovate proposes chart and image updates. Secrets and cluster environment values are encrypted with SOPS and Age.

### Platform

| Area | Components |
|---|---|
| Operating system | Talos Linux |
| GitOps | Flux CD, Kustomize, Helm Controller |
| Networking | Cilium, Multus, Whereabouts, MetalLB, ingress-nginx |
| Storage and backup | Longhorn, OpenEBS, CSI snapshots, VolSync |
| Databases | CloudNativePG |
| Certificates and DNS | cert-manager, Blocky, Cloudflare DDNS |
| Hardware integration | Intel and generic device plugins, Node Feature Discovery |
| Image distribution | Spegel |
| Automation | Renovate, TUPPR system upgrades |

## Repository Structure

```text
.
├── clusters/main/
│   ├── clusterenv.yaml              # SOPS-encrypted cluster substitutions
│   ├── talos/                       # Talos machine configuration and patches
│   └── kubernetes/
│       ├── apps/                    # General user-facing applications
│       ├── core/                    # Cluster-wide configuration services
│       ├── flux-system/             # Flux bootstrap, sources, and notifications
│       ├── kube-system/             # Kubernetes networking and node services
│       ├── media/                   # Media servers and acquisition automation
│       ├── networking/              # Internal and external ingress controllers
│       ├── observability/           # Metrics, logs, dashboards, health, and exporters
│       └── system/                  # Storage, databases, certificates, and controllers
├── repositories/                    # Helm and OCI repository definitions
└── .sops.yaml                       # SOPS encryption policy
```

Each managed workload follows the same pattern:

```text
<domain>/<workload>/
├── ks.yaml                          # Flux Kustomization and Git path
└── app/
    ├── helm-release.yaml            # HelmRelease values and version
    ├── kustomization.yaml           # Workload resources
    └── namespace.yaml               # Namespace and Pod Security labels
```

## TrueCharts values schema (repository/editor validation)

The [TrueCharts common 30.4.0 announcement](https://truecharts.org/news/truecharts/common-3-4-0-json-schema/) describes a **Helm values schema**, not a Kubernetes CRD to install. This repository pins [the upstream 30.4.0 schema](https://github.com/trueforge-org/truecharts/blob/50389743654b19cc64faa23e099cd5f2e1b1b69a/charts/library/common/values.schema.json) in `schemas/truecharts-common-30.4.0.schema.json` (SHA-256 `25e4d0bd45dbca0ee1ca389cacea595b75cf455e9f7de220859fed5df0abb761`). VS Code's YAML extension uses the local `schemas/truecharts-helmrelease.schema.json` wrapper for the TrueCharts HelmRelease files listed in `.vscode/settings.json`. It validates `spec.values`; it does **not** replace Kubernetes API validation for the rest of a HelmRelease. When adding a new TrueCharts release, add its path to that list.

To check every TrueCharts release from the repository root (Node.js/npm required):

```sh
npm ci --prefix tools/truecharts-schema
npm run report --prefix tools/truecharts-schema      # report existing schema issues; exit 0
npm run validate --prefix tools/truecharts-schema    # strict mode; exit 1 on issues
npm run self-test --prefix tools/truecharts-schema   # mapping and type checks
```

The current 30.4.0 schema reports issues in **22 of 38** releases with inline `spec.values` (42 TrueCharts releases total). Many installed charts still depend on older common versions (for example Home Assistant uses 30.2.9), so these are migration warnings, **not proof that the running chart is broken**. Review keys such as `credentials.b2` and `cnpg.*.recovery` against the exact chart/common version before changing production values. Strict validation is deliberately **not a CI merge gate** while the existing issues remain. The upstream change also notes that stable chart releases do not yet bundle the new schema for automatic Helm values enforcement; this repository/editor aid does not modify deployed charts or Flux behavior.

## Observability

Observability workloads live under [`clusters/main/kubernetes/observability`](clusters/main/kubernetes/observability).

| Workload | Purpose |
|---|---|
| Alloy | Telemetry and log collection |
| Gatus | Endpoint and service health monitoring |
| Grafana | Dashboards and visualization |
| Headlamp | Kubernetes visibility and administration |
| Kromgo | Public, Prometheus-backed status badges |
| kube-prometheus-stack | Prometheus, Alertmanager, exporters, and alert rules |
| Loki | Centralized log storage and querying |
| TrueNAS Exporter | TrueNAS metrics collection |
| Unpoller | UniFi metrics collection |

## Media

Media workloads live under [`clusters/main/kubernetes/media`](clusters/main/kubernetes/media).

| Workload | Purpose |
|---|---|
| Emby | Primary media server |
| Flaresolverr | Indexer challenge helper |
| Immich | Photo and video library |
| Jellyfin | Secondary media server |
| Lidarr | Music library automation |
| Ombi | Media request management |
| Prowlarr | Indexer management |
| qBittorrent | Download client |
| Radarr | Movie library automation |
| Recyclarr | Servarr profile synchronization |
| Sonarr | TV library automation |

## Applications

General applications remain under [`clusters/main/kubernetes/apps`](clusters/main/kubernetes/apps).

| Category | Workloads |
|---|---|
| Identity and access | Authentik, Vaultwarden |
| Development and AI | Code Server, Gitea, Ollama |
| Home and personal | Home Assistant, TeslaMate |
| Productivity | Nextcloud, Proton Mail Bridge |
| Dashboards and utilities | Homepage, IT-Tools, Kubernetes Dashboard, Static |
| External service portals | Proxmox GUI, TrueNAS GUI |
| Networking helper | Cloudflare DDNS |

## GitOps and Secrets

- Flux reconciles the root Kustomization at `clusters/main/kubernetes`.
- Workloads are grouped by operational domain, but retain their existing namespaces and Flux object names when moved.
- Helm and OCI sources are declared under `repositories/` and `clusters/main/kubernetes/flux-system`.
- Renovate updates pinned chart versions, container tags, and digests.
- SOPS encryption rules cover `clusterenv.yaml`, `*.secret.yaml`, and secret-bearing values files.
- Plaintext credentials must never be committed.

## Prerequisites

- [ClusterTool](https://truecharts.org/clustertool/) CLI
- [SOPS](https://github.com/getsops/sops) with the cluster Age key
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [talosctl](https://www.talos.dev/latest/introduction/getting-started/)
- [Flux CLI](https://fluxcd.io/flux/installation/)

## Reconciliation Workflow

1. Clone the repository and configure the SOPS Age key.
2. Make changes in a focused branch.
3. Render the affected Kustomization and validate resources against the cluster API.
4. Open a pull request and wait for repository checks.
5. Merge the pull request; Flux applies the desired state and reports reconciliation status.

## License

[AGPL-3.0](LICENSE)
