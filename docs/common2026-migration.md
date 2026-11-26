# Common2026 migration record and pre-migration backup

The migration was deployed by [#6076](https://github.com/Brocklobsta/cluster/pull/6076)
after the [Barman plugin prerequisite](common2026-barman-prerequisite.md), with a
Gluetun follow-up in [#6079](https://github.com/Brocklobsta/cluster/pull/6079).
The preparation notes below describe the historical rollout, not current chart
versions, PostgreSQL images, or instructions to replay it.

The backup and recovery ObjectStores are plugin configuration, not legacy
in-tree Barman settings. Keep active schedules, credential references, and
recovery sources. Blocky, Immich, and Nextcloud now run on separate Valkey
volumes. The unmounted pre-migration Redis PVCs remain protected; running
Valkey does not prove the old data was restored or can be discarded. Retire
those PVCs only as a separate, reviewed data-retention decision.

Upstream references:

- [Common2026 announcement](https://truecharts.org/news/truecharts/common-2026/)
- [Common2026 rollout](https://truecharts.org/news/truecharts/common-2026-rollout/)
- [CloudNativePG 1.30 PostgreSQL upgrades](https://github.com/cloudnative-pg/cloudnative-pg/blob/v1.30.2/docs/src/postgres_upgrades.md)

This migration must separate the common-library and dependency-values changes from PostgreSQL major-version upgrades. A pull request, successful render, or healthy operator does **not** establish that the live application has migrated successfully. Leave migration pull requests unmerged for owner review.

## Historical PostgreSQL version bridge

The rollout article recommends pinning PostgreSQL 16. That is not a harmless pin for this cluster: Authentik, Gitea, Nextcloud, and Vaultwarden currently use PostgreSQL 15.19 based on Debian bullseye. The installed CNPG 1.30.2 operator automatically starts an offline major upgrade when the requested image major increases. CNPG only supports that operation between images based on the **same operating-system distribution**; changing directly from PG15 bullseye to a new PG16 trixie default is not supported.

The initial common2026 migration must therefore retain each cluster's current major and exact deployed image digest through the supported `dependencies.postgresql.operator.cluster.imageName` override, using target chart artifacts whose bundled schema accepts that major. Gatus, Grafana, Home Assistant, Immich, and TeslaMate remain on PostgreSQL 16. Immich retains its existing VectorChord image and extension configuration. Do not remove these overrides merely to follow a newer default.

Preserve CNPG Cluster and PVC identities, application database and role names, hibernation, storage settings, and the existing backup destination, server name, and revision. Move backups to the Barman Cloud plugin only with the plugin and its CRDs ready in the CNPG operator namespace. Old physical backups must remain available; a database-major upgrade cannot reuse pre-upgrade WAL history for cross-major PITR.

A later PostgreSQL major upgrade requires its own fresh backups, compatible images/extensions, rehearsed restore or upgrade, maintenance window, rollback boundary, and post-upgrade base backup. A successfully upgraded data directory cannot simply be downgraded.

## Verified pre-migration backup

A backup taken on 2026-11-24 UTC (2026-11-23 Pacific) is stored in the **admin Nextcloud account**:

```text
CNPG-Backups/cnpg-common2026-20261124T005310Z/
  cnpg-common2026-20261124T005310Z.tar.age
  SHA256SUMS
```

- Encrypted archive size: **413295304 bytes**.
- SHA-256: `5bddd0bf2b7831c4f9a02536350ea8cc41f2e4bf53c04df9e4830b3baced0bff`.
- All nine live CNPG clusters are included: Authentik, Gatus, Gitea, Grafana, Home Assistant, Immich, Nextcloud, TeslaMate, and Vaultwarden.
- Each cluster has a `pg_dumpall --globals-only` export and custom-format dumps of every non-template database: **18 database archives** in total, including the nine `postgres` databases.
- Every archive passed a full `pg_restore --exit-on-error` into a disposable PostgreSQL instance, not merely an archive-list check. Restored application table counts and exact source images are recorded in `restore-verification.json` inside the archive.
- The three live Valkey stores (Blocky, Immich, Nextcloud) have RDB exports validated with `valkey-check-rdb`.
- Gitea and Vaultwarden were temporarily woken for their dumps, then verified hibernated again with zero database Pods and their original HelmRelease suspension state restored. Their applications were not enabled.
- Local age decryption was tested against every archived file. After upload, the complete remote archive was downloaded and its byte count and SHA-256 matched.

The archive is encrypted to the repository's existing SOPS age public recipient; **the private identity is not included**. Keep a separately secured, off-cluster copy of that identity and retain the existing independent S3 backups. Nextcloud itself depends on this cluster, so a Nextcloud-only copy is not a complete disaster-recovery strategy.

Decrypt on a trusted restore host using the existing identity:

```sh
age --decrypt --identity /path/to/age.agekey cnpg-common2026-20261124T005310Z.tar.age \
  | tar -x -C /safe/restore-directory
```

Logical dumps are consistent per database, not transactionally synchronized across separate applications, and do not provide WAL/PITR recovery. They do not replace application-file and volume backups.

### Immich restore compatibility

Immich's database still declares `vectors`0.2.1, although its current VectorChord image no longer contains `vectors.control` or `vectors.so`. A plain restore into that image fails. The complete, unfiltered Immich dump was successfully restored by supplying the matching upstream pgvecto.rs PostgreSQL 16 package alongside the existing VectorChord image and preloading both `vectors.so` and `vchord.so`.

The encrypted archive includes the required package under `restore-dependencies/`, its source URL and checksum, and instructions in its README. This is an isolated restore dependency—not authorization to install obsolete binaries in production or drop production extensions. Preserve and audit extension dependencies before any later database migration.

## Original GitOps proposal and verification

- All **43 existing TrueCharts common-library consumers** are pinned to exact chart releases bundling **common 32.8.5**. Unrelated upstream charts are unchanged.
- The official `plugin-barman-cloud` chart is pinned to **0.9.0** (plugin v0.16.0) in `cloudnative-pg`. Cert-manager and CNPG readiness precede the plugin; the nine database-bearing apps depend on plugin readiness.
- All nine exact database image digests and majors are retained. Generic Device Plugin also retains its existing binary image and resources while crossing its older common 25 baseline.
- Blocky, Immich, and Nextcloud retain their old Redis PVCs explicitly, offline and unmounted, with a Helm keep policy. The new Valkey volumes do not automatically contain the old data.
- Parent verification rendered all 43 exact charts using dummy substitutions and normal chart schema enforcement. **535/535 Kubernetes resources** across those charts and the plugin passed strict schema validation, with zero missing schemas or skips.
- **56/56 changed HelmRelease and Flux Kustomization objects** passed API-server dry-run validation. The intended atomic CNPG Cluster replacements passed **9/9** admission checks. Independent review also derived the actual Helm old-release-to-target merge patches and server-side dry-ran all nine: each backup-enabled Cluster removes old in-tree Barman fields and adds the plugin in one accepted update. This is atomic per Cluster, not across the entire release. Plain client-side `kubectl apply` is not an equivalent migration test because it can retain unmanaged old Barman fields and produce a false conflicting-WAL-archiver error.
- Root Kustomize rendering, Flux dependency-cycle checks, original database/bootstrap/PVC and backup-destination invariants, and secret-encryption checks passed. These are source/schema/admission checks, not a deployed application or plugin-runtime test.
- TrueCharts metadata advertises testing through Kubernetes 1.35; the live cluster is 1.37.2. The local validations do not establish upstream runtime support for 1.37.

## Original deployment gates

1. Confirm fresh CNPG, application-file, and persistent-volume backups before deployment. The backup above is a fixed recovery point, not an automatically refreshed pre-cutover snapshot.
2. Install and verify the Barman Cloud plugin and its prerequisites before reconciling dependent application charts. Verify the exact rendered ObjectStores, credentials references, server names, destination paths, and backup schedules.
3. Review the before/after render of every upgraded chart: resource identity, PVC retention and mounts, database roles, application connection credentials, probes, ingress, image changes, and the closed values schema all matter.
4. Migrate dependency-bearing applications in a maintenance window. Common2026 Valkey dependencies use different data layout and volumes. Fence writers and capture a final RDB before cutover; restore into the new dependency's verified data path before starting the application. Do not assume a chart upgrade restores the RDB automatically or that a stale running-cache export is a final cutover backup.
5. Preserve stopped applications as stopped. Do not wake them solely to satisfy a rollout readiness check. If their persistent dependency stores exist but are not in the three live Valkey exports, back them up and define their restore path before re-enabling them.
6. After each deployment, verify Flux and Helm readiness, actual CNPG image/version and quorum, successful plugin backups, PVC attachment, and application-level reads and writes. For Nextcloud, test authenticated login, DAV listing, and a temporary upload/read/delete. For media applications and Immich, verify representative existing library data and background-job behavior.
7. Only after all application-level checks pass should a later revision consider database image/distribution or major-version upgrades. Take new backups before and after those separate changes.

Do not commit temporary backup/restore Pods, recovery Jobs, operational scripts, or credentials to the steady-state GitOps tree.
