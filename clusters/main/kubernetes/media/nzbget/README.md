# NZBGet

TrueCharts `nzbget` 31.1.5 deploys NZBGet 26.3.0 using the chart's digest-pinned image.

## Access and setup

- Browser: `https://nzbget.${DOMAIN_0}` through the **internal** ingress and Authentik.
- Native NZBGet authentication is also required: the deployment uses the existing SOPS-backed `${ADMIN_USER}` / `${ADMIN_PASSWORD}` substitutions. No credentials are stored in Homepage annotations.
- Configure your Usenet provider, TLS, connections, and categories in NZBGet after deployment. This PR does not add provider credentials or modify existing Arr download-client settings.
- From Sonarr/Radarr/Lidarr, configure NZBGet at `nzbget.nzbget.svc.cluster.local:10057` (HTTP inside the cluster), using its native credentials. This avoids the browser-only Authentik redirect.

## VPN prerequisite and behavior

NZBGet uses the same ProtonVPN/WireGuard Gluetun approach as qBittorrent, but **requires a separate Proton WireGuard profile**. Do not share qBittorrent's private key between concurrent tunnels: WireGuard peer endpoint roaming can disrupt connectivity.

The dedicated `nzbget-CH-744` profile is included as SOPS-encrypted `app/vpn.secret.yaml`, creating Secret `nzbget-vpn` in namespace `nzbget`. Its six keys hold the client private key, server public key, IPv4 endpoint and port, client IPv4 address, and persistent keepalive. Flux decrypts it through the existing SOPS configuration; no separate manual Secret creation is needed. Missing Secret keys prevent the VPN container from starting; application startup is not explicitly gated on VPN health.

The deployment selects the profile's IPv4 path and preserves its endpoint port and 25-second keepalive. IPv6 addresses/routes are not enabled by this change. The profile's DNS addresses are not imported: existing cluster DNS behavior remains, so Proton NetShield DNS filtering is not guaranteed. NAT-PMP stays disabled for the outbound-only Usenet workload, regardless of the profile comment.

Gluetun runs as an ordinary chart-generated sidecar, following qBittorrent's convention. There is no Flux post-renderer, custom VPN health probe, native-sidecar conversion, or explicit VPN startup/shutdown gate. Application readiness does not establish that the VPN is connected.

- Firewall stays enabled; Internet download traffic is routed through the VPN once connected. Verify the actual egress IP and tunnel-loss behavior after rollout; rendering cannot prove absence of leaks.
- LAN `192.168.1.0/24` is an explicit non-VPN exception, matching qBittorrent. Pod/service exceptions use the chart's normal discovery/default behavior; no extra `chartContext` CIDRs are supplied. This is not an all-traffic isolation policy.
- Native application port **6789** is allowed through Gluetun; the chart also adds Service port 10057. The ingress and Arr RPC address are unchanged.
- The addon retains its default cluster nameserver behavior, as with qBittorrent; this does not establish DNS privacy through Proton.
- Torrent port forwarding, its qBittorrent callback, and the HTTP proxy are not needed and are disabled.
- The dedicated namespace receives the same Pod Security `enforce: privileged` exception as qBittorrent, because Gluetun's network capabilities are rejected by baseline policy. This relaxes admission for the namespace; the containers are not themselves set `privileged: true`.
- The pod now needs one `truecharts.org/tun` device and Gluetun's NET_ADMIN/NET_RAW/MKNOD capabilities; the NZBGet application container retains its non-root hardening. `resources.excludeExtra: false` is retained because this pinned chart otherwise filters out the requested TUN device.

After deployment, independently verify VPN health (do not rely on application readiness), verify authenticated UI/RPC, check the observed public egress IP, and deliberately test tunnel-loss blocking in a maintenance window. Confirm that qBittorrent remains connected and NZBGet can download/unpack/import. NFS traffic and backup mover Jobs are not tunneled by this pod sidecar.

## Storage

- `/config`: new 5 GiB PVC on the cluster's default storage class (currently Longhorn).
- Downloads: the same `${TRUENAS_IP}:${DOWNLOADS_PATH}` NFS export and `${DOWNLOADS_MOUNT_PATH}` mount used by the existing Arr applications.
- Completed files: `${DOWNLOADS_MOUNT_PATH}/usenet/completed`.
- Intermediate files: `${DOWNLOADS_MOUNT_PATH}/usenet/intermediate`.
- Both download paths are set as command-line overrides; edit the HelmRelease to change them, not only the UI.
- The container runs as UID/GID 568. Verify that the NFS export permits this identity to create, rename, and remove files. No recursive permission-changing init container is added.

## Backups and rollout verification

The config PVC has a daily VolSync Restic source at `50 9 * * *`, using the existing B2 credentials. Restore destination is disabled for the fresh install; a restore must be explicitly configured. Downloads on NFS are not included in this config backup.

After merge, verify the Flux Kustomization and HelmRelease, PVC binding, startup/readiness, HTTPS/Auth workflows, and native authenticated RPC. Then test NFS writes, a provider connection, an actual download/unpack/import, and the first successful config backup. Render/schema checks do not establish these runtime outcomes.

Upstream chart metadata advertises a maximum tested Kubernetes version of 1.35.0, while this cluster runs 1.37.2; the chart's actual `kubeVersion` constraint accepts 1.33+. Rendering and admission dry-runs are useful checks but do not prove upstream-tested support for 1.37.
