<div align="center">

# Kubernetes Home Cluster

A GitOps-managed Kubernetes cluster powered by [TrueCharts ClusterTool](https://truecharts.org/clustertool/), [Talos Linux](https://www.talos.dev/), and [Flux CD](https://fluxcd.io/).


[![Talos](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.brocklobsta.net%2Ftalos_version&style=for-the-badge&logo=talos&logoColor=white&label=%20&color=blue)](https://www.talos.dev/)&nbsp;&nbsp;
[![Kubernetes](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.brocklobsta.net%2Fkubernetes_version&style=for-the-badge&logo=kubernetes&logoColor=white&label=%20&color=blue)](https://www.kubernetes.io/)&nbsp;&nbsp;
[![Flux](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.brocklobsta.net%2Fflux_version&style=for-the-badge&logo=flux&logoColor=white&color=blue&label=%20)](https://fluxcd.io)&nbsp;&nbsp;

[![Home-Internet](https://img.shields.io/endpoint?url=https%3A%2F%2Fstatus.brocklobsta.net%2Fapi%2Fv1%2Fendpoints%2Fbuddy_ping-(buddy)%2Fhealth%2Fbadge.shields&style=for-the-badge&logo=ubiquiti&logoColor=white&label=Home%20Internet)](https://status.brocklobsta.net)&nbsp;&nbsp;
[![Alertmanager](https://img.shields.io/endpoint?url=https%3A%2F%2Fstatus.brocklobsta.net%2Fapi%2Fv1%2Fendpoints%2Fbuddy_heartbeat-(buddy)%2Fhealth%2Fbadge.shields&style=for-the-badge&logo=prometheus&logoColor=white&label=Alertmanager)](https://status.brocklobsta.net)

[![Age-Days](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.brocklobsta.net%2Fcluster_age_days&style=flat-square&label=Age)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![Uptime-Days](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.brocklobsta.net%2Fcluster_uptime_days&style=flat-square&label=Uptime)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![Node-Count](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.brocklobsta.net%2Fcluster_node_count&style=flat-square&label=Nodes)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![Pod-Count](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.brocklobsta.net%2Fcluster_pod_count&style=flat-square&label=Pods)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![CPU-Usage](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.brocklobsta.net%2Fcluster_cpu_usage&style=flat-square&label=CPU)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![Memory-Usage](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.brocklobsta.net%2Fcluster_memory_usage&style=flat-square&label=Memory)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![Alerts](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.brocklobsta.net%2Fcluster_alert_count&style=flat-square&label=Alerts)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;

</div>

---

## Overview

This repository contains the declarative configuration for a home Kubernetes cluster using:

- **Talos Linux** - Immutable, secure Kubernetes OS
- **Flux CD** - GitOps continuous delivery
- **SOPS** - Secrets encryption with Age
- **Renovate** - Automated dependency updates

## Repository Structure

```
├── clusters/main/
│   ├── clusterenv.yaml          # Encrypted cluster environment variables
│   ├── talos/                   # Talos Linux configuration
│   │   ├── talconfig.yaml       # Talos cluster config
│   │   └── patches/             # Node-specific patches (GPU, NVIDIA)
│   └── kubernetes/
│       ├── flux-system/         # Flux bootstrap and settings
│       ├── kube-system/         # Core K8s components (Cilium, metrics-server)
│       ├── system/              # Cluster infrastructure
│       ├── networking/          # Ingress controllers (nginx internal/external)
│       ├── core/                # Core services (cert-manager, MetalLB, Blocky)
│       └── apps/                # User applications
├── repositories/                # Helm and Git repository definitions
└── .sops.yaml                   # SOPS encryption rules
```

## System Components

| Component | Purpose |
|-----------|---------|
| Cilium | CNI networking |
| MetalLB | Load balancer |
| cert-manager | TLS certificates |
| Longhorn | Distributed storage |
| CloudNative-PG | PostgreSQL operator |
| kube-prometheus-stack | Monitoring |
| Spegel | P2P image distribution |

## Applications

Media: Emby, Sonarr, Radarr, Lidarr, Prowlarr, qBittorrent, Ombi, Recyclarr

Home: Home Assistant, Immich, KitchenOwl, Teslamate

Infrastructure: Authentik, Grafana, Vaultwarden, Gitea, Nextcloud, Ollama

Utilities: Homepage, IT-Tools, Blocky (DNS), Cloudflare DDNS

## Prerequisites

- [ClusterTool](https://truecharts.org/clustertool/) CLI
- [SOPS](https://github.com/getsops/sops) with Age key
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Talosctl](https://www.talos.dev/latest/introduction/getting-started/)

## Secrets Management

Secrets are encrypted using SOPS with Age. The `.sops.yaml` file defines encryption rules for:
- `clusterenv.yaml` - Cluster-wide environment variables
- `*.secret.yaml` - Kubernetes secrets
- `values.yaml` - Helm values containing sensitive data

## Getting Started

1. Clone this repository
2. Configure your Age key for SOPS decryption
3. Update `clusters/main/clusterenv.yaml` with your values
4. Deploy Talos nodes using ClusterTool
5. Flux will automatically reconcile the cluster state

## License

[AGPL-3.0](LICENSE)

